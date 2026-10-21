package werewolf

import "testing"

// testMode (X1): admin ép vai cho vài người, phần còn lại vẫn đủ bộ của bảng 1.2.
// 10 người: 2 sói, tiên tri, bảo vệ, 6 dân.
func TestDealForcedKeepsForcedRolesAndTable(t *testing.T) {
	players := uids(10)
	forced := map[string]Role{players[0]: Wolf, players[1]: Seer, players[9]: Villager}
	for s := byte(0); s < 50; s++ {
		roles, err := DealForced(Seed{s}, players, Config{}, forced)
		if err != nil {
			t.Fatal(err)
		}
		for uid, r := range forced {
			if roles[uid] != r {
				t.Fatalf("seed %d: %s = %s, ép %s", s, uid, roles[uid], r)
			}
		}
		got := countRoles(roles)
		want := map[Role]int{Wolf: 2, Seer: 1, Guard: 1, Villager: 6}
		for r, n := range want {
			if got[r] != n {
				t.Fatalf("seed %d: bộ vai %v, mong đợi %v", s, got, want)
			}
		}
	}
}

func TestDealForcedWithoutForcedEqualsDeal(t *testing.T) {
	for s := byte(0); s < 20; s++ {
		a, err := Deal(Seed{s}, uids(13), Config{})
		if err != nil {
			t.Fatal(err)
		}
		b, err := DealForced(Seed{s}, uids(13), Config{}, nil)
		if err != nil {
			t.Fatal(err)
		}
		for uid := range a {
			if a[uid] != b[uid] {
				t.Fatalf("seed %d: Deal và DealForced(nil) khác nhau ở %s", s, uid)
			}
		}
	}
}

// Ép vai mà bộ không còn chỗ thì lỗi: 10 người chỉ có 2 sói và không có Cupid;
// vai đã tắt cũng không ép được; ép cho người không có trong ván cũng lỗi.
func TestDealForcedRejectsImpossibleForcing(t *testing.T) {
	p := uids(10)
	cases := map[string]struct {
		cfg    Config
		forced map[string]Role
	}{
		"3 sói":       {Config{}, map[string]Role{p[0]: Wolf, p[1]: Wolf, p[2]: Wolf}},
		"cupid":       {Config{}, map[string]Role{p[0]: Cupid}},
		"vai đã tắt":  {Config{Disabled: []Role{Guard}}, map[string]Role{p[0]: Guard}},
		"người ngoài": {Config{}, map[string]Role{"x-ngoai": Wolf}},
		"vai lạ":      {Config{}, map[string]Role{p[0]: "king"}},
	}
	for name, c := range cases {
		if _, err := DealForced(Seed{1}, p, c.cfg, c.forced); err == nil {
			t.Fatalf("%s: không lỗi", name)
		}
	}
}
