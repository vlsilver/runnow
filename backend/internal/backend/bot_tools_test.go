package backend

import (
	"testing"
	"time"
)

// Khoá bug "2 người ma 0 km": leaderboardEntries chỉ rebuild khi CHÍNH chủ nó
// có activity mới, nên qua tuần/tháng mới mà người đó chưa chạy thì currentWeek/
// currentMonth vẫn giữ số kỳ trước. Bot phải coi số kỳ CŨ là hết hạn (giống app),
// nếu không sẽ hiện người tuần này 0 km như đang dẫn đầu.
func TestLeaderboardPeriodFresh(t *testing.T) {
	now := time.Date(2026, 8, 5, 10, 0, 0, 0, vietnam) // Thứ 4, tuần 03/08–09/08
	periods := PeriodsAt(now)
	weekKey := dateKey(periods.Week.Start)   // "2026-08-03"
	monthKey := dateKey(periods.Month.Start) // "2026-08-01"
	lastWeekKey := dateKey(periods.Week.Start.AddDate(0, 0, -7))

	cases := []struct {
		name  string
		data  map[string]any
		field string
		want  bool
	}{
		{"week fresh", map[string]any{"currentWeekStart": weekKey}, "currentWeek", true},
		{"week stale (kỳ trước)", map[string]any{"currentWeekStart": lastWeekKey}, "currentWeek", false},
		{"week missing key -> stale", map[string]any{}, "currentWeek", false},
		{"month fresh", map[string]any{"currentMonthStart": monthKey}, "currentMonth", true},
		{"month stale", map[string]any{"currentMonthStart": "2026-07-01"}, "currentMonth", false},
		{"rolling7 luôn tươi (cửa sổ trượt)", map[string]any{}, "rollingSevenDays", true},
	}
	for _, c := range cases {
		if got := leaderboardPeriodFresh(c.data, c.field, periods); got != c.want {
			t.Errorf("%s: leaderboardPeriodFresh = %v, want %v", c.name, got, c.want)
		}
	}
}
