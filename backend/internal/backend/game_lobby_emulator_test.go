//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"
)

// Sảnh hiện km 24 tiếng gần nhất: 12:20 thì khung là 13h hôm trước tới 13h hôm
// nay. Người giả không có số, và số được giữ một phút.
func TestEmulatorLobbyRecentKm(t *testing.T) {
	db := emulatorDB(t)
	store := NewGameStore(db, testPscChat)
	wantStart := time.Date(2026, 11, 10, 13, 0, 0, 0, vietnam)
	wantEnd := time.Date(2026, 11, 11, 13, 0, 0, 0, vietnam)
	reads := 0
	store.frameKm = func(_ context.Context, uid string, start, end time.Time) (FrameKm, error) {
		if !start.Equal(wantStart) || !end.Equal(wantEnd) {
			t.Errorf("khung của %s: %v – %v", uid, start, end)
		}
		reads++
		return FrameKm{Meters: map[string]float64{"an": 12500}[uid]}, nil
	}
	h := newAPIHarness(t, store)
	id := openUserGame(t, h)
	seed(t, db, "games/"+id+"/players/an", map[string]any{"uid": "an", "name": "An"})
	seed(t, db, "games/"+id+"/players/binh", map[string]any{"uid": "binh", "name": "Bình"})
	seed(t, db, "games/"+id+"/players/gia", map[string]any{"uid": "gia", "name": "Giả", "fake": true})

	wall := time.Date(2026, 11, 11, 12, 20, 0, 0, vietnam)
	d, err := store.Detail(context.Background(), id, GameViewer{UID: "an"}, wall)
	if err != nil {
		t.Fatal(err)
	}
	recent := map[string]*float64{}
	for _, p := range d.Players {
		recent[p.UID] = p.RecentKm
	}
	if recent["an"] == nil || *recent["an"] != 12.5 {
		t.Fatalf("an = %v", recent["an"])
	}
	if recent["binh"] == nil || *recent["binh"] != 0 {
		t.Fatalf("binh = %v", recent["binh"])
	}
	if recent["gia"] != nil {
		t.Fatalf("người giả = %v", *recent["gia"])
	}
	first := reads
	if _, err := store.Detail(context.Background(), id, GameViewer{UID: "an"}, wall.Add(59*time.Second)); err != nil {
		t.Fatal(err)
	}
	if reads != first {
		t.Fatalf("chưa đủ một phút mà đọc lại km: %d → %d", first, reads)
	}
	if _, err := store.Detail(context.Background(), id, GameViewer{UID: "an"}, wall.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	if reads == first {
		t.Fatal("đủ một phút mà không đọc lại km")
	}
}
