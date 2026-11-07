package werewolf

import (
	"maps"
	"slices"
	"testing"
)

// Luật km (RulesetKm): bằng phiếu thì nhóm phiếu có tổng km cao hơn thắng, vẫn
// bằng thì bốc thăm. Ván cũ (Ruleset 0) giữ luật hoà thì tha.

// 6 người 2 km bấm Treo, 6 người 1 km bấm Tha: 18 km chia 1 km = 18 ≥ 12 nên
// không ai mất phiếu; 6 – 6, Treo 12 km hơn Tha 6 km → treo.
func TestKmTieHangSideWithMoreKmWins(t *testing.T) {
	km := map[string]float64{"w1": 2000, "w2": 2000, "w3": 2000, "seer": 2000, "guard": 2000, "witch": 2000}
	g := trial(t, km)
	g.st.Config.Ruleset = RulesetKm
	voteSixSix(g)
	e := find(g.next(), EventVoteResult)
	if e == nil || e.Hang != 6 || e.Spare != 6 || !e.Hanged || e.HangKm != 12000 || e.SpareKm != 6000 || e.Draw {
		t.Fatalf("kết quả = %+v", e)
	}
}

// 6 – 6, ai cũng 1 km nên hai bên đều 6 km: bốc thăm, đổi seed thì ra được cả
// treo lẫn tha.
func TestKmTieSameKmIsDrawn(t *testing.T) {
	seen := map[bool]bool{}
	for s := byte(0); s < 40; s++ {
		g := trial(t, nil)
		g.st.Config.Ruleset = RulesetKm
		g.st.Seed = Seed{s}
		voteSixSix(g)
		e := find(g.next(), EventVoteResult)
		if e == nil || !e.Draw || e.HangKm != 6000 || e.SpareKm != 6000 {
			t.Fatalf("seed %d: %+v", s, e)
		}
		seen[e.Hanged] = true
	}
	if len(seen) != 2 {
		t.Fatalf("40 seed chỉ ra %v", seen)
	}
}

// Đề cử: w1 và hunter mỗi người 2 đề cử, seer và guard mỗi người 1. Suất thứ ba
// giữa seer (người đề cử chạy 3 km) và guard (1 km) → seer lên; w1 hơn hunter
// vì nhóm đề cử w1 có 6 + 5 = 11 km, nhóm hunter 5 + 5 = 10 km.
func nominateFour(g *tg) {
	g.toPhase(PhaseDay)
	g.st.Km["v2"], g.st.Km["v6"], g.st.Km["witch"] = 6000, 3000, 1000
	g.do(KindNominate, "v2", "w1")
	g.do(KindNominate, "v3", "w1")
	g.do(KindNominate, "v4", "hunter")
	g.do(KindNominate, "v5", "hunter")
	g.do(KindNominate, "v6", "seer")
	g.do(KindNominate, "witch", "guard")
}

func TestKmTieNomineeSeatGoesToMoreKm(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset = RulesetKm
	nominateFour(g)
	e := find(g.next(), EventNominee)
	want := map[string]float64{"w1": 11000, "hunter": 10000, "seer": 3000, "guard": 1000}
	if e == nil || e.Draw || !slices.Equal(e.Targets, []string{"w1", "hunter", "seer"}) || !maps.Equal(e.Km, want) {
		t.Fatalf("đề cử = %+v", e)
	}
}

func TestOldRulesetNomineeSeatIsDrawn(t *testing.T) {
	g := game13(t)
	nominateFour(g)
	if e := find(g.next(), EventNominee); e == nil || !e.Draw || e.Km != nil {
		t.Fatalf("đề cử = %+v", e)
	}
}

// bite: mỗi sói bấm một mục tiêu theo thứ tự cho sẵn, rồi chốt 0h.
func bite(g *tg, picks ...[2]string) *Event {
	for _, p := range picks {
		g.do(KindWolfBite, p[0], p[1])
	}
	return find(g.next(), EventWolvesTarget)
}

// Sói bầu: v2 có 2 phiếu, v1 có 1 phiếu dù w1 bấm sau cùng → cắn v2.
func TestKmRulesWolvesBiteByVote(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset = RulesetKm
	e := bite(g, [2]string{"w2", "v2"}, [2]string{"w3", "v2"}, [2]string{"w1", "v1"})
	if e == nil || e.UID != "v2" || e.Draw || !maps.Equal(e.Counts, map[string]int{"v1": 1, "v2": 2}) {
		t.Fatalf("cắn = %+v", e)
	}
}

// Ván cũ: lựa chọn bấm sau cùng của phe thắng.
func TestOldRulesetWolvesLastPickWins(t *testing.T) {
	g := game13(t)
	if e := bite(g, [2]string{"w2", "v2"}, [2]string{"w3", "v2"}, [2]string{"w1", "v1"}); e == nil || e.UID != "v1" {
		t.Fatalf("cắn = %+v", e)
	}
}

// 1 – 1: nhóm phiếu v1 (w1 chạy 7 km) hơn nhóm v2 (w2 chạy 5 km) → cắn v1.
func TestKmRulesBiteTieGoesToMoreKm(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset = RulesetKm
	g.st.Km["w1"] = 7000
	e := bite(g, [2]string{"w1", "v1"}, [2]string{"w2", "v2"})
	if e == nil || e.UID != "v1" || e.Draw || !maps.Equal(e.Km, map[string]float64{"v1": 7000, "v2": 5000}) {
		t.Fatalf("cắn = %+v", e)
	}
}

// Theo nhóm, 4 km một phiếu: 6 + 5 + 0,5 = 11,5 km → 2 phiếu, w3 ít km nhất
// mất phiếu. Còn v2 (w1, 6 km) 1 – v1 (w2, 5 km) 1 → cắn v2. Phe thiếu km theo
// luật cũ (11,5 < 3 × 4) vẫn bấm được vì phiếu chỉ bị loại lúc chốt.
func TestKmRulesBiteVotesCutByGroupKm(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset = RulesetKm
	g.st.Config.SkillKm = map[Role]float64{Wolf: 4}
	g.st.Km["w1"], g.st.Km["w2"], g.st.Km["w3"] = 6000, 5000, 500
	g.do(KindWolfBite, "w1", "v2")
	g.do(KindWolfBite, "w2", "v1")
	g.do(KindWolfBite, "w3", "v1")
	evs := g.next()
	e := find(evs, EventWolvesTarget)
	if e == nil || e.UID != "v2" || !maps.Equal(e.Counts, map[string]int{"v1": 1, "v2": 1}) {
		t.Fatalf("cắn = %+v", e)
	}
	if got := voids(evs); !maps.Equal(got, map[string]string{"w3/wolf_bite": VoidVoteCut}) {
		t.Fatalf("phiếu bị loại = %v", got)
	}
}

// Luật km: phe cắn được khi đủ km cho một phiếu, nên mức cần là km một phiếu
// chứ không nhân số sói.
func TestKmRulesWolfKmNeedIsOneVote(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset = RulesetKm
	g.st.Config.SkillKm = map[Role]float64{Wolf: 4}
	g.st.Km["w1"], g.st.Km["w2"], g.st.Km["w3"] = 2000, 1000, 500
	if have, need := WolfKm(g.st); have != 3500 || need != 4000 {
		t.Fatalf("WolfKm = %v, %v", have, need)
	}
	g.reject(ErrKmInsufficient, act(KindWolfBite, "w1", "v1"))
	g.st.Km["w3"] = 1000
	g.do(KindWolfBite, "w1", "v1")
}

// Km mỗi phiếu 0: sói nào cũng có phiếu dù không chạy.
func TestKmRulesBiteFreeWhenWolfKmZero(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset = RulesetKm
	g.st.Config.SkillKm = map[Role]float64{Wolf: 0}
	g.st.Km["w1"], g.st.Km["w2"], g.st.Km["w3"] = 0, 0, 0
	if e := bite(g, [2]string{"w1", "v1"}, [2]string{"w2", "v1"}); e == nil || e.UID != "v1" || e.Counts["v1"] != 2 {
		t.Fatalf("cắn = %+v", e)
	}
}

// Cùng phiếu đó ở ván cũ: hoà thì tha.
func TestOldRulesetTieStillSpares(t *testing.T) {
	km := map[string]float64{"w1": 2000, "w2": 2000, "w3": 2000, "seer": 2000, "guard": 2000, "witch": 2000}
	g := trial(t, km)
	voteSixSix(g)
	if e := find(g.next(), EventVoteResult); e == nil || e.Hanged || e.HangKm != 0 || e.SpareKm != 0 {
		t.Fatalf("kết quả = %+v", e)
	}
}
