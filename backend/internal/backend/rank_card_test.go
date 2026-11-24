package backend

import (
	"testing"
	"time"
)

// Kỳ chốt lúc 12:00 giờ VN ngày đầu kỳ mới: trước giờ đó vẫn là kỳ trước nữa.
func TestClosedRankPeriodsSwitchAtNoonVietnam(t *testing.T) {
	vn := func(month, day, hour, minute int) time.Time {
		return time.Date(2026, time.Month(month), day, hour, minute, 0, 0, vietnam)
	}
	cases := []struct {
		now                  time.Time
		weekStart, weekEnd   string
		monthStart, monthEnd string
	}{
		// Thứ Hai 2/11 11:59: tuần 26/10–1/11 chưa chốt; tháng 10 chưa chốt
		// vì ngày 1/11 12:00 đã qua thì tháng 10 đã chốt.
		{vn(11, 2, 11, 59), "2026-10-19", "2026-10-26", "2026-10-01", "2026-11-01"},
		{vn(11, 2, 12, 0), "2026-10-26", "2026-11-02", "2026-10-01", "2026-11-01"},
		{vn(11, 1, 11, 59), "2026-10-19", "2026-10-26", "2026-09-01", "2026-10-01"},
		{vn(11, 1, 12, 0), "2026-10-19", "2026-10-26", "2026-10-01", "2026-11-01"},
	}
	for _, c := range cases {
		week, month := closedRankPeriods(c.now)
		if dateKey(week.Start) != c.weekStart || dateKey(week.End) != c.weekEnd || dateKey(month.Start) != c.monthStart || dateKey(month.End) != c.monthEnd {
			t.Errorf("%v: tuần %s–%s tháng %s–%s, mong đợi %s–%s, %s–%s", c.now, dateKey(week.Start), dateKey(week.End), dateKey(month.Start), dateKey(month.End), c.weekStart, c.weekEnd, c.monthStart, c.monthEnd)
		}
	}
}
