package backend

import (
	"encoding/json"
	"math"
	"testing"
)

func garminSamples(t *testing.T, raw string) []map[string]any {
	t.Helper()
	detail, _, err := decodeGarminDetail(json.RawMessage(`{"samples":` + raw + `}`))
	if err != nil {
		t.Fatal(err)
	}
	return detail.Samples
}

// Quãng đường 1500 m, tính tay: km đầu cắt giữa mẫu 600 m (180 s) và 1200 m
// (360 s), tức 180 + 400/600*180 = 300 s. Phần còn lại 500 m có 600-300 = 300 s
// đồng hồ, nhưng mẫu cuối đứng yên 120 s nên thời gian di chuyển chỉ 480-300 = 180 s.
func TestGarminDetailSplitsPerKilometer(t *testing.T) {
	const start = 1_000
	fields := garminDetailFields(garminSamples(t, `[
		{"startTimeInSeconds":1000,"totalDistanceInMeters":0,"movingDurationInSeconds":0,"heartRate":120},
		{"startTimeInSeconds":1180,"totalDistanceInMeters":600,"movingDurationInSeconds":180,"heartRate":140},
		{"startTimeInSeconds":1360,"totalDistanceInMeters":1200,"movingDurationInSeconds":360,"heartRate":160},
		{"startTimeInSeconds":1480,"totalDistanceInMeters":1500,"movingDurationInSeconds":480,"heartRate":170},
		{"startTimeInSeconds":1600,"totalDistanceInMeters":1500,"movingDurationInSeconds":480,"heartRate":150}
	]`), start)

	splits, _ := fields["splits"].([]any)
	if len(splits) != 2 {
		t.Fatalf("splits = %v, muốn 2 dòng", fields["splits"])
	}
	first := splits[0].(map[string]any)
	if first["split"] != 1 || first["distanceMeters"] != 1000.0 || first["movingTimeSeconds"] != int64(300) || first["elapsedTimeSeconds"] != int64(300) {
		t.Fatalf("km 1 = %v", first)
	}
	last := splits[1].(map[string]any)
	if last["split"] != 2 || last["distanceMeters"] != 500.0 || last["movingTimeSeconds"] != int64(180) || last["elapsedTimeSeconds"] != int64(300) {
		t.Fatalf("km lẻ = %v", last)
	}
	if got := first["averageSpeedMetersPerSecond"].(float64); math.Abs(got-1000.0/300) > 1e-9 {
		t.Fatalf("tốc độ km 1 = %v", got)
	}
}

// Chỉ một mẫu có thời gian di chuyển thì không được trộn với đồng hồ thường: trộn
// thì km 2 ra 390 - 400 = -10 s. Đúng là 800 - 400 = 400 s theo đồng hồ.
func TestGarminDetailDoesNotMixClocks(t *testing.T) {
	fields := garminDetailFields(garminSamples(t, `[
		{"startTimeInSeconds":1000,"totalDistanceInMeters":0},
		{"startTimeInSeconds":1400,"totalDistanceInMeters":1000},
		{"startTimeInSeconds":1800,"totalDistanceInMeters":2000,"movingDurationInSeconds":390}
	]`), 1_000)
	splits, _ := fields["splits"].([]any)
	if len(splits) != 2 {
		t.Fatalf("splits = %v", fields["splits"])
	}
	if got := splits[1].(map[string]any)["movingTimeSeconds"]; got != int64(400) {
		t.Fatalf("km 2 movingTimeSeconds = %v, muốn 400", got)
	}
}

// Mẫu GPS hỏng không vào tuyến; thiếu GPS (chạy trong nhà) thì không có trường
// tuyến để lần merge không xoá tuyến đã có.
func TestGarminDetailRoute(t *testing.T) {
	fields := garminDetailFields(garminSamples(t, `[
		{"startTimeInSeconds":1000,"latitudeInDegree":21.01,"longitudeInDegree":105.81,"totalDistanceInMeters":0},
		{"startTimeInSeconds":1010,"latitudeInDegree":0,"longitudeInDegree":0,"totalDistanceInMeters":30},
		{"startTimeInSeconds":1020,"latitudeInDegree":95,"longitudeInDegree":105.82,"totalDistanceInMeters":60},
		{"startTimeInSeconds":1030,"totalDistanceInMeters":90},
		{"startTimeInSeconds":1040,"latitudeInDegree":21.02,"longitudeInDegree":105.82,"totalDistanceInMeters":120}
	]`), 1_000)
	route, _ := fields["routePoints"].([]any)
	if len(route) != 2 {
		t.Fatalf("routePoints = %v, muốn 2 điểm", fields["routePoints"])
	}
	first := route[0].(map[string]any)
	if first["latitude"] != 21.01 || first["longitude"] != 105.81 || first["timestamp"] != "1970-01-01T00:16:40Z" {
		t.Fatalf("điểm đầu = %v", first)
	}
	if fields["routeSketch"] == nil {
		t.Fatal("thiếu routeSketch")
	}

	indoor := garminDetailFields(garminSamples(t, `[
		{"startTimeInSeconds":1000,"totalDistanceInMeters":0},
		{"startTimeInSeconds":1600,"totalDistanceInMeters":1500}
	]`), 1_000)
	if _, ok := indoor["routePoints"]; ok {
		t.Fatalf("buổi không GPS có routePoints: %v", indoor["routePoints"])
	}
	if _, ok := indoor["streams"]; !ok {
		t.Fatal("buổi không GPS vẫn phải có đồ thị")
	}
}

// Các dãy phải cùng độ dài vì app ghép theo chỉ số. Tốc độ tính tay: 100 m trong
// 20 s = 5 m/s. Nhịp tim thiếu ở mẫu giữa thì giữ giá trị trước đó.
func TestGarminDetailStreamsStayAligned(t *testing.T) {
	fields := garminDetailFields(garminSamples(t, `[
		{"startTimeInSeconds":1000,"totalDistanceInMeters":0,"heartRate":120},
		{"startTimeInSeconds":1020,"totalDistanceInMeters":100},
		{"startTimeInSeconds":1040,"totalDistanceInMeters":90,"heartRate":200},
		{"startTimeInSeconds":1060,"totalDistanceInMeters":300,"heartRate":140,"elevationInMeters":12.5}
	]`), 1_000)
	streams := fields["streams"].(map[string]any)
	distance := streams["distance"].([]float64)
	if len(distance) != 3 || distance[1] != 100 || distance[2] != 300 {
		t.Fatalf("distance = %v, mẫu tụt quãng đường phải bị bỏ", distance)
	}
	for _, key := range []string{"time", "velocity_smooth", "heartrate", "altitude"} {
		if got := len(streams[key].([]float64)); got != 3 {
			t.Fatalf("%s dài %d, muốn 3", key, got)
		}
	}
	if got := streams["velocity_smooth"].([]float64)[1]; got != 5 {
		t.Fatalf("velocity_smooth[1] = %v, muốn 5", got)
	}
	if got := streams["heartrate"].([]float64); got[1] != 120 || got[2] != 140 {
		t.Fatalf("heartrate = %v", got)
	}
	if got := streams["altitude"].([]float64); got[0] != 12.5 {
		t.Fatalf("altitude đầu = %v, muốn lấp bằng giá trị đo được", got[0])
	}
}

func TestGarminDetailActivityKeepsSummaryDocID(t *testing.T) {
	detail, keys, err := decodeGarminDetail(json.RawMessage(`{"userId":"g-1","summaryId":"77-detail","activityId":77,"summary":{"activityType":"RUNNING"},"samples":[]}`))
	if err != nil {
		t.Fatal(err)
	}
	a := detail.activity()
	if a.UserID != "g-1" || a.SummaryID != "77" || a.ActivityID != json.Number("77") {
		t.Fatalf("activity = %+v", a)
	}
	if len(keys) != 5 {
		t.Fatalf("keys = %v", keys)
	}
}
