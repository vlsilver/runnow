package backend

import "testing"

func TestParseGoal(t *testing.T) {
	cases := []struct {
		goal    string
		km      float64
		sec     int
		weeks   int
		paceSec int
	}{
		// Câu đã làm ra giáo án sai: mục tiêu thời gian trước đây không có
		// chỗ nào chứa, nên pace đích không bao giờ tới được model.
		{"chạy 10km dưới 1h", 10, 3600, 0, 360},
		{"chạy 10km dưới 60 phút", 10, 3600, 0, 360},
		{"sub 60 10k", 10, 3600, 0, 360},
		{"10km sub 55", 10, 3300, 0, 330},

		// Số trong phần "trong N ..." là độ dài giáo án, không phải cự ly.
		{"chạy 5km trong 42 ngày", 5, 0, 6, 0},
		{"chạy 21 phút mỗi buổi", 0, 1260, 0, 0},
		{"chạy 10km trong 8 tuần", 10, 0, 8, 0},
		{"chạy 10km trong 2 tháng", 10, 0, 8, 0},

		// Cự ly chuẩn theo tên.
		{"half marathon", 21.1, 0, 0, 0},
		{"muốn chạy full marathon sub 4", 42.2, 14400, 0, 341},
		{"marathon trong 16 tuần", 42.2, 0, 16, 0},

		// Kết hợp đủ ba đại lượng.
		{"chạy 21km dưới 2h trong 12 tuần", 21, 7200, 12, 343},
		{"5,5km dưới 30 phút", 5.5, 1800, 0, 327},

		// Không nêu gì thì để 0, người gọi tự quyết.
		{"muốn khoẻ hơn", 0, 0, 0, 0},
	}

	for _, c := range cases {
		got := parseGoal(c.goal)
		if got.DistanceKm != c.km {
			t.Errorf("%q: cự ly = %.1f, mong đợi %.1f", c.goal, got.DistanceKm, c.km)
		}
		if got.TargetSec != c.sec {
			t.Errorf("%q: thời gian đích = %d giây, mong đợi %d", c.goal, got.TargetSec, c.sec)
		}
		if got.PlanWeeks != c.weeks {
			t.Errorf("%q: số tuần = %d, mong đợi %d", c.goal, got.PlanWeeks, c.weeks)
		}
		if got.TargetPaceSec() != c.paceSec {
			t.Errorf("%q: pace đích = %d giây/km, mong đợi %d", c.goal, got.TargetPaceSec(), c.paceSec)
		}
	}
}

func TestFmtHelpers(t *testing.T) {
	if got := fmtDuration(3600); got != "1h00" {
		t.Errorf("fmtDuration(3600) = %q", got)
	}
	if got := fmtDuration(3300); got != "55 phút" {
		t.Errorf("fmtDuration(3300) = %q", got)
	}
	if got := fmtDuration(0); got != "" {
		t.Errorf("fmtDuration(0) = %q, phải rỗng", got)
	}
	if got := fmtGoalPace(360); got != "6:00/km" {
		t.Errorf("fmtGoalPace(360) = %q", got)
	}
	if got := fmtGoalPace(0); got != "" {
		t.Errorf("fmtGoalPace(0) = %q, phải rỗng", got)
	}
}
