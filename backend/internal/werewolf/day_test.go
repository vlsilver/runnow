package werewolf

import (
	"reflect"
	"testing"
	"time"
)

func TestR5HangedHunterShootsOnce(t *testing.T) {
	g := game13(t)
	evs := g.hang("hunter")
	if find(evs, EventHunterTurn) == nil || g.st.Hunter == nil || g.st.Hunter.Phase != PhaseNight {
		t.Fatalf("thợ săn bị treo phải được bắn trong đêm sau: %+v", g.st.Hunter)
	}
	g.reject(ErrInvalidTarget, act(KindHunterShoot, "hunter", "hunter"))
	g.do(KindHunterShoot, "hunter", "v1")
	g.reject(ErrAlreadyUsed, act(KindHunterShoot, "hunter", "v2"))
	sameDeaths(t, g.next(), map[string]Cause{"v1": CauseShot})
	g.reject(ErrPhaseClosed, act(KindHunterShoot, "hunter", "v2"))
}

func TestR5PoisonedOrLowKmHunterCannotShoot(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "hunter") // vừa bị cắn vừa bị độc: chết vì độc (C4)
	g.next()
	g.do(KindWitchPoison, "witch", "hunter")
	evs := g.next()
	if deaths(evs)["hunter"] != CausePoison || find(evs, EventHunterTurn) != nil {
		t.Fatalf("thợ săn bị độc không được bắn: %+v", evs)
	}
	g.reject(ErrPhaseClosed, act(KindHunterShoot, "hunter", "w1"))

	g = game13(t)
	g.km["hunter"] = 999 // km lần chốt gần nhất (lúc treo) < X
	if evs := g.hang("hunter"); find(evs, EventHunterTurn) != nil {
		t.Fatal("thợ săn thiếu km không được bắn")
	}
}

func TestR6CupidPairsOnceAndLoversDieTogether(t *testing.T) {
	roles := baseRoles()
	roles["cupid"] = Cupid
	g := newGame(t, roles)
	g.do(KindCupidPair, "cupid", "v1", "v2")
	g.reject(ErrAlreadyUsed, act(KindCupidPair, "cupid", "v3", "v4"))
	g.next()
	g.do(KindWolfBite, "w1", "v1")
	evs := g.next()
	if e := find(evs, EventLovers); e == nil || e.Draw || !reflect.DeepEqual(e.Targets, []string{"v1", "v2"}) {
		t.Fatalf("cặp đôi = %+v", e)
	}
	g.reject(ErrPhaseClosed, act(KindCupidPair, "cupid", "v3", "v4")) // quá 0h đêm 1
	sameDeaths(t, g.next(), map[string]Cause{"v1": CauseBite, "v2": CauseLover})
	g.toPhase(PhaseNight)
	g.reject(ErrPhaseClosed, act(KindCupidPair, "cupid", "v3", "v4")) // đêm 2 cũng là phase night nhưng đã quá lượt ghép
}

// Cupid ghép xong rồi rời PSC trước 0h: lựa chọn bị huỷ và không ai thành cặp,
// vì bot chỉ ghép thay khi Cupid còn sống (R19).
func TestR6CupidLeavesBeforeLockPairIsVoided(t *testing.T) {
	roles := baseRoles()
	roles["cupid"] = Cupid
	g := newGame(t, roles)
	g.do(KindCupidPair, "cupid", "v1", "v2")
	g.next("cupid")
	evs := g.next()
	if e := find(evs, EventLovers); e != nil || len(g.st.Lovers) != 0 {
		t.Fatalf("Cupid đã rời mà vẫn có cặp: %+v, lovers %v", e, g.st.Lovers)
	}
	if r := voids(evs)["cupid/"+string(KindCupidPair)]; r != VoidActorDead {
		t.Fatalf("void = %v, mong đợi %s", voids(evs), VoidActorDead)
	}
}

// Quá 0h chưa ghép thì bot ghép ngẫu nhiên, không gồm Cupid; cùng seed ra cùng cặp.
func TestR6UnpairedCupidGetsDeterministicRandomPairWithoutCupid(t *testing.T) {
	roles := baseRoles()
	roles["cupid"] = Cupid
	var first []string
	for seed := byte(0); seed < 200; seed++ {
		st := NewState(Seed{seed}, Config{}, roles, testStart)
		st, _, _ = Step(st, Inputs{})
		st, evs, _ := Step(st, Inputs{})
		e := find(evs, EventLovers)
		if e == nil || !e.Draw || len(st.Lovers) != 2 || st.Lovers[0] == st.Lovers[1] {
			t.Fatalf("seed %d: cặp = %+v", seed, e)
		}
		for _, uid := range st.Lovers {
			if uid == "cupid" {
				t.Fatalf("seed %d: bot ghép cả Cupid", seed)
			}
		}
		if seed == 0 {
			first = st.Lovers
		}
	}
	st := NewState(Seed{0}, Config{}, roles, testStart)
	st, _, _ = Step(st, Inputs{})
	st, _, _ = Step(st, Inputs{})
	if !reflect.DeepEqual(st.Lovers, first) {
		t.Fatal("cùng seed phải ra cùng cặp")
	}
}

// Ghép Sói với Dân thì thành phe ba; ghép 2 Sói vẫn là phe Sói.
func TestR6MixedCoupleIsThirdTeamTwoWolvesStayWolves(t *testing.T) {
	g := game13(t)
	g.st.Lovers = []string{"v1", "w1"}
	if !g.st.mixedCouple() {
		t.Fatal("Sói + Dân phải là phe ba")
	}
	g.st.Lovers = []string{"w1", "w2"}
	if g.st.mixedCouple() {
		t.Fatal("2 Sói vẫn là phe Sói")
	}
	// 2 Sói yêu nhau vẫn tính là sói khi xét thắng: w1, w2 còn sống với 2 người.
	g.setDead("w3", "seer", "guard", "witch", "hunter", "v1", "v2", "v3", "v4")
	if g.st.winner() != TeamWolves {
		t.Fatalf("winner = %q", g.st.winner())
	}
}

func TestR7VillagerOnlyNominatesAndVotes(t *testing.T) {
	g := game13(t)
	for _, k := range []Kind{KindWolfBite, KindSeerPeek, KindGuard} {
		g.reject(ErrNotYourRole, act(k, "v1", "v2"))
	}
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v1", "v2")
	g.next()
	g.vote("v3", ChoiceHang)
}

func TestR10ConfigSnapshotAtStart(t *testing.T) {
	cfg := Config{KmPerUnit: 2, Disabled: []Role{Witch}}
	st := NewState(Seed{1}, cfg, baseRoles(), testStart)
	cfg.Disabled[0] = Hunter
	if st.Config.Disabled[0] != Witch || st.Config.unitMeters() != 2000 {
		t.Fatalf("cấu hình trong ván bị đổi theo: %+v", st.Config)
	}
}

func TestR12FirstNightIsFirst22hAtLeastTwoHoursAfterStart(t *testing.T) {
	day := func(d, h, m int) time.Time { return time.Date(2026, 10, d, h, m, 0, 0, vietnam) }
	for _, c := range []struct{ start, want time.Time }{
		{day(15, 9, 0), day(15, 22, 0)},
		{day(15, 20, 0), day(15, 22, 0)}, // đúng 2 giờ: được
		{day(15, 20, 1), day(16, 22, 0)},
		{day(15, 23, 30), day(16, 22, 0)},
		{time.Date(2026, 10, 15, 14, 30, 0, 0, time.UTC), day(16, 22, 0)}, // 21:30 VN
	} {
		if got := FirstNight(c.start); !got.Equal(c.want) {
			t.Errorf("start %s: đêm 1 = %s, mong đợi %s", c.start, got, c.want)
		}
	}
	// Không vào giữa ván được: ai không có trong ván thì không hành động được.
	g := game13(t)
	g.reject(ErrNotYourRole, act(KindNominate, "stranger", "v1"))
	// Cupid ghép được từ lúc Start tới 0h đêm 1.
	roles := baseRoles()
	roles["cupid"] = Cupid
	g = newGame(t, roles)
	g.next()
	g.do(KindCupidPair, "cupid", "cupid", "v1")
}

// R13: ván không giới hạn số vòng. Chưa phe nào thắng thì ván chạy tiếp, kể
// cả qua vòng 14 (trước đây hết vòng 14 thì Dân thắng).
func TestR13NoRoundLimit(t *testing.T) {
	g := game13(t)
	for g.st.Round <= 30 {
		if g.st.Phase == PhaseEnded {
			t.Fatalf("kết thúc ở vòng %d, winner %s", g.st.Round, g.st.Winner)
		}
		g.next()
	}
}

func TestR14PausedRejectsActionsAndSteps(t *testing.T) {
	g := game13(t)
	g.st.Paused = true
	g.reject(ErrPaused, act(KindWolfBite, "w1", "v1"))
	if _, _, err := Step(g.st, Inputs{}); err != ErrNotRunning {
		t.Fatalf("Step lúc pause: %v", err)
	}
}

func TestR16NomineeWhoLeftSkipsVote(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v2", "v1")
	g.next()
	g.vote("v3", ChoiceHang)
	evs := g.next("v1")
	if e := find(evs, EventVoteResult); e == nil || e.Reason != ReasonNoTrial || e.Hanged {
		t.Fatalf("vote = %+v", e)
	}
	sameDeaths(t, evs, map[string]Cause{"v1": CauseLeft})
	if voids(evs)["v3/vote"] != VoidTargetDead {
		t.Fatalf("voids = %v", voids(evs))
	}
}

// R16: người rời PSC → treo → người yêu chết theo → khung thợ săn.
func TestR16DayOrderLeaverHangLoverHunter(t *testing.T) {
	g := game13(t)
	g.st.Lovers = []string{"hunter", "v3"}
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v2", "v1")
	g.next()
	for _, v := range []string{"v2", "v4", "v5", "v6"} {
		g.vote(v, ChoiceHang)
	}
	evs := g.next("v3")
	var order []string
	for _, e := range evs {
		if e.Kind == EventDeath || e.Kind == EventHunterTurn {
			order = append(order, string(e.Kind)+":"+e.UID+":"+string(e.Cause))
		}
	}
	want := []string{"death:v3:left", "death:v1:hang", "death:hunter:lover", "hunter_turn:hunter:"}
	if !reflect.DeepEqual(order, want) {
		t.Fatalf("thứ tự = %v, mong đợi %v", order, want)
	}
}

func TestR17HunterShotKillsLoverToo(t *testing.T) {
	g := game13(t)
	g.st.Lovers = []string{"v1", "v2"}
	g.hang("hunter")
	g.do(KindHunterShoot, "hunter", "v1")
	sameDeaths(t, g.next(), map[string]Cause{"v1": CauseShot, "v2": CauseLover})
}

// R18: kết quả còn phụ thuộc phát bắn thì chưa báo thắng.
func TestR18NoWinnerWhileHunterShotCanStillChangeIt(t *testing.T) {
	g := game13(t)
	g.setDead("w3", "seer", "guard", "witch", "v3", "v4", "v5", "v6") // còn w1 w2 hunter v1 v2
	g.do(KindWolfBite, "w1", "hunter")
	g.next()
	evs := g.next() // còn w1 w2 v1 v2: sói thắng nếu thợ săn không bắn
	if find(evs, EventWinner) != nil || g.st.Phase != PhaseDay || g.st.Hunter == nil {
		t.Fatalf("chưa được báo thắng khi thợ săn còn bắn: %+v", evs)
	}
	g.do(KindHunterShoot, "hunter", "w1")
	evs = g.next()
	if find(evs, EventWinner) != nil {
		t.Fatalf("bắn w1 xong còn w2 v1 v2, chưa ai thắng: %+v", evs)
	}
	// Hết khung mà không bắn thì giờ mới báo sói thắng.
	g = game13(t)
	g.setDead("w3", "seer", "guard", "witch", "v3", "v4", "v5", "v6")
	g.do(KindWolfBite, "w1", "hunter")
	g.next()
	g.next()
	if evs := g.next(); find(evs, EventWinner) == nil || g.st.Winner != TeamWolves {
		t.Fatalf("thợ săn không bắn: winner = %q", g.st.Winner)
	}
}

// Dân đã thắng (hết sói) thì phát bắn không đổi được gì: kết thúc luôn, huỷ lượt bắn.
func TestR18VillageWinDoesNotWaitForHunter(t *testing.T) {
	g := game13(t)
	g.setDead("w2", "w3")
	g.do(KindWolfBite, "w1", "hunter")
	g.next()
	g.do(KindWitchPoison, "witch", "w1")
	evs := g.next()
	if g.st.Winner != TeamVillage || g.st.Hunter != nil || find(evs, EventHunterTurn) != nil {
		t.Fatalf("winner=%s hunter=%+v evs=%+v", g.st.Winner, g.st.Hunter, evs)
	}
}

// R19: đề cử của người đã chết và đề cử nhắm vào người đã chết bị huỷ.
func TestR19NominationsOfAndOnTheDeadAreVoided(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "hunter")
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v1", "v2")
	g.do(KindNominate, "v2", "v3")
	g.do(KindNominate, "v4", "v3")
	g.do(KindNominate, "v3", "v5")
	g.do(KindHunterShoot, "hunter", "v3")
	evs := g.next()
	v := voids(evs)
	if v["v2/nominate"] != VoidTargetDead || v["v4/nominate"] != VoidTargetDead || v["v3/nominate"] != VoidActorDead {
		t.Fatalf("voids = %v", v)
	}
	evs = g.next()
	if e := find(evs, EventNominee); e == nil || e.UID != "v2" || e.Draw {
		t.Fatalf("lên giàn = %+v, mong đợi v2 (v3 đã chết)", e)
	}
}

// R20: thợ săn bị treo bắn trúng mục tiêu sói đang chọn thì sói chọn lại tới 0h.
func TestR20HunterShotOnWolfTargetLetsWolvesRechoose(t *testing.T) {
	g := game13(t)
	g.hang("hunter")
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindHunterShoot, "hunter", "v1")
	evs := g.next()
	if voids(evs)["w1/wolf_bite"] != VoidTargetDead {
		t.Fatalf("voids = %v", voids(evs))
	}
	g.do(KindWolfBite, "w2", "v2")
	g.next()
	if g.st.Bitten != "v2" {
		t.Fatalf("bitten = %q, mong đợi v2", g.st.Bitten)
	}

	g = game13(t)
	g.hang("hunter")
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindHunterShoot, "hunter", "v1")
	g.next()
	g.next() // không ai chọn lại thì mất lượt
	if g.st.Bitten != "" {
		t.Fatalf("bitten = %q, mong đợi không ai", g.st.Bitten)
	}
}

func TestR20ShotThatEndsGameVoidsNightActions(t *testing.T) {
	g := game13(t)
	g.setDead("w2", "w3")
	g.hang("hunter")
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindSeerPeek, "seer", "v2")
	g.do(KindHunterShoot, "hunter", "w1")
	evs := g.next()
	v := voids(evs)
	if g.st.Winner != TeamVillage || v["w1/wolf_bite"] != VoidActorDead || v["seer/seer_peek"] != VoidGameOver {
		t.Fatalf("winner=%s voids=%v", g.st.Winner, v)
	}
}

// R21: Validate không đổi state; Step không sửa state đầu vào (replay so được).
func TestR21OnlyStepChangesStateAndNeverMutatesInput(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "v1")
	before := g.st.clone()
	if !reflect.DeepEqual(before, g.st) {
		t.Fatal("clone sai")
	}
	g.next()
	g.do(KindWitchPoison, "witch", "v2")
	mid := g.st.clone()
	old := g.st
	g.next()
	if !reflect.DeepEqual(old, mid) {
		t.Fatal("Step sửa state đầu vào")
	}
	if !old.alive("v1") || g.st.alive("v1") {
		t.Fatal("chỉ state mới có v1 chết")
	}
}

func TestR22VillageWinsWhenNoWolfLeftIncludingWolfLover(t *testing.T) {
	g := game13(t)
	g.setDead("w2", "w3")
	g.st.Lovers = []string{"v1", "w1"}
	if g.st.winner() != "" {
		t.Fatal("sói đang yêu còn sống thì Dân chưa thắng")
	}
	evs := g.hang("w1")
	if g.st.Winner != TeamVillage || deaths(evs)["v1"] != CauseLover {
		t.Fatalf("winner=%s evs=%+v", g.st.Winner, evs)
	}
}

func TestR23WolvesWinWhenFreeWolvesAtLeastTheRest(t *testing.T) {
	g := game13(t)
	g.setDead("w3", "seer", "guard", "witch", "hunter", "v4", "v5", "v6") // còn w1 w2 v1 v2 v3
	g.do(KindWolfBite, "w1", "v3")
	g.toPhase(PhaseDay)
	if g.st.Winner != TeamWolves {
		t.Fatalf("2 sói còn 2 dân: winner = %q", g.st.Winner)
	}
	// Sói đang yêu tính vào phe ba: w1 w2(yêu v1) v1 v2 → 1 sói tự do với 3 người.
	g = game13(t)
	g.setDead("w3", "seer", "guard", "witch", "hunter", "v4", "v5", "v6")
	g.st.Lovers = []string{"v1", "w2"}
	g.do(KindWolfBite, "w1", "v3")
	g.toPhase(PhaseDay)
	if g.st.Winner != "" {
		t.Fatalf("winner = %q, mong đợi chưa ai thắng", g.st.Winner)
	}
}

func TestR24LoversWinWhenOnlyTheTwoRemain(t *testing.T) {
	g := game13(t)
	g.setDead("w2", "w3", "seer", "guard", "witch", "hunter", "v3", "v4", "v5", "v6") // còn w1 v1 v2
	g.st.Lovers = []string{"v1", "w1"}
	g.do(KindWolfBite, "w1", "v2")
	g.toPhase(PhaseDay)
	if g.st.Winner != TeamLovers {
		t.Fatalf("winner = %q", g.st.Winner)
	}
	// Cupid ghép người khác thì vẫn ở phe Dân: còn Cupid thì cặp chưa thắng.
	roles := baseRoles()
	roles["cupid"] = Cupid
	g = newGame(t, roles)
	g.do(KindCupidPair, "cupid", "v1", "w1")
	g.next()
	g.setDead("w2", "w3", "seer", "guard", "witch", "hunter", "v3", "v4", "v5", "v6") // còn w1 v1 v2 cupid
	g.do(KindWolfBite, "w1", "v2")
	g.toPhase(PhaseDay)
	if g.st.Winner != "" {
		t.Fatalf("còn Cupid: winner = %q", g.st.Winner)
	}
	// Cupid tự ghép mình với sói thì thuộc cặp.
	g = newGame(t, roles)
	g.do(KindCupidPair, "cupid", "cupid", "w1")
	g.next()
	g.setDead("w2", "w3", "seer", "guard", "witch", "hunter", "v1", "v3", "v4", "v5", "v6") // còn w1 cupid v2
	g.do(KindWolfBite, "w1", "v2")
	g.toPhase(PhaseDay)
	if g.st.Winner != TeamLovers {
		t.Fatalf("Cupid tự ghép: winner = %q", g.st.Winner)
	}
}

func TestR32DeathRevealsRole(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "seer")
	g.toPhase(PhaseDay)
	evs := g.hang("w2")
	for _, e := range evs {
		if e.Kind == EventDeath && e.UID == "w2" && e.Role == Wolf {
			return
		}
	}
	t.Fatalf("lật bài thiếu: %+v", evs)
}

func TestR33LeaverDiesAtNextResolutionLoverFollowsHunterCannotShoot(t *testing.T) {
	g := game13(t)
	g.st.Lovers = []string{"hunter", "v1"}
	g.next()
	evs := g.next("hunter")
	sameDeaths(t, evs, map[string]Cause{"hunter": CauseLeft, "v1": CauseLover})
	if find(evs, EventHunterTurn) != nil {
		t.Fatal("thợ săn rời PSC không được bắn")
	}
}

func TestR34NobodyActsNobodyDies(t *testing.T) {
	g := game13(t)
	evs := g.toPhase(PhaseNight)
	sameDeaths(t, evs, map[string]Cause{})
	if g.st.Round != 2 || find(evs, EventWolvesTarget).Reason != ReasonNoChoice {
		t.Fatalf("round=%d evs=%+v", g.st.Round, evs)
	}
}
