package werewolf

import "testing"

// C2: sói chọn khác nhau thì lựa chọn bấm sau cùng thắng.
func TestR1LastWolfChoiceWins(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindWolfBite, "w2", "v2")
	g.next()
	if g.st.Bitten != "v2" {
		t.Fatalf("bitten = %q, mong đợi v2 (w2 bấm sau)", g.st.Bitten)
	}
	g.reject(ErrPhaseClosed, act(KindWolfBite, "w1", "v3")) // khoá lúc 0h
	sameDeaths(t, g.next(), map[string]Cause{"v2": CauseBite})
}

func TestR1WolvesNeedTotalKmOfXPerAliveWolf(t *testing.T) {
	g := newGame(t, baseRoles())
	g.km["w1"], g.km["w2"], g.km["w3"] = 1000, 1000, 999 // 2999 m < 3 × 1000 m
	g.next()
	g.reject(ErrKmInsufficient, act(KindWolfBite, "w1", "v1"))

	g = newGame(t, baseRoles())
	g.km["w1"], g.km["w2"], g.km["w3"] = 3000, 0, 0 // đúng 3000 m: đủ, km dồn cho một sói cũng được
	g.next()
	g.do(KindWolfBite, "w2", "v1")
}

// "Lúc 0h": thợ săn bị treo bắn chết sói gánh km lúc 22h–23h thì tới 0h phe sói
// không còn đủ km, lựa chọn bị huỷ.
func TestR1WolfKmCheckedAgainAtMidnight(t *testing.T) {
	g := game13(t)
	g.hang("hunter")
	g.st.Km["w1"], g.st.Km["w2"], g.st.Km["w3"] = 3000, 0, 0
	g.do(KindWolfBite, "w2", "v1")
	g.do(KindHunterShoot, "hunter", "w1")
	g.next() // thợ săn bắn
	evs := g.next()
	if g.st.Bitten != "" || voids(evs)["w2/wolf_bite"] != VoidNoKm {
		t.Fatalf("bitten=%q voids=%v, mong đợi không ai bị cắn vì thiếu km", g.st.Bitten, voids(evs))
	}
}

func TestR1WolfCannotBiteOwnLover(t *testing.T) {
	roles := baseRoles()
	roles["cupid"] = Cupid
	g := newGame(t, roles)
	g.do(KindCupidPair, "cupid", "w1", "v1")
	g.next()
	// Cặp đôi áp lúc 0h, nên trước đó w1 vẫn bấm được; tới 0h lựa chọn bị huỷ.
	g.do(KindWolfBite, "w1", "v1")
	evs := g.next()
	if g.st.Bitten != "" || voids(evs)["w1/wolf_bite"] != VoidLoverTarget {
		t.Fatalf("bitten=%q voids=%v", g.st.Bitten, voids(evs))
	}
	g.toPhase(PhaseNight)
	g.reject(ErrLoverTarget, act(KindWolfBite, "w1", "v1"))
	g.do(KindWolfBite, "w2", "v1") // sói khác thì cắn được
}

func TestR2SeerPeeksOncePerNightAndWolfLoverStillWolf(t *testing.T) {
	g := game13(t)
	g.st.Lovers = []string{"v1", "w1"}
	if g.st.Peek("w1") != TeamWolves || g.st.Peek("v1") != TeamVillage || g.st.Peek("witch") != TeamVillage {
		t.Fatal("kết quả soi sai")
	}
	g.reject(ErrInvalidTarget, act(KindSeerPeek, "seer", "seer"))
	g.do(KindSeerPeek, "seer", "w1")
	g.reject(ErrAlreadyUsed, act(KindSeerPeek, "seer", "w2"))
	g.toPhase(PhaseNight)
	g.do(KindSeerPeek, "seer", "w2") // đêm sau soi tiếp được

	g = newGame(t, baseRoles())
	g.km["seer"] = 999
	g.next()
	g.reject(ErrKmInsufficient, act(KindSeerPeek, "seer", "w1"))
}

func TestR3GuardBlocksBiteButNotPoison(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindGuard, "guard", "v1")
	g.next()
	g.do(KindWitchPoison, "witch", "v2")
	sameDeaths(t, g.next(), map[string]Cause{"v2": CausePoison})

	g = game13(t)
	g.do(KindGuard, "guard", "v2")
	g.next()
	g.do(KindWitchPoison, "witch", "v2")
	sameDeaths(t, g.next(), map[string]Cause{"v2": CausePoison})
}

func TestR3GuardMaySelfGuardButNotRepeatLastValidNight(t *testing.T) {
	g := game13(t)
	g.do(KindGuard, "guard", "v1")
	g.toPhase(PhaseNight)
	g.reject(ErrGuardRepeat, act(KindGuard, "guard", "v1"))
	g.do(KindGuard, "guard", "v2")
	// v2 rời PSC, chết ở đầu lần chốt 10h, nên lần bảo vệ v2 bị huỷ và không
	// tính là "đêm trước": đêm 3 vẫn so với v1.
	evs := g.toPhase(PhaseDawn)
	evs = append(evs, g.next("v2")...)
	if voids(evs)["guard/guard"] != VoidTargetDead {
		t.Fatalf("voids = %v", voids(evs))
	}
	g.toPhase(PhaseNight)
	g.reject(ErrGuardRepeat, act(KindGuard, "guard", "v1"))
	g.do(KindGuard, "guard", "guard")
}

func TestR4WitchSeesBittenAndUsesBothPotionsOnce(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "v1")
	evs := g.next()
	if e := find(evs, EventWolvesTarget); e == nil || e.UID != "v1" || g.st.Bitten != "v1" {
		t.Fatalf("phù thuỷ phải thấy v1 bị cắn: %+v", evs)
	}
	g.do(KindWitchSave, "witch")
	g.do(KindWitchPoison, "witch", "v2")
	sameDeaths(t, g.next(), map[string]Cause{"v2": CausePoison})
	if g.st.SavePotion || g.st.PoisonPotion {
		t.Fatal("hai bình phải hết")
	}
	g.toPhase(PhaseNight)
	g.do(KindWolfBite, "w1", "v3")
	g.next()
	g.reject(ErrAlreadyUsed, act(KindWitchSave, "witch"))
	g.reject(ErrAlreadyUsed, act(KindWitchPoison, "witch", "v4"))
}

func TestR4WitchSelfSaveOnlyOnNightOne(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "witch")
	g.next()
	g.do(KindWitchSave, "witch")
	sameDeaths(t, g.next(), map[string]Cause{})

	g = game13(t)
	g.toPhase(PhaseNight) // sang đêm 2, chưa dùng bình nào
	g.do(KindWolfBite, "w1", "witch")
	g.next()
	g.reject(ErrInvalidTarget, act(KindWitchSave, "witch"))
}

func TestR4WitchCannotSaveAndPoisonSamePersonOrPoisonSelf(t *testing.T) {
	g := game13(t)
	g.next() // sói không cắn
	g.reject(ErrInvalidTarget, act(KindWitchSave, "witch"))

	g = game13(t)
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	g.reject(ErrInvalidTarget, act(KindWitchPoison, "witch", "witch"))
	g.do(KindWitchSave, "witch")
	g.reject(ErrInvalidTarget, act(KindWitchPoison, "witch", "v1"))

	g = game13(t)
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	g.do(KindWitchPoison, "witch", "v1")
	g.reject(ErrInvalidTarget, act(KindWitchSave, "witch"))
	// Đổi ý từng bình được: bỏ độc rồi cứu.
	if err := g.try(Action{Kind: KindWitchPoison, Actor: "witch", Clear: true}); err != nil {
		t.Fatal(err)
	}
	g.do(KindWitchSave, "witch")
}

// R15: thứ tự cắn → bảo vệ → phù thuỷ; cùng cứu một người thì sống, bình vẫn mất.
func TestR15GuardAndWitchSaveSamePersonPotionStillSpent(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindGuard, "guard", "v1")
	g.next()
	g.do(KindWitchSave, "witch")
	sameDeaths(t, g.next(), map[string]Cause{})
	if g.st.SavePotion {
		t.Fatal("bình cứu phải mất")
	}
}

// R15: người yêu chết theo rồi mới tới khung thợ săn; thợ săn chết theo người yêu
// vẫn được bắn (chỉ độc và rời PSC mới mất lượt).
func TestR15LoverDiesThenHunterTurnOpens(t *testing.T) {
	g := game13(t)
	g.st.Lovers = []string{"hunter", "v1"}
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	evs := g.next()
	if len(evs) < 3 || evs[0].UID != "v1" || evs[1].UID != "hunter" || evs[1].Cause != CauseLover || evs[2].Kind != EventHunterTurn {
		t.Fatalf("thứ tự event sai: %+v", evs)
	}
	if g.st.Hunter == nil || g.st.Hunter.Phase != PhaseDay {
		t.Fatalf("lượt thợ săn = %+v, mong đợi mở trong phase day (10h–12h)", g.st.Hunter)
	}
}
