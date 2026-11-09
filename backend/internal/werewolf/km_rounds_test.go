package werewolf

import (
	"testing"
	"time"
)

// Ván km ba vòng một ngày (8 tiếng mỗi vòng, mở 22h, 6h, 14h). Start 9h ngày 15
// nên đêm 1 mở 14h ngày 15, lấy 24 tiếng trước đó. Lần chốt nào cũng lấy đủ 24
// tiếng trước giờ chốt, các khung được phép chồng nhau.
func TestKmFrameIs24HoursBeforeEachClose(t *testing.T) {
	cfg := Config{Schedule: &Schedule{StartHour: 22, RoundHours: 8, Rounds: 3}}
	if err := cfg.Validate(); err != nil {
		t.Fatal(err)
	}
	g := &tg{t: t, st: NewState(Seed{7}, cfg, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	var got [][4]int
	for i := 0; i < 16 && len(got) < 4; i++ {
		if f, ok := g.st.DueKmFrame(); ok {
			got = append(got, [4]int{f.Start.Day(), f.Start.Hour(), f.End.Day(), f.End.Hour()})
		}
		g.next()
	}
	want := [][4]int{{14, 14, 15, 14}, {14, 22, 15, 22}, {15, 6, 16, 6}, {15, 14, 16, 14}}
	for i := range want {
		if i >= len(got) || got[i] != want[i] {
			t.Fatalf("khung km theo từng lần chốt = %v, mong đợi %v", got, want)
		}
	}
}

// Admin dời hạn chốt quá mốc thì khung vẫn là khung của lịch, không dời theo.
func TestDueKmFrameIgnoresMovedDeadline(t *testing.T) {
	cfg := Config{Schedule: &Schedule{StartHour: 22, RoundHours: 12, Rounds: 2}}
	st := NewState(Seed{7}, cfg, baseRoles(), testStart)
	st.Phase, st.NightAt = PhaseTrial, time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam)
	st.Extra, st.ExtraKey = 90*time.Minute, st.PhaseKey() // hạn gốc 10h, dời tới 11h30
	f, ok := st.DueKmFrame()
	want := KmFrame{Start: time.Date(2026, 10, 15, 10, 0, 0, 0, vietnam), End: time.Date(2026, 10, 16, 10, 0, 0, 0, vietnam)}
	if !ok || !f.Start.Equal(want.Start) || !f.End.Equal(want.End) {
		t.Fatalf("khung = %v %v, mong đợi %v", f, ok, want)
	}
}

// Khung đang gom lúc at: kết thúc ở lần chốt kế tiếp, dài 24 tiếng.
func TestKmFrameAtFollowsSchedule(t *testing.T) {
	vn := func(d, h, m int) time.Time { return time.Date(2026, 10, d, h, m, 0, 0, vietnam) }
	base := Config{}
	twoRounds := Config{Schedule: &Schedule{StartHour: 22, RoundHours: 12, Rounds: 2}}
	at6h := Config{Schedule: &Schedule{StartHour: 6, RoundHours: 24, Rounds: 1}}
	cases := []struct {
		name       string
		cfg        Config
		at         time.Time
		start, end time.Time
	}{
		{"gốc, ngay trước chốt", base, vn(23, 21, 59), vn(22, 22, 0), vn(23, 22, 0)},
		{"gốc, đúng mốc sang khung mới", base, vn(23, 22, 0), vn(23, 22, 0), vn(24, 22, 0)},
		{"gốc, giờ UTC", base, time.Date(2026, 10, 23, 15, 30, 0, 0, time.UTC), vn(23, 22, 0), vn(24, 22, 0)},
		{"gốc, rạng sáng", base, vn(23, 2, 0), vn(22, 22, 0), vn(23, 22, 0)},
		{"hai vòng, chốt 10h", twoRounds, vn(23, 9, 59), vn(22, 10, 0), vn(23, 10, 0)},
		{"hai vòng, chốt 22h", twoRounds, vn(23, 10, 0), vn(22, 22, 0), vn(23, 22, 0)},
		{"hai vòng, sau 22h", twoRounds, vn(23, 22, 30), vn(23, 10, 0), vn(24, 10, 0)},
		{"mở 6h, trước mốc", at6h, vn(23, 5, 59), vn(22, 6, 0), vn(23, 6, 0)},
		{"mở 6h, đúng mốc", at6h, vn(23, 6, 0), vn(23, 6, 0), vn(24, 6, 0)},
	}
	for _, c := range cases {
		f := c.cfg.KmFrameAt(c.at)
		if !f.Start.Equal(c.start) || !f.End.Equal(c.end) {
			t.Errorf("%s: khung = %s → %s, mong đợi %s → %s", c.name, f.Start, f.End, c.start, c.end)
		}
	}
}

// Ván km mở giờ nào cũng được, miễn các vòng nối kín 24 tiếng để không giờ chạy
// nào rơi ra ngoài khung.
func TestKmRoundsValidate(t *testing.T) {
	bad := []Schedule{
		{StartHour: 22, RoundHours: 8, Rounds: 2},
		{StartHour: 6, RoundHours: 8, Rounds: 2},
	}
	for _, s := range bad {
		s := s
		if err := (Config{Schedule: &s}).Validate(); err == nil {
			t.Fatalf("lịch km %+v không bị từ chối", s)
		}
	}
}
