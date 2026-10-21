package backend

import (
	"math"
	"testing"
	"time"
)

// Khung chốt ngày 15/10: 22:00 14/10 → 22:00 15/10 giờ VN.
var kmFrameEnd = time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam)

func vn(day, hour, min int) time.Time { return time.Date(2026, 10, day, hour, min, 0, 0, vietnam) }

func hourly(m map[int]float64) []float64 {
	h := make([]float64, 24)
	for i, v := range m {
		h[i] = v
	}
	return h
}

func near(a, b float64) bool { return math.Abs(a-b) < 1e-6 }

// R28, số tính tay:
//   - hôm qua: distance 10000, Σhourly 8000 → scale 1.25; giờ 22–23 có 1000+1000 → 2500
//   - hôm nay: distance 6000, Σhourly 6000 → scale 1; giờ 0–21 có 4000 (giờ 22 có 2000, không tính) → 4000
//   - health = 6500, không có buổi chính thức → km = 6500, nguồn health
func TestR28HealthKmUsesScaledHourlyAcrossTheFrame(t *testing.T) {
	got, err := computeFrameKm(kmFrameEnd, nil,
		&stepDayKm{DistanceMeters: 10000, HourlyDistance: hourly(map[int]float64{8: 6000, 22: 1000, 23: 1000})},
		&stepDayKm{DistanceMeters: 6000, HourlyDistance: hourly(map[int]float64{7: 3000, 21: 1000, 22: 2000})},
	)
	if err != nil {
		t.Fatal(err)
	}
	if !near(got.HealthMeters, 6500) || !near(got.Meters, 6500) || got.Source != "health" {
		t.Fatalf("health=%v meters=%v source=%q, mong đợi 6500/6500/health", got.HealthMeters, got.Meters, got.Source)
	}
	if !got.HourlyYesterday || !got.HourlyToday || !near(got.ScaleYesterday, 1.25) || !near(got.ScaleToday, 1) {
		t.Fatalf("snapshot thiếu nguồn: %+v", got)
	}
}

func run(id, source, sport string, start time.Time, meters float64, minutes int64) ActivityFact {
	return ActivityFact{ID: id, Source: source, SportType: sport, StartedAt: start, DistanceMeters: meters, ElapsedTimeSeconds: minutes * 60, MovingTimeSeconds: minutes * 60}
}

func mustFrame(t *testing.T, acts []ActivityFact, y, d *stepDayKm) FrameKm {
	t.Helper()
	got, err := computeFrameKm(kmFrameEnd, acts, y, d)
	if err != nil {
		t.Fatal(err)
	}
	return got
}

// Thiếu hourly cả hai ngày: phần hôm qua 0, phần hôm nay lấy distance cả ngày.
func TestR28MissingHourlyFallsBackToDayDistance(t *testing.T) {
	got := mustFrame(t, nil, &stepDayKm{DistanceMeters: 9000}, &stepDayKm{DistanceMeters: 7000})
	if !near(got.HealthMeters, 7000) || got.HourlyYesterday || got.HourlyToday {
		t.Fatalf("%+v, mong đợi health 7000 và không có hourly", got)
	}
	// Chưa có doc stepDay nào thì 0, không lỗi.
	if got := mustFrame(t, nil, nil, nil); got.Meters != 0 || got.Source != "none" {
		t.Fatalf("không có dữ liệu: %+v", got)
	}
}

// Σhourly = 0 (đủ 24 ô nhưng toàn 0) xử lý như thiếu hourly.
func TestR28ZeroHourlySumTreatedAsMissing(t *testing.T) {
	got := mustFrame(t, nil, &stepDayKm{DistanceMeters: 5000, HourlyDistance: hourly(nil)}, &stepDayKm{DistanceMeters: 3000, HourlyDistance: hourly(nil)})
	if !near(got.HealthMeters, 3000) {
		t.Fatalf("health = %v, mong đợi 3000 (0 hôm qua + distance hôm nay)", got.HealthMeters)
	}
}

// Ô âm kẹp về 0 trước khi tính Σ: Σ = 2000 → scale 1 → hôm nay 2000, không phải 1500.
func TestR28NegativeHourlyClamped(t *testing.T) {
	got := mustFrame(t, nil, nil, &stepDayKm{DistanceMeters: 2000, HourlyDistance: hourly(map[int]float64{3: -500, 5: 2000})})
	if !near(got.HealthMeters, 2000) || !near(got.ScaleToday, 1) {
		t.Fatalf("health=%v scale=%v, mong đợi 2000 và 1", got.HealthMeters, got.ScaleToday)
	}
}

// R26: khung là [22:00 hôm qua, 22:00 hôm nay). Buổi bắt đầu đúng 22:00:00 hôm
// nay thuộc khung sau; đúng 22:00:00 hôm qua thì thuộc khung này.
func TestR26FrameBoundaryAtExactly2200(t *testing.T) {
	got := mustFrame(t, []ActivityFact{
		run("a", "strava", "Run", vn(15, 22, 0), 5000, 30),
		run("b", "strava", "Run", vn(14, 22, 0), 3000, 20),
	}, nil, nil)
	if !near(got.OfficialMeters, 3000) {
		t.Fatalf("official = %v, mong đợi 3000", got.OfficialMeters)
	}
}

// Buổi bắt đầu 21:59 chạy qua mốc 22:00 tính trọn vào khung của ngày bắt đầu.
func TestR26RunStartingAt2159CountsWhollyInThisFrame(t *testing.T) {
	got := mustFrame(t, []ActivityFact{run("a", "strava", "Run", vn(15, 21, 59), 10000, 60)}, nil, nil)
	if !near(got.OfficialMeters, 10000) {
		t.Fatalf("official = %v, mong đợi 10000", got.OfficialMeters)
	}
}

// R27: cùng một buổi có ở Strava (official 5000) và trong Health (5200) thì
// lấy max, không cộng thành 10200.
func TestR27OfficialAndHealthTakeMaxNotSum(t *testing.T) {
	got := mustFrame(t, []ActivityFact{run("a", "strava", "Run", vn(15, 6, 0), 5000, 30)},
		nil, &stepDayKm{DistanceMeters: 5200})
	if !near(got.Meters, 5200) || got.Source != "health" {
		t.Fatalf("meters=%v source=%q, mong đợi 5200/health", got.Meters, got.Source)
	}
	// Hoà thì ghi nguồn official: buổi có GPS dễ soát hơn số Health.
	tie := mustFrame(t, []ActivityFact{run("a", "strava", "Run", vn(15, 6, 0), 5000, 30)}, nil, &stepDayKm{DistanceMeters: 5000})
	if tie.Source != "official" {
		t.Fatalf("hoà 5000/5000 mà source = %q", tie.Source)
	}
}

// R27: đi bộ, đạp xe ghi bằng 3i không phải buổi chính thức (nguồn phụ chỉ tính
// Run ≥ 500 m); đi bộ trên Strava thì có.
func TestR27OnlyOfficialActivitiesCount(t *testing.T) {
	got := mustFrame(t, []ActivityFact{
		run("walk3i", "runnow", "Walk", vn(15, 7, 0), 3000, 40),
		run("ride3i", "runnow", "Ride", vn(15, 8, 0), 20000, 50),
		run("short3i", "runnow", "Run", vn(15, 9, 0), 400, 3),
		run("walkStrava", "strava", "Walk", vn(15, 12, 0), 2000, 25),
	}, nil, nil)
	if !near(got.OfficialMeters, 2000) {
		t.Fatalf("official = %v, mong đợi 2000 (chỉ đi bộ Strava)", got.OfficialMeters)
	}
}

// Bản Strava bắt đầu 21:59 hôm qua và bản Health của cùng buổi bắt đầu 22:00:30
// hôm qua: phải khử trùng nhờ nạp lùi, không được tính bản Health vào khung này.
func TestR27DuplicateAcrossBoundaryNotCountedTwice(t *testing.T) {
	health := run("h", "apple_health", "Run", vn(14, 22, 0).Add(30*time.Second), 5100, 30)
	got := mustFrame(t, []ActivityFact{run("s", "strava", "Run", vn(14, 21, 59), 5000, 31), health}, nil, nil)
	if got.OfficialMeters != 0 {
		t.Fatalf("official = %v: bản Health trùng buổi Strava của khung trước bị tính", got.OfficialMeters)
	}
}

func TestFrameMustEndAt2200VN(t *testing.T) {
	for _, end := range []time.Time{vn(15, 21, 0), time.Date(2026, 10, 15, 22, 0, 0, 0, time.UTC)} {
		if _, err := computeFrameKm(end, nil, nil, nil); err == nil {
			t.Fatalf("%s không phải 22:00 VN mà không bị từ chối", end)
		}
	}
}
