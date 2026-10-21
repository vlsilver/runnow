package backend

import (
	"context"
	"testing"
)

func TestShrinkTrackedActivityFitsUnderLimit(t *testing.T) {
	// Dựng một buổi chạy khổng lồ (kiểu 21km): rất nhiều routePoints + streams,
	// mô phỏng đúng ca doc vượt 1MB đã làm mất buổi 8.2km.
	const n = 14000
	rp := make([]any, 0, n)
	for i := 0; i < n; i++ {
		rp = append(rp, map[string]any{
			"lat": 10.0 + float64(i)*1e-6, "lng": 106.0 + float64(i)*1e-6,
			"alt": 5.0 + float64(i%30), "t": i,
		})
	}
	mkStream := func() []any {
		a := make([]any, n)
		for i := range a {
			a[i] = float64(i%200) + 0.5
		}
		return a
	}
	next := map[string]any{
		"id": "runnow-huge", "distanceMeters": 21097.0, "movingTimeSeconds": 7200,
		"routePoints": rp,
		"streams": map[string]any{
			"heartrate": mkStream(), "pace": mkStream(),
			"altitude": mkStream(), "cadence": mkStream(),
		},
	}
	if estimateDocJSONSize(next) <= trackedActivityMaxJSONBytes {
		t.Fatalf("setup: buổi test chưa đủ lớn (%d bytes)", estimateDocJSONSize(next))
	}

	shrinkTrackedActivity(context.Background(), "uid-test", next)

	if got := estimateDocJSONSize(next); got > trackedActivityMaxJSONBytes {
		t.Fatalf("sau downsample vẫn vượt ngưỡng: %d > %d", got, trackedActivityMaxJSONBytes)
	}
	// Vẫn phải giữ route (không cắt sạch) để bản đồ còn hiển thị được.
	if rp2, _ := next["routePoints"].([]any); len(rp2) < 2 {
		t.Fatalf("routePoints bị cắt sạch, còn %d", len(rp2))
	}
}

func TestShrinkTrackedActivityLeavesSmallOneAlone(t *testing.T) {
	rp := []any{
		map[string]any{"lat": 10.0, "lng": 106.0},
		map[string]any{"lat": 10.1, "lng": 106.1},
	}
	next := map[string]any{"id": "runnow-small", "distanceMeters": 1000.0, "routePoints": rp}
	shrinkTrackedActivity(context.Background(), "uid", next)
	if rp2, _ := next["routePoints"].([]any); len(rp2) != 2 {
		t.Fatalf("buổi nhỏ bị đụng tới: routePoints còn %d", len(rp2))
	}
}
