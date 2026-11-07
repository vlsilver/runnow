package werewolf

import "testing"

// Ván km ba vòng một ngày (8 tiếng mỗi vòng, mở 22h, 6h, 14h). Start 9h ngày 15
// nên đêm 1 mở 14h ngày 15, lấy khung kết thúc 22h ngày 14. Vòng chốt 22h ngày
// 15 sang khung mới; hai vòng chốt 6h và 14h ngày 16 vẫn dùng khung đó.
func TestKmRoundsShareDayFrame(t *testing.T) {
	cfg := Config{Schedule: &Schedule{StartHour: 22, RoundHours: 8, Rounds: 3}}
	if err := cfg.Validate(); err != nil {
		t.Fatal(err)
	}
	g := &tg{t: t, st: NewState(Seed{7}, cfg, baseRoles(), testStart), actions: map[string]Action{}, km: map[string]float64{}}
	var got [][3]int
	for i := 0; i < 16 && len(got) < 4; i++ {
		if end, ok := g.st.KmFrameEnd(); ok {
			got = append(got, [3]int{end.Day(), end.Hour(), end.Minute()})
		}
		g.next()
	}
	want := [][3]int{{14, 22, 0}, {15, 22, 0}, {15, 22, 0}, {15, 22, 0}}
	for i := range want {
		if i >= len(got) || got[i] != want[i] {
			t.Fatalf("khung km theo từng lần chốt = %v, mong đợi %v", got, want)
		}
	}
}

// Ván km nhiều vòng phải mở 22h và các vòng cộng lại đúng 24 tiếng.
func TestKmRoundsValidate(t *testing.T) {
	bad := []Schedule{
		{StartHour: 22, RoundHours: 8, Rounds: 2},
		{StartHour: 6, RoundHours: 8, Rounds: 3},
	}
	for _, s := range bad {
		s := s
		if err := (Config{Schedule: &s}).Validate(); err == nil {
			t.Fatalf("lịch km %+v không bị từ chối", s)
		}
	}
}
