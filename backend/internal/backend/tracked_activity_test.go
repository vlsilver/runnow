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

// Đạp/xe máy track tay: PHẢI được nhận và GIỮ NGUYÊN sportType (trước đây bị ép
// về "Run" → sai bảng xếp hạng). Môn khác (vd Swim) KHÔNG track tay được → loại.
func TestNormalizeTrackedActivityPreservesAppRecordableSport(t *testing.T) {
	startedAt := time.Now().Add(-time.Hour).UTC().Format(time.RFC3339)
	base := func(sport string) map[string]any {
		return map[string]any{
			"id": "runnow-42", "name": "Buổi đạp", "source": "runnow",
			"sportType": sport, "startedAt": startedAt,
			"distanceMeters": 12000.0, "movingTimeSeconds": 1800, "elapsedTimeSeconds": 1900,
		}
	}
	for _, sport := range []string{"Ride", "Motorbike"} {
		got, err := normalizeTrackedActivity(base(sport))
		if err != nil {
			t.Fatalf("%s bị loại oan: %v", sport, err)
		}
		if got["sportType"] != sport {
			t.Fatalf("sportType %s bị đổi thành %v (không được ép về Run)", sport, got["sportType"])
		}
	}
	// Swim/Gym/Walk chỉ vào từ Health, không track tay → phải bị loại.
	if _, err := normalizeTrackedActivity(base("Swim")); err == nil {
		t.Fatal("Swim không phải môn track tay, phải bị loại")
	}
	// Rỗng (client cũ) → coi là Run.
	got, err := normalizeTrackedActivity(base(""))
	if err != nil || got["sportType"] != "Run" {
		t.Fatalf("sportType rỗng phải thành Run, got %v err %v", got["sportType"], err)
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
