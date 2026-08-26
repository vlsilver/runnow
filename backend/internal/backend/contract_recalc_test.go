package backend

import (
	"testing"
	"time"
)

func TestContractProgressWithWalk(t *testing.T) {
	loc := time.FixedZone("VN", 7*3600)
	day := func(s string) time.Time {
		tm, _ := time.ParseInLocation("2006-01-02 15:04", s, loc)
		return tm
	}
	start := day("2026-08-24 00:00")
	end := day("2026-08-31 00:00") // [24, 31) — tuần

	dist := map[string]float64{"r1": 5000, "r2": 2000}     // 5km, 2km
	startAt := map[string]time.Time{
		"r1": day("2026-08-24 07:00"), // thứ 2
		"r2": day("2026-08-25 07:00"), // thứ 3
	}
	officialByDay := map[string]float64{"2026-08-24": 5000, "2026-08-25": 2000}
	// stepDays: ngày 24 đi tổng 6km (chạy 5 + đi bộ 1), 3000 bước; ngày 26 đi bộ
	// 1.5km, 2600 bước (>=2500 → 1 buổi); ngày 27: 800m, 900 bước (<2500).
	stepMeters := map[string]float64{"2026-08-24": 6000, "2026-08-26": 1500, "2026-08-27": 800}
	stepCount := map[string]int64{"2026-08-24": 3000, "2026-08-26": 2600, "2026-08-27": 900}
	ids := []string{"r1", "r2"}

	// distance: km chạy (5+2=7) + đi-bộ-thuần (ngày24: 6-5=1; ngày26: 1.5-0=1.5;
	// ngày27: 0.8 nhưng <... vẫn tính đi bộ 0.8) = 7 + 1 + 1.5 + 0.8 = 10.3km.
	got := contractProgressWithWalk("distance", ids, start, end, dist, startAt, officialByDay, stepMeters, stepCount)
	if got < 10.29 || got > 10.31 {
		t.Fatalf("distance: muốn ~10.3km, được %.3f", got)
	}

	// activity_count: 2 buổi chạy + số ngày >=2500 bước (24: 3000, 26: 2600) = 2 ngày → 4.
	got = contractProgressWithWalk("activity_count", ids, start, end, dist, startAt, officialByDay, stepMeters, stepCount)
	if got != 4 {
		t.Fatalf("activity_count: muốn 4 (2 chạy + 2 ngày bước), được %.0f", got)
	}

	// active_days: ngày có chạy {24,25} ∪ ngày >=2500 bước {24,26} = {24,25,26} = 3.
	got = contractProgressWithWalk("active_days", ids, start, end, dist, startAt, officialByDay, stepMeters, stepCount)
	if got != 3 {
		t.Fatalf("active_days: muốn 3, được %.0f", got)
	}

	// longest_run: buổi dài nhất = 5km (đi bộ KHÔNG tính).
	got = contractProgressWithWalk("longest_run", ids, start, end, dist, startAt, officialByDay, stepMeters, stepCount)
	if got != 5 {
		t.Fatalf("longest_run: muốn 5km, được %.3f", got)
	}
}

func TestDayInWindow(t *testing.T) {
	loc := time.FixedZone("VN", 7*3600)
	start, _ := time.ParseInLocation("2006-01-02 15:04", "2026-08-24 00:00", loc)
	end, _ := time.ParseInLocation("2006-01-02 15:04", "2026-08-31 00:00", loc)
	if !dayInWindow("2026-08-24", start, end) {
		t.Fatal("24 phải trong [24,31)")
	}
	if !dayInWindow("2026-08-30", start, end) {
		t.Fatal("30 phải trong [24,31)")
	}
	if dayInWindow("2026-08-31", start, end) {
		t.Fatal("31 KHÔNG được trong [24,31) (end exclusive)")
	}
	if dayInWindow("2026-08-23", start, end) {
		t.Fatal("23 KHÔNG được trong window")
	}
}
