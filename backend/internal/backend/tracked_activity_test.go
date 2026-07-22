package backend

import (
	"testing"
	"time"
)

func TestNormalizeTrackedActivity(t *testing.T) {
	startedAt := time.Now().Add(-time.Hour).UTC().Format(time.RFC3339)
	got, err := normalizeTrackedActivity(map[string]any{
		"id":                 "runnow-42",
		"name":               "Morning Run",
		"source":             "runnow",
		"sportType":          "Run",
		"startedAt":          startedAt,
		"distanceMeters":     5000.0,
		"movingTimeSeconds":  1500,
		"elapsedTimeSeconds": 1600,
		"unknownClientField": "drop-me",
	})
	if err != nil {
		t.Fatalf("normalizeTrackedActivity() error = %v", err)
	}
	if got["officialState"] != "candidate" || got["updatedBy"] != "backend" {
		t.Fatalf("backend-owned fields missing: %#v", got)
	}
	if _, exists := got["unknownClientField"]; exists {
		t.Fatal("unknown client field must not be persisted")
	}
}

func TestNormalizeTrackedActivityRejectsInvalidSource(t *testing.T) {
	_, err := normalizeTrackedActivity(map[string]any{
		"id":                 "runnow-42",
		"name":               "Morning Run",
		"source":             "strava",
		"sportType":          "Run",
		"startedAt":          time.Now().Add(-time.Hour).UTC().Format(time.RFC3339),
		"distanceMeters":     5000,
		"movingTimeSeconds":  1500,
		"elapsedTimeSeconds": 1600,
	})
	if err == nil {
		t.Fatal("normalizeTrackedActivity() must reject non-RunNow sources")
	}
}

func TestTrackedDerivedCauseIsStableAndChangesWithSummary(t *testing.T) {
	activity := map[string]any{
		"id": "runnow-42", "sportType": "Run",
		"startedAt": "2026-07-17T06:00:00Z", "distanceMeters": 5000,
		"movingTimeSeconds": 1500, "elapsedTimeSeconds": 1600,
		"officialState": "candidate",
	}
	first := trackedDerivedCause(activity)
	activity["photos"] = []any{"ignored-by-aggregate"}
	if second := trackedDerivedCause(activity); second != first {
		t.Fatalf("non-summary field changed task identity: %q != %q", second, first)
	}
	activity["distanceMeters"] = 5100
	if changed := trackedDerivedCause(activity); changed == first {
		t.Fatal("summary change must create a new derived task identity")
	}
}
