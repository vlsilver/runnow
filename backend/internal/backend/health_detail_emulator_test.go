//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"
)

// Buổi từ kho sức khoẻ chỉ có phần tóm tắt và không có gì để kéo thêm. App coi
// doc thiếu hydrated là chưa có chi tiết rồi gọi hydrate, mà hydrate chỉ đi qua
// Strava nên trả 409 và màn chi tiết không mở được.
func TestEmulatorHealthImportMarksDetailComplete(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	tasks, _ := newRecordingTaskPublisher(t)
	activities := NewActivityService(db, nil, nil, tasks, nil, "", "")

	workouts := []healthWorkout{{SourceID: "w1", SportType: "Run", StartedAt: time.Now().Add(-time.Hour).UTC().Format(time.RFC3339), DistanceMeters: 5000, MovingTimeSeconds: 1500}}
	if n, err := activities.ImportHealthWorkouts(ctx, "u1", workouts, "apple_health", "", ""); err != nil || n != 1 {
		t.Fatalf("import = %d, %v", n, err)
	}
	snap, err := db.Doc("users/u1/activities/health-w1").Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if snap.Data()["hydrated"] != true {
		t.Fatalf("hydrated = %v, muốn true", snap.Data()["hydrated"])
	}
}

func TestEmulatorBackfillHealthHydrated(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	seed(t, db, "users/u1", map[string]any{"displayName": "A"})
	// u2 không có doc users/u2, chỉ có subcollection: backfill vẫn phải thấy.
	seed(t, db, "users/u1/activities/health-a", map[string]any{"source": "apple_health", "sportType": "Run"})
	seed(t, db, "users/u1/activities/health-b", map[string]any{"source": "apple_health", "sportType": "Run", "hydrated": true})
	seed(t, db, "users/u2/activities/health-c", map[string]any{"source": "health_connect", "sportType": "Run"})
	seed(t, db, "users/u1/activities/9001", map[string]any{"source": "strava", "sportType": "Run"})
	seed(t, db, "users/u1/activities/run-1", map[string]any{"source": "runnow", "sportType": "Run"})

	n, err := BackfillHealthHydrated(ctx, db)
	if err != nil || n != 2 {
		t.Fatalf("backfill = %d, %v; muốn 2 (health-a, health-c)", n, err)
	}
	for path, want := range map[string]any{
		"users/u1/activities/health-a": true,
		"users/u1/activities/health-b": true,
		"users/u2/activities/health-c": true,
		"users/u1/activities/9001":     nil,
		"users/u1/activities/run-1":    nil,
	} {
		snap, err := db.Doc(path).Get(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if got := snap.Data()["hydrated"]; got != want {
			t.Errorf("%s hydrated = %v, muốn %v", path, got, want)
		}
	}
	if n, err := BackfillHealthHydrated(ctx, db); err != nil || n != 0 {
		t.Fatalf("chạy lại = %d, %v; muốn 0", n, err)
	}
}
