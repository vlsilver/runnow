package werewolf

import (
	"errors"
	"reflect"
	"strconv"
	"testing"
	"time"
)

// at(d, h, m) là giờ VN ngày d/10/2026.
func at(d, h, m int) time.Time { return time.Date(2026, 10, d, h, m, 0, 0, vietnam) }

// advance gọi Advance với các action đang lưu; tới hạn thì áp state mới.
func (g *tg) advance(now time.Time) ([]Event, error) {
	g.t.Helper()
	var acts []Action
	for _, a := range g.actions {
		acts = append(acts, a)
	}
	round := g.st.Round
	st, evs, err := Advance(g.st, Inputs{Actions: acts, Km: g.km}, now)
	if err != nil {
		return nil, err
	}
	g.st = st
	if st.Round != round {
		g.actions = map[string]Action{}
	}
	return evs, nil
}

func (g *tg) tryAt(a Action, now time.Time) error {
	a.ReceivedAt = now
	return Validate(g.st, a, g.mine(a.Actor), now)
}

// Start 9h ngày 15 → đêm 1 lúc 22h ngày 15; các mốc theo bảng 1.3.
func TestPhaseDeadlinesFollowDailySchedule(t *testing.T) {
	g := newGame(t, baseRoles())
	want := []struct {
		phase    Phase
		deadline time.Time
	}{
		{PhaseSetup, at(15, 22, 0)}, {PhaseNight, at(16, 0, 0)}, {PhaseDawn, at(16, 10, 0)},
		{PhaseDay, at(16, 20, 0)}, {PhaseTrial, at(16, 22, 0)}, {PhaseNight, at(17, 0, 0)},
	}
	for i, w := range want {
		if g.st.Phase != w.phase || !g.st.Deadline().Equal(w.deadline) {
			t.Fatalf("bước %d: %s hạn %s, mong đợi %s hạn %s", i, g.st.Phase, g.st.Deadline(), w.phase, w.deadline)
		}
		g.next()
	}
}

// Hành động tới sau hạn mà bước chốt chưa chạy thì bị từ chối, không lọt vào.
func TestWindowClosesAtDeadlineEvenIfStepIsLate(t *testing.T) {
	g := game13(t)
	if err := g.tryAt(act(KindWolfBite, "w1", "v1"), at(15, 23, 59).Add(59*time.Second)); err != nil {
		t.Fatal(err)
	}
	if err := g.tryAt(act(KindWolfBite, "w1", "v1"), at(16, 0, 0)); !errors.Is(err, ErrPhaseClosed) {
		t.Fatalf("0h đúng: %v", err)
	}
	g.toPhase(PhaseTrial)
	g.st.Nominee = "v1"
	vote := Action{Kind: KindVote, Actor: "v2", Choice: ChoiceSpare}
	for _, c := range []struct {
		now time.Time
		ok  bool
	}{{at(16, 19, 59), false}, {at(16, 20, 0), true}, {at(16, 21, 59), true}, {at(16, 22, 0), false}} {
		if err := g.tryAt(vote, c.now); (err == nil) != c.ok {
			t.Errorf("biểu quyết lúc %s: %v", c.now.Format("15:04"), err)
		}
	}
}

func TestHunterWindowDependsOnHowHeDied(t *testing.T) {
	// Chết trong đêm: bắn trong 10h–12h.
	g := game13(t)
	g.do(KindWolfBite, "w1", "hunter")
	g.toPhase(PhaseDay)
	shot := act(KindHunterShoot, "hunter", "v1")
	if err := g.tryAt(shot, at(16, 11, 59)); err != nil {
		t.Fatal(err)
	}
	if err := g.tryAt(shot, at(16, 12, 0)); !errors.Is(err, ErrPhaseClosed) {
		t.Fatalf("12h: %v", err)
	}
	if !g.st.NextAt().Equal(at(16, 12, 0)) {
		t.Fatalf("NextAt = %s", g.st.NextAt())
	}
	// Không bắn thì tới 12h mới chốt lượt; trước đó Advance không làm gì.
	if _, err := g.advance(at(16, 11, 0)); !errors.Is(err, ErrNotDue) {
		t.Fatalf("11h: %v", err)
	}
	if _, err := g.advance(at(16, 12, 0)); err != nil || g.st.Hunter != nil {
		t.Fatalf("12h: err=%v hunter=%+v", err, g.st.Hunter)
	}

	// Bị treo: bắn trong 22h–23h; bắn xong thì chốt ngay, không chờ 23h.
	g = game13(t)
	g.hang("hunter")
	if err := g.tryAt(shot, at(16, 23, 0)); !errors.Is(err, ErrPhaseClosed) {
		t.Fatalf("23h: %v", err)
	}
	g.do(KindHunterShoot, "hunter", "v1")
	evs, err := g.advance(at(16, 22, 10))
	if err != nil || deaths(evs)["v1"] != CauseShot {
		t.Fatalf("bắn lúc 22:10: err=%v evs=%+v", err, evs)
	}
}

// Gọi lặp: cùng đầu vào ra cùng kết quả; gọi tiếp trên state mới ở cùng giờ thì
// không làm gì, kể cả tin nhắc.
func TestAdvanceRepeatedIsNoop(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseDay)
	now := at(16, 18, 0)
	a, evA, errA := Advance(g.st, Inputs{}, now)
	b, evB, errB := Advance(g.st, Inputs{}, now)
	if errA != nil || errB != nil || !reflect.DeepEqual(a, b) || !reflect.DeepEqual(evA, evB) {
		t.Fatalf("hai lần chạy khác nhau: %v %v", errA, errB)
	}
	if len(evA) != 1 || evA[0].Kind != EventReminder || evA[0].Reason != ReminderNominate {
		t.Fatalf("18h phải nhắc đề cử: %+v", evA)
	}
	if _, _, err := Advance(a, Inputs{}, now); !errors.Is(err, ErrNotDue) {
		t.Fatalf("chạy lại sau khi đã nhắc: %v", err)
	}
	if !a.NextAt().Equal(at(16, 20, 0)) {
		t.Fatalf("NextAt sau khi nhắc = %s", a.NextAt())
	}
}

// Trễ 2 mốc (service chết từ 21h tới 10:05 hôm sau): chạy bù 22h → 0h → 10h đúng
// thứ tự, không gửi tin nhắc 21h vì đã quá giờ.
func TestAdvanceCatchesUpMissedMarksInOrder(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseTrial)
	var keys []string
	var all []Event
	for {
		key := g.st.PhaseKey()
		evs, err := g.advance(at(17, 10, 5))
		if errors.Is(err, ErrNotDue) {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		keys, all = append(keys, key), append(all, evs...)
	}
	if want := []string{"r1/trial", "r2/night", "r2/dawn"}; !reflect.DeepEqual(keys, want) {
		t.Fatalf("thứ tự chạy bù = %v, mong đợi %v", keys, want)
	}
	if find(all, EventReminder) != nil {
		t.Fatal("không được gửi tin nhắc đã quá giờ")
	}
	if g.st.Phase != PhaseDay || !g.st.NextAt().Equal(at(17, 18, 0)) {
		t.Fatalf("sau chạy bù: %s NextAt %s", g.st.PhaseKey(), g.st.NextAt())
	}
}

// R14: pause lúc 22:00 (trước khi chốt ngày), resume 10:30 hôm sau. Phase biểu
// quyết nhận hạn mới là 22h hôm đó; mọi giờ khác của vòng dời theo.
func TestR14PauseAt2200ResumeAt1030(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v2", "v1")
	g.next()
	st, err := Pause(g.st)
	if err != nil {
		t.Fatal(err)
	}
	g.st = st
	if _, err := g.advance(at(16, 22, 0).Add(30 * time.Second)); !errors.Is(err, ErrNotRunning) {
		t.Fatalf("Advance lúc pause: %v", err)
	}
	if err := g.tryAt(Action{Kind: KindVote, Actor: "v3", Choice: ChoiceHang}, at(16, 21, 0)); !errors.Is(err, ErrPaused) {
		t.Fatalf("vote lúc pause: %v", err)
	}
	if g.st, err = Resume(g.st, at(17, 10, 30)); err != nil {
		t.Fatal(err)
	}
	if !g.st.Deadline().Equal(at(17, 22, 0)) || g.st.Phase != PhaseTrial || g.st.Nominee != "v1" {
		t.Fatalf("sau resume: %s hạn %s, giàn %q", g.st.Phase, g.st.Deadline(), g.st.Nominee)
	}
	if err := g.tryAt(Action{Kind: KindVote, Actor: "v3", Choice: ChoiceHang}, at(17, 10, 31)); !errors.Is(err, ErrPhaseClosed) {
		t.Fatalf("10:31 chưa tới giờ biểu quyết: %v", err)
	}
	if _, err := g.advance(at(17, 10, 31)); !errors.Is(err, ErrNotDue) {
		t.Fatalf("không bù bước đã lỡ: %v", err)
	}
	if _, err := g.advance(at(17, 22, 0).Add(30 * time.Second)); err != nil {
		t.Fatal(err)
	}
	if g.st.Round != 2 || !g.st.Deadline().Equal(at(18, 0, 0)) {
		t.Fatalf("vòng 2: round %d hạn %s", g.st.Round, g.st.Deadline())
	}
}

// Pause ngắn, resume trước hạn thì hạn giữ nguyên.
func TestR14ShortPauseKeepsDeadline(t *testing.T) {
	g := game13(t)
	st, _ := Pause(g.st)
	st, err := Resume(st, at(15, 23, 0))
	if err != nil || !st.Deadline().Equal(at(16, 0, 0)) {
		t.Fatalf("hạn = %s, err %v", st.Deadline(), err)
	}
	if _, err := Resume(st, at(15, 23, 0)); !errors.Is(err, ErrPauseState) {
		t.Fatalf("resume khi không pause: %v", err)
	}
}

// Task hẹn sau resume phải có khoá khác task cũ, nếu không Cloud Tasks coi là
// trùng và không tạo. Lượt thợ săn cũng có khoá riêng với mốc 0h cùng vòng.
func TestTaskKeyChangesWithDeadlineAndHunterTurn(t *testing.T) {
	g := game13(t)
	before := g.st.TaskKey()
	st, _ := Pause(g.st)
	st, _ = Resume(st, at(16, 1, 0))
	if st.PhaseKey() != g.st.PhaseKey() || st.TaskKey() == before {
		t.Fatalf("khoá task không đổi sau resume: %s", before)
	}
	g.hang("hunter")
	hunterKey := g.st.TaskKey()
	g.next()
	if g.st.TaskKey() == hunterKey || hunterKey != "r2/night/hunter@"+strconv.FormatInt(at(16, 23, 0).Unix(), 10) {
		t.Fatalf("khoá lượt thợ săn = %s, khoá 0h = %s", hunterKey, g.st.TaskKey())
	}
}

func TestKmFrameEndOnlyAt22h(t *testing.T) {
	g := newGame(t, baseRoles())
	want := map[Phase]time.Time{PhaseSetup: at(15, 22, 0), PhaseTrial: at(16, 22, 0)}
	for i := 0; i < 5; i++ {
		end, ok := g.st.KmFrameEnd()
		if w, need := want[g.st.Phase]; ok != need || !end.Equal(w) {
			t.Fatalf("%s: KmFrameEnd = %s %v", g.st.Phase, end, ok)
		}
		g.next()
	}
}

// Đang pause thì cũng không gửi tin nhắc.
func TestR14PausedSendsNoReminder(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseDay)
	st, _ := Pause(g.st)
	if _, _, err := Advance(st, Inputs{}, at(16, 15, 0)); !errors.Is(err, ErrNotRunning) {
		t.Fatalf("15h lúc pause: %v", err)
	}
}
