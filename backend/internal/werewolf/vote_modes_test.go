package werewolf

import (
	"maps"
	"slices"
	"testing"
)

// Riêng: ai đủ km một phiếu thì phiếu người đó được tính, không xét tổng.
// v3, v4 chạy 0,5 km: theo nhóm thì tổng 11 km chỉ cắt 1 người (bốc thăm),
// Riêng thì cắt cả hai.
func TestSoloVoteCutsEveryoneShortOfOneVote(t *testing.T) {
	g := trial(t, map[string]float64{"v3": 500, "v4": 500})
	g.st.Config.Ruleset, g.st.Config.Vote = RulesetKm, VoteSolo
	e := find(g.next(), EventVoteCut)
	if e == nil || e.Draw || !slices.Equal(e.Targets, []string{"v3", "v4"}) {
		t.Fatalf("mất phiếu = %+v", e)
	}
}

// Riêng với sói: 4 km một phiếu, w1 6 km, w2 và w3 mỗi người 3 km. Theo nhóm
// thì 12 km đủ 3 phiếu; Riêng thì chỉ w1 có phiếu → cắn v2 dù v1 có 2 người bấm.
func TestSoloWolfVoteNeedsOwnKm(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset, g.st.Config.Vote = RulesetKm, VoteSolo
	g.st.Config.SkillKm = map[Role]float64{Wolf: 4}
	g.st.Km["w1"], g.st.Km["w2"], g.st.Km["w3"] = 6000, 3000, 3000
	g.do(KindWolfBite, "w1", "v2")
	g.do(KindWolfBite, "w2", "v1")
	g.do(KindWolfBite, "w3", "v1")
	evs := g.next()
	if e := find(evs, EventWolvesTarget); e == nil || e.UID != "v2" || !maps.Equal(e.Counts, map[string]int{"v2": 1}) {
		t.Fatalf("cắn = %+v", e)
	}
	if got := voids(evs); !maps.Equal(got, map[string]string{"w2/wolf_bite": VoidVoteCut, "w3/wolf_bite": VoidVoteCut}) {
		t.Fatalf("phiếu bị loại = %v", got)
	}
}

// topFiveHang: w1 chạy 1,5 km nên là Top 1. Treo: w1, w2, w3, seer, guard;
// Tha: witch, hunter, v2, v3, v4, v5.
func topFiveHang(t *testing.T, vote VoteRule, weight int) *Event {
	g := trial(t, map[string]float64{"w1": 1500})
	g.st.Config.Ruleset, g.st.Config.Vote = RulesetKm, vote
	g.st.Config.TopVoters, g.st.Config.TopWeight = 1, weight
	for _, v := range []string{"w1", "w2", "w3", "seer", "guard"} {
		g.vote(v, ChoiceHang)
	}
	for _, v := range []string{"witch", "hunter", "v2", "v3", "v4", "v5"} {
		g.vote(v, ChoiceSpare)
	}
	evs := g.next()
	if b := find(evs, EventVoteBonus); weight > 0 && (b == nil || !slices.Equal(b.Targets, []string{"w1"}) || b.Weight != weight) {
		t.Fatalf("top = %+v", b)
	}
	return find(evs, EventVoteResult)
}

// Top 1 được x3: Treo 4 + 3 = 7 hơn Tha 6 → treo. Tắt Top thì 5 – 6 → tha.
func TestTopWeightAddsOnTopOfGroupAndSolo(t *testing.T) {
	for _, vote := range []VoteRule{VoteCut, VoteSolo} {
		if e := topFiveHang(t, vote, 3); e == nil || e.Hang != 7 || e.Spare != 6 || !e.Hanged {
			t.Fatalf("%s x3: %+v", vote, e)
		}
		if e := topFiveHang(t, vote, 0); e == nil || e.Hang != 5 || e.Hanged {
			t.Fatalf("%s tắt top: %+v", vote, e)
		}
	}
}

// Treo tối đa 1: chỉ người nhiều đề cử nhất lên giàn.
func TestMaxHangLimitsNominees(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset, g.st.Config.MaxHang = RulesetKm, 1
	nominateFour(g)
	if e := find(g.next(), EventNominee); e == nil || !slices.Equal(e.Targets, []string{"w1"}) {
		t.Fatalf("đề cử = %+v", e)
	}
}
