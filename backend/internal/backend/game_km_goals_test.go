package backend

import (
	"reflect"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// goalState: ván 4 người còn sống, luật mặc định (1 km một phiếu, một lượt kỹ năng).
func goalState(cfg ww.Config) *ww.State {
	return &ww.State{Config: cfg, Round: 2, Phase: ww.PhaseDay, Players: map[string]*ww.Player{
		"s1": {Role: ww.Seer, Alive: true},
		"v1": {Role: ww.Villager, Alive: true},
		"v2": {Role: ww.Villager, Alive: true},
		"w1": {Role: ww.Wolf, Alive: true},
	}}
}

func TestKmGoalsSeerUnderVoteCut(t *testing.T) {
	st := goalState(ww.Config{})
	live := &liveKm{Meters: map[string]float64{"s1": 1400, "v1": 3000, "v2": 200, "w1": 900}}
	got := kmGoals(st, "s1", live, nil)
	want := []GameKmGoal{
		{Key: "vote", Label: "Giữ phiếu biểu quyết", NeedKm: 1, HaveKm: f64(1.4)},
		{Key: "skill", Label: "Soi ở đêm tới", NeedKm: 1, HaveKm: f64(1.4)},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("goals = %+v", got)
	}
}

// Sói: mốc cắn là km cả phe Sói còn sống (2 sói × 2 km), giữ phiếu vẫn theo km riêng.
func TestKmGoalsWolfBiteIsTeamTotal(t *testing.T) {
	st := goalState(ww.Config{SkillKm: map[ww.Role]float64{ww.Wolf: 2}})
	st.Players["w2"] = &ww.Player{Role: ww.Wolf, Alive: true}
	live := &liveKm{Meters: map[string]float64{"w1": 900, "w2": 2500, "v1": 5000}}
	got := kmGoals(st, "w1", live, wolfTeamKm(st, live))
	want := []GameKmGoal{
		{Key: "vote", Label: "Giữ phiếu biểu quyết", NeedKm: 1, HaveKm: f64(0.9)},
		{Key: "team_skill", Label: "Phe Sói cắn ở đêm tới", NeedKm: 4, HaveKm: f64(3.4)},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("goals = %+v", got)
	}
}

// Mỗi vai có lượt cần km có câu riêng; phù thuỷ hết cả hai bình thì không còn mốc.
func TestKmGoalsSkillPerRole(t *testing.T) {
	cases := []struct {
		role  ww.Role
		label string
	}{
		{ww.Guard, "Bảo vệ ở đêm tới"},
		{ww.Witch, "Dùng thuốc ở đêm tới"},
		{ww.Hunter, "Giữ phát bắn khi ngã"},
		{ww.Cupid, ""},
		{ww.Villager, ""},
	}
	for _, c := range cases {
		st := goalState(ww.Config{SkillKm: map[ww.Role]float64{c.role: 3}})
		st.SavePotion = true
		st.Players["x"] = &ww.Player{Role: c.role, Alive: true}
		want := []GameKmGoal{{Key: "vote", Label: "Giữ phiếu biểu quyết", NeedKm: 1}}
		if c.label != "" {
			want = append(want, GameKmGoal{Key: "skill", Label: c.label, NeedKm: 3})
		}
		if got := kmGoals(st, "x", nil, nil); !reflect.DeepEqual(got, want) {
			t.Errorf("%s: goals = %+v", c.role, got)
		}
	}
	st := goalState(ww.Config{})
	st.Players["x"] = &ww.Player{Role: ww.Witch, Alive: true}
	if got := kmGoals(st, "x", nil, nil); len(got) != 1 || got[0].Key != "vote" {
		t.Errorf("phù thuỷ hết bình: goals = %+v", got)
	}
	// Admin đặt km kỹ năng của vai về 0: kỹ năng không cần km nên không có mốc.
	st = goalState(ww.Config{SkillKm: map[ww.Role]float64{ww.Seer: 0}})
	if got := kmGoals(st, "s1", nil, nil); len(got) != 1 || got[0].Key != "vote" {
		t.Errorf("soi không cần km: goals = %+v", got)
	}
}

// villageGate: kỹ năng mở theo tổng km phe Dân. Tổng đó cộng bảng km công khai
// cho ra km phe Sói, nên không có mốc kỹ năng; câu luật của vai đã nói cách tính.
func TestKmGoalsVillageGateHidesTeamSum(t *testing.T) {
	st := goalState(ww.Config{VillageGate: true})
	got := kmGoals(st, "s1", nil, nil)
	want := []GameKmGoal{{Key: "vote", Label: "Giữ phiếu biểu quyết", NeedKm: 1}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("goals = %+v", got)
	}
}

// Không có mốc nào khi ván tắt km hay người gọi đã chết; Kẻ ngốc đã lật mất phiếu
// nên không có mốc giữ phiếu.
func TestKmGoalsNoneWhenNoKmOrNoVote(t *testing.T) {
	if got := kmGoals(goalState(ww.Config{KmOff: true}), "s1", nil, nil); got != nil {
		t.Errorf("kmOff: goals = %+v", got)
	}
	st := goalState(ww.Config{})
	st.Players["s1"].Alive = false
	if got := kmGoals(st, "s1", nil, nil); got != nil {
		t.Errorf("đã chết: goals = %+v", got)
	}
	st.Players["i1"] = &ww.Player{Role: ww.Idiot, Alive: true, Revealed: true}
	if got := kmGoals(st, "i1", nil, nil); got != nil {
		t.Errorf("kẻ ngốc đã lật: goals = %+v", got)
	}
}

// Luật top: đủ X km mới được tranh suất x2; không ai mất phiếu nên không có mốc giữ phiếu.
func TestKmGoalsVoteTopNeedsUnitToCompete(t *testing.T) {
	st := goalState(ww.Config{Vote: ww.VoteTop, KmPerUnit: 2})
	live := &liveKm{Meters: map[string]float64{"v1": 3200}}
	got := kmGoals(st, "v1", live, nil)
	want := []GameKmGoal{{Key: "vote_top", Label: "Đủ km để tranh suất x2 phiếu", NeedKm: 2, HaveKm: f64(3.2)}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("goals = %+v", got)
	}
}
