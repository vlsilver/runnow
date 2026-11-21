package werewolf

import (
	"testing"
	"time"
)

// Cắn xét km 24 tiếng tới lúc chốt cắn, không phải km của lần chốt phiếu trước:
// ba sói cần 3000 m, lần chốt trước có 0 m nhưng tới lúc chốt cắn đủ 3000 m.
func TestBiteUsesKmAtLock(t *testing.T) {
	g := game13(t)
	g.st.Km["w1"], g.st.Km["w2"], g.st.Km["w3"] = 0, 0, 0
	g.biteKm = map[string]float64{"w1": 3000}
	g.do(KindWolfBite, "w2", "v1")
	g.next()
	if g.st.Bitten != "v1" {
		t.Fatalf("bitten = %q, mong đợi v1", g.st.Bitten)
	}
}

// Khung kỹ năng kết thúc ở giờ tròn kế tiếp, vì Health chỉ có số theo giờ.
func TestKmFrameUntilRoundsUpToWholeHour(t *testing.T) {
	cases := []struct{ at, start, end time.Time }{
		{vnTime(9, 21, 40), vnTime(8, 22, 0), vnTime(9, 22, 0)},
		{vnTime(9, 22, 0), vnTime(8, 22, 0), vnTime(9, 22, 0)},
		{vnTime(9, 23, 59), vnTime(9, 0, 0), vnTime(10, 0, 0)},
	}
	for _, c := range cases {
		if f := KmFrameUntil(c.at); !f.Start.Equal(c.start) || !f.End.Equal(c.end) {
			t.Errorf("%v: khung %v – %v", c.at, f.Start, f.End)
		}
	}
}

func vnTime(day, hour, minute int) time.Time {
	return time.Date(2026, 11, day, hour, minute, 0, 0, vietnam)
}

func TestDueBiteFrameOnlyAtBiteLock(t *testing.T) {
	g := game13(t)
	lock := g.st.Deadline()
	f, ok := g.st.DueBiteFrame()
	if !ok || !f.End.Equal(lock) || !f.Start.Equal(lock.Add(-24*time.Hour)) {
		t.Fatalf("khung = %+v, ok = %v, chốt cắn %v", f, ok, lock)
	}
	g.st.Hunter = &HunterTurn{UID: "hunter", Phase: PhaseNight}
	if _, ok := g.st.DueBiteFrame(); ok {
		t.Fatal("đang lượt thợ săn thì bước kế không phải chốt cắn")
	}
	g.st.Hunter = nil
	g.st.Config.KmOff = true
	if _, ok := g.st.DueBiteFrame(); ok {
		t.Fatal("ván tắt km không đọc km")
	}
	g.st.Config.KmOff = false
	g.toPhase(PhaseDawn)
	if _, ok := g.st.DueBiteFrame(); ok {
		t.Fatal("sang rạng sáng thì không còn chốt cắn")
	}
}

// checked đưa thẳng action đã qua kiểm km lúc bấm vào vòng, km đã chốt của người
// đó là 0 nên chỉ đường KmChecked mới cho qua.
func (g *tg) checked(kind Kind, actor string, targets ...string) {
	g.st.Km[actor] = 0
	g.seq++
	g.actions[actor+"/"+string(kind)] = Action{Kind: kind, Actor: actor, Targets: targets, KmChecked: true, ReceivedAt: g.now()}
}

func TestSkillCheckedAtUseKeepsAtResolve(t *testing.T) {
	g := game13(t)
	g.checked(KindGuard, "guard", "v1")
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	if deaths(g.next())["v1"] != "" {
		t.Fatal("bảo vệ đã đủ km lúc bấm mà v1 vẫn chết")
	}

	g = game13(t)
	g.do(KindWolfBite, "w1", "v1")
	g.next()
	g.checked(KindWitchSave, "witch")
	g.checked(KindWitchPoison, "witch", "v2")
	evs := g.next()
	if d := deaths(evs); d["v1"] != "" || d["v2"] != CausePoison {
		t.Fatalf("cứu và độc đã đủ km lúc bấm: %v", d)
	}
}

// Action chưa có dấu (ván đang chạy lúc deploy) thì vẫn xét km đã chốt.
func TestSkillWithoutCheckStillUsesLockedKm(t *testing.T) {
	g := game13(t)
	g.do(KindGuard, "guard", "v1")
	g.do(KindWolfBite, "w1", "v1")
	g.st.Km["guard"] = 0
	g.next()
	if deaths(g.next())["v1"] != CauseBite {
		t.Fatal("action chưa có dấu mà thiếu km thì không được bảo vệ")
	}
}

// Thợ săn ngã thì luôn có lượt; có bắn được không là km tới lúc bắn.
func TestHunterKmCheckedWhenShooting(t *testing.T) {
	g := game13(t)
	g.km["hunter"] = 999
	if evs := g.hang("hunter"); find(evs, EventHunterTurn) == nil {
		t.Fatal("thợ săn ngã phải có lượt")
	}
	g.reject(ErrKmInsufficient, act(KindHunterShoot, "hunter", "w1"))
	a := act(KindHunterShoot, "hunter", "w1")
	a.ReceivedAt = g.now()
	if err := Validate(g.st.WithKm(map[string]float64{"hunter": 1000}), a, nil, g.now()); err != nil {
		t.Fatalf("đủ km lúc bắn: %v", err)
	}
}
