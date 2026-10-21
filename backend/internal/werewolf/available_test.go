package werewolf

import (
	"reflect"
	"testing"
)

func TestAvailableFollowsPhaseRoleAndPotions(t *testing.T) {
	roles := baseRoles()
	roles["cupid"] = Cupid
	g := newGame(t, roles)
	want := func(uid string, kinds ...Kind) {
		t.Helper()
		if got := g.st.Available(uid); !reflect.DeepEqual(got, kinds) && (len(got) != 0 || len(kinds) != 0) {
			t.Fatalf("%s ở %s: %v, mong đợi %v", uid, g.st.PhaseKey(), got, kinds)
		}
	}
	want("cupid", KindCupidPair) // setup
	want("w1")
	g.do(KindCupidPair, "cupid", "v5", "v6")
	g.next()
	want("w1", KindWolfBite)
	want("seer", KindSeerPeek)
	want("guard", KindGuard)
	want("cupid", KindCupidPair)
	want("witch")
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	want("witch", KindWitchSave, KindWitchPoison) // có người bị cắn, còn đủ bình
	want("seer", KindSeerPeek)
	want("w1")
	g.do(KindWitchSave, "witch")
	g.toPhase(PhaseDay)
	want("v1", KindNominate)
	want("witch", KindNominate)
	for _, v := range g.st.aliveUIDs() {
		if v != "v2" {
			g.do(KindNominate, v, "v2")
		}
	}
	g.next()
	want("v1", KindVote)
	want("v2") // người lên giàn không bỏ phiếu
	g.next()
	g.do(KindWolfBite, "w1", "v3")
	g.toPhase(PhaseDawn)
	want("witch", KindWitchPoison) // hết bình cứu
}

func TestAvailableHunterTurnAndDeadOrPaused(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "hunter")
	g.toPhase(PhaseDay)
	if g.st.Hunter == nil {
		t.Fatal("thợ săn chưa có lượt")
	}
	if got := g.st.Available("hunter"); !reflect.DeepEqual(got, []Kind{KindHunterShoot}) {
		t.Fatalf("thợ săn: %v", got)
	}
	if got := g.st.Available("v1"); !reflect.DeepEqual(got, []Kind{KindNominate}) {
		t.Fatalf("v1 lúc thợ săn còn lượt: %v", got)
	}
	paused, _ := Pause(g.st)
	if got := paused.Available("v1"); got != nil {
		t.Fatalf("pause mà vẫn mở: %v", got)
	}
	if got := g.st.Available("nguoi-ngoai"); got != nil {
		t.Fatalf("người ngoài ván: %v", got)
	}
}

// Không ai bị cắn thì phù thuỷ chỉ còn bình độc; dùng rồi thì đêm sau hết cả hai.
// Không ai lên giàn thì không có biểu quyết. Cupid hết lượt từ vòng 2.
func TestAvailableClosesWhatIsUsedOrMissing(t *testing.T) {
	roles := baseRoles()
	roles["cupid"] = Cupid
	g := newGame(t, roles)
	g.do(KindCupidPair, "cupid", "v5", "v6")
	g.next()
	g.toPhase(PhaseDawn)
	if got := g.st.Available("witch"); !reflect.DeepEqual(got, []Kind{KindWitchPoison}) {
		t.Fatalf("phù thuỷ đêm không ai bị cắn: %v", got)
	}
	g.do(KindWitchPoison, "witch", "w2")
	g.toPhase(PhaseTrial)
	if got := g.st.Available("v1"); got != nil {
		t.Fatalf("không ai lên giàn mà vẫn mở: %v", got)
	}
	g.toPhase(PhaseNight)
	if got := g.st.Available("cupid"); got != nil {
		t.Fatalf("Cupid đêm 2: %v", got)
	}
	g.toPhase(PhaseDawn)
	if got := g.st.Available("witch"); got != nil {
		t.Fatalf("phù thuỷ đã dùng bình độc, không ai bị cắn: %v", got)
	}
}

// Lượt bắn thuộc đúng thợ săn vừa chết, không thuộc mọi người có vai thợ săn.
func TestAvailableHunterTurnBelongsToTheDeadHunter(t *testing.T) {
	roles := baseRoles()
	roles["hunter2"] = Hunter
	g := newGame(t, roles)
	g.next()
	g.do(KindWolfBite, "w1", "hunter")
	g.toPhase(PhaseDay)
	if got := g.st.Available("hunter2"); !reflect.DeepEqual(got, []Kind{KindNominate}) {
		t.Fatalf("thợ săn còn sống: %v", got)
	}
}
