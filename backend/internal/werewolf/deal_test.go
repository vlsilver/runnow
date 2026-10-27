package werewolf

import (
	"crypto/sha256"
	"errors"
	"fmt"
	"math"
	"testing"
)

func uids(n int) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = string(rune('a'+i)) + "-uid"
	}
	return out
}

func countRoles(roles map[string]Role) map[Role]int {
	c := map[Role]int{}
	for _, r := range roles {
		c[r]++
	}
	return c
}

// Bảng 1.2 của plan, chép tay: số người → sói + vai đặc biệt.
func TestDealCompositionFollowsTable(t *testing.T) {
	cases := []struct {
		n    int
		want map[Role]int
	}{
		{10, map[Role]int{Wolf: 2, Seer: 1, Guard: 1, Villager: 6}},
		{11, map[Role]int{Wolf: 3, Seer: 1, Guard: 1, Witch: 1, Villager: 5}},
		{12, map[Role]int{Wolf: 3, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Villager: 5}},
		{13, map[Role]int{Wolf: 3, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 5}},
		{16, map[Role]int{Wolf: 3, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 8}},
		{17, map[Role]int{Wolf: 4, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 8}},
		{20, map[Role]int{Wolf: 4, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 11}},
		{21, map[Role]int{Wolf: 5, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 11}},
		{24, map[Role]int{Wolf: 5, Seer: 1, Guard: 1, Witch: 1, Hunter: 1, Cupid: 1, Villager: 14}},
	}
	for _, c := range cases {
		roles, err := Deal(Seed{1}, uids(c.n), Config{})
		if err != nil {
			t.Fatalf("n=%d: %v", c.n, err)
		}
		if len(roles) != c.n {
			t.Fatalf("n=%d: chia cho %d người", c.n, len(roles))
		}
		got := countRoles(roles)
		for role, want := range c.want {
			if got[role] != want {
				t.Fatalf("n=%d: %s = %d, mong đợi %d (cả bộ %v)", c.n, role, got[role], want, got)
			}
		}
	}
}

func TestR9PlayerCountOutsideTenToTwentyFourRejected(t *testing.T) {
	for _, n := range []int{0, 9, 25} {
		if _, err := Deal(Seed{1}, uids(n), Config{}); !errors.Is(err, ErrPlayerCount) {
			t.Fatalf("n=%d: err = %v, mong đợi ErrPlayerCount", n, err)
		}
	}
	for _, n := range []int{10, 16, 24} {
		if _, err := Deal(Seed{1}, uids(n), Config{}); err != nil {
			t.Fatalf("n=%d phải Start được: %v", n, err)
		}
	}
}

func TestR8DisabledRolesBecomeVillagersWolfCountUnchanged(t *testing.T) {
	roles, err := Deal(Seed{2}, uids(13), Config{Disabled: []Role{Cupid, Hunter}})
	if err != nil {
		t.Fatal(err)
	}
	got := countRoles(roles)
	want := map[Role]int{Wolf: 3, Seer: 1, Guard: 1, Witch: 1, Hunter: 0, Cupid: 0, Villager: 7}
	for role, n := range want {
		if got[role] != n {
			t.Fatalf("%s = %d, mong đợi %d (cả bộ %v)", role, got[role], n, got)
		}
	}
}

func TestR8CannotDisableWolfOrVillager(t *testing.T) {
	for _, r := range []Role{Wolf, Villager, "lạ"} {
		if _, err := Deal(Seed{2}, uids(12), Config{Disabled: []Role{r}}); err == nil {
			t.Fatalf("tắt %q phải bị từ chối", r)
		}
	}
}

func TestR11SameSeedSameRolesWhateverRegistrationOrder(t *testing.T) {
	players := uids(14)
	first, err := Deal(Seed{7}, players, Config{})
	if err != nil {
		t.Fatal(err)
	}
	reversed := make([]string, len(players))
	for i, p := range players {
		reversed[len(players)-1-i] = p
	}
	second, err := Deal(Seed{7}, reversed, Config{})
	if err != nil {
		t.Fatal(err)
	}
	for uid, r := range first {
		if second[uid] != r {
			t.Fatalf("%s: %s rồi %s — cùng seed phải ra cùng vai", uid, r, second[uid])
		}
	}
	other, _ := Deal(Seed{8}, players, Config{})
	same := true
	for uid, r := range first {
		if other[uid] != r {
			same = false
		}
	}
	if same {
		t.Fatal("seed khác mà ra y hệt — chia vai không dùng seed")
	}
}

func TestDuplicatePlayerRejected(t *testing.T) {
	p := uids(10)
	p[9] = p[0]
	if _, err := Deal(Seed{1}, p, Config{}); err == nil {
		t.Fatal("người chơi trùng phải bị từ chối")
	}
}

// 10.000 seed, 16 người: mỗi người làm sói ~3/16 và tiên tri ~1/16. Ngưỡng 2
// điểm phần trăm (khoảng 5 độ lệch chuẩn ở cỡ mẫu này), seed sinh tất định nên
// test không chập chờn.
func TestR11DealIsUniformAcrossPlayers(t *testing.T) {
	const games = 10000
	players := uids(16)
	wolf := map[string]int{}
	seer := map[string]int{}
	for i := 0; i < games; i++ {
		seed := Seed(sha256.Sum256([]byte(fmt.Sprintf("seed-%d", i))))
		roles, err := Deal(seed, players, Config{})
		if err != nil {
			t.Fatal(err)
		}
		for uid, r := range roles {
			switch r {
			case Wolf:
				wolf[uid]++
			case Seer:
				seer[uid]++
			}
		}
	}
	for _, uid := range players {
		if d := math.Abs(float64(wolf[uid])/games - 3.0/16); d > 0.02 {
			t.Fatalf("%s làm sói %.4f, lệch %.4f so với 3/16", uid, float64(wolf[uid])/games, d)
		}
		if d := math.Abs(float64(seer[uid])/games - 1.0/16); d > 0.02 {
			t.Fatalf("%s làm tiên tri %.4f, lệch %.4f so với 1/16", uid, float64(seer[uid])/games, d)
		}
	}
}
