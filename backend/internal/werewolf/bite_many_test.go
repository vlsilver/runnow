package werewolf

import (
	"encoding/json"
	"slices"
	"testing"
)

// Luật km, cắn tối đa 2: v2 2 phiếu, v1 1 phiếu → cắn cả hai, sáng ra cả hai
// chết (không ai bảo vệ, không ai cứu).
func TestMaxBiteKmRulesTopTwoVotesBitten(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset, g.st.Config.MaxBite = RulesetKm, 2
	e := bite(g, [2]string{"w2", "v2"}, [2]string{"w3", "v2"}, [2]string{"w1", "v1"})
	if e == nil || e.UID != "v2" || !slices.Equal(e.Targets, []string{"v2", "v1"}) || e.Draw {
		t.Fatalf("cắn = %+v", e)
	}
	if !slices.Equal(g.st.Bites, []string{"v2", "v1"}) || g.st.Bitten != "v2" {
		t.Fatalf("bites = %v, bitten = %q", g.st.Bites, g.st.Bitten)
	}
	sameDeaths(t, g.next(), map[string]Cause{"v1": CauseBite, "v2": CauseBite})
}

// Ba người mỗi người 1 phiếu, cùng km, cắn tối đa 2: suất thứ hai bốc thăm.
func TestMaxBiteKmRulesTieAtLastSeatIsDraw(t *testing.T) {
	g := game13(t)
	g.st.Config.Ruleset, g.st.Config.MaxBite = RulesetKm, 2
	e := bite(g, [2]string{"w1", "v1"}, [2]string{"w2", "v2"}, [2]string{"w3", "v3"})
	if e == nil || len(e.Targets) != 2 || !e.Draw {
		t.Fatalf("cắn = %+v", e)
	}
}

// Ván cũ, cắn tối đa 2: hai lựa chọn bấm sau cùng thắng (w3 rồi w2).
func TestMaxBiteOldRulesetLastTwoPicksWin(t *testing.T) {
	g := game13(t)
	g.st.Config.MaxBite = 2
	e := bite(g, [2]string{"w1", "v1"}, [2]string{"w2", "v2"}, [2]string{"w3", "v3"})
	if e == nil || !slices.Equal(e.Targets, []string{"v3", "v2"}) {
		t.Fatalf("cắn = %+v", e)
	}
}

// Ván cũ, cắn tối đa 2 mà cả phe chọn một người: chỉ cắn người đó, sự kiện
// giữ dạng một người (không có Targets).
func TestMaxBiteSameTargetBitesOnce(t *testing.T) {
	g := game13(t)
	g.st.Config.MaxBite = 2
	e := bite(g, [2]string{"w1", "v1"}, [2]string{"w2", "v1"})
	if e == nil || e.UID != "v1" || e.Targets != nil || !slices.Equal(g.st.BittenUIDs(), []string{"v1"}) {
		t.Fatalf("cắn = %+v, bites = %v", e, g.st.BittenUIDs())
	}
}

// Cắn v1 và v2: Bảo vệ đỡ v2, phù thuỷ phải chọn người cứu trong số bị cắn,
// cứu v1 thì không độc v1 được. Sáng ra không ai chết.
func TestMaxBiteGuardAndWitchSaveOnePersonEach(t *testing.T) {
	g := game13(t)
	g.st.Config.MaxBite = 2
	g.do(KindGuard, "guard", "v2")
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindWolfBite, "w2", "v2")
	g.next()
	g.reject(ErrInvalidTarget, act(KindWitchSave, "witch"))
	g.reject(ErrInvalidTarget, act(KindWitchSave, "witch", "v5"))
	g.do(KindWitchSave, "witch", "v1")
	g.reject(ErrInvalidTarget, act(KindWitchPoison, "witch", "v1"))
	sameDeaths(t, g.next(), map[string]Cause{})
	if g.st.SavePotion || len(g.st.BittenUIDs()) != 0 {
		t.Fatalf("bình cứu phải hết, bites phải trống: %v", g.st.BittenUIDs())
	}
}

// Cứu một người thì người còn lại vẫn chết.
func TestMaxBiteWitchSavesOnlyChosenPerson(t *testing.T) {
	g := game13(t)
	g.st.Config.MaxBite = 2
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindWolfBite, "w2", "v2")
	g.next()
	g.do(KindWitchSave, "witch", "v2")
	sameDeaths(t, g.next(), map[string]Cause{"v1": CauseBite})
}

// Cắn Im Lặng với hai người bị cắn: cả hai chết sau lần chốt biểu quyết.
func TestMaxBiteDarkSilentDelaysEveryBite(t *testing.T) {
	g := darkGame(t, Config{MaxBite: 2})
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindWolfBite, "w2", "v2")
	g.dark("w3", DarkSilent)
	g.next()                                    // 0h
	sameDeaths(t, g.next(), map[string]Cause{}) // 10h
	if !slices.Equal(g.st.Silenced, []string{"v2", "v1"}) || g.st.Delayed != "v2" {
		t.Fatalf("silenced = %v, delayed = %q", g.st.Silenced, g.st.Delayed)
	}
	g.do(KindNominate, "v3", "v4")
	g.next()                                                                    // 20h
	sameDeaths(t, g.next(), map[string]Cause{"v1": CauseBite, "v2": CauseBite}) // 22h
}

// State ghi trước khi có Bites chỉ có bitten/delayed: vẫn đọc ra người bị cắn.
func TestBittenLegacyStateStillRead(t *testing.T) {
	var st State
	if err := json.Unmarshal([]byte(`{"bitten":"v1","delayed":"v2"}`), &st); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(st.BittenUIDs(), []string{"v1"}) || !slices.Equal(st.delayedUIDs(), []string{"v2"}) {
		t.Fatalf("bites = %v, delayed = %v", st.BittenUIDs(), st.delayedUIDs())
	}
}

func TestMaxBiteConfigRange(t *testing.T) {
	for _, n := range []int{-1, MaxBites + 1} {
		if err := (Config{MaxBite: n}).Validate(); err == nil {
			t.Fatalf("maxBite %d phải bị từ chối", n)
		}
	}
	if (Config{}).BiteSeats() != 1 || (Config{MaxBite: 3}).BiteSeats() != 3 {
		t.Fatal("BiteSeats sai")
	}
}
