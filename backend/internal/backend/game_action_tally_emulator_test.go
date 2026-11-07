//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Me của sói có bảng kiểm phiếu cắn đọc từ action đã lưu của vòng; người không
// phải sói không có action cắn nên không thấy bảng. Ván luật cũ không có bảng.
func TestEmulatorMeWolfBiteTally(t *testing.T) {
	ctx := context.Background()
	g := newStoreGameWith(t, ww.Config{Ruleset: ww.RulesetKm})
	g.advance(g.start.NightAt)
	at := g.start.NightAt.Add(time.Minute)
	g.act(1, ww.KindWolfBite, "w1", at, "v1")
	g.act(1, ww.KindWolfBite, "w2", at, "v1")
	me, err := g.store.Me(ctx, g.id, GameViewer{UID: "w1"}, at)
	if err != nil {
		t.Fatal(err)
	}
	var tally *GameTally
	for _, a := range me.Actions {
		if a.Kind == string(ww.KindWolfBite) {
			tally = a.Tally
		}
	}
	if tally == nil || len(tally.Rows) != 1 || tally.Rows[0].ID != "v1" || tally.Rows[0].Votes != 2 || !tally.Rows[0].Lead || tally.Reason != "Nhiều phiếu hơn" {
		t.Fatalf("tally cắn của w1 = %+v, mong đợi v1 2 phiếu dẫn", tally)
	}
	seer, err := g.store.Me(ctx, g.id, GameViewer{UID: "seer"}, at)
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range seer.Actions {
		if a.Tally != nil {
			t.Fatalf("tiên tri thấy bảng kiểm phiếu ở %s", a.Kind)
		}
	}

	old := newStoreGame(t)
	old.advance(old.start.NightAt)
	old.act(1, ww.KindWolfBite, "w1", at, "v1")
	me, err = old.store.Me(ctx, old.id, GameViewer{UID: "w1"}, at)
	if err != nil {
		t.Fatal(err)
	}
	for _, a := range me.Actions {
		if a.Tally != nil {
			t.Fatalf("ván cũ có bảng kiểm phiếu ở %s", a.Kind)
		}
	}
}
