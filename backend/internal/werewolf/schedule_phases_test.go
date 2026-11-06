package werewolf

import (
	"errors"
	"testing"
	"time"
)

// kmShortNight: ván km mở 22h, vòng 24 tiếng, đêm chỉ 1 tiếng: đêm 22h–23h,
// rạng sáng 23h–10h, ngày 10h–20h, biểu quyết 20h–22h.
var kmShortNight = Config{Schedule: &Schedule{StartHour: 22, RoundHours: 24, Rounds: 1, Phases: []int{60, 660, 600, 120}}}

func TestPhasesDeadlines(t *testing.T) {
	if err := kmShortNight.Validate(); err != nil {
		t.Fatal(err)
	}
	g := &tg{t: t, st: NewState(Seed{7}, kmShortNight, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	want := []struct {
		phase    Phase
		deadline [3]int
	}{
		{PhaseSetup, [3]int{15, 22, 0}}, {PhaseNight, [3]int{15, 23, 0}}, {PhaseDawn, [3]int{16, 10, 0}},
		{PhaseDay, [3]int{16, 20, 0}}, {PhaseTrial, [3]int{16, 22, 0}}, {PhaseNight, [3]int{16, 23, 0}},
	}
	for i, w := range want {
		if d := at(w.deadline[0], w.deadline[1], w.deadline[2]); g.st.Phase != w.phase || !g.st.Deadline().Equal(d) {
			t.Fatalf("bước %d: %s hạn %s, mong đợi %s hạn %s", i, g.st.Phase, g.st.Deadline(), w.phase, d)
		}
		g.next()
	}
}

func TestPhasesValidate(t *testing.T) {
	ok := []Config{
		kmShortNight,
		// Cổ điển, vòng 7 tiếng: có Phases thì không cần số chẵn.
		{KmOff: true, Schedule: &Schedule{StartHour: 6, RoundHours: 7, Rounds: 3, Phases: []int{60, 120, 180, 60}}},
	}
	for _, c := range ok {
		if err := c.Validate(); err != nil {
			t.Fatalf("%+v: %v", *c.Schedule, err)
		}
	}
	bad := map[string]Config{
		"thiếu pha":         {KmOff: true, Schedule: &Schedule{StartHour: 22, RoundHours: 24, Rounds: 1, Phases: []int{120, 600, 720}}},
		"pha dưới 1 tiếng":  {KmOff: true, Schedule: &Schedule{StartHour: 22, RoundHours: 24, Rounds: 1, Phases: []int{30, 690, 600, 120}}},
		"lệch bước 30 phút": {KmOff: true, Schedule: &Schedule{StartHour: 22, RoundHours: 24, Rounds: 1, Phases: []int{75, 645, 600, 120}}},
		"tổng lệch vòng":    {KmOff: true, Schedule: &Schedule{StartHour: 22, RoundHours: 24, Rounds: 1, Phases: []int{120, 600, 600, 60}}},
		"km mở 6h":          {Schedule: &Schedule{StartHour: 6, RoundHours: 24, Rounds: 1, Phases: []int{120, 600, 600, 120}}},
		"km vòng 12 tiếng":  {Schedule: &Schedule{StartHour: 22, RoundHours: 12, Rounds: 1}},
		"không pha thì lẻ":  {KmOff: true, Schedule: &Schedule{StartHour: 6, RoundHours: 7, Rounds: 1}},
	}
	for name, c := range bad {
		if c.Validate() == nil {
			t.Fatalf("%s: %+v mà không bị từ chối", name, *c.Schedule)
		}
	}
}

// Đêm 22h–8h, rạng sáng 8h–10h: dời hạn đêm phải chừa 30 phút cho rạng sáng,
// nên dời được tối đa 1 tiếng 30.
func TestPhasesExtendKeepsHalfHour(t *testing.T) {
	cfg := Config{KmOff: true, Schedule: &Schedule{StartHour: 22, RoundHours: 24, Rounds: 1, Phases: []int{600, 120, 600, 120}}}
	g := &tg{t: t, st: NewState(Seed{7}, cfg, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	g.next()
	if _, err := Extend(g.st, 90*time.Minute); err != nil {
		t.Fatal(err)
	}
	var tooLong *ExtendTooLong
	if _, err := Extend(g.st, 91*time.Minute); !errors.As(err, &tooLong) || tooLong.Max != 90*time.Minute {
		t.Fatalf("dời 91 phút = %v", err)
	}
}

// longDay: đêm 22h–0h, rạng sáng 0h–8h, ngày 8h–20h, biểu quyết 20h–22h. Nhắc
// đề cử ở 4/5 pha Ngày là 17h36; thợ săn chết trong đêm bắn tới 1/5 pha Ngày
// là 10h24. Co đều cả vòng thì sẽ ra 18h và 12h.
var longDay = Config{KmOff: true, Schedule: &Schedule{StartHour: 22, RoundHours: 24, Rounds: 1, Phases: []int{120, 480, 720, 120}}}

func TestPhasesMarksFollowTheirPhase(t *testing.T) {
	g := &tg{t: t, st: NewState(Seed{7}, longDay, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	g.next()
	g.do(KindWolfBite, "w1", "hunter")
	g.toPhase(PhaseDay)
	if g.st.Hunter == nil || !g.st.TurnClose().Equal(at(16, 10, 24)) {
		t.Fatalf("lượt bắn = %+v, hạn %s", g.st.Hunter, g.st.TurnClose())
	}
	g.next()
	if g.st.Phase != PhaseDay || !g.st.NextAt().Equal(at(16, 17, 36)) {
		t.Fatalf("%s, nhắc đề cử = %s", g.st.Phase, g.st.NextAt())
	}
}
