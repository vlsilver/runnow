package backend

import (
	"testing"
	"time"
)

func TestShouldEnqueueTelegramActivityAllowsRecentExistingUnnotifiedStravaRun(t *testing.T) {
	now := time.Date(2026, 7, 20, 10, 0, 0, 0, time.UTC)
	next := map[string]any{
		"source":    "strava",
		"sportType": "Run",
		"startedAt": now.Add(-2 * time.Hour).Format(time.RFC3339),
	}
	previous := map[string]any{"importedAt": "already-backfilled"}

	if !shouldEnqueueTelegramActivity(previous, next, now) {
		t.Fatal("expected a recent existing Strava run without telegramNotifiedAt to enqueue")
	}
}

func TestShouldEnqueueTelegramActivitySkipsAlreadyNotified(t *testing.T) {
	now := time.Date(2026, 7, 20, 10, 0, 0, 0, time.UTC)
	next := map[string]any{
		"source":    "strava",
		"sportType": "Run",
		"startedAt": now.Add(-2 * time.Hour).Format(time.RFC3339),
	}
	previous := map[string]any{"telegramNotifiedAt": now.Add(-time.Hour)}

	if shouldEnqueueTelegramActivity(previous, next, now) {
		t.Fatal("expected an already-notified activity to skip enqueue")
	}
}

func TestShouldEnqueueTelegramActivitySkipsHistoricalBackfill(t *testing.T) {
	now := time.Date(2026, 7, 20, 10, 0, 0, 0, time.UTC)
	next := map[string]any{
		"source":    "strava",
		"sportType": "Run",
		"startedAt": now.Add(-7 * 24 * time.Hour).Format(time.RFC3339),
	}

	if shouldEnqueueTelegramActivity(nil, next, now) {
		t.Fatal("expected old backfilled activity to skip Telegram enqueue")
	}
}

func TestShouldEnqueueTelegramActivitySkipsRunNowTrackedActivity(t *testing.T) {
	now := time.Date(2026, 7, 20, 10, 0, 0, 0, time.UTC)
	next := map[string]any{
		"source":    "runnow",
		"sportType": "Run",
		"startedAt": now.Add(-30 * time.Minute).Format(time.RFC3339),
	}

	if shouldEnqueueTelegramActivity(nil, next, now) {
		t.Fatal("expected 3i tracked activity to skip Telegram enqueue")
	}
}
