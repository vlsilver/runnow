package werewolf

import (
	"slices"
	"testing"
	"time"
)

func teamState(winner Team, lovers ...string) *State {
	st := NewState(Seed{}, Config{}, map[string]Role{
		"w1": Wolf, "w2": Wolf, "s": Seer, "v1": Villager, "v2": Villager, "c": Cupid,
	}, time.Date(2026, 10, 25, 9, 0, 0, 0, time.UTC))
	st.Lovers = lovers
	st.Winner = winner
	st.Players["v1"].Alive = false // người chết vẫn thắng theo phe
	return st
}

func TestWinnersAreTheWinningSideDeadOrAlive(t *testing.T) {
	cases := []struct {
		name   string
		st     *State
		winner []string
	}{
		{"chưa xong", teamState(""), nil},
		{"dân thắng", teamState(TeamVillage), []string{"c", "s", "v1", "v2"}},
		{"sói thắng", teamState(TeamWolves), []string{"w1", "w2"}},
		// Cặp Sói–Dân là phe ba: không còn thuộc phe cũ dù phe đó thắng.
		{"dân thắng, có cặp phe ba", teamState(TeamVillage, "v2", "w1"), []string{"c", "s", "v1"}},
		{"sói thắng, có cặp phe ba", teamState(TeamWolves, "v2", "w1"), []string{"w2"}},
		{"cặp đôi thắng", teamState(TeamLovers, "v2", "w1"), []string{"v2", "w1"}},
		// Hai người cùng phe yêu nhau thì vẫn ở phe mình.
		{"cặp cùng phe", teamState(TeamVillage, "s", "v2"), []string{"c", "s", "v1", "v2"}},
	}
	for _, c := range cases {
		if got := c.st.Winners(); !slices.Equal(got, c.winner) {
			t.Errorf("%s: Winners() = %v, mong đợi %v", c.name, got, c.winner)
		}
	}
}
