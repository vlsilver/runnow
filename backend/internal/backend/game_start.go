package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Start của Ma Sói (2.4) đi hai chặng. api kiểm sơ bộ, đặt status=starting rồi
// enqueue game-start sang bot. Bot hỏi lại Telegram cho từng người, loại người
// không còn đủ điều kiện, chia vai và ghi state. Không đủ người thì bot đưa ván
// về registering kèm startError để admin thấy.

const (
	excludeNotLinked = "not_linked"
	excludeNotInPsc  = "not_in_psc"
)

var excludeLabels = map[string]string{
	excludeNotLinked: "Chưa liên kết Telegram",
	excludeNotInPsc:  "Không còn ở group PSC",
}

var (
	errStartClosed   = &HTTPError{Status: http.StatusConflict, Code: "game_running", Message: "Ván đã bắt đầu hoặc đã kết thúc."}
	errGameNotActive = &HTTPError{Status: http.StatusConflict, Code: "invalid_state", Message: "Ván đã kết thúc hoặc đã huỷ."}
)

// roleWeight là điểm "Village Team Impact" kiểu Ultimate Werewolf: dương có
// lợi cho Dân, âm có lợi cho Sói. Các số này chưa đối chiếu với lá bài in, chỉ
// để admin so các bộ vai với nhau, không ảnh hưởng luật.
var roleWeight = map[werewolf.Role]int{
	werewolf.Villager: 1, werewolf.Wolf: -6, werewolf.Seer: 7, werewolf.Guard: 3,
	werewolf.Witch: 4, werewolf.Hunter: 3, werewolf.Cupid: -3,
}

func balanceScore(roles []werewolf.Role) int {
	sum := 0
	for _, r := range roles {
		sum += roleWeight[r]
	}
	return sum
}

type StartPreview struct {
	WillExclude  []StartExcluded `json:"willExclude"`
	Players      []StartPlayer   `json:"players"`
	Count        int             `json:"count"`
	MinPlayers   int             `json:"minPlayers"`
	MaxPlayers   int             `json:"maxPlayers"`
	CanStart     bool            `json:"canStart"`
	BalanceScore *int            `json:"balanceScore"`
}

type StartExcluded struct {
	UID         string `json:"uid"`
	Name        string `json:"name"`
	Reason      string `json:"reason"`
	ReasonLabel string `json:"reasonLabel"`
}

type StartPlayer struct {
	UID        string `json:"uid"`
	Name       string `json:"name"`
	TgUsername string `json:"tgUsername,omitempty"`
	Fake       bool   `json:"fake,omitempty"`
}

type GameStartError struct {
	Code    string    `json:"code"`
	Message string    `json:"message"`
	At      time.Time `json:"at"`
}

func startErrorOf(g map[string]any) *GameStartError {
	raw, ok := g["startError"].(map[string]any)
	if !ok {
		return nil
	}
	return &GameStartError{Code: stringValue(raw["code"]), Message: stringValue(raw["message"]), At: timeValue(raw["at"])}
}

// startCandidate là một người đã đăng ký cùng liên kết Telegram hiện tại.
// reason rỗng là đạt.
type startCandidate struct {
	player gamePlayerInfo
	link   viewerLink
	reason string
}

// readStartGame đọc ván cho các lệnh admin; id sai dạng hay không có thì 404.
func (s *GameStore) readStartGame(ctx context.Context, gameID string) (*firestore.DocumentSnapshot, error) {
	if gameID == "" || len(gameID) > 64 {
		return nil, errGameNotFound
	}
	g, err := s.gameRef(gameID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, errGameNotFound
	}
	return g, err
}

// startCandidates xét từng người đã đăng ký theo liên kết đang lưu: liên kết
// có thể đã đổi hay bị huỷ từ lúc đăng ký. Người giả luôn đạt.
func (s *GameStore) startCandidates(ctx context.Context, game *firestore.DocumentRef) ([]startCandidate, error) {
	players, err := s.loadPlayers(ctx, game)
	if err != nil {
		return nil, err
	}
	out := make([]startCandidate, 0, len(players))
	for _, p := range players {
		c := startCandidate{player: p}
		if !p.fake {
			if c.link, err = s.readLink(ctxGetter(ctx), p.uid); err != nil {
				return nil, err
			}
			switch {
			case !c.link.linked:
				c.reason = excludeNotLinked
			case !c.link.inPsc:
				c.reason = excludeNotInPsc
			}
		}
		out = append(out, c)
	}
	return out, nil
}

func previewOf(cands []startCandidate, cfg werewolf.Config) StartPreview {
	out := StartPreview{WillExclude: []StartExcluded{}, Players: []StartPlayer{}, MinPlayers: werewolf.MinPlayers, MaxPlayers: werewolf.MaxPlayers}
	for _, c := range cands {
		if c.reason != "" {
			out.WillExclude = append(out.WillExclude, StartExcluded{UID: c.player.uid, Name: c.player.name, Reason: c.reason, ReasonLabel: excludeLabels[c.reason]})
			continue
		}
		out.Players = append(out.Players, StartPlayer{UID: c.player.uid, Name: c.player.name, TgUsername: c.link.username, Fake: c.player.fake})
	}
	out.Count = len(out.Players)
	if roles, err := werewolf.Composition(out.Count, cfg); err == nil {
		score := balanceScore(roles)
		out.CanStart, out.BalanceScore = true, &score
	}
	return out
}

func gameConfigOf(g map[string]any) (werewolf.Config, error) {
	var cfg werewolf.Config
	if err := json.Unmarshal([]byte(stringValue(g["config"])), &cfg); err != nil {
		return cfg, fmt.Errorf("đọc config của ván: %w", err)
	}
	return cfg, nil
}

// StartPreview là dryRun của Start: ai sẽ bị loại và vì sao, bảng uid ↔ @tg để
// admin soát. Theo inPsc đang lưu; lúc Start thật bot hỏi lại Telegram.
func (s *GameStore) StartPreview(ctx context.Context, gameID string) (StartPreview, error) {
	g, err := s.readStartGame(ctx, gameID)
	if err != nil {
		return StartPreview{}, err
	}
	if st := stringValue(g.Data()["status"]); st != gameRegistering && st != gameStarting {
		return StartPreview{}, errStartClosed
	}
	cfg, err := gameConfigOf(g.Data())
	if err != nil {
		return StartPreview{}, err
	}
	cands, err := s.startCandidates(ctx, g.Ref)
	if err != nil {
		return StartPreview{}, err
	}
	return previewOf(cands, cfg), nil
}

// RequestStart đặt status=starting và trả số lần Start, để TaskID của mỗi lần
// một khác: Cloud Tasks giữ tên task đã chạy một thời gian, dùng lại tên cũ thì
// lần Start sau khi bot trả về đăng ký sẽ không được tạo. Đang starting mà gọi
// lại (enqueue lần trước lỗi) thì được; bot chỉ chạy khi còn starting, nên hai
// task cùng chạy thì một bên thấy ván đã chạy và thôi.
func (s *GameStore) RequestStart(ctx context.Context, gameID, by string, wall time.Time) (int64, error) {
	preview, err := s.StartPreview(ctx, gameID)
	if err != nil {
		return 0, err
	}
	if preview.Count < werewolf.MinPlayers {
		return 0, &HTTPError{Status: http.StatusUnprocessableEntity, Code: "not_enough_players",
			Message: fmt.Sprintf("Mới có %d người đủ điều kiện, cần ít nhất %d.", preview.Count, werewolf.MinPlayers),
			Extra:   map[string]any{"count": preview.Count, "willExclude": preview.WillExclude}}
	}
	game := s.gameRef(gameID)
	var attempt int64
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		if st := stringValue(g.Data()["status"]); st != gameRegistering && st != gameStarting {
			return errStartClosed
		}
		attempt = int64(number(g.Data()["startAttempt"])) + 1
		return tx.Update(game, []firestore.Update{
			{Path: "status", Value: gameStarting}, {Path: "startAttempt", Value: attempt},
			{Path: "startRequestedBy", Value: by}, {Path: "startRequestedAt", Value: wall},
			{Path: "startError", Value: nil}, {Path: "version", Value: firestore.Increment(1)},
			{Path: "updatedAt", Value: wall},
		})
	})
	return attempt, err
}

// gameStartTask là payload của /tasks/game-start. Bot decode chặt, nên thêm
// field thì deploy bot trước.
type gameStartTask struct {
	GameID  string `json:"gameId"`
	Attempt int64  `json:"attempt"`
}

func gameStartTaskFor(gameID string, attempt int64) PublishTask {
	return PublishTask{
		Queue: QueueGameInbound, HandlerPath: "/tasks/game-start",
		Payload: gameStartTask{GameID: gameID, Attempt: attempt},
		TaskID:  StableTaskID("gamestart", []any{gameID, attempt}),
	}
}

// StartOutcome là việc game-start đã làm.
type StartOutcome struct {
	Result   string          `json:"result"` // started | reverted | skipped
	Players  int             `json:"players"`
	Excluded []StartExcluded `json:"excluded"`
}

// pscMembership hỏi Telegram một tg có đang ở PSC không, và ghi lại kết quả.
type pscMembership func(ctx context.Context, tgUserID int64) (bool, error)

// RunStart là phần của bot trong Start. Ván không còn starting (đã chạy, admin
// huỷ, hay task chạy lại) thì thôi. Telegram lỗi thì trả lỗi để task retry, không
// đoán là người đó đã rời nhóm.
func (s *GameStore) RunStart(ctx context.Context, gameID string, inPsc pscMembership, wall time.Time) (StartOutcome, error) {
	out := StartOutcome{Result: "skipped", Excluded: []StartExcluded{}}
	g, err := s.readStartGame(ctx, gameID)
	if errors.Is(err, errGameNotFound) {
		return out, nil
	}
	if err != nil {
		return out, err
	}
	if stringValue(g.Data()["status"]) != gameStarting {
		return out, nil
	}
	cands, err := s.startCandidates(ctx, g.Ref)
	if err != nil {
		return out, err
	}
	roster := &startRoster{tgUserID: map[string]int64{}}
	var uids []string
	for _, c := range cands {
		if c.link.linked {
			ok, err := inPsc(ctx, c.link.tgUserID)
			if err != nil {
				return out, err
			}
			c.reason = ""
			if !ok {
				c.reason = excludeNotInPsc
			}
			roster.tgUserID[c.player.uid] = c.link.tgUserID
		}
		if c.reason != "" {
			roster.exclude = append(roster.exclude, c.player.uid)
			out.Excluded = append(out.Excluded, StartExcluded{UID: c.player.uid, Name: c.player.name, Reason: c.reason, ReasonLabel: excludeLabels[c.reason]})
			continue
		}
		uids = append(uids, c.player.uid)
	}
	out.Players = len(uids)
	if len(uids) < werewolf.MinPlayers || len(uids) > werewolf.MaxPlayers {
		msg := fmt.Sprintf("Lúc chia bài chỉ còn %d người đủ điều kiện, cần từ %d tới %d.", len(uids), werewolf.MinPlayers, werewolf.MaxPlayers)
		return s.revertStart(ctx, g.Ref, "not_enough_players", msg, out, wall)
	}
	seed, err := werewolf.NewSeed()
	if err != nil {
		return out, err
	}
	st, err := s.NewStartState(ctx, gameID, uids, seed, wall)
	if err != nil {
		if _, isRPC := status.FromError(err); isRPC || ctx.Err() != nil {
			return out, err
		}
		// Bộ vai ép của ván thử không vừa số người, hay config hỏng: chạy lại task
		// cũng vậy, nên trả về đăng ký cho admin sửa.
		return s.revertStart(ctx, g.Ref, "deal_failed", "Không chia được bài: "+err.Error(), out, wall)
	}
	err = s.startGame(ctx, gameID, st, roster, wall)
	var he *HTTPError
	if errors.As(err, &he) && he.Code == errStartClosed.Code {
		return out, nil
	}
	if err != nil {
		return out, err
	}
	out.Result = "started"
	return out, nil
}

// revertStart đưa ván từ starting về registering kèm lý do. Ván đã rời starting
// (task khác đã Start, admin huỷ) thì không đụng.
func (s *GameStore) revertStart(ctx context.Context, game *firestore.DocumentRef, code, msg string, out StartOutcome, wall time.Time) (StartOutcome, error) {
	reverted := false
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		reverted = false
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		if stringValue(g.Data()["status"]) != gameStarting {
			return nil
		}
		reverted = true
		return tx.Update(game, []firestore.Update{
			{Path: "status", Value: gameRegistering},
			{Path: "startError", Value: map[string]any{"code": code, "message": msg, "at": wall}},
			{Path: "version", Value: firestore.Increment(1)}, {Path: "updatedAt", Value: wall},
		})
	})
	if err != nil {
		return out, err
	}
	if reverted {
		out.Result = "reverted"
		slog.WarnContext(ctx, "game.start_reverted", "gameId", game.ID, "code", code, "players", out.Players, "excluded", len(out.Excluded))
	}
	return out, nil
}

// ---- Lệnh admin: pause, resume, cancel ----

const tplAdmin = "admin" // group: admin tạm dừng, chạy tiếp hay huỷ ván

// AdminPause và AdminResume đóng băng hay mở lại ván đang chạy (R14). Không ghi
// feed. Event pause/resume mang at (giờ ván), replay chạy lại Pause/Resume theo đó.
func (s *GameStore) AdminPause(ctx context.Context, gameID, by string, wall time.Time) error {
	return s.adminSetPaused(ctx, gameID, by, true, wall)
}

func (s *GameStore) AdminResume(ctx context.Context, gameID, by string, wall time.Time) error {
	return s.adminSetPaused(ctx, gameID, by, false, wall)
}

func (s *GameStore) adminSetPaused(ctx context.Context, gameID, by string, pause bool, wall time.Time) error {
	action := "pause"
	if !pause {
		action = "resume"
	}
	return s.adminUpdate(ctx, gameID, wall, map[string]any{"kind": action, "by": by}, func(st *werewolf.State, now time.Time) (*werewolf.State, map[string]any, error) {
		if pause {
			next, err := werewolf.Pause(st)
			if errors.Is(err, werewolf.ErrPauseState) {
				return nil, nil, &HTTPError{Status: http.StatusConflict, Code: "invalid_state", Message: "Ván đang tạm dừng rồi."}
			}
			return next, map[string]any{"action": action}, err
		}
		next, err := werewolf.Resume(st, now)
		if errors.Is(err, werewolf.ErrPauseState) {
			return nil, nil, &HTTPError{Status: http.StatusConflict, Code: "invalid_state", Message: "Ván không tạm dừng."}
		}
		if err != nil {
			return nil, nil, err
		}
		return next, map[string]any{"action": action, "deadline": next.Deadline().UTC().Format(time.RFC3339)}, nil
	})
}

// maxExtendMinutes chặn số phút gõ nhầm (/extend 3000); engine còn chặn theo lượt sau.
const maxExtendMinutes = 240

// AdminExtend dời hạn lượt đang mở thêm minutes phút (werewolf.Extend). Event
// extend mang minutes, replay chạy lại Extend. Không ghi feed; group nhận tin admin.
func (s *GameStore) AdminExtend(ctx context.Context, gameID, by string, minutes int, wall time.Time) error {
	return s.adminUpdate(ctx, gameID, wall, map[string]any{"kind": "extend", "by": by, "minutes": minutes}, func(st *werewolf.State, _ time.Time) (*werewolf.State, map[string]any, error) {
		next, err := werewolf.Extend(st, time.Duration(minutes)*time.Minute)
		var tooLong *werewolf.ExtendTooLong
		switch {
		case errors.As(err, &tooLong):
			msg := "Lượt sau cần ít nhất 1 giờ nên không dời thêm được nữa."
			if m := int(tooLong.Max / time.Minute); m > 0 {
				msg = fmt.Sprintf("Chỉ dời thêm được tối đa %d phút, để lượt sau còn ít nhất 1 giờ.", m)
			}
			return nil, nil, &HTTPError{Status: http.StatusUnprocessableEntity, Code: "extend_too_long", Message: msg}
		case err != nil:
			return nil, nil, err
		}
		return next, map[string]any{"action": "extend", "minutes": minutes, "deadline": next.TurnClose().UTC().Format(time.RFC3339)}, nil
	})
}

// adminUpdate chạy một lệnh admin đổi state của ván đang chạy: change trả state
// mới và data của tin admin gửi group. event ghi vào events (kèm at, để replay).
func (s *GameStore) adminUpdate(ctx context.Context, gameID string, wall time.Time, event map[string]any, change func(st *werewolf.State, now time.Time) (*werewolf.State, map[string]any, error)) error {
	if _, err := s.readStartGame(ctx, gameID); err != nil {
		return err
	}
	game := s.gameRef(gameID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		if stringValue(g.Data()["status"]) != gameRunning {
			return &HTTPError{Status: http.StatusConflict, Code: "invalid_state", Message: "Ván không đang chạy."}
		}
		sec, err := tx.Get(secretRef(game))
		if err != nil {
			return err
		}
		st, err := decodeState(sec.Data())
		if err != nil {
			return err
		}
		now := gameNow(g.Data(), wall)
		next, data, err := change(st, now)
		if err != nil {
			return err
		}
		msgs := []gameMsg{{ChatKey: chatGroup, Template: tplAdmin, Data: data}}
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		w := stepWrite{tx: tx, game: game, gameData: g.Data(), after: next, msgs: msgs, chats: chats, now: now, wall: wall}
		return w.commit(event)
	})
}

// AdminCancel huỷ ván chưa kết thúc, ở bất kỳ trạng thái nào. Huỷ lúc đang
// starting thì task game-start chạy sau thấy ván không còn starting và thôi.
func (s *GameStore) AdminCancel(ctx context.Context, gameID, by string, wall time.Time) error {
	if _, err := s.readStartGame(ctx, gameID); err != nil {
		return err
	}
	game := s.gameRef(gameID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		if gameClosed(stringValue(g.Data()["status"])) {
			return errGameNotActive
		}
		msgs := []gameMsg{{ChatKey: chatGroup, Template: tplAdmin, Data: map[string]any{"action": "cancel"}}}
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		eventSeq := int64(number(g.Data()["eventSeq"])) + 1
		if err := tx.Create(game.Collection("events").Doc(fmt.Sprint(eventSeq)), map[string]any{
			"kind": "cancel", "by": by, "seq": eventSeq, "at": gameNow(g.Data(), wall), "wallAt": wall,
		}); err != nil {
			return err
		}
		if err := tx.Update(game, []firestore.Update{
			{Path: "status", Value: gameCancelled}, {Path: "cancelledBy", Value: by}, {Path: "cancelledAt", Value: wall},
			{Path: "deadline", Value: nil}, {Path: "nextAt", Value: nil}, {Path: "eventSeq", Value: eventSeq},
			{Path: "version", Value: firestore.Increment(1)}, {Path: "updatedAt", Value: wall},
		}); err != nil {
			return err
		}
		w := stepWrite{tx: tx, game: game, msgs: msgs, chats: chats, wall: wall}
		return w.writeOutbox(eventSeq)
	})
}
