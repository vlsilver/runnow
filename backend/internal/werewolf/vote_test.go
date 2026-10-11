package werewolf

import (
	"reflect"
	"testing"
)

// trial đưa v1 lên giàn ở ván 13 người (12 người được bỏ phiếu) với km cho sẵn
// cho lần chốt 22h; người không có trong km thì có 1000 m.
func trial(t *testing.T, km map[string]float64) *tg {
	g := game13(t)
	for uid := range g.km {
		g.km[uid] = 1000
	}
	for uid, m := range km {
		g.km[uid] = m
	}
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v2", "v1")
	g.next()
	return g
}

// 6 Treo, 6 Tha (v2 bấm Tha): đủ phiếu thì hoà → tha.
func voteSixSix(g *tg) {
	for _, v := range []string{"w1", "w2", "w3", "seer", "guard", "witch"} {
		g.vote(v, ChoiceHang)
	}
	for _, v := range []string{"hunter", "v2", "v3", "v4", "v5", "v6"} {
		g.vote(v, ChoiceSpare)
	}
}

// R30: 12 người × 1000 m = đúng 12 phiếu, không ai mất phiếu.
func TestR30ExactlyXPerVoterKeepsEveryVote(t *testing.T) {
	g := trial(t, nil)
	voteSixSix(g)
	evs := g.next()
	if find(evs, EventVoteCut) != nil {
		t.Fatal("không ai được mất phiếu")
	}
	if e := find(evs, EventVoteResult); e.Hang != 6 || e.Spare != 6 || e.Hanged {
		t.Fatalf("kết quả = %+v, mong đợi 6–6 và tha", e)
	}
}

// R30: thiếu 1 m (11999 m) thì chỉ còn 11 phiếu; v2 ít km nhất mất phiếu, nên
// 6 Treo – 5 Tha và v1 bị treo.
func TestR30OneMeterShortCutsLowestKmVoter(t *testing.T) {
	// v1 lên giàn có 5000 m nhưng không nằm trong nhóm được bỏ phiếu.
	g := trial(t, map[string]float64{"v2": 999, "v1": 5000})
	voteSixSix(g)
	evs := g.next()
	if e := find(evs, EventVoteCut); e == nil || !reflect.DeepEqual(e.Targets, []string{"v2"}) || e.Draw {
		t.Fatalf("mất phiếu = %+v, mong đợi [v2]", e)
	}
	if e := find(evs, EventVoteResult); e.Hang != 6 || e.Spare != 5 || !e.Hanged {
		t.Fatalf("kết quả = %+v", e)
	}
	if voids(evs)["v2/vote"] != VoidVoteCut || deaths(evs)["v1"] != CauseHang {
		t.Fatalf("voids=%v deaths=%v", voids(evs), deaths(evs))
	}
}

// R30: người mất phiếu tính cả người không bấm. v6 không bấm và ít km nhất, nên
// mất phiếu thay cho người đã bấm.
func TestR30NonVoterCanBeTheOneCut(t *testing.T) {
	g := trial(t, map[string]float64{"v6": 0, "v5": 1000}) // tổng 11000 → 11 phiếu
	for _, v := range []string{"w1", "w2", "w3"} {
		g.vote(v, ChoiceHang)
	}
	evs := g.next()
	if e := find(evs, EventVoteCut); e == nil || !reflect.DeepEqual(e.Targets, []string{"v6"}) {
		t.Fatalf("mất phiếu = %+v", e)
	}
	if e := find(evs, EventVoteResult); e.Hang != 3 || !e.Hanged {
		t.Fatalf("kết quả = %+v", e)
	}
}

// R30: bằng km ở đúng ngưỡng thì bốc thăm tất định và công bố là bốc thăm.
func TestR30TieAtCutoffIsDrawnDeterministically(t *testing.T) {
	km := map[string]float64{"v3": 500, "v4": 500} // tổng 11000 → 11 phiếu, cắt 1 trong v3/v4
	g := trial(t, km)
	e := find(g.next(), EventVoteCut)
	if e == nil || !e.Draw || len(e.Targets) != 1 || (e.Targets[0] != "v3" && e.Targets[0] != "v4") {
		t.Fatalf("mất phiếu = %+v", e)
	}
	again := find(trial(t, km).next(), EventVoteCut)
	if !reflect.DeepEqual(e, again) {
		t.Fatalf("cùng seed ra khác: %+v vs %+v", e, again)
	}
	// Bốc thăm phải đổi theo seed, không cố định một người.
	seen := map[string]bool{}
	for s := byte(0); s < 40; s++ {
		g := trial(t, km)
		g.st.Seed = Seed{s}
		seen[find(g.next(), EventVoteCut).Targets[0]] = true
	}
	if len(seen) != 2 {
		t.Fatalf("40 seed chỉ ra %v", seen)
	}
}

func TestR30NoKmMeansNoVoteCounts(t *testing.T) {
	g := trial(t, nil)
	for uid := range g.km {
		g.km[uid] = 0
	}
	voteSixSix(g)
	evs := g.next()
	if e := find(evs, EventVoteResult); e.Hang != 0 || e.Spare != 0 || e.Hanged {
		t.Fatalf("kết quả = %+v", e)
	}
	if e := find(evs, EventVoteCut); len(e.Targets) != 12 {
		t.Fatalf("mất phiếu = %+v", e)
	}
}

func TestR31LoverOfNomineeCanSpareButNotHang(t *testing.T) {
	g := trial(t, nil)
	g.st.Lovers = []string{"v1", "v3"}
	g.reject(ErrLoverTarget, Action{Kind: KindVote, Actor: "v3", Choice: ChoiceHang})
	g.vote("v3", ChoiceSpare)
	g.reject(ErrNotYourRole, Action{Kind: KindVote, Actor: "v1", Choice: ChoiceSpare}) // người lên giàn không bỏ phiếu
}

// Hoà đề cử thì bốc thăm; không ai đề cử thì không ai lên giàn và không có biểu quyết.
func TestNomineeTieDrawnAndNoNominationMeansNoTrial(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v1", "v3")
	g.do(KindNominate, "v2", "v4")
	e := find(g.next(), EventNominee)
	if e == nil || !e.Draw || (e.UID != "v3" && e.UID != "v4") || e.Counts["v3"] != 1 || e.Counts["v4"] != 1 {
		t.Fatalf("lên giàn = %+v", e)
	}
	// Bốc thăm đổi theo seed, không cố định một người.
	seen := map[string]bool{}
	for s := byte(0); s < 40; s++ {
		g := game13(t)
		g.st.Seed = Seed{s}
		g.toPhase(PhaseDay)
		g.do(KindNominate, "v1", "v3")
		g.do(KindNominate, "v2", "v4")
		seen[find(g.next(), EventNominee).UID] = true
	}
	if len(seen) != 2 {
		t.Fatalf("40 seed chỉ ra %v", seen)
	}

	g = game13(t)
	g.toPhase(PhaseDay)
	if e := find(g.next(), EventNominee); e == nil || e.UID != "" {
		t.Fatalf("lên giàn = %+v", e)
	}
	g.reject(ErrPhaseClosed, Action{Kind: KindVote, Actor: "v2", Choice: ChoiceHang})
}
