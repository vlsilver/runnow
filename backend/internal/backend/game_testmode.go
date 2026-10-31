package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"math"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Ván thử (X1): người chơi giả, admin bấm thay người giả, sửa km, ép vai trước
// Start, và đẩy giờ ván tới mốc kế tiếp. Caller (L2) đã kiểm người gọi là admin;
// các hàm ở đây chỉ kiểm ván có phải ván thử không.
//
// Đẩy giờ không sửa lịch trong state mà cộng độ lệch clockOffsetNs vào giờ thật
// (gameNow). Engine, cửa sổ hành động, snapshot km và tick đều đọc giờ ván, nên
// lịch trong vòng giữ nguyên (biểu quyết vẫn mở 20h) và replay events vẫn khớp.
// Độ lệch chỉ tăng, nên giờ ván không bao giờ lùi.

var (
	errNotTestMode   = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "not_test_mode", Message: "Chỉ dùng được ở ván thử."}
	errTestModeInPsc = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "test_mode_psc", Message: "Ván thử không được chạy trong group PSC."}
	errNotFakePlayer = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "not_fake_player", Message: "Chỉ bấm thay được người chơi giả."}
	errPhaseMoved    = &HTTPError{Status: http.StatusConflict, Code: "phase_moved", Message: "Ván đã sang bước khác, tải lại rồi thử lại."}
	errNotRunning    = &HTTPError{Status: http.StatusConflict, Code: "phase_closed", Message: "Ván chưa chạy hoặc đã kết thúc."}
	errGamePaused    = &HTTPError{Status: http.StatusConflict, Code: "paused", Message: "Ván đang tạm dừng."}
	errStarted       = &HTTPError{Status: http.StatusConflict, Code: "game_running", Message: "Ván đã bắt đầu."}
	errKmRound       = &HTTPError{Status: http.StatusConflict, Code: "phase_closed", Message: "km của vòng này đã chốt hoặc chưa tới lượt."}
	errInvalidKm     = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_km", Message: "km phải từ 0 tới 1000."}
	errNotPlayer     = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_target", Message: "Người này không có trong ván."}
	errInvalidRole   = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_role", Message: "Vai không hợp lệ."}
)

// clockOffset là độ lệch giờ ván so với giờ thật; ván thật luôn là 0.
func clockOffset(gameData map[string]any) time.Duration {
	n, _ := gameData["clockOffsetNs"].(int64)
	return time.Duration(n)
}

// gameNow là giờ ván ứng với giờ thật wall.
func gameNow(gameData map[string]any, wall time.Time) time.Time {
	return wall.Add(clockOffset(gameData))
}

func fakeUIDs(gameData map[string]any) map[string]bool {
	out := map[string]bool{}
	raw, _ := gameData["fakeUids"].([]any)
	for _, v := range raw {
		out[stringValue(v)] = true
	}
	return out
}

// withoutFakeDMs bỏ tin DM gửi người chơi giả: họ không có Telegram, ghi vào
// outbox thì bộ gửi chỉ có lỗi.
func withoutFakeDMs(msgs []gameMsg, gameData map[string]any) []gameMsg {
	fake := fakeUIDs(gameData)
	if len(fake) == 0 {
		return msgs
	}
	out := msgs[:0:0]
	for _, m := range msgs {
		if uid, ok := strings.CutPrefix(m.ChatKey, "dm:"); ok && fake[uid] {
			continue
		}
		out = append(out, m)
	}
	return out
}

func fakeUID(i int) string { return fmt.Sprintf("fake-%02d", i) }

// testGame đọc ván trong transaction và kiểm đó là ván thử.
func (s *GameStore) testGame(tx *firestore.Transaction, gameID string) (*firestore.DocumentSnapshot, error) {
	g, err := tx.Get(s.gameRef(gameID))
	if err != nil {
		return nil, err
	}
	if g.Data()["testMode"] != true {
		return nil, errNotTestMode
	}
	return g, nil
}

// SetFakePlayers đặt số người chơi giả của ván thử về đúng n, trước Start: tạo
// fake-01…fake-n còn thiếu, xoá phần dư. Gọi lại với cùng n thì không đổi gì,
// nên request bị gửi lại không sinh thêm người.
func (s *GameStore) SetFakePlayers(ctx context.Context, gameID string, n int, wall time.Time) ([]string, error) {
	if n < 0 || n > werewolf.MaxPlayers {
		return nil, &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_count", Message: fmt.Sprintf("Số người giả phải từ 0 tới %d.", werewolf.MaxPlayers)}
	}
	game := s.gameRef(gameID)
	var uids []string
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := s.testGame(tx, gameID)
		if err != nil {
			return err
		}
		if stringValue(g.Data()["status"]) != gameRegistering {
			return errStarted
		}
		want := map[string]bool{}
		uids = uids[:0]
		for i := 1; i <= n; i++ {
			want[fakeUID(i)] = true
			uids = append(uids, fakeUID(i))
		}
		// Đọc trước mọi lần ghi để đếm lại playerCount cho /v1/games.
		players, err := tx.Documents(game.Collection("players")).GetAll()
		if err != nil {
			return err
		}
		realPlayers := 0
		for _, p := range players {
			if p.Data()["fake"] != true {
				realPlayers++
			}
		}
		have := fakeUIDs(g.Data())
		for uid := range have {
			if !want[uid] {
				if err := tx.Delete(game.Collection("players").Doc(uid)); err != nil {
					return err
				}
			}
		}
		for i, uid := range uids {
			if have[uid] {
				continue
			}
			if err := tx.Set(game.Collection("players").Doc(uid), map[string]any{
				"uid": uid, "name": fmt.Sprintf("Người giả %02d", i+1), "fake": true, "registeredAt": wall,
			}); err != nil {
				return err
			}
		}
		return tx.Update(game, []firestore.Update{{Path: "fakeUids", Value: uids}, {Path: "playerCount", Value: realPlayers + n}, {Path: "updatedAt", Value: wall}})
	})
	return uids, err
}

func forcedRolesRef(game *firestore.DocumentRef) *firestore.DocumentRef {
	return game.Collection("secret").Doc("roles")
}

// SetForcedRoles ghi vai admin ép cho ván thử, trước Start. Ghi đè cả bộ; map
// rỗng là bỏ ép. Bộ có vừa với số người không thì lúc chia vai (NewStartState)
// mới biết, vì người đăng ký còn đổi tới lúc Start.
func (s *GameStore) SetForcedRoles(ctx context.Context, gameID string, roles map[string]werewolf.Role, wall time.Time) error {
	doc := map[string]any{}
	for uid, r := range roles {
		if !werewolf.ValidRole(r) {
			return errInvalidRole
		}
		doc[uid] = string(r)
	}
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := s.testGame(tx, gameID)
		if err != nil {
			return err
		}
		if stringValue(g.Data()["status"]) != gameRegistering {
			return errStarted
		}
		return tx.Set(forcedRolesRef(s.gameRef(gameID)), map[string]any{"roles": doc, "updatedAt": wall})
	})
}

// NewStartState chia vai cho uids theo cấu hình đã lưu của ván và dựng state lúc
// Start. Ván thử thì áp vai đã ép. Caller (game-start) đã lọc người không đủ
// điều kiện, rồi đưa state này cho StartGame.
func (s *GameStore) NewStartState(ctx context.Context, gameID string, uids []string, seed werewolf.Seed, start time.Time) (*werewolf.State, error) {
	game := s.gameRef(gameID)
	g, err := game.Get(ctx)
	if err != nil {
		return nil, err
	}
	var cfg werewolf.Config
	if err := json.Unmarshal([]byte(stringValue(g.Data()["config"])), &cfg); err != nil {
		return nil, fmt.Errorf("đọc config của ván %s: %w", gameID, err)
	}
	var forced map[string]werewolf.Role
	if g.Data()["testMode"] == true {
		doc, err := forcedRolesRef(game).Get(ctx)
		if err != nil && status.Code(err) != codes.NotFound {
			return nil, err
		}
		if err == nil {
			raw, _ := doc.Data()["roles"].(map[string]any)
			forced = map[string]werewolf.Role{}
			for uid, r := range raw {
				forced[uid] = werewolf.Role(stringValue(r))
			}
		}
	}
	roles, err := werewolf.DealForced(seed, uids, cfg, forced)
	if err != nil {
		return nil, err
	}
	return werewolf.NewState(seed, cfg, roles, start), nil
}

// AdminSetKm ghi đè km của một người cho snapshot 22h sắp tới (round phải là
// vòng đó). Snapshot đã chốt vào state thì không sửa được nữa: transaction này
// đọc secret/state mà bước chốt ghi, nên sửa hoặc vào kịp bước chốt, hoặc bị từ
// chối sau đó.
func (s *GameStore) AdminSetKm(ctx context.Context, gameID string, round int, uid string, km float64, wall time.Time) error {
	if math.IsNaN(km) || km < 0 || km > 1000 {
		return errInvalidKm
	}
	game := s.gameRef(gameID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := s.testGame(tx, gameID)
		if err != nil {
			return err
		}
		if stringValue(g.Data()["status"]) != gameRunning {
			return errNotRunning
		}
		sec, err := tx.Get(secretRef(game))
		if err != nil {
			return err
		}
		st, err := decodeState(sec.Data())
		if err != nil {
			return err
		}
		if st.Players[uid] == nil {
			return errNotPlayer
		}
		if round != kmRound(st) {
			return errKmRound
		}
		return tx.Set(roundRef(game, round).Collection("km").Doc(uid), map[string]any{
			"meters": km * 1000, "source": "override", "createdAt": wall,
		})
	})
}

// AdminAdvance chạy đúng một bước của ván thử, kể cả khi chưa tới hạn: chưa có
// gì tới hạn thì đẩy giờ ván tới NextAt rồi chạy. expectedKey là taskKey admin
// đang thấy (CAS). Không dùng phaseKey vì tin nhắc 18h/21h không đổi phaseKey;
// bấm lại một lần sẽ nhảy qua luôn hạn chốt.
func (s *GameStore) AdminAdvance(ctx context.Context, gameID, expectedKey string, wall time.Time) (AdvanceResult, error) {
	var res AdvanceResult
	if err := s.fastForward(ctx, gameID, expectedKey, wall); err != nil {
		return res, err
	}
	for i := 0; i < maxAdvanceSteps; i++ {
		if err := s.snapshotKmIfDue(ctx, gameID, wall); err != nil {
			return res, err
		}
		stepped, err := s.advanceOnce(ctx, gameID, wall, expectedKey, &res)
		if errors.Is(err, errKmNotReady) {
			continue
		}
		if err != nil {
			return res, err
		}
		if stepped {
			res.Steps = 1
		}
		return res, nil
	}
	return res, errKmNotReady
}

// fastForward đẩy giờ ván tới NextAt nếu giờ ván còn trước đó.
func (s *GameStore) fastForward(ctx context.Context, gameID, expectedKey string, wall time.Time) error {
	game := s.gameRef(gameID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := s.testGame(tx, gameID)
		if err != nil {
			return err
		}
		if stringValue(g.Data()["status"]) != gameRunning {
			return errNotRunning
		}
		sec, err := tx.Get(secretRef(game))
		if err != nil {
			return err
		}
		st, err := decodeState(sec.Data())
		if err != nil {
			return err
		}
		if st.Paused {
			return errGamePaused
		}
		if st.TaskKey() != expectedKey {
			return errPhaseMoved
		}
		target := st.NextAt()
		if !gameNow(g.Data(), wall).Before(target) {
			return nil
		}
		return tx.Update(game, []firestore.Update{{Path: "clockOffsetNs", Value: int64(target.Sub(wall))}})
	})
}
