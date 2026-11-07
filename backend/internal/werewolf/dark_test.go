package werewolf

import "testing"

// darkGame là ván 13 người có đủ năm đặc quyền, mọi người 5 km, qua mốc 22h đêm 1.
func darkGame(t *testing.T, cfg Config) *tg {
	t.Helper()
	g := newGame(t, baseRoles())
	cfg.Dark = DarkPowers()
	g.st.Config = cfg
	g.next()
	return g
}

func (g *tg) dark(actor string, p DarkPower, targets ...string) {
	g.t.Helper()
	if err := g.try(Action{Kind: KindWolfDark, Actor: actor, Choice: string(p), Targets: targets}); err != nil {
		g.t.Fatalf("%s chọn %s %v bị từ chối: %v", actor, p, targets, err)
	}
}

// Cắn Im Lặng: sáng không ai chết, người bị cắn vẫn biểu quyết, chốt biểu quyết
// xong mới chết.
func TestDarkSilentBiteDiesAfterTrial(t *testing.T) {
	g := darkGame(t, Config{})
	g.do(KindWolfBite, "w1", "v1")
	g.dark("w2", DarkSilent)
	g.next() // 0h
	if g.st.Bitten != "v1" {
		t.Fatalf("phù thuỷ phải thấy v1 bị cắn, thấy %q", g.st.Bitten)
	}
	sameDeaths(t, g.next(), map[string]Cause{}) // 10h
	g.do(KindNominate, "v1", "v2")
	g.next() // 20h
	g.vote("v1", ChoiceSpare)
	evs := g.next() // 22h
	sameDeaths(t, evs, map[string]Cause{"v1": CauseBite})
	if r := find(evs, EventVoteResult); r == nil || r.Spare != 1 {
		t.Fatalf("phiếu của v1 phải được tính trước khi v1 chết: %+v", r)
	}
}

// Đột Biến: Bảo vệ che đúng người bị cắn mà người đó vẫn chết; chỉ một lần cả ván.
func TestDarkPierceIgnoresGuardOnce(t *testing.T) {
	g := darkGame(t, Config{})
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindGuard, "guard", "v1")
	g.dark("w1", DarkPierce)
	g.next()
	sameDeaths(t, g.next(), map[string]Cause{"v1": CauseBite})
	g.toPhase(PhaseNight)
	g.reject(ErrAlreadyUsed, Action{Kind: KindWolfDark, Actor: "w1", Choice: string(DarkPierce)})
}

// Tàng Hình và Vu Khống đổi kết quả soi: trong đêm theo lựa chọn đang chờ,
// sau 0h theo bản đã chốt.
func TestDarkCloakAndFrameChangePeek(t *testing.T) {
	g := darkGame(t, Config{})
	g.dark("w2", DarkCloak, "w1")
	pending := func() *DarkUse {
		var acts []Action
		for _, a := range g.actions {
			acts = append(acts, a)
		}
		return PendingDark(g.st, acts)
	}
	if got := g.st.PeekWith("w1", pending()); got != TeamVillage {
		t.Fatalf("soi w1 đang Tàng Hình = %s, mong đợi Dân", got)
	}
	g.dark("w3", DarkFrame, "v2") // bấm sau thì thắng, như cú cắn
	if got := g.st.PeekWith("w1", pending()); got != TeamWolves {
		t.Fatalf("Tàng Hình đã bị thay mà soi w1 vẫn ra %s", got)
	}
	g.next() // 0h
	if g.st.Peek("v2") != TeamWolves || g.st.Peek("v3") != TeamVillage {
		t.Fatalf("sau 0h: soi v2 = %s, v3 = %s", g.st.Peek("v2"), g.st.Peek("v3"))
	}
	g.reject(ErrPhaseClosed, Action{Kind: KindWolfDark, Actor: "w1", Choice: string(DarkCloak), Targets: []string{"w2"}})
}

// Tàng Hình mỗi sói một lần; Vu Khống chỉ nhắm người không phải sói.
func TestDarkTargets(t *testing.T) {
	g := darkGame(t, Config{})
	g.reject(ErrInvalidTarget, Action{Kind: KindWolfDark, Actor: "w1", Choice: string(DarkFrame), Targets: []string{"w2"}})
	g.reject(ErrInvalidTarget, Action{Kind: KindWolfDark, Actor: "w1", Choice: string(DarkCloak), Targets: []string{"v1"}})
	g.reject(ErrInvalidTarget, Action{Kind: KindWolfDark, Actor: "w1", Choice: string(DarkSilent), Targets: []string{"v1"}})
	g.dark("w1", DarkCloak, "w1")
	g.toPhase(PhaseNight)
	g.reject(ErrAlreadyUsed, Action{Kind: KindWolfDark, Actor: "w1", Choice: string(DarkCloak), Targets: []string{"w1"}})
	g.dark("w1", DarkCloak, "w2")
}

// Phiếu Đôi: phiếu của sói được chọn tính 2 ở phiên biểu quyết hôm sau.
func TestDarkVoteCountsTwice(t *testing.T) {
	g := darkGame(t, Config{Vote: VoteFlat})
	g.dark("w1", DarkVote, "w2")
	g.toPhase(PhaseDay)
	g.do(KindNominate, "w1", "v1")
	g.next()
	g.vote("w2", ChoiceHang)
	g.vote("v2", ChoiceSpare)
	r := find(g.next(), EventVoteResult)
	if r == nil || r.Hang != 2 || r.Spare != 1 || !r.Hanged {
		t.Fatalf("kết quả phiên = %+v, mong đợi Treo 2, Tha 1", r)
	}
}

// Mở khoá: tổng km sói còn sống phải đủ DarkKm × số sói còn sống. 3 sói, mức
// 2 km: 5,9 km thì khoá, 6 km thì mở.
func TestDarkUnlockByWolfKm(t *testing.T) {
	g := newGame(t, baseRoles())
	g.st.Config = Config{Dark: DarkPowers(), DarkKm: 2, SkillKm: map[Role]float64{Wolf: 0}}
	g.km["w1"], g.km["w2"], g.km["w3"] = 5900, 0, 0
	g.next()
	g.reject(ErrKmInsufficient, Action{Kind: KindWolfDark, Actor: "w1", Choice: string(DarkSilent)})
	g.do(KindWolfBite, "w1", "v1") // thiếu km đặc quyền vẫn cắn được

	g = newGame(t, baseRoles())
	g.st.Config = Config{Dark: DarkPowers(), DarkKm: 2}
	g.km["w1"], g.km["w2"], g.km["w3"] = 6000, 0, 0
	g.next()
	g.dark("w2", DarkSilent)
}

// Ván không dùng km: đặc quyền nào cũng một lần cả ván, không cần km.
func TestDarkKmOffOncePerGame(t *testing.T) {
	g := darkGame(t, Config{KmOff: true})
	g.dark("w1", DarkFrame, "v1")
	g.toPhase(PhaseNight)
	g.reject(ErrAlreadyUsed, Action{Kind: KindWolfDark, Actor: "w1", Choice: string(DarkFrame), Targets: []string{"v2"}})
	g.dark("w1", DarkVote, "w1")
}

// Cắn Im Lặng mà không cắn ai thì không dùng, không mất lượt.
func TestDarkSilentWithoutBiteKeepsTurn(t *testing.T) {
	g := darkGame(t, Config{KmOff: true})
	g.dark("w1", DarkSilent)
	evs := g.next()
	if voids(evs)["w1/wolf_dark"] != VoidNoBite || g.st.Dark != nil {
		t.Fatalf("void = %v, dark = %+v", voids(evs), g.st.Dark)
	}
	g.toPhase(PhaseNight)
	g.dark("w1", DarkSilent)
}
