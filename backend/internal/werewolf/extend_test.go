package werewolf

import (
	"errors"
	"testing"
	"time"
)

// Admin dời hạn phase đang mở: cửa sổ và lần chốt dời theo, phase sau giữ giờ
// cũ.
func TestExtendMovesOnlyCurrentDeadline(t *testing.T) {
	g := game13(t)
	st, err := Extend(g.st, 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if !st.Deadline().Equal(at(16, 0, 30)) || !st.NextAt().Equal(at(16, 0, 30)) {
		t.Fatalf("hạn đêm = %s, NextAt = %s", st.Deadline(), st.NextAt())
	}
	// Task hẹn theo hạn mới phải có khoá khác task cũ.
	if st.TaskKey() == g.st.TaskKey() {
		t.Fatal("khoá task không đổi sau khi dời hạn")
	}
	g.st = st
	if _, closes := st.Window(KindWolfBite); !closes.Equal(at(16, 0, 30)) {
		t.Fatalf("cửa sổ cắn đóng lúc %s", closes)
	}
	if err := g.tryAt(act(KindWolfBite, "w1", "v1"), at(16, 0, 15)); err != nil {
		t.Fatalf("cắn lúc 0:15: %v", err)
	}
	if _, err := g.advance(at(16, 0, 10)); !errors.Is(err, ErrNotDue) {
		t.Fatalf("0:10: %v", err)
	}
	if _, err := g.advance(at(16, 0, 30)); err != nil || g.st.Phase != PhaseDawn {
		t.Fatalf("0:30: %v, phase %s", err, g.st.Phase)
	}
	if !g.st.Deadline().Equal(at(16, 10, 0)) {
		t.Fatalf("hạn rạng sáng = %s", g.st.Deadline())
	}
}

// Không dời được tới mức phase sau còn chưa tới 1 giờ; dời nhiều lần thì cộng dồn.
func TestExtendLimitIsOneHourBeforeNextDeadline(t *testing.T) {
	g := game13(t)
	g.toPhase(PhaseTrial) // chốt 22h, đêm sau khoá lúc 0h
	var tooLong *ExtendTooLong
	if _, err := Extend(g.st, 61*time.Minute); !errors.As(err, &tooLong) || tooLong.Max != time.Hour {
		t.Fatalf("dời 61 phút: %v", err)
	}
	st, err := Extend(g.st, 40*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Extend(st, 21*time.Minute); !errors.As(err, &tooLong) || tooLong.Max != 20*time.Minute {
		t.Fatalf("dời thêm 21 phút: %v", err)
	}
	if st, err = Extend(st, 20*time.Minute); err != nil || !st.Deadline().Equal(at(16, 23, 0)) {
		t.Fatalf("hạn = %v, err %v", st, err)
	}
	if _, err := Extend(g.st, 0); !errors.Is(err, ErrExtendState) {
		t.Fatalf("dời 0 phút: %v", err)
	}
	g.st.Phase = PhaseEnded
	if _, err := Extend(g.st, time.Minute); !errors.Is(err, ErrExtendState) {
		t.Fatalf("dời khi hết ván: %v", err)
	}
}

// Giới hạn của từng phase: lượt sau khoá lúc 0h, 10h, 17h, 22h, 0h.
func TestExtendLimitPerPhase(t *testing.T) {
	g := newGame(t, baseRoles())
	want := map[Phase]time.Duration{
		PhaseSetup: time.Hour, PhaseNight: 9 * time.Hour, PhaseDawn: 6 * time.Hour, PhaseDay: 4 * time.Hour, PhaseTrial: time.Hour,
	}
	for i := 0; i < 5; i++ {
		var tooLong *ExtendTooLong
		if _, err := Extend(g.st, 24*time.Hour); !errors.As(err, &tooLong) || tooLong.Max != want[g.st.Phase] {
			t.Fatalf("%s: %v", g.st.Phase, err)
		}
		g.next()
	}
}

// Lượt thợ săn ban ngày (10h–12h) dời được, phase ngày vẫn khoá lúc 17h. Lượt
// thợ săn bị treo (22h–23h) sát mốc 0h nên không dời được.
func TestExtendHunterTurn(t *testing.T) {
	g := game13(t)
	g.do(KindWolfBite, "w1", "hunter")
	g.toPhase(PhaseDay)
	st, err := Extend(g.st, 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	g.st = st
	if err := g.tryAt(act(KindHunterShoot, "hunter", "v1"), at(16, 12, 15)); err != nil {
		t.Fatalf("bắn lúc 12:15: %v", err)
	}
	if !g.st.NextAt().Equal(at(16, 12, 30)) || !g.st.TurnClose().Equal(at(16, 12, 30)) {
		t.Fatalf("NextAt = %s, TurnClose = %s", g.st.NextAt(), g.st.TurnClose())
	}
	if _, err := g.advance(at(16, 12, 30)); err != nil || g.st.Hunter != nil || !g.st.Deadline().Equal(at(16, 17, 0)) {
		t.Fatalf("12:30: err=%v hunter=%+v hạn %s", err, g.st.Hunter, g.st.Deadline())
	}

	g = game13(t)
	g.hang("hunter")
	var tooLong *ExtendTooLong
	if _, err := Extend(g.st, time.Minute); !errors.As(err, &tooLong) || tooLong.Max != 0 {
		t.Fatalf("dời lượt thợ săn bị treo: %v", err)
	}
}
