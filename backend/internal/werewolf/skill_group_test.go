package werewolf

import "testing"

// groupSkillKm: bốn vai cần 1 km mỗi vai (4 km). Phe Dân còn sống chạy 3 km:
// Tiên tri 1,5, Bảo vệ 1, Phù thuỷ 0,2, v1 0,3. Thợ săn chạy ít nhất (0 km).
func groupSkillKm(t *testing.T, ruleset int, vote VoteRule) *tg {
	g := game13(t)
	g.st.Config.Ruleset, g.st.Config.Vote = ruleset, vote
	for uid := range g.st.Km {
		g.st.Km[uid] = 0 // game13 cho mọi người 5 km
	}
	g.st.Km["seer"], g.st.Km["guard"], g.st.Km["witch"], g.st.Km["v1"] = 1500, 1000, 200, 300
	g.st.Km["w1"] = 9000 // km của sói không vào phần phe Dân
	return g
}

// Theo nhóm: 3 km đủ cho 3 vai, Thợ săn ít km nhất nên mất lượt; Phù thuỷ chỉ
// chạy 0,2 km vẫn dùng được nhờ km chung.
func TestGroupSkillKmDropsLeastKmRole(t *testing.T) {
	g := groupSkillKm(t, RulesetKm, VoteCut)
	want := map[string]bool{"seer": true, "guard": true, "witch": true, "hunter": false}
	for uid, ok := range want {
		if got := g.st.hasKm(uid); got != ok {
			t.Errorf("%s: hasKm = %v, mong đợi %v", uid, got, ok)
		}
	}
}

// Riêng, hay ván luật cũ: mỗi vai tự đủ 1 km.
func TestSoloAndOldRulesetSkillKmIsOwn(t *testing.T) {
	for _, g := range []*tg{groupSkillKm(t, RulesetKm, VoteSolo), groupSkillKm(t, 0, VoteCut)} {
		want := map[string]bool{"seer": true, "guard": true, "witch": false, "hunter": false}
		for uid, ok := range want {
			if got := g.st.hasKm(uid); got != ok {
				t.Errorf("ruleset %d %s: %s hasKm = %v, mong đợi %v", g.st.Config.Ruleset, g.st.Config.Vote, uid, got, ok)
			}
		}
	}
}

// Bằng km ở ngưỡng: Phù thuỷ và Thợ săn cùng 0 km, chỉ một người mất lượt, bốc
// thăm theo seed và giữ nguyên trong cả vòng.
func TestGroupSkillKmTieIsDrawnOnce(t *testing.T) {
	g := groupSkillKm(t, RulesetKm, VoteCut)
	g.st.Km["witch"], g.st.Km["v1"] = 0, 500
	witch, hunter := g.st.hasKm("witch"), g.st.hasKm("hunter")
	if witch == hunter {
		t.Fatalf("witch %v, hunter %v: phải đúng một người mất lượt", witch, hunter)
	}
	g.st.Phase = PhaseDawn
	if g.st.hasKm("witch") != witch {
		t.Fatal("bốc thăm đổi giữa đêm và rạng sáng")
	}
}
