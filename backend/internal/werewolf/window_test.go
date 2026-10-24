package werewolf

import (
	"errors"
	"testing"
	"time"
)

// Cửa sổ theo bảng 1.3; Start 9h 15/10 nên đêm 1 là 22h 15/10.
func TestWindowFollowsScheduleTable(t *testing.T) {
	roles := baseRoles()
	roles["cupid"] = Cupid
	g := newGame(t, roles)
	check := func(kind Kind, opens, closes time.Time) {
		t.Helper()
		o, c := g.st.Window(kind)
		if !o.Equal(opens) || !c.Equal(closes) {
			t.Errorf("%s ở %s: [%v, %v), mong đợi [%v, %v)", kind, g.st.Phase, o, c, opens, closes)
		}
	}
	check(KindCupidPair, time.Time{}, at(16, 0, 0))
	g.next() // night 1
	check(KindCupidPair, at(15, 22, 0), at(16, 0, 0))
	check(KindWolfBite, at(15, 22, 0), at(16, 0, 0))
	check(KindSeerPeek, at(15, 22, 0), at(16, 10, 0))
	check(KindGuard, at(15, 22, 0), at(16, 10, 0))
	g.do(KindCupidPair, "cupid", "v1", "v2")
	g.toPhase(PhaseDawn)
	check(KindWitchSave, at(16, 0, 0), at(16, 10, 0))
	check(KindWitchPoison, at(16, 0, 0), at(16, 10, 0))
	g.toPhase(PhaseDay)
	check(KindNominate, at(16, 10, 0), at(16, 20, 0))
	g.toPhase(PhaseTrial)
	check(KindVote, at(16, 20, 0), at(16, 22, 0))
	check(KindHunterShoot, time.Time{}, time.Time{})
}

func TestWindowOfHunterDependsOnHowHeDied(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "hunter")
	g.toPhase(PhaseDay)
	if o, c := g.st.Window(KindHunterShoot); !o.Equal(at(16, 10, 0)) || !c.Equal(at(16, 12, 0)) {
		t.Fatalf("chết trong đêm: [%v, %v)", o, c)
	}

	g = game13(t)
	g.toPhase(PhaseDay)
	g.hang("hunter")
	if o, c := g.st.Window(KindHunterShoot); !o.Equal(at(16, 22, 0)) || !c.Equal(at(16, 23, 0)) {
		t.Fatalf("bị treo: [%v, %v)", o, c)
	}
}

func TestPrecheckReasonsBeforeTarget(t *testing.T) {
	g := game13(t)
	now := at(15, 23, 0)
	cases := []struct {
		kind  Kind
		actor string
		mine  []Action
		want  error
	}{
		{KindWolfBite, "w1", nil, nil},
		{KindSeerPeek, "seer", nil, nil},
		{KindSeerPeek, "seer", []Action{{Kind: KindSeerPeek, Actor: "seer", Targets: []string{"v1"}}}, ErrAlreadyUsed},
		{KindSeerPeek, "v1", nil, ErrNotYourRole},
		{KindWitchSave, "witch", nil, ErrPhaseClosed}, // phù thuỷ mở từ 0h
		{KindNominate, "v1", nil, ErrPhaseClosed},
	}
	for _, c := range cases {
		if err := Precheck(g.st, c.kind, c.actor, c.mine, now); !errors.Is(err, c.want) && err != c.want {
			t.Errorf("%s/%s: %v, mong đợi %v", c.kind, c.actor, err, c.want)
		}
	}
	g.km["seer"] = 999
	g.st.Km = map[string]float64{"seer": 999}
	if err := Precheck(g.st, KindSeerPeek, "seer", nil, now); !errors.Is(err, ErrKmInsufficient) {
		t.Fatalf("999 m: %v", err)
	}
	g.st.Km = map[string]float64{}
	if err := Precheck(g.st, KindWolfBite, "w1", nil, now); !errors.Is(err, ErrKmInsufficient) {
		t.Fatalf("sói thiếu km: %v", err)
	}

	// Rạng sáng không ai bị cắn thì không có gì để cứu.
	g = game13(t)
	g.toPhase(PhaseDawn)
	if err := Precheck(g.st, KindWitchSave, "witch", nil, at(16, 1, 0)); !errors.Is(err, ErrInvalidTarget) {
		t.Fatalf("không ai bị cắn: %v", err)
	}
	if err := Precheck(g.st, KindWitchPoison, "witch", nil, at(16, 1, 0)); err != nil {
		t.Fatalf("bình độc: %v", err)
	}
	g.st.Paused = true
	if err := Precheck(g.st, KindWitchPoison, "witch", nil, at(16, 1, 0)); !errors.Is(err, ErrPaused) {
		t.Fatalf("pause: %v", err)
	}

	// Người lên giàn không tự biểu quyết.
	g = game13(t)
	g.toPhase(PhaseTrial)
	g.st.Nominee = "v1"
	if err := Precheck(g.st, KindVote, "v1", nil, at(16, 20, 30)); !errors.Is(err, ErrNotYourRole) {
		t.Fatalf("nominee: %v", err)
	}
	if err := Precheck(g.st, KindVote, "v2", nil, at(16, 20, 30)); err != nil {
		t.Fatalf("v2: %v", err)
	}
	g.st.Nominee = ""
	if err := Precheck(g.st, KindVote, "v2", nil, at(16, 20, 30)); !errors.Is(err, ErrPhaseClosed) {
		t.Fatalf("không ai lên giàn: %v", err)
	}
}
