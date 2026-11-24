package backend

import (
	"math"
	"testing"
	"time"
)

// Ví dụ trong tài liệu "Encoded Polyline Algorithm Format" của Google Maps.
func TestDecodePolylineGoogleExample(t *testing.T) {
	got, err := decodePolyline("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
	if err != nil {
		t.Fatal(err)
	}
	want := [][2]float64{{38.5, -120.2}, {40.7, -120.95}, {43.252, -126.453}}
	if len(got) != len(want) {
		t.Fatalf("got %d points, want %d", len(got), len(want))
	}
	for i := range want {
		if math.Abs(got[i][0]-want[i][0]) > 1e-9 || math.Abs(got[i][1]-want[i][1]) > 1e-9 {
			t.Fatalf("point %d = %v, want %v", i, got[i], want[i])
		}
	}
}

// Sát xích đạo nên cos(vĩ độ) coi như 1. Chiều ngang 0.002 dài hơn chiều dọc
// 0.001 nên lấy 0.002 làm 1000; bắc ở trên nên vĩ độ lớn ra y nhỏ.
func TestRouteSketchKeepsAspectAndPutsNorthUp(t *testing.T) {
	got := routeSketch([][2]float64{{0, 0}, {0, 0.002}, {0.001, 0.002}})
	want := []int{0, 500, 1000, 500, 1000, 0}
	if !slicesEqual(got, want) {
		t.Fatalf("got %v, want %v", got, want)
	}
}

// Một đường thẳng 1000 điểm dọc xích đạo thu về 64 điểm cách đều nhau theo
// quãng đường: điểm i nằm ở i·1000/63.
func TestRouteSketchResamplesLongRouteEvenly(t *testing.T) {
	points := make([][2]float64, 1000)
	for i := range points {
		points[i] = [2]float64{0, float64(i) * 0.00001}
	}
	got := routeSketch(points)
	if len(got) != 2*64 {
		t.Fatalf("got %d values, want %d", len(got), 2*64)
	}
	for i := 0; i < 64; i++ {
		wantX := int(math.Round(float64(i) * 1000 / 63))
		if got[2*i] != wantX || got[2*i+1] != 0 {
			t.Fatalf("point %d = (%d, %d), want (%d, 0)", i, got[2*i], got[2*i+1], wantX)
		}
	}
}

// Buổi ghi bằng app: routeSketch tính từ routePoints, không lấy bản app gửi.
func TestNormalizeTrackedActivityWritesRouteSketch(t *testing.T) {
	point := func(lat, lng float64) any { return map[string]any{"latitude": lat, "longitude": lng} }
	got, err := normalizeTrackedActivity(map[string]any{
		"id": "runnow-7", "name": "Chạy", "source": "runnow", "sportType": "Run",
		"startedAt":      time.Now().Add(-time.Hour).UTC().Format(time.RFC3339),
		"distanceMeters": 300.0, "movingTimeSeconds": 120, "elapsedTimeSeconds": 130,
		"routePoints": []any{point(0, 0), point(0, 0.002), point(0.001, 0.002)},
		"routeSketch": []any{1.0, 2.0, 3.0, 4.0},
	})
	if err != nil {
		t.Fatal(err)
	}
	want := []int{0, 500, 1000, 500, 1000, 0}
	if sk, _ := got["routeSketch"].([]int); !slicesEqual(sk, want) {
		t.Fatalf("routeSketch = %v, want %v", got["routeSketch"], want)
	}
}

// Buổi Strava: cùng ba điểm trên, mã hoá tay thành polyline "???oKgE?"
// (độ lệch theo 1e-5 độ: (0,0), (0,200), (100,0)).
func TestNormalizeActivityWritesRouteSketchFromPolyline(t *testing.T) {
	poly := "???oKgE?"
	got := NormalizeActivity(StravaActivity{ID: 1, SportType: "Run", Map: &StravaMap{SummaryPolyline: &poly}}, false, nil)
	want := []int{0, 500, 1000, 500, 1000, 0}
	if sk, _ := got["routeSketch"].([]int); !slicesEqual(sk, want) {
		t.Fatalf("routeSketch = %v, want %v", got["routeSketch"], want)
	}
}

func slicesEqual(a, b []int) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestDecodePolylineRejectsTruncatedInput(t *testing.T) {
	// Cắt giữa một số: byte cuối còn bit "còn tiếp".
	if _, err := decodePolyline("_p~iF~ps|U_"); err == nil {
		t.Fatal("want error for truncated polyline")
	}
}
