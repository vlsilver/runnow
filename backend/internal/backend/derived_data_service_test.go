package backend

import (
	"testing"
	"time"
)

func TestStravaWinsWhenRunNowOverlapExceedsThirtyPercent(t *testing.T) {
	start := time.Date(2026, 7, 17, 6, 0, 0, 0, time.UTC)
	runnow := ActivityFact{ID: "r", Source: "runnow", SportType: "Run", StartedAt: start, DistanceMeters: 5000, MovingTimeSeconds: 1800, ElapsedTimeSeconds: 1800}
	strava := ActivityFact{ID: "s", Source: "strava", SportType: "Run", StartedAt: start.Add(8 * time.Minute), DistanceMeters: 5000, MovingTimeSeconds: 1800, ElapsedTimeSeconds: 1800}
	got := SelectOfficialActivities([]ActivityFact{runnow, strava})
	if len(got) != 1 || got[0].ID != "s" {
		t.Fatalf("got %#v, want only Strava", got)
	}
}

func TestRunNowUnderFiveHundredMetersIsNotOfficial(t *testing.T) {
	got := SelectOfficialActivities([]ActivityFact{{ID: "r", Source: "runnow", SportType: "Run", DistanceMeters: 499}})
	if len(got) != 0 {
		t.Fatalf("got %d activities", len(got))
	}
}

// Cùng một lần chạy nằm ở CẢ Apple Health lẫn 3i native (không có Strava): chỉ
// tính MỘT, và giữ 3i native (giàu dữ liệu hơn) — chống đếm đôi km.
func TestNonStravaOverlapCountsOncePreferringRunNow(t *testing.T) {
	start := time.Date(2026, 7, 17, 6, 0, 0, 0, time.UTC)
	health := ActivityFact{ID: "health-x", Source: "apple_health", SportType: "Run", StartedAt: start.Add(2 * time.Minute), DistanceMeters: 5000, MovingTimeSeconds: 1800, ElapsedTimeSeconds: 1800}
	runnow := ActivityFact{ID: "r", Source: "runnow", SportType: "Run", StartedAt: start, DistanceMeters: 5000, MovingTimeSeconds: 1800, ElapsedTimeSeconds: 1800}
	// Đảo thứ tự đầu vào để chắc kết quả order-independent.
	for _, in := range [][]ActivityFact{{health, runnow}, {runnow, health}} {
		got := SelectOfficialActivities(in)
		if len(got) != 1 || got[0].Source != "runnow" {
			t.Fatalf("got %#v, want only runnow", got)
		}
	}
}

// Hai buổi non-Strava KHÔNG trùng thời gian: cả hai đều được tính.
func TestNonStravaDistinctRunsBothCount(t *testing.T) {
	base := time.Date(2026, 7, 17, 6, 0, 0, 0, time.UTC)
	a := ActivityFact{ID: "health-a", Source: "apple_health", SportType: "Run", StartedAt: base, DistanceMeters: 5000, MovingTimeSeconds: 1800, ElapsedTimeSeconds: 1800}
	b := ActivityFact{ID: "health-b", Source: "apple_health", SportType: "Run", StartedAt: base.Add(3 * time.Hour), DistanceMeters: 3000, MovingTimeSeconds: 1200, ElapsedTimeSeconds: 1200}
	if got := SelectOfficialActivities([]ActivityFact{a, b}); len(got) != 2 {
		t.Fatalf("got %d, want 2", len(got))
	}
}

func TestPeriodsUseVietnamCalendar(t *testing.T) {
	periods := PeriodsAt(time.Date(2026, 7, 19, 18, 0, 0, 0, time.UTC)) // Monday 01:00 in Vietnam.
	if got := periods.Week.Start.In(vietnam).Format(time.RFC3339); got != "2026-07-20T00:00:00+07:00" {
		t.Fatalf("week start = %s", got)
	}
}
