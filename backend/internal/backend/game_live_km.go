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
// một lần, mỗi người chơi tốn ba lần đọc (LoadFrameKm), nên cả ván dùng chung
// một bản tính và chỉ tính lại sau mốc này.
const liveKmMaxAge = 5 * time.Minute

// liveKm là km khung 22h tới của người còn sống, theo mét, tính lúc AsOf (giờ
// của ván).
type liveKm struct {
	AsOf     time.Time          `firestore:"asOf"`
	FrameEnd time.Time          `firestore:"frameEnd"`
	Meters   map[string]float64 `firestore:"meters"`
}

// metersOf là km sống của uid; nil-safe để chỗ gọi không phải tách ván thử.
func (l *liveKm) metersOf(uid string) (float64, bool) {
	if l == nil {
		return 0, false
	}
	m, ok := l.Meters[uid]
	return m, ok
}

func liveKmRef(game *firestore.DocumentRef) *firestore.DocumentRef {
	return game.Collection("live").Doc("km")
}

// liveKm đọc bản giữ ở games/{id}/live/km, hoặc tính lại cho mọi người còn sống
// khi bản đó cũ quá liveKmMaxAge, thuộc khung khác, hay thiếu người. Nil khi
// ván không chạy hoặc là ván thử, vì ván thử không đọc buổi chạy thật
// (snapshotKmIfDue). Hai request cùng tính lại thì cùng ghi một kết quả.
func (s *GameStore) liveKm(ctx context.Context, game *firestore.DocumentRef, data map[string]any, st *werewolf.State, wall time.Time) (*liveKm, error) {
	if st == nil || data["testMode"] == true || stringValue(data["status"]) != gameRunning {
		return nil, nil
	}
	now := gameNow(data, wall)
	end := nextKmFrameEnd(now)
	var alive []string
	for _, uid := range sortedPlayers(st) {
		if st.Players[uid].Alive {
			alive = append(alive, uid)
		}
	}
	snap, err := liveKmRef(game).Get(ctx)
	switch {
	case status.Code(err) == codes.NotFound:
	case err != nil:
		return nil, err
	default:
		var kept liveKm
		if err := snap.DataTo(&kept); err != nil {
			return nil, err
		}
		if kept.FrameEnd.Equal(end) && now.Sub(kept.AsOf) < liveKmMaxAge && hasAllKeys(kept.Meters, alive) {
			return &kept, nil
		}
	}

	out := liveKm{AsOf: now, FrameEnd: end, Meters: make(map[string]float64, len(alive))}
	var mu sync.Mutex
	group, gctx := errgroup.WithContext(ctx)
	group.SetLimit(8)
	for _, uid := range alive {
		group.Go(func() error {
			fk, err := s.frameKm(gctx, uid, end)
			if err != nil {
				return fmt.Errorf("km của %s: %w", uid, err)
			}
			mu.Lock()
			out.Meters[uid] = fk.Meters
			mu.Unlock()
			return nil
		})
	}
	if err := group.Wait(); err != nil {
		return nil, err
	}
	if _, err := liveKmRef(game).Set(ctx, out); err != nil {
		return nil, err
	}
	return &out, nil
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
	if st == nil || stringValue(data["status"]) != gameRunning {
		return nil
	}
	now := gameNow(data, wall).In(vietnam)
	end := nextKmFrameEnd(now)
	t := &GameKmTable{
		LastLabel: "Hôm qua · chốt 22h",
		UnitKm:    kmPerUnit(st.Config),
		Note:      "Km chốt lúc 22h, dùng cho biểu quyết và kỹ năng đêm ngay sau đó. Chạy xong mở app để km kịp đồng bộ.",
	}
	if sameDate(end.AddDate(0, 0, -1), now) {
		t.LastLabel = "Hôm nay · chốt 22h"
	}
	if live == nil {
		t.TodayLabel, t.Note = "Hôm nay", "Ván thử không đọc km chạy thật."
		return t
	}
	at := live.AsOf.In(vietnam)
	t.AsOf = &at
	t.TodayLabel = "Hôm nay · tới " + at.Format("15:04")
	if !sameDate(end, now) {
		t.TodayLabel = "Từ 22h nay · tới " + at.Format("15:04")
	}
	return t
}

func sameDate(a, b time.Time) bool {
	ay, am, ad := a.In(vietnam).Date()
	by, bm, bd := b.In(vietnam).Date()
	return ay == by && am == bm && ad == bd
}

// wolfTeamKm là km của phe Sói cho một sói còn sống: tổng km chốt 22h gần nhất,
// tổng km đang gom, và mức cần để cắn (WolfKm). Today nil ở ván thử.
func (s *GameStore) wolfTeamKm(ctx context.Context, game *firestore.DocumentRef, data map[string]any, st *werewolf.State, wall time.Time) (*GameTeamKm, error) {
	have, need := werewolf.WolfKm(st)
	out := &GameTeamKm{Label: "Km phe Sói", Last: have / 1000, Need: need / 1000, NeedLabel: "Cần " + formatKm(need/1000) + " km để cắn"}
	live, err := s.liveKm(ctx, game, data, st, wall)
	if err != nil {
		return nil, err
	}
	if live == nil {
		return out, nil
	}
	var today float64
	for _, uid := range sortedPlayers(st) {
		if p := st.Players[uid]; p.Alive && p.Role == werewolf.Wolf {
			today += live.Meters[uid]
		}
	}
	today /= 1000
	out.Today = &today
	return out, nil
}
