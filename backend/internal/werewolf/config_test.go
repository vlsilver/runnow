package werewolf

import (
	"slices"
	"testing"
)

// ExtraWolves lấy chỗ của Dân, vai đặc biệt giữ nguyên; sói không quá 1/3 số
// người (làm tròn xuống). Số mong đợi tính tay từ bảng 1.2.
func TestExtraWolvesReplaceVillagersUpToAThird(t *testing.T) {
	cases := []struct {
		n, extra int
		want     map[Role]int
	}{
		{10, 1, map[Role]int{Wolf: 3, Seer: 1, Guard: 1, Villager: 5}},
		{10, 2, map[Role]int{Wolf: 3, Seer: 1, Guard: 1, Villager: 5}}, // trần 10/3 = 3
		{13, 1, map[Role]int{Wolf: 4, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 4}},
		{13, 2, map[Role]int{Wolf: 4, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 4}}, // trần 13/3 = 4
		{21, 2, map[Role]int{Wolf: 7, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 9}},
	}
	for _, c := range cases {
		roles, err := Deal(Seed{1}, uids(c.n), Config{ExtraWolves: c.extra})
		if err != nil {
			t.Fatalf("n=%d extra=%d: %v", c.n, c.extra, err)
		}
		got := countRoles(roles)
		for role, want := range c.want {
			if got[role] != want {
				t.Fatalf("n=%d extra=%d: %s = %d, mong đợi %d (cả bộ %v)", c.n, c.extra, role, got[role], want, got)
			}
		}
	}
}

// newGameCfg như newGame nhưng với cấu hình riêng.
func newGameCfg(t *testing.T, cfg Config) *tg {
	g := newGame(t, baseRoles())
	g.st.Config = cfg
	return g
}

// trialCfg là trial (v1 lên giàn, 12 người bỏ phiếu) với cấu hình riêng.
func trialCfg(t *testing.T, cfg Config, km map[string]float64) *tg {
	g := game13(t)
	g.st.Config = cfg
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

func zeroKm() map[string]float64 {
	km := map[string]float64{}
	for uid := range baseRoles() {
		km[uid] = 0
	}
	return km
}

// KmOff: cả làng 0 km mà kỹ năng vẫn dùng được và không ai mất phiếu.
func TestKmOffNeedsNoKmForSkillsOrVotes(t *testing.T) {
	g := newGameCfg(t, Config{KmOff: true})
	g.km = zeroKm()
	g.next()
	g.do(KindSeerPeek, "seer", "w1")
	g.do(KindGuard, "guard", "v2")
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	if g.st.Bitten != "v1" {
		t.Fatalf("bitten = %q, mong đợi v1", g.st.Bitten)
	}

	g = trialCfg(t, Config{KmOff: true}, zeroKm())
	voteSixSix(g)
	evs := g.next()
	if find(evs, EventVoteCut) != nil {
		t.Fatal("tắt km thì không ai mất phiếu")
	}
	if e := find(evs, EventVoteResult); e.Hang != 6 || e.Spare != 6 {
		t.Fatalf("kết quả = %+v, mong đợi 6–6", e)
	}
}

// VoteFlat: còn km cho kỹ năng nhưng phiếu không theo km.
func TestVoteFlatCountsEveryVote(t *testing.T) {
	g := trialCfg(t, Config{Vote: VoteFlat}, zeroKm())
	voteSixSix(g)
	evs := g.next()
	if find(evs, EventVoteCut) != nil {
		t.Fatal("luật flat thì không ai mất phiếu")
	}
	if e := find(evs, EventVoteResult); e.Hang != 6 || e.Spare != 6 {
		t.Fatalf("kết quả = %+v, mong đợi 6–6", e)
	}
}

// VoteTop: 3 sói còn sống nên mặc định 4 người chạy nhiều nhất được x2. v3–v6
// bấm Tha thành 8 phiếu, cộng v2 là 9 Tha; 7 Treo, kể cả hunter 0 km vẫn được
// tính. Không có x2 thì 7 Treo – 5 Tha và v1 bị treo.
func TestVoteTopDoublesTopRunners(t *testing.T) {
	km := map[string]float64{"v3": 9000, "v4": 8000, "v5": 7000, "v6": 6000, "hunter": 0}
	g := trialCfg(t, Config{Vote: VoteTop}, km)
	for _, v := range []string{"w1", "w2", "w3", "seer", "guard", "witch", "hunter"} {
		g.vote(v, ChoiceHang)
	}
	for _, v := range []string{"v2", "v3", "v4", "v5", "v6"} {
		g.vote(v, ChoiceSpare)
	}
	evs := g.next()
	if find(evs, EventVoteCut) != nil {
		t.Fatal("luật top thì không ai mất phiếu")
	}
	if e := find(evs, EventVoteBonus); e == nil || e.UID != "v1" || !slices.Equal(e.Targets, []string{"v3", "v4", "v5", "v6"}) || e.Draw {
		t.Fatalf("x2 = %+v, mong đợi v3 v4 v5 v6", e)
	}
	if e := find(evs, EventVoteResult); e.Hang != 7 || e.Spare != 9 || e.Hanged {
		t.Fatalf("kết quả = %+v, mong đợi 7 Treo – 9 Tha", e)
	}
}

// VoteTop: TopVoters đặt tay thì theo số đó; người chưa đủ km một phiếu
// (KmPerUnit) không vào top dù không ai chạy hơn; bằng km ở suất cuối thì bốc
// thăm và cùng seed ra cùng kết quả.
func TestVoteTopCountEligibilityAndDraw(t *testing.T) {
	km := zeroKm()
	km["v3"], km["v4"], km["v5"] = 3000, 2000, 2000
	km["v6"] = 999
	cfg := Config{Vote: VoteTop, TopVoters: 2}
	var first []string
	for i := 0; i < 2; i++ {
		g := trialCfg(t, cfg, km)
		e := find(g.next(), EventVoteBonus)
		if e == nil || len(e.Targets) != 2 || !slices.Contains(e.Targets, "v3") || !e.Draw {
			t.Fatalf("x2 = %+v, mong đợi v3 và một trong v4, v5 bốc thăm", e)
		}
		if !slices.Contains(e.Targets, "v4") && !slices.Contains(e.Targets, "v5") {
			t.Fatalf("x2 = %v", e.Targets)
		}
		if first != nil && !slices.Equal(first, e.Targets) {
			t.Fatalf("bốc thăm không ổn định: %v rồi %v", first, e.Targets)
		}
		first = e.Targets
	}
	km["v3"], km["v4"], km["v5"] = 999, 0, 0
	g := trialCfg(t, cfg, km)
	if e := find(g.next(), EventVoteBonus); e != nil {
		t.Fatalf("không ai đủ 1 km thì không ai được x2, có %+v", e)
	}
}

// VillageGate: 10 người không phải sói, cần 10 × 1 km cả phe. Tiên tri 0 km vẫn
// soi được khi phe đủ 10 km; phe thiếu 1 m thì tiên tri 5 km cũng bị chặn.
func TestVillageGateUsesVillageTeamKm(t *testing.T) {
	g := newGameCfg(t, Config{VillageGate: true})
	g.km = zeroKm()
	g.km["v1"] = 10000
	g.next()
	g.do(KindSeerPeek, "seer", "w1")

	g = newGameCfg(t, Config{VillageGate: true})
	g.km = zeroKm()
	g.km["seer"], g.km["v1"] = 5000, 4999
	g.km["w1"] = 50000 // km của sói không tính cho phe Dân
	g.next()
	g.reject(ErrKmInsufficient, act(KindSeerPeek, "seer", "w1"))
}

func TestConfigValidateRejectsBadKnobs(t *testing.T) {
	bad := []Config{
		{ExtraWolves: 3},
		{ExtraWolves: -1},
		{SkillKm: map[Role]float64{Cupid: 1}},
		{SkillKm: map[Role]float64{Villager: 1}},
		{SkillKm: map[Role]float64{Seer: -1}},
		{Vote: "double"},
		{TopVoters: MaxPlayers + 1},
	}
	for _, c := range bad {
		if c.Validate() == nil {
			t.Fatalf("%+v phải bị từ chối", c)
		}
	}
	ok := Config{ExtraWolves: 2, SkillKm: map[Role]float64{Wolf: 0, Seer: 2, Guard: 0, Witch: 1, Hunter: 3}, Vote: VoteTop, TopVoters: 4, VillageGate: true}
	if err := ok.Validate(); err != nil {
		t.Fatal(err)
	}
}

// SkillKm[Wolf] = 0: phe sói cắn được dù không ai chạy, và 0h vẫn khoá được.
func TestSkillKmZeroLetsWolvesBiteWithoutKm(t *testing.T) {
	g := newGameCfg(t, Config{SkillKm: map[Role]float64{Wolf: 0}})
	g.km["w1"], g.km["w2"], g.km["w3"] = 0, 0, 0
	g.next()
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	if g.st.Bitten != "v1" {
		t.Fatalf("bitten = %q, mong đợi v1", g.st.Bitten)
	}
}

// SkillKm theo từng vai: tiên tri cần 2 km thì 1,5 km bị chặn, bảo vệ đặt 0 thì
// 0 km vẫn bảo vệ được; vai không có trong map (phù thuỷ) vẫn theo KmPerUnit.
func TestSkillKmPerRole(t *testing.T) {
	g := newGameCfg(t, Config{KmPerUnit: 1, SkillKm: map[Role]float64{Seer: 2, Guard: 0}})
	g.km["seer"], g.km["guard"], g.km["witch"] = 1500, 0, 999
	g.next()
	g.reject(ErrKmInsufficient, act(KindSeerPeek, "seer", "v1"))
	g.do(KindGuard, "guard", "v1")
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	if err := Precheck(g.st, KindWitchSave, "witch", nil, g.now()); err != ErrKmInsufficient {
		t.Fatalf("Precheck witch = %v, mong đợi thiếu km", err)
	}
	sameDeaths(t, g.next(), map[string]Cause{}) // bảo vệ 0 km vẫn đỡ được v1
	if g.st.LastGuarded != "v1" {
		t.Fatalf("lastGuarded = %q, mong đợi v1", g.st.LastGuarded)
	}
}
