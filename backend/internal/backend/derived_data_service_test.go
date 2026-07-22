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

func TestPeriodsUseVietnamCalendar(t *testing.T) {
	periods := PeriodsAt(time.Date(2026, 7, 19, 18, 0, 0, 0, time.UTC)) // Monday 01:00 in Vietnam.
	if got := periods.Week.Start.In(vietnam).Format(time.RFC3339); got != "2026-07-20T00:00:00+07:00" {
		t.Fatalf("week start = %s", got)
	}
}
