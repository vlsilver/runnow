package werewolf

import (
	"reflect"
	"testing"
)

func elderGame(t *testing.T) *tg {
	roles := baseRoles()
	roles["v1"] = Elder
	g := newGame(t, roles)
	g.st.Config.Extended = []Role{Elder}
	g.next()
	return g
}

// Cú cắn đầu tiên không giết Già làng, chỉ Già làng được báo; cú thứ hai giết.
func TestElderSurvivesFirstBite(t *testing.T) {
	g := elderGame(t)
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	evs := g.next()
	sameDeaths(t, evs, map[string]Cause{})
	if e := find(evs, EventSurvived); e == nil || e.UID != "v1" {
		t.Fatalf("event thoát chết = %+v", e)
	}
	g.toPhase(PhaseNight)
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	sameDeaths(t, g.next(), map[string]Cause{"v1": CauseBite})
}

// Đêm bị cắn mà được bảo vệ thì Già làng chưa mất lần thoát; bị độc thì chết.
func TestElderGuardedBiteKeepsSpareLife(t *testing.T) {
	g := elderGame(t)
	g.do(KindWolfBite, "w1", "v1")
	g.do(KindGuard, "guard", "v1")
	g.next()
	if evs := g.next(); find(evs, EventSurvived) != nil {
		t.Fatal("được bảo vệ mà vẫn tính là thoát chết")
	}
	g.toPhase(PhaseNight)
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	sameDeaths(t, g.next(), map[string]Cause{})

	g = elderGame(t)
	g.next()
	g.do(KindWitchPoison, "witch", "v1")
	sameDeaths(t, g.next(), map[string]Cause{"v1": CausePoison})

	// Cùng đêm vừa bị cắn vừa bị độc: chết vì độc, không được báo là thoát.
	g = elderGame(t)
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	g.do(KindWitchPoison, "witch", "v1")
	evs := g.next()
	sameDeaths(t, evs, map[string]Cause{"v1": CausePoison})
	if find(evs, EventSurvived) != nil {
		t.Fatal("Già làng chết vì độc mà vẫn được báo là thoát cú cắn")
	}
}

// Bật Già làng thì một Dân thành Già làng; không bật thì bộ bài như cũ.
func TestElderTakesVillagerSlot(t *testing.T) {
	roles, err := Composition(10, Config{Extended: []Role{Elder}})
	if err != nil {
		t.Fatal(err)
	}
	got := map[Role]int{}
	for _, r := range roles {
		got[r]++
	}
	want := map[Role]int{Wolf: 2, Seer: 1, Guard: 1, Elder: 1, Villager: 5}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("bộ 10 người = %v, mong đợi %v", got, want)
	}
	if err := (Config{Extended: []Role{Seer}}).Validate(); err == nil {
		t.Fatal("bật thêm vai không thuộc nhóm mở rộng mà không bị từ chối")
	}
	if err := (Config{Extended: []Role{Elder, Elder}}).Validate(); err == nil {
		t.Fatal("bật Già làng hai lần mà không bị từ chối")
	}
}

// Ván chụp danh sách vai mở rộng lúc tạo; caller sửa slice sau đó không đổi ván.
func TestElderConfigSnapshot(t *testing.T) {
	cfg := Config{Extended: []Role{Elder}}
	st := NewState(Seed{1}, cfg, baseRoles(), testStart)
	cfg.Extended[0] = Seer
	if st.Config.Extended[0] != Elder {
		t.Fatalf("ván bị đổi theo caller: %v", st.Config.Extended)
	}
}
