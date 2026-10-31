//go:build emulator

package backend

import (
	"context"
	"fmt"
	"sync/atomic"
	"testing"
	"time"
)

// Bảng km trong app: km tới giờ của người còn sống lấy từ games/{id}/live/km,
// chỉ tính lại khi bản giữ đã cũ 5 phút; sói thấy thêm km của phe trong /me.
func TestEmulatorDetailLiveKmCached(t *testing.T) {
	g := newStoreGame(t)
	g.advance(time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam)) // chốt 5 km mỗi người
	var calls atomic.Int32
	live := map[string]float64{"w1": 1200, "w2": 300, "v1": 2500}
	g.store.frameKm = func(_ context.Context, uid string, end time.Time) (FrameKm, error) {
		calls.Add(1)
		if !end.Equal(time.Date(2026, 10, 16, 22, 0, 0, 0, vietnam)) {
			return FrameKm{}, fmt.Errorf("khung %v", end)
		}
		return FrameKm{FrameEnd: end, Meters: live[uid]}, nil
	}
	ctx := context.Background()
	at := time.Date(2026, 10, 16, 15, 40, 0, 0, vietnam)
	detail := func(wall time.Time) GameDetail {
		t.Helper()
		d, err := g.store.Detail(ctx, g.id, GameViewer{UID: "v1"}, wall)
		if err != nil {
			t.Fatal(err)
		}
		return d
	}
	km := func(d GameDetail, uid string) (last, today string) {
		for _, p := range d.Players {
			if p.UID == uid {
				if p.LastKm != nil {
					last = fmt.Sprint(*p.LastKm)
				}
				if p.TodayKm != nil {
					today = fmt.Sprint(*p.TodayKm)
				}
			}
		}
		return last, today
	}

	d := detail(at)
	if tb := d.KmTable; tb == nil || tb.LastLabel != "Hôm qua · chốt 22h" || tb.TodayLabel != "Hôm nay · tới 15:40" || tb.UnitKm != 1 {
		t.Fatalf("kmTable = %+v", d.KmTable)
	}
	for uid, want := range map[string][2]string{"v1": {"5", "2.5"}, "w1": {"5", "1.2"}, "v2": {"5", "0"}} {
		if last, today := km(d, uid); last != want[0] || today != want[1] {
			t.Fatalf("%s: hôm qua %q, hôm nay %q; mong đợi %v", uid, last, today, want)
		}
	}
	if calls.Load() != 10 {
		t.Fatalf("lần đầu tính %d người, mong đợi 10", calls.Load())
	}

	if d := detail(at.Add(4 * time.Minute)); calls.Load() != 10 || d.KmTable.TodayLabel != "Hôm nay · tới 15:40" {
		t.Fatalf("trong 5 phút vẫn tính lại: %d lần, %q", calls.Load(), d.KmTable.TodayLabel)
	}
	live["v1"] = 3000
	d = detail(at.Add(5 * time.Minute))
	if _, today := km(d, "v1"); calls.Load() != 20 || today != "3" || d.KmTable.TodayLabel != "Hôm nay · tới 15:45" {
		t.Fatalf("sau 5 phút: %d lần, v1 %q, %q", calls.Load(), today, d.KmTable.TodayLabel)
	}

	me, err := g.store.Me(ctx, g.id, GameViewer{UID: "w1"}, at.Add(5*time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	if tk := me.TeamKm; tk == nil || tk.Label != "Km phe Sói" || tk.Last != 10 || tk.Today == nil || *tk.Today != 1.5 || tk.Need != 2 || tk.NeedLabel != "Cần 2 km để cắn" {
		t.Fatalf("teamKm của sói = %+v", me.TeamKm)
	}
	if calls.Load() != 20 {
		t.Fatalf("/me tính lại km dù bản giữ còn mới: %d lần", calls.Load())
	}
	if me, err := g.store.Me(ctx, g.id, GameViewer{UID: "v1"}, at); err != nil || me.TeamKm != nil {
		t.Fatalf("dân có teamKm = %+v, err %v", me.TeamKm, err)
	}
}
