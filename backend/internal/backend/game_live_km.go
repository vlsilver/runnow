package backend

import (
	"context"
	"fmt"
	"sync"
	"time"

	"cloud.google.com/go/firestore"
	"golang.org/x/sync/errgroup"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// liveKmMaxAge là tuổi tối đa của km sống đã giữ. App poll Detail 15–300 giây
// một lần, mỗi người chơi tốn sáu lần đọc (hai lần LoadFrameKm), nên cả ván dùng
// chung một bản tính và chỉ tính lại sau mốc này.
const liveKmMaxAge = time.Minute

// liveKm là km của người còn sống theo mét, tính lúc AsOf (giờ của ván). Meters
// là km khung đang gom tới lần chốt phiếu kế tiếp; Recent là km 24 tiếng tới lúc
// này (werewolf.KmFrameUntil), số xét kỹ năng.
type liveKm struct {
	AsOf      time.Time          `firestore:"asOf"`
	FrameEnd  time.Time          `firestore:"frameEnd"`
	Meters    map[string]float64 `firestore:"meters"`
	RecentEnd time.Time          `firestore:"recentEnd"`
	Recent    map[string]float64 `firestore:"recent"`
}

// metersOf là km sống của uid; nil-safe để chỗ gọi không phải tách ván thử.
func (l *liveKm) metersOf(uid string) (float64, bool) {
	if l == nil {
		return 0, false
	}
	m, ok := l.Meters[uid]
	return m, ok
}

// recentOf là km 24 tiếng tới lúc này của uid; nil-safe như metersOf.
func (l *liveKm) recentOf(uid string) (float64, bool) {
	if l == nil {
		return 0, false
	}
	m, ok := l.Recent[uid]
	return m, ok
}

// skillView là st nhìn theo km 24 tiếng tới lúc này, để xét kỹ năng. checked
// false khi không có km sống (ván thử, ván tắt km): lúc đó xét km đã chốt.
func (l *liveKm) skillView(st *werewolf.State) (view *werewolf.State, checked bool) {
	if l == nil {
		return st, false
	}
	return st.WithKm(l.Recent), true
}

func liveKmRef(game *firestore.DocumentRef) *firestore.DocumentRef {
	return game.Collection("live").Doc("km")
}

// liveKm đọc bản giữ ở games/{id}/live/km, hoặc tính lại cho mọi người còn sống
// khi bản đó cũ quá liveKmMaxAge, thuộc khung khác, hay thiếu người. Nil khi
// ván không chạy hoặc là ván thử, vì ván thử không đọc buổi chạy thật
// (snapshotKmIfDue). Hai request cùng tính lại thì cùng ghi một kết quả.
func (s *GameStore) liveKm(ctx context.Context, game *firestore.DocumentRef, data map[string]any, st *werewolf.State, wall time.Time) (*liveKm, error) {
	if st == nil || data["testMode"] == true || st.Config.KmOff || stringValue(data["status"]) != gameRunning {
		return nil, nil
	}
	now := gameNow(data, wall)
	frame, recent := st.Config.KmFrameAt(now), werewolf.KmFrameUntil(now)
	var uids []string
	for _, uid := range sortedPlayers(st) {
		// Thợ săn đã ngã vẫn cần km để bắn.
		if st.Players[uid].Alive || (st.Hunter != nil && st.Hunter.UID == uid) {
			uids = append(uids, uid)
		}
	}
	kept, err := readLiveKm(ctx, game)
	if err != nil {
		return nil, err
	}
	if kept != nil && kept.FrameEnd.Equal(frame.End) && kept.RecentEnd.Equal(recent.End) && now.Sub(kept.AsOf) < liveKmMaxAge &&
		hasAllKeys(kept.Meters, uids) && hasAllKeys(kept.Recent, uids) {
		return kept, nil
	}

	out := liveKm{AsOf: now, FrameEnd: frame.End, RecentEnd: recent.End}
	if out.Meters, err = s.metersIn(ctx, uids, frame); err != nil {
		return nil, err
	}
	if out.Recent, err = s.metersIn(ctx, uids, recent); err != nil {
		return nil, err
	}
	if _, err := liveKmRef(game).Set(ctx, out); err != nil {
		return nil, err
	}
	return &out, nil
}

// readLiveKm trả nil khi chưa có bản giữ nào.
func readLiveKm(ctx context.Context, game *firestore.DocumentRef) (*liveKm, error) {
	snap, err := liveKmRef(game).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var kept liveKm
	if err := snap.DataTo(&kept); err != nil {
		return nil, err
	}
	return &kept, nil
}

// metersIn đọc km khung frame của từng uid, song song có giới hạn.
func (s *GameStore) metersIn(ctx context.Context, uids []string, frame werewolf.KmFrame) (map[string]float64, error) {
	out := make(map[string]float64, len(uids))
	var mu sync.Mutex
	group, gctx := errgroup.WithContext(ctx)
	group.SetLimit(8)
	for _, uid := range uids {
		group.Go(func() error {
			fk, err := s.frameKm(gctx, uid, frame.Start, frame.End)
			if err != nil {
				return fmt.Errorf("km của %s: %w", uid, err)
			}
			mu.Lock()
			out[uid] = fk.Meters
			mu.Unlock()
			return nil
		})
	}
	if err := group.Wait(); err != nil {
		return nil, err
	}
	return out, nil
}

func hasAllKeys(m map[string]float64, keys []string) bool {
	for _, k := range keys {
		if _, ok := m[k]; !ok {
			return false
		}
	}
	return true
}

// kmTable là đầu cột và chú thích của bảng km trong app. Server ghi chữ để đổi
// cách gọi mà không phải ra bản app mới.
func kmTable(data map[string]any, st *werewolf.State, live *liveKm, wall time.Time) *GameKmTable {
	if st == nil || st.Config.KmOff || stringValue(data["status"]) != gameRunning {
		return nil
	}
	now := gameNow(data, wall).In(vietnam)
	frame := st.Config.KmFrameAt(now)
	closes := hm(frame.End)
	lastClose := st.Config.LastKmClose(frame)
	t := &GameKmTable{
		LastLabel: "Hôm qua · chốt " + hm(lastClose),
		UnitKm:    kmPerUnit(st.Config),
		Note:      "Biểu quyết tính km tới " + closes + ", kỹ năng tính 24 tiếng tới lúc dùng. Chạy xong mở app để km kịp đồng bộ.",
	}
	switch st.Config.VoteMode() {
	case werewolf.VoteFlat:
		t.Note = "Kỹ năng tính km 24 tiếng tới lúc dùng. Chạy xong mở app để km kịp đồng bộ."
	case werewolf.VoteTop:
		t.UnitLabel = "tranh x2 phiếu"
	case werewolf.VoteCut:
		// Đủ mốc thì chắc giữ phiếu; dưới mốc chỉ mất khi tổng km không đủ
		// phiếu cho mọi người (PlanVoteCut).
		t.UnitLabel = "giữ phiếu"
		t.CutLabel = "Dưới " + formatKm(t.UnitKm) + " km · có thể mất phiếu"
	case werewolf.VoteSolo:
		t.UnitLabel = "giữ phiếu"
		t.CutLabel = "Dưới " + formatKm(t.UnitKm) + " km · mất phiếu"
	}
	if sameDate(lastClose, now) {
		t.LastLabel = "Hôm nay · chốt " + hm(lastClose)
	}
	if live == nil {
		t.TodayLabel, t.Note = "Hôm nay", "Ván thử không đọc km chạy thật."
		return t
	}
	at := live.AsOf.In(vietnam)
	t.AsOf = &at
	t.TodayLabel = "Hôm nay · tới " + at.Format("15:04")
	if !sameDate(frame.End, now) || st.Config.RoundLen() < werewolf.KmFrameLen {
		startDay := "qua"
		if sameDate(frame.Start, now) {
			startDay = "nay"
		}
		t.TodayLabel = "Từ " + hm(frame.Start) + " " + startDay + " · tới " + at.Format("15:04")
	}
	return t
}

// liveVoteTags là nhãn "x2" của những người đang trong suất Top theo km đang
// gom. Đây là dự đoán: lúc chốt engine còn trừ người lên giàn của từng phiên.
// Ván không có suất Top hay không có km sống (ván thử) thì không ai có nhãn.
func liveVoteTags(st *werewolf.State, live *liveKm) map[string]string {
	if st == nil || live == nil || st.Config.KmOff {
		return nil
	}
	weight := cardTopWeight(st.Config)
	if weight == 0 {
		return nil
	}
	var voters []string
	for _, uid := range sortedPlayers(st) {
		if st.Players[uid].Alive && st.CanVote(uid) {
			voters = append(voters, uid)
		}
	}
	var cut map[string]bool
	if mode := st.Config.VoteMode(); mode == werewolf.VoteCut || mode == werewolf.VoteSolo {
		plan := werewolf.PlanVoteCut(voters, live.Meters, st.Config)
		cut, _ = tallyCut(plan, func([]string) string { return "" }, "", "")
	}
	_, top := voteTopPlan(st, voters, cut, live.Meters)
	tags := make(map[string]string, len(top))
	for _, uid := range top {
		tags[uid] = fmt.Sprintf("x%d", weight)
	}
	return tags
}

func sameDate(a, b time.Time) bool {
	ay, am, ad := a.In(vietnam).Date()
	by, bm, bd := b.In(vietnam).Date()
	return ay == by && am == bm && ad == bd
}

// wolfTeamKm là km của phe Sói cho một sói còn sống: tổng km chốt gần nhất, tổng
// km 24 tiếng tới lúc này (live, nil ở ván thử thì Today nil), và mức cần để
// cắn (WolfKm). Phe cắn không cần km thì nil.
func wolfTeamKm(st *werewolf.State, live *liveKm) *GameTeamKm {
	have, need := werewolf.WolfKm(st)
	if need == 0 {
		return nil
	}
	out := &GameTeamKm{Label: "Km phe Sói", Last: have / 1000, Need: need / 1000, NeedLabel: "Cần " + formatKm(need/1000) + " km để cắn"}
	if live == nil {
		return out
	}
	var today float64
	for _, uid := range sortedPlayers(st) {
		if p := st.Players[uid]; p.Alive && p.Role == werewolf.Wolf {
			today += live.Recent[uid]
		}
	}
	today /= 1000
	out.Today = &today
	return out
}
