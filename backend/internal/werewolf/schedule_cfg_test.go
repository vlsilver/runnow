package werewolf

import (
	"errors"
	"testing"
	"time"
)

// threeShifts: 3 vòng mỗi ngày, mỗi vòng 6 tiếng, vòng đầu mở 6h; hoạt động
// 6h–24h. Một giờ của lịch gốc 24 tiếng thành 15 phút.
var threeShifts = Config{KmOff: true, Schedule: &Schedule{StartHour: 6, RoundHours: 6, Rounds: 3}}

// Start 9h ngày 15: mốc sớm nhất cách Start 2 tiếng là 12h. Vòng sau mở ngay
// lúc vòng trước chốt nếu còn trong khung; hết khung (24h) thì đợi 6h hôm sau.
func TestScheduleSlotsAndScaledDeadlines(t *testing.T) {
	g := &tg{t: t, st: NewState(Seed{7}, threeShifts, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	want := []struct {
		phase    Phase
		deadline time.Time
	}{
		{PhaseSetup, at(15, 12, 0)}, {PhaseNight, at(15, 12, 30)}, {PhaseDawn, at(15, 15, 0)},
		{PhaseDay, at(15, 17, 30)}, {PhaseTrial, at(15, 18, 0)},
		{PhaseNight, at(15, 18, 30)}, {PhaseDawn, at(15, 21, 0)}, {PhaseDay, at(15, 23, 30)}, {PhaseTrial, at(16, 0, 0)},
		{PhaseNight, at(16, 6, 30)},
	}
	for i, w := range want {
		if g.st.Phase != w.phase || !g.st.Deadline().Equal(w.deadline) {
			t.Fatalf("bước %d: %s hạn %s, mong đợi %s hạn %s", i, g.st.Phase, g.st.Deadline(), w.phase, w.deadline)
		}
		g.next()
	}
}

func TestScheduleValidate(t *testing.T) {
	if err := threeShifts.Validate(); err != nil {
		t.Fatal(err)
	}
	for _, s := range []Schedule{
		{StartHour: 6, RoundHours: 5, Rounds: 1},  // lẻ
		{StartHour: 6, RoundHours: 2, Rounds: 1},  // ngắn quá
		{StartHour: 6, RoundHours: 26, Rounds: 1}, // dài quá
		{StartHour: 6, RoundHours: 8, Rounds: 4},  // 32 tiếng
		{StartHour: 6, RoundHours: 8, Rounds: 0},
		{StartHour: 24, RoundHours: 8, Rounds: 1},
		{StartHour: -1, RoundHours: 8, Rounds: 1},
	} {
		if (Config{KmOff: true, Schedule: &s}).Validate() == nil {
			t.Fatalf("%+v mà không bị từ chối", s)
		}
	}
	if (Config{Schedule: threeShifts.Schedule}).Validate() == nil {
		t.Fatal("lịch riêng mà vẫn dùng km")
	}
}

// Phiên biểu quyết chốt 24h; vòng sau khoá sói 6h30 hôm sau, chừa 15 phút
// (1 tiếng của lịch gốc), nên dời được tới 6h15.
func TestScheduleExtendAcrossOffHours(t *testing.T) {
	g := &tg{t: t, st: NewState(Seed{7}, threeShifts, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	for g.st.Round < 2 || g.st.Phase != PhaseTrial {
		g.next()
	}
	if _, err := Extend(g.st, 6*time.Hour+15*time.Minute); err != nil {
		t.Fatal(err)
	}
	var tooLong *ExtendTooLong
	if _, err := Extend(g.st, 6*time.Hour+16*time.Minute); !errors.As(err, &tooLong) || tooLong.Max != 6*time.Hour+15*time.Minute {
		t.Fatalf("dời 6h16 = %v", err)
	}
}

// Vòng mở 12h: nhắc đề cử 17h (18h của lịch gốc), biểu quyết mở 17h30 (20h),
// nhắc biểu quyết 17h45 (21h).
func TestScheduleRemindersAndVoteOpen(t *testing.T) {
	g := &tg{t: t, st: NewState(Seed{7}, threeShifts, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	for g.st.Phase != PhaseDay {
		g.next()
	}
	if got := g.st.NextAt(); !got.Equal(at(15, 17, 0)) {
		t.Fatalf("nhắc đề cử = %s", got)
	}
	g.do(KindNominate, "v2", "v1")
	g.next()
	if got := g.st.NextAt(); !got.Equal(at(15, 17, 45)) {
		t.Fatalf("nhắc biểu quyết = %s", got)
	}
	if opens, _ := g.st.Window(KindVote); !opens.Equal(at(15, 17, 30)) {
		t.Fatalf("biểu quyết mở = %s", opens)
	}
	vote := Action{Kind: KindVote, Actor: "v3", Choice: ChoiceHang}
	if err := g.tryAt(vote, at(15, 17, 29)); !errors.Is(err, ErrPhaseClosed) {
		t.Fatalf("17h29 = %v", err)
	}
	if err := g.tryAt(vote, at(15, 17, 31)); err != nil {
		t.Fatalf("17h31 = %v", err)
	}
}

// Khung 20h–4h kéo qua nửa đêm: vòng 2 của hôm 15 mở 4h ngày 16. Start 1h
// ngày 16 thì vòng đầu là mốc đó.
func TestScheduleSlotFromPreviousDay(t *testing.T) {
	cfg := Config{KmOff: true, Schedule: &Schedule{StartHour: 20, RoundHours: 8, Rounds: 2}}
	if got := cfg.FirstNight(at(16, 1, 0)); !got.Equal(at(16, 4, 0)) {
		t.Fatalf("vòng đầu = %s", got)
	}
}

// Vòng mở 12h: soi đóng 15h (10h của lịch gốc), đề cử mở 15h; thợ săn chết
// trong đêm bắn tới 15h30 (12h).
func TestScheduleWindowsAndHunter(t *testing.T) {
	g := &tg{t: t, st: NewState(Seed{7}, threeShifts, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	g.next()
	if _, closes := g.st.Window(KindSeerPeek); !closes.Equal(at(15, 15, 0)) {
		t.Fatalf("soi đóng = %s", closes)
	}
	if opens, _ := g.st.Window(KindNominate); !opens.Equal(at(15, 15, 0)) {
		t.Fatalf("đề cử mở = %s", opens)
	}
	g.do(KindWolfBite, "w1", "hunter")
	g.toPhase(PhaseDay)
	if g.st.Hunter == nil || !g.st.TurnClose().Equal(at(15, 15, 30)) {
		t.Fatalf("lượt bắn = %+v, hạn %s", g.st.Hunter, g.st.TurnClose())
	}
}

// Giờ in cho người chơi: lịch gốc 22h → 0h, 10h, 20h, 22h hôm sau; vòng 6
// tiếng mở 12h → 12h30, 15h, 17h30, 18h.
func TestScheduleClock(t *testing.T) {
	if k := (Config{}).Clock(at(15, 22, 0)); !k.WolfLock.Equal(at(16, 0, 0)) || !k.Dawn.Equal(at(16, 10, 0)) ||
		!k.NominateClose.Equal(at(16, 20, 0)) || !k.Close.Equal(at(16, 22, 0)) {
		t.Fatalf("lịch gốc = %+v", k)
	}
	if k := threeShifts.Clock(at(15, 12, 0)); !k.Night.Equal(at(15, 12, 0)) || !k.WolfLock.Equal(at(15, 12, 30)) ||
		!k.Dawn.Equal(at(15, 15, 0)) || !k.NominateClose.Equal(at(15, 17, 30)) || !k.Close.Equal(at(15, 18, 0)) {
		t.Fatalf("vòng 6 tiếng = %+v", k)
	}
}

// Hết khung 24h thì nghỉ: tới 6h hôm sau sói mới cắn được, cửa sổ báo đúng giờ.
func TestScheduleOffHoursAcceptNothing(t *testing.T) {
	g := &tg{t: t, st: NewState(Seed{7}, threeShifts, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	for g.st.Round < 3 {
		g.next()
	}
	if err := g.tryAt(act(KindWolfBite, "w1", "v1"), at(16, 3, 0)); !errors.Is(err, ErrPhaseClosed) {
		t.Fatalf("3h sáng = %v, mong đợi phase_closed", err)
	}
	if err := g.tryAt(act(KindWolfBite, "w1", "v1"), at(16, 6, 10)); err != nil {
		t.Fatalf("6h10 = %v", err)
	}
	if opens, closes := g.st.Window(KindWolfBite); !opens.Equal(at(16, 6, 0)) || !closes.Equal(at(16, 6, 30)) {
		t.Fatalf("cửa sổ cắn = %s – %s", opens, closes)
	}
}
