package backend

import (
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Ván luật km: chữ luật nói sói bầu cắn và cách phân định bằng phiếu; ván cũ
// giữ chữ cũ.
func TestRulesTextKmTie(t *testing.T) {
	newCfg := ww.Config{Ruleset: ww.RulesetKm, SkillKm: map[ww.Role]float64{ww.Wolf: 2}}
	oldCfg := ww.Config{SkillKm: map[ww.Role]float64{ww.Wolf: 2}}

	wolf := roleRulesFor(ww.Wolf, newCfg, "1")
	for _, s := range []string{"Mỗi sói một phiếu", "nhóm phiếu chạy nhiều km hơn", "chia 2 km", "sói ít km nhất mất phiếu trước"} {
		if !strings.Contains(wolf, s) {
			t.Errorf("luật Sói thiếu %q: %s", s, wolf)
		}
	}
	if strings.Contains(wolf, "sau cùng") {
		t.Errorf("luật Sói còn câu cũ: %s", wolf)
	}
	if free := roleRulesFor(ww.Wolf, ww.Config{Ruleset: ww.RulesetKm, SkillKm: map[ww.Role]float64{ww.Wolf: 0}}, "1"); !strings.Contains(free, "Sói nào cũng có phiếu") {
		t.Errorf("luật Sói km 0: %s", free)
	}
	if old := roleRulesFor(ww.Wolf, oldCfg, "1"); !strings.Contains(old, "Lựa chọn bấm sau cùng của phe được tính.") {
		t.Errorf("ván cũ đổi luật Sói: %s", old)
	}

	const tie = "Bằng phiếu thì bên có tổng km cao hơn thắng, vẫn bằng thì bốc thăm."
	if got := gameRulesFor(newCfg); !strings.Contains(got, "22h chốt phiếu và km. "+tie) {
		t.Errorf("luật chung: %s", got)
	}
	if got := gameRulesFor(oldCfg); strings.Contains(got, tie) {
		t.Errorf("ván cũ có câu mới: %s", got)
	}

	bot := botVoteRulesFor(newCfg, "1")
	if strings.Contains(bot, "hoà thì tha") || strings.Count(bot, "vẫn bằng thì bốc thăm") != 2 {
		t.Errorf("luật phiếu cho bot: %s", bot)
	}
	if !strings.Contains(botVoteRulesFor(oldCfg, "1"), "hoà thì tha") {
		t.Error("ván cũ đổi luật phiếu cho bot")
	}

	st := ww.NewState(ww.Seed{1}, newCfg, map[string]ww.Role{"a": ww.Wolf}, time.Date(2026, 11, 7, 9, 0, 0, 0, vietnam))
	if help := actionHelp(st, ww.KindWolfBite); !strings.Contains(help, "Mỗi sói một phiếu") || strings.Contains(help, "sau cùng") {
		t.Errorf("hướng dẫn cắn: %s", help)
	}
}

// Theo nhóm: vai phe Dân dùng chung km, câu luật nói vai chạy ít nhất mất lượt;
// Riêng thì mỗi vai tự đủ km. Bảng km đầu ngày không còn câu sói cũ.
func TestSkillKmTextByMode(t *testing.T) {
	group := ww.Config{Ruleset: ww.RulesetKm, Vote: ww.VoteCut}
	solo := ww.Config{Ruleset: ww.RulesetKm, Vote: ww.VoteSolo}
	const shared = "vai chạy ít nhất mất lượt trước"
	if got := roleKmLine(ww.Seer, group, "1"); !strings.Contains(got, shared) {
		t.Errorf("Theo nhóm: %s", got)
	}
	if got := roleKmLine(ww.Seer, solo, "1"); got != "Cần đủ 1 km." {
		t.Errorf("Riêng: %s", got)
	}
	needs := kmNeedsText(group)
	if !strings.Contains(needs, shared) || strings.Contains(needs, "cho mỗi sói") {
		t.Errorf("bảng km: %s", needs)
	}
	soloWolf := ww.Config{Ruleset: ww.RulesetKm, Vote: ww.VoteSolo, SkillKm: map[ww.Role]float64{ww.Wolf: 2}}
	if got := roleKmLine(ww.Wolf, soloWolf, "1"); got != "Sói nào tự chạy đủ 2 km thì phiếu đó được tính." {
		t.Errorf("Riêng, sói: %s", got)
	}
	if mySkillKm(group, ww.Seer) == " Cần 1 km để dùng kỹ năng đêm." {
		t.Error("hộp km của tôi vẫn nói km riêng ở chế độ Theo nhóm")
	}
}

// Riêng: luật phiếu nói ai đủ km người đó được tính, không có câu cộng km cả
// nhóm. Top x phiếu: luật nói số người và số phiếu mỗi người.
func TestVoteRulesSoloAndTopWeight(t *testing.T) {
	solo := ww.Config{Ruleset: ww.RulesetKm, Vote: ww.VoteSolo}
	if bot := botVoteRulesFor(solo, "1"); !strings.Contains(bot, "ai đủ 1 km thì phiếu được tính") || strings.Contains(bot, "tổng km chia") {
		t.Errorf("Riêng, bot: %s", bot)
	}
	top := ww.Config{Ruleset: ww.RulesetKm, Vote: ww.VoteCut, TopVoters: 2, TopWeight: 3}
	const want = "2 người chạy nhiều nhất, mỗi người đủ 1 km, được tính 3 phiếu"
	if got := botVoteRulesFor(top, "1"); !strings.Contains(got, want) {
		t.Errorf("Top, bot: %s", got)
	}
	if got := gameRulesFor(top); !strings.Contains(got, want) {
		t.Errorf("Top, luật chung: %s", got)
	}
	if got := gameRulesFor(solo); strings.Contains(got, "được tính 3 phiếu") || strings.Contains(got, "chạy nhiều nhất") {
		t.Errorf("tắt Top mà luật vẫn nói: %s", got)
	}
	one := ww.Config{Ruleset: ww.RulesetKm, MaxHang: 1}
	if got := gameRulesFor(one); !strings.Contains(got, "tối đa 1 người nhiều đề cử nhất lên giàn") {
		t.Errorf("treo tối đa 1, luật chung: %s", got)
	}
	if got := botVoteRulesFor(one, "1"); !strings.Contains(got, "tối đa 1 người nhiều đề cử nhất lên giàn") {
		t.Errorf("treo tối đa 1, bot: %s", got)
	}
}

// Luật km: phe Sói chỉ cần đủ một phiếu để cắn, nên câu thiếu km không nhân số sói.
func TestWolfNeedText(t *testing.T) {
	if got := wolfNeedText(ww.Config{Ruleset: ww.RulesetKm}, 3500, 4000, 4); got != "cả phe có 3.5 km, cần 4 km cho một phiếu" {
		t.Errorf("luật km: %q", got)
	}
	if got := wolfNeedText(ww.Config{}, 3500, 12000, 4); got != "cả phe có 3.5 km, cần 12 km (4 km cho mỗi sói còn sống)" {
		t.Errorf("luật cũ: %q", got)
	}
}

// Bản tin nói lý do khi bằng phiếu Treo/Tha ở ván luật km.
func TestVoteResultLineKmTie(t *testing.T) {
	name := func(uid string) string { return uid }
	cases := []struct {
		e    ww.Event
		want string
	}{
		{ww.Event{Kind: ww.EventVoteResult, UID: "An", Hang: 6, Spare: 6, Hanged: true, HangKm: 12000, SpareKm: 6000},
			"Treo 6, Tha 6, bên Treo chạy nhiều km hơn (12 – 6 km): An bị treo."},
		{ww.Event{Kind: ww.EventVoteResult, UID: "An", Hang: 6, Spare: 6, HangKm: 6000, SpareKm: 6500},
			"Treo 6, Tha 6, bên Tha chạy nhiều km hơn (6.5 – 6 km): An được tha."},
		{ww.Event{Kind: ww.EventVoteResult, UID: "An", Hang: 6, Spare: 6, Hanged: true, HangKm: 6000, SpareKm: 6000, Draw: true},
			"Treo 6, Tha 6, bằng cả km nên bốc thăm: An bị treo."},
		{ww.Event{Kind: ww.EventVoteResult, UID: "An", Hang: 6, Spare: 6},
			"Treo 6, Tha 6: An được tha."},
	}
	for _, c := range cases {
		if got, _ := eventLine(c.e, name); got != c.want {
			t.Errorf("%+v\n  = %q\n  mong đợi %q", c.e, got, c.want)
		}
	}
}
