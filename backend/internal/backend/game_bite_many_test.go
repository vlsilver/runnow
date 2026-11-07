package backend

import (
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Sói cắn hai người: thẻ Bình cứu chuyển sang chọn một người, chỉ gồm người bị
// cắn; cắn một người thì vẫn là nút xác nhận như trước.
func TestMeActionsWitchSavePicksAmongBitten(t *testing.T) {
	players := []gamePlayerInfo{{uid: "witch", name: "Hà"}, {uid: "v1", name: "An"}, {uid: "v2", name: "Bình"}, {uid: "v3", name: "Chi"}}
	save := func(bites []string) *GameAction {
		st := ww.NewState(ww.Seed{1}, ww.Config{KmOff: true, MaxBite: 2}, msgRoles(), msgStart)
		st.Phase, st.Bites, st.Bitten = ww.PhaseDawn, bites, bites[0]
		now := st.TurnClose().Add(-30 * time.Minute)
		for _, a := range meActions(st, "witch", nil, nil, players, now, 0) {
			if a.Kind == string(ww.KindWitchSave) {
				return &a
			}
		}
		return nil
	}
	a := save([]string{"v2", "v1"})
	if a == nil || a.Input != "single_target" || !a.Enabled || len(a.Options) != 2 || a.Options[0].ID != "v1" || a.Options[1].ID != "v2" {
		t.Fatalf("bình cứu khi cắn hai người = %+v", a)
	}
	if !strings.Contains(a.Help, "Chọn một người bị cắn") {
		t.Fatalf("help = %q", a.Help)
	}
	if a := save([]string{"v1"}); a == nil || a.Input != "confirm" || len(a.Options) != 0 {
		t.Fatalf("bình cứu khi cắn một người = %+v", a)
	}
}

// Câu luật của sói theo số người cắn tối đa, cả ván luật km lẫn ván cũ.
func TestWolfRuleTextFollowsMaxBite(t *testing.T) {
	cases := []struct {
		cfg  ww.Config
		want string
	}{
		{ww.Config{}, wolfPickOld},
		{ww.Config{Ruleset: ww.RulesetKm}, wolfPickVote},
		{ww.Config{MaxBite: 2}, "2 người khác nhau được chọn sau cùng bị cắn"},
		{ww.Config{Ruleset: ww.RulesetKm, MaxBite: 3}, "tối đa 3 người nhiều phiếu nhất bị cắn"},
	}
	for _, c := range cases {
		got := roleRulesFor(ww.Wolf, c.cfg, "1")
		if !strings.Contains(got, c.want) {
			t.Fatalf("maxBite %d ruleset %d: %q không có %q", c.cfg.MaxBite, c.cfg.Ruleset, got, c.want)
		}
	}
	if got := roleRulesFor(ww.Wolf, ww.Config{MaxBite: 2}, "1"); !strings.Contains(got, "chọn tối đa 2 người để cắn") {
		t.Fatalf("luật sói = %q", got)
	}
}

// Tổng kết đêm cắn hai người ghi đủ tên cả hai.
func TestBiteTargetsReadsBothEventShapes(t *testing.T) {
	if got := biteTargets(ww.Event{Kind: ww.EventWolvesTarget, UID: "v1"}); len(got) != 1 || got[0] != "v1" {
		t.Fatalf("sự kiện một người = %v", got)
	}
	if got := biteTargets(ww.Event{Kind: ww.EventWolvesTarget, UID: "v2", Targets: []string{"v2", "v1"}}); len(got) != 2 {
		t.Fatalf("sự kiện hai người = %v", got)
	}
	if got := biteTargets(ww.Event{Kind: ww.EventWolvesTarget}); got != nil {
		t.Fatalf("không cắn = %v", got)
	}
}
