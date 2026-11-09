//go:build emulator

package backend

import (
	"context"
	"errors"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Kỹ năng xét km 24 tiếng tới lúc bấm, không phải km của lần chốt trước. Bấm lúc
// 23:10 thì khung là 0h hôm đó tới 0h hôm sau; lần chốt 22h ghi 0 km cho mọi người.
func TestEmulatorSkillUsesKmAtUse(t *testing.T) {
	g := newStoreGame(t)
	lockedKm := func(context.Context, string, time.Time, time.Time) (FrameKm, error) { return FrameKm{}, nil }
	g.store.frameKm = lockedKm
	night := time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam)
	g.advance(night)
	if g.state().Km["guard"] != 0 {
		t.Fatalf("km chốt của bảo vệ = %v", g.state().Km["guard"])
	}

	bấm := night.Add(70 * time.Minute)
	recentEnd := time.Date(2026, 10, 16, 0, 0, 0, 0, vietnam)
	g.store.frameKm = func(_ context.Context, uid string, start, end time.Time) (FrameKm, error) {
		if end.Equal(recentEnd) && start.Equal(recentEnd.Add(-24*time.Hour)) && uid == "guard" {
			return FrameKm{Meters: 1000}, nil
		}
		return FrameKm{}, nil
	}
	ctx := context.Background()
	res, err := g.store.SubmitAction(ctx, ActionRequest{GameID: g.id, UID: "guard", Kind: ww.KindGuard, Targets: []string{"v1"}, ReceivedAt: bấm})
	if err != nil || res.Reject != nil {
		t.Fatalf("bảo vệ đủ km lúc bấm: %v, %v", err, res.Reject)
	}
	res, err = g.store.SubmitAction(ctx, ActionRequest{GameID: g.id, UID: "seer", Kind: ww.KindSeerPeek, Targets: []string{"v1"}, ReceivedAt: bấm})
	if err != nil || !errors.Is(res.Reject, ww.ErrKmInsufficient) {
		t.Fatalf("tiên tri thiếu km lúc bấm: %v, %v", err, res.Reject)
	}

	// Km đã chốt vẫn là 0, nhưng lúc chốt không xét lại.
	g.store.frameKm = lockedKm
	g.advance(recentEnd)
	g.advance(recentEnd.Add(10 * time.Hour))
	if g.state().LastGuarded != "v1" {
		t.Fatalf("LastGuarded = %q, mong đợi v1", g.state().LastGuarded)
	}
}

// Đọc km lỗi thì trả lỗi, không coi là thiếu km.
func TestEmulatorSkillKmReadErrorIsNotReject(t *testing.T) {
	g := newStoreGame(t)
	night := time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam)
	g.advance(night)
	boom := errors.New("firestore hỏng")
	g.store.frameKm = func(context.Context, string, time.Time, time.Time) (FrameKm, error) { return FrameKm{}, boom }
	res, err := g.store.SubmitAction(context.Background(), ActionRequest{GameID: g.id, UID: "guard", Kind: ww.KindGuard, Targets: []string{"v1"}, ReceivedAt: night.Add(time.Hour)})
	if !errors.Is(err, boom) || res.Reject != nil {
		t.Fatalf("err = %v, reject = %v", err, res.Reject)
	}
}

// Cắn xét km 24 tiếng tới lúc chốt cắn: khung 0h tới 0h, lấy một lần rồi ghi lại.
func TestEmulatorBiteUsesKmAtLock(t *testing.T) {
	g := newStoreGame(t)
	g.store.frameKm = func(context.Context, string, time.Time, time.Time) (FrameKm, error) { return FrameKm{}, nil }
	night := time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam)
	g.advance(night)

	lock := time.Date(2026, 10, 16, 0, 0, 0, 0, vietnam)
	g.act(1, ww.KindWolfBite, "w1", night.Add(time.Hour), "v1")
	g.store.frameKm = func(_ context.Context, uid string, start, end time.Time) (FrameKm, error) {
		if end.Equal(lock) && start.Equal(lock.Add(-24*time.Hour)) && (uid == "w1" || uid == "w2") {
			return FrameKm{Meters: 5000}, nil
		}
		return FrameKm{}, nil
	}
	g.advance(lock)
	if st := g.state(); st.Bitten != "v1" || st.Phase != ww.PhaseDawn {
		t.Fatalf("bitten = %q, phase = %s", st.Bitten, st.Phase)
	}
	snap, err := g.ref("rounds/1/biteKm/w1").Get(context.Background())
	if err != nil || number(snap.Data()["meters"]) != 5000 {
		t.Fatalf("snapshot cắn: %v, %v", snap, err)
	}
}
