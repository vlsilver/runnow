//go:build emulator

package backend

import (
	"context"
	"reflect"
	"testing"
)

func TestEmulatorBackfillRouteSketch(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	point := func(lat, lng float64) any { return map[string]any{"latitude": lat, "longitude": lng} }
	seed(t, db, "users/u1", map[string]any{"displayName": "A"})
	seed(t, db, "users/u1/activities/run-1", map[string]any{"source": "runnow",
		"routePoints": []any{point(0, 0), point(0, 0.002), point(0.001, 0.002)}})
	// u2 không có doc users/u2, chỉ có subcollection: backfill vẫn phải thấy.
	seed(t, db, "users/u2/activities/9001", map[string]any{"source": "strava", "polyline": "???oKgE?"})
	seed(t, db, "users/u1/activities/9002", map[string]any{"source": "strava", "polyline": "???oKgE?",
		"routeSketch": []any{1, 2, 3, 4}})
	seed(t, db, "users/u1/activities/health-a", map[string]any{"source": "apple_health"})

	n, err := BackfillRouteSketch(ctx, db)
	if err != nil || n != 2 {
		t.Fatalf("backfill = %d, %v; muốn 2 (run-1, 9001)", n, err)
	}
	shape := []any{int64(0), int64(500), int64(1000), int64(500), int64(1000), int64(0)}
	for path, want := range map[string]any{
		"users/u1/activities/run-1":    shape,
		"users/u2/activities/9001":     shape,
		"users/u1/activities/9002":     []any{int64(1), int64(2), int64(3), int64(4)},
		"users/u1/activities/health-a": nil,
	} {
		snap, err := db.Doc(path).Get(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if got := snap.Data()["routeSketch"]; !reflect.DeepEqual(got, want) {
			t.Errorf("%s routeSketch = %v, muốn %v", path, got, want)
		}
	}
	if n, err := BackfillRouteSketch(ctx, db); err != nil || n != 0 {
		t.Fatalf("chạy lại = %d, %v; muốn 0", n, err)
	}
}
