package backend

import (
	"errors"
	"testing"
)

func TestRunCardOddsAtAnchorsAndMidpoints(t *testing.T) {
	// Điểm giữa mỗi khoảng là trung bình cộng hai đầu, tính tay từ bảng tỉ lệ.
	cases := []struct {
		km   float64
		want [5]int64
	}{
		{0.5, [5]int64{700000, 220000, 60000, 17000, 3000}},
		{2.75, [5]int64{575000, 260000, 110000, 43500, 11500}},
		{5, [5]int64{0, 660000, 240000, 80000, 20000}},
		{23.5, [5]int64{0, 505000, 310000, 140000, 45000}},
		{42, [5]int64{0, 0, 550000, 330000, 120000}},
		{51, [5]int64{0, 0, 450000, 390000, 160000}},
		{60, [5]int64{0, 0, 350000, 450000, 200000}},
		{100, [5]int64{0, 0, 350000, 450000, 200000}},
	}
	for _, c := range cases {
		if got := runCardOdds(c.km); got != c.want {
			t.Errorf("km %.2f: %v, muốn %v", c.km, got, c.want)
		}
	}
}

func TestRunCardOddsSumToOneMillionAndRiseWithKm(t *testing.T) {
	prev := runCardOdds(0.5)
	for i := 5; i <= 800; i++ {
		km := float64(i) / 10
		odds := runCardOdds(km)
		var sum int64
		for _, w := range odds {
			if w < 0 {
				t.Fatalf("km %.1f: tỉ lệ âm %v", km, odds)
			}
			sum += w
		}
		if sum != runCardPpm {
			t.Fatalf("km %.1f: tổng %d", km, sum)
		}
		if odds[4] < prev[4] {
			t.Fatalf("km %.1f: thần thoại giảm từ %d xuống %d", km, prev[4], odds[4])
		}
		if km >= 5 && odds[0] != 0 {
			t.Fatalf("km %.1f: từ 5 km không còn bậc thường, có %d", km, odds[0])
		}
		if km >= 42 && odds[1] != 0 {
			t.Fatalf("km %.1f: từ 42 km không còn bậc hiếm, có %d", km, odds[1])
		}
		prev = odds
	}
}

func TestRunCardPickWalksCumulativeOdds(t *testing.T) {
	odds := [5]int64{0, 505000, 310000, 140000, 45000}
	cases := map[int64]runCardTier{0: runCardRare, 504999: runCardRare, 505000: runCardEpic, 814999: runCardEpic, 815000: runCardLegendary, 954999: runCardLegendary, 955000: runCardMythic, 999999: runCardMythic}
	for r, want := range cases {
		if got := runCardPick(odds, r); got != want {
			t.Errorf("r=%d: %s, muốn %s", r, got, want)
		}
	}
}

// Dưới 3 km chỉ 1/5 lượt lật ra thẻ; mốc xét trên km đã làm tròn như in trên thẻ.
func TestRunCardChanceBelowThreeKm(t *testing.T) {
	for m, want := range map[float64]int64{500: 200000, 2949: 200000, 2950: 1000000, 3000: 1000000, 42195: 1000000} {
		if got := runCardChancePpm(runCardKm(m)); got != want {
			t.Errorf("%v m: %d, muốn %d", m, got, want)
		}
	}
}

func TestRunCardKmRoundsToTenth(t *testing.T) {
	for m, want := range map[float64]float64{42195: 42.2, 4949: 4.9, 4950: 5, 500: 0.5} {
		if got := runCardKm(m); got != want {
			t.Errorf("%v m: %v km, muốn %v", m, got, want)
		}
	}
}

func TestRunCardEligible(t *testing.T) {
	cases := []struct {
		name string
		data map[string]any
		want error
	}{
		{"chạy 5 km", map[string]any{"sportType": "Run", "distanceMeters": 5000.0}, nil},
		{"trail", map[string]any{"sportType": "TrailRun", "distanceMeters": 5000.0}, nil},
		{"máy chạy", map[string]any{"sportType": "VirtualRun", "distanceMeters": 5000.0}, nil},
		{"thiếu sportType là chạy", map[string]any{"distanceMeters": 500.0}, nil},
		{"đi bộ", map[string]any{"sportType": "Walk", "distanceMeters": 5000.0}, errRunCardNotRun},
		{"đạp xe", map[string]any{"sportType": "Ride", "distanceMeters": 20000.0}, errRunCardNotRun},
		{"dưới 500 m", map[string]any{"sportType": "Run", "distanceMeters": 499.0}, errRunCardNotRun},
		{"bản trùng Strava", map[string]any{"sportType": "Run", "distanceMeters": 5000.0, "duplicateOfActivityId": "s1"}, errRunCardDuplicate},
	}
	for _, c := range cases {
		if got := runCardEligible(c.data); !errors.Is(got, c.want) {
			t.Errorf("%s: %v, muốn %v", c.name, got, c.want)
		}
	}
}

func TestRunCardSnapshotKeepsWhatTheCardDraws(t *testing.T) {
	route := []any{map[string]any{"latitude": 0.0, "longitude": 0.0}}
	for i := 0; i < 200; i++ {
		route = append(route, map[string]any{"latitude": 21.0 + float64(i)/1000, "longitude": 105.123456789, "timestamp": "x"})
	}
	splits := []any{
		map[string]any{"distanceMeters": 1000.0, "movingTimeSeconds": 330.0, "averageHeartRate": 150.0},
		map[string]any{"distanceMeters": 0.0, "movingTimeSeconds": 10.0},
		map[string]any{"distanceMeters": 400.0, "movingTimeSeconds": 140.0},
	}
	got := runCardSnapshot(map[string]any{
		"name": "Chạy sáng", "sportType": "Run", "source": "strava", "startedAt": "2026-10-24T23:30:00Z",
		"distanceMeters": 1400.0, "movingTimeSeconds": int64(470), "elapsedTimeSeconds": 500.0,
		"routePoints": route, "splits": splits, "streams": map[string]any{"heartrate": []any{1.0}},
	})
	if _, ok := got["streams"]; ok {
		t.Fatal("snapshot không chép streams")
	}
	if got["movingTimeSeconds"] != 470.0 || got["name"] != "Chạy sáng" || got["startedAt"] != "2026-10-24T23:30:00Z" {
		t.Fatalf("snapshot sai số liệu: %v", got)
	}
	r := got["route"].([]any)
	// 80 điểm lấy đều trên 201 điểm, bỏ điểm (0,0) đầu tiên.
	if len(r) != 79 {
		t.Fatalf("route có %d điểm, muốn 79", len(r))
	}
	if p := r[0].(map[string]any); p["lng"] != 105.12346 {
		t.Fatalf("toạ độ phải làm tròn 5 chữ số: %v", p)
	}
	s := got["splits"].([]any)
	if len(s) != 2 || s[1].(map[string]any)["distanceMeters"] != 400.0 {
		t.Fatalf("splits = %v, muốn 2 chặng có số đo", s)
	}
	if _, ok := s[0].(map[string]any)["averageHeartRate"]; ok {
		t.Fatal("splits chỉ giữ quãng và thời gian")
	}
}

func TestRunCardVariantSplitsTheSecretSliceByElement(t *testing.T) {
	// Trúng khi số quay dưới 10.000 phần triệu (1 %), mỗi hành 2.000 liền nhau
	// theo thứ tự kim, mộc, thuỷ, hoả, thổ; từ 10.000 là thẻ thường.
	cases := []struct {
		r    int64
		want string
	}{
		{0, "secret.metal"},
		{1999, "secret.metal"},
		{2000, "secret.wood"},
		{4100, "secret.water"},
		{6000, "secret.fire"},
		{9999, "secret.earth"},
		{10000, ""},
		{999999, ""},
	}
	for _, c := range cases {
		if got := runCardVariant(c.r); got != c.want {
			t.Errorf("r %d: %q, muốn %q", c.r, got, c.want)
		}
	}
}
