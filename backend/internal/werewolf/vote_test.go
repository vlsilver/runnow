package werewolf

import (
	"encoding/json"
	"reflect"
	"slices"
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

// Bằng đề cử ở suất thứ ba thì bốc thăm ai ở lại; không ai đề cử thì không ai
// lên giàn và không có biểu quyết.
func TestNomineeTieAtLastSeatDrawnAndNoNominationMeansNoTrial(t *testing.T) {
	tied := func(seed byte) *Event {
		g := game13(t)
		g.st.Seed = Seed{seed}
		g.toPhase(PhaseDay)
		g.do(KindNominate, "v1", "v3")
		g.do(KindNominate, "v2", "v4")
		g.do(KindNominate, "w1", "v5")
		g.do(KindNominate, "w2", "v6")
		return find(g.next(), EventNominee)
	}
	e := tied(7)
	if e == nil || !e.Draw || len(e.Targets) != 3 || e.UID != e.Targets[0] {
		t.Fatalf("lên giàn = %+v", e)
	}
	// Bốc thăm đổi theo seed: ai trong bốn người cũng có lúc ở lại.
	left := map[string]bool{}
	for s := byte(0); s < 40; s++ {
		up := tied(s).Targets
		for _, uid := range []string{"v3", "v4", "v5", "v6"} {
			if !slices.Contains(up, uid) {
				left[uid] = true
			}
		}
	}
	if len(left) != 4 {
		t.Fatalf("40 seed chỉ để lại %v", left)
	}

	g := game13(t)
	g.toPhase(PhaseDay)
	if e := find(g.next(), EventNominee); e == nil || e.UID != "" || len(e.Targets) != 0 {
		t.Fatalf("lên giàn = %+v", e)
	}
	g.reject(ErrPhaseClosed, Action{Kind: KindVote, Actor: "v2", Choice: ChoiceHang})
}

// Ba người nhiều đề cử nhất lên giàn theo thứ tự số đề cử, người thứ tư thì
// không; bằng đề cử trong top ba thì không phải bốc thăm suất.
func TestTopThreeNomineesGoUpInOrder(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseDay)
	for _, v := range []string{"v1", "v2", "v3"} {
		g.do(KindNominate, v, "w1") // 3
	}
	g.do(KindNominate, "v4", "v6") // 2
	g.do(KindNominate, "v5", "v6")
	g.do(KindNominate, "seer", "hunter") // 2
	g.do(KindNominate, "guard", "hunter")
	g.do(KindNominate, "witch", "v2") // 1
	e := find(g.next(), EventNominee)
	if e == nil || e.Draw || len(e.Targets) != 3 || e.Targets[0] != "w1" || e.UID != "w1" ||
		!slices.Contains(e.Targets, "v6") || !slices.Contains(e.Targets, "hunter") {
		t.Fatalf("lên giàn = %+v", e)
	}
	if !reflect.DeepEqual(g.st.TrialNominees(), e.Targets) || g.st.Nominee != "w1" {
		t.Fatalf("state lên giàn = %v, %q", g.st.Nominees, g.st.Nominee)
	}
	for i, kind := range VoteKinds() {
		if g.st.NomineeOf(kind) != e.Targets[i] {
			t.Fatalf("phiên %s của %q, mong đợi %q", kind, g.st.NomineeOf(kind), e.Targets[i])
		}
	}
}

// Hai người lên giàn thì chỉ có hai phiên.
func TestTwoNomineesOpenTwoTrials(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v1", "w1")
	g.do(KindNominate, "v2", "v3")
	g.next()
	if got := g.st.Available("v4"); !reflect.DeepEqual(got, []Kind{KindVote, KindVote2}) {
		t.Fatalf("v4 bấm được %v", got)
	}
	g.reject(ErrPhaseClosed, Action{Kind: KindVote3, Actor: "v4", Choice: ChoiceHang})
}

// voteIn bỏ phiếu ở phiên kind, fail nếu luật từ chối.
func (g *tg) voteIn(kind Kind, actor, choice string) {
	g.t.Helper()
	if err := g.try(Action{Kind: kind, Actor: actor, Choice: choice}); err != nil {
		g.t.Fatalf("%s %s %s bị từ chối: %v", actor, kind, choice, err)
	}
}

// Ba phiên chốt cùng lúc 22h. Tính tay, 13 người đủ km nên không ai mất phiếu:
//   - phiên w1: 7 Treo, 5 Tha → treo.
//   - phiên hunter: 5 Treo (có w1), 6 Tha → tha.
//   - phiên v1: 4 Treo (có w1), 3 Tha → treo.
//
// w1 bị treo ở phiên đầu mà phiếu ở phiên sau vẫn tính; người lên giàn không bỏ
// phiếu ở phiên của mình; người yêu không Treo người yêu ở phiên của người đó
// nhưng Treo được ở phiên khác.
func TestThreeTrialsResolveTogether(t *testing.T) {
	g := game13(t)
	g.st.Lovers = []string{"v1", "v3"}
	g.toPhase(PhaseDay)
	for _, v := range []string{"v2", "v3", "v4"} {
		g.do(KindNominate, v, "w1")
	}
	g.do(KindNominate, "v5", "hunter")
	g.do(KindNominate, "v6", "hunter")
	g.do(KindNominate, "seer", "v1")
	g.next()
	if got := g.st.TrialNominees(); !reflect.DeepEqual(got, []string{"w1", "hunter", "v1"}) {
		t.Fatalf("lên giàn = %v", got)
	}

	g.reject(ErrNotYourRole, Action{Kind: KindVote, Actor: "w1", Choice: ChoiceSpare})
	for _, v := range []string{"v1", "v2", "v3", "v4", "v5", "v6", "seer"} {
		g.voteIn(KindVote, v, ChoiceHang)
	}
	for _, v := range []string{"w2", "w3", "guard", "witch", "hunter"} {
		g.voteIn(KindVote, v, ChoiceSpare)
	}

	for _, v := range []string{"w1", "v2", "v3", "v4", "v5"} {
		g.voteIn(KindVote2, v, ChoiceHang)
	}
	for _, v := range []string{"w2", "w3", "seer", "guard", "witch", "v6"} {
		g.voteIn(KindVote2, v, ChoiceSpare)
	}

	g.reject(ErrNotYourRole, Action{Kind: KindVote3, Actor: "v1", Choice: ChoiceSpare})
	g.reject(ErrLoverTarget, Action{Kind: KindVote3, Actor: "v3", Choice: ChoiceHang})
	for _, v := range []string{"w1", "v2", "v4", "v5"} {
		g.voteIn(KindVote3, v, ChoiceHang)
	}
	for _, v := range []string{"v3", "w2", "w3"} {
		g.voteIn(KindVote3, v, ChoiceSpare)
	}

	evs := g.next()
	results := map[string][3]int{} // Treo, Tha, treo hay không
	for _, e := range evs {
		if e.Kind == EventVoteResult {
			hanged := 0
			if e.Hanged {
				hanged = 1
			}
			results[e.UID] = [3]int{e.Hang, e.Spare, hanged}
		}
	}
	want := map[string][3]int{"w1": {7, 5, 1}, "hunter": {5, 6, 0}, "v1": {4, 3, 1}}
	if !reflect.DeepEqual(results, want) {
		t.Fatalf("kết quả = %v, mong đợi %v", results, want)
	}
	// v1 bị treo nên v3 (người yêu) chết theo.
	sameDeaths(t, evs, map[string]Cause{"w1": CauseHang, "v1": CauseHang, "v3": CauseLover})
	if len(voids(evs)) != 0 {
		t.Fatalf("phiếu bị huỷ = %v", voids(evs))
	}
}

// Thợ săn bị treo cùng người khác vẫn được bắn.
func TestHunterHangedWithOthersGetsShot(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v1", "hunter")
	g.do(KindNominate, "v2", "hunter")
	g.do(KindNominate, "v3", "v6")
	g.next()
	for _, kind := range []Kind{KindVote, KindVote2} {
		for _, v := range []string{"w1", "w2", "w3"} {
			g.voteIn(kind, v, ChoiceHang)
		}
	}
	evs := g.next()
	sameDeaths(t, evs, map[string]Cause{"hunter": CauseHang, "v6": CauseHang})
	if e := find(evs, EventHunterTurn); e == nil || e.UID != "hunter" || g.st.Hunter == nil {
		t.Fatalf("lượt thợ săn = %+v, %+v", e, g.st.Hunter)
	}
}

// State ghi trước khi có nhiều phiên chỉ có "nominee". Ván đang biểu quyết lúc
// deploy vẫn bỏ phiếu và chốt đúng người đó, không mở phiên thứ hai.
func TestTrialStateWithOnlyNomineeStillCounts(t *testing.T) {
	g := trial(t, nil)
	raw, err := json.Marshal(g.st)
	if err != nil {
		t.Fatal(err)
	}
	var doc map[string]any
	if err := json.Unmarshal(raw, &doc); err != nil {
		t.Fatal(err)
	}
	if doc["nominee"] != "v1" {
		t.Fatalf("nominee = %v", doc["nominee"])
	}
	delete(doc, "nominees")
	if raw, err = json.Marshal(doc); err != nil {
		t.Fatal(err)
	}
	g.st = &State{}
	if err := json.Unmarshal(raw, g.st); err != nil {
		t.Fatal(err)
	}
	g.reject(ErrPhaseClosed, Action{Kind: KindVote2, Actor: "v2", Choice: ChoiceHang})
	g.reject(ErrNotYourRole, Action{Kind: KindVote, Actor: "v1", Choice: ChoiceSpare})
	for _, v := range []string{"w1", "w2", "w3"} {
		g.vote(v, ChoiceHang)
	}
	evs := g.next()
	if e := find(evs, EventVoteResult); e == nil || e.UID != "v1" || e.Hang != 3 || !e.Hanged {
		t.Fatalf("kết quả = %+v", e)
	}
	sameDeaths(t, evs, map[string]Cause{"v1": CauseHang})
	if len(g.st.TrialNominees()) != 0 || g.st.Nominee != "" {
		t.Fatalf("sang đêm mà còn người lên giàn: %v %q", g.st.Nominees, g.st.Nominee)
	}
}
