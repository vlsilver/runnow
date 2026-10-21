package backend

import (
	"testing"
	"time"
)

func TestPeriodsForBasicKeys(t *testing.T) {
	// Wednesday, July 15, 2026 at noon Vietnam time.
	instant := time.Date(2026, 7, 15, 5, 0, 0, 0, time.UTC)
	periods := periodsFor(instant)
	want := map[string]string{"day": "2026-07-15", "week": "2026-W29", "month": "2026-07"}
	for _, period := range periods {
		if got, ok := want[period.Type]; !ok || got != period.Key {
			t.Fatalf("periodType %s: got key %s, want %s", period.Type, period.Key, want[period.Type])
		}
	}
}

func TestPeriodsForWeekKeyUsesISOWeekYearNotCalendarYear(t *testing.T) {
	// Jan 1, 2027 is a Friday that ISO 8601 assigns to week 53 of 2026, not
	// week 1 of 2027 — a naive `date.Year()` instead of ISOWeek() would get
	// this wrong right at every year boundary.
	instant := time.Date(2027, 1, 1, 3, 0, 0, 0, time.UTC)
	var weekKey string
	for _, period := range periodsFor(instant) {
		if period.Type == "week" {
			weekKey = period.Key
		}
	}
	if weekKey != "2026-W53" {
		t.Fatalf("week key = %s, want 2026-W53", weekKey)
	}
}

func TestRebuildDoesNotDoubleCountAnOverlappingRunNowStravaPair(t *testing.T) {
	start := time.Date(2026, 7, 15, 6, 0, 0, 0, time.UTC)
	runnow := ActivityFact{ID: "r", Source: "runnow", SportType: "Run", StartedAt: start, DistanceMeters: 5000, MovingTimeSeconds: 1800, ElapsedTimeSeconds: 1800}
	strava := ActivityFact{ID: "s", Source: "strava", SportType: "Run", StartedAt: start.Add(8 * time.Minute), DistanceMeters: 5000, MovingTimeSeconds: 1800, ElapsedTimeSeconds: 1800}
	official := SelectOfficialActivities([]ActivityFact{runnow, strava})
	stats := StatsFor(official, Period{Start: start.Add(-time.Hour), End: start.Add(24 * time.Hour)})
	if got := stats["distanceMeters"]; got != 5000.0 {
		t.Fatalf("distanceMeters = %v, want 5000 (counted once, not summed across the duplicate pair)", got)
	}
	if got := stats["activityCount"]; got != int64(1) {
		t.Fatalf("activityCount = %v, want 1", got)
	}
}
