package backend

import (
	"reflect"
	"testing"
	"time"
)

func planTestTime(day string, hour int) time.Time {
	t, _ := time.ParseInLocation("2006-01-02", day, vietnam)
	return t.Add(time.Duration(hour) * time.Hour)
}

func planTestRun(id, day string, hour int, meters float64) ActivityFact {
	start := planTestTime(day, hour)
	return ActivityFact{ID: id, Source: "strava", SportType: "Run", StartedAt: start, DistanceMeters: meters, MovingTimeSeconds: 1800, ElapsedTimeSeconds: 1800}
}

// Giáo án bắt đầu 02/11: 02 chạy nhẹ 5 km, 03 nghỉ, 04 tempo 6 km, 05 nghỉ,
// 06 chạy dài 10 km.
func planTestDoc(participant map[string]any) map[string]any {
	return map[string]any{
		"startDate": "2026-11-02",
		"days": []any{
			map[string]any{"type": "easy", "distanceKm": 5.0},
			map[string]any{"type": "rest"},
			map[string]any{"type": "tempo", "distanceKm": 6.0},
			map[string]any{"type": "rest"},
			map[string]any{"type": "long", "distanceKm": 10.0},
		},
		"participants": map[string]any{"an": participant},
	}
}

func dueIndices(sessions []planSession) []int {
	out := []int{}
	for _, s := range sessions {
		out = append(out, s.index)
	}
	return out
}

func TestDuePlanSessionsSkipsRestFutureDoneAndUnticked(t *testing.T) {
	// Hôm nay 04/11: buổi 06/11 chưa tới, ngày nghỉ không xét.
	now := planTestTime("2026-11-04", 20)
	got := dueIndices(duePlanSessions(planTestDoc(map[string]any{}), "an", now))
	if want := []int{0, 2}; !reflect.DeepEqual(got, want) {
		t.Fatalf("buổi tới hạn = %v, muốn %v", got, want)
	}
	// Buổi 0 đã xong. Buổi 2 từng được tự đánh dấu rồi người dùng bỏ tick.
	part := map[string]any{"doneIndices": []any{int64(0)}, "matched": map[string]any{"2": "a1"}}
	if got := dueIndices(duePlanSessions(planTestDoc(part), "an", now)); len(got) != 0 {
		t.Fatalf("buổi đã xong hoặc đã bỏ tick vẫn bị xét: %v", got)
	}
	// Người không theo giáo án thì không có buổi nào.
	if got := duePlanSessions(planTestDoc(map[string]any{}), "binh", now); got != nil {
		t.Fatalf("người ngoài có buổi tới hạn: %v", got)
	}
}

func TestDuePlanSessionsBoundedByJoinDayAndLookback(t *testing.T) {
	// Tham gia 03/11 thì buổi 02/11 không phải của mình.
	part := map[string]any{"joinedAt": planTestTime("2026-11-03", 9)}
	got := dueIndices(duePlanSessions(planTestDoc(part), "an", planTestTime("2026-11-04", 20)))
	if want := []int{2}; !reflect.DeepEqual(got, want) {
		t.Fatalf("buổi tới hạn = %v, muốn %v", got, want)
	}
	// 12/11: buổi 04/11 đã quá 7 ngày, buổi 06/11 còn trong hạn.
	got = dueIndices(duePlanSessions(planTestDoc(map[string]any{}), "an", planTestTime("2026-11-12", 8)))
	if want := []int{4}; !reflect.DeepEqual(got, want) {
		t.Fatalf("buổi tới hạn = %v, muốn %v", got, want)
	}
}

func TestMatchPlanSessionsNeedsEightyPercentOfTheDay(t *testing.T) {
	sessions := []planSession{
		{index: 0, day: "2026-11-02", meters: 5000},
		{index: 2, day: "2026-11-04", meters: 6000},
		{index: 4, day: "2026-11-06", meters: 10000},
	}
	walk := planTestRun("walk", "2026-11-06", 6, 9000)
	walk.SportType = "Walk"
	got := matchPlanSessions(sessions, []ActivityFact{
		// 3,9 km trên 5 km là 78%: chưa đủ.
		planTestRun("short", "2026-11-02", 6, 3900),
		// Khởi động 1,5 km và bài chính 3,5 km: 5 km trên 6 km là 83%.
		planTestRun("warmup", "2026-11-04", 6, 1500),
		planTestRun("main", "2026-11-04", 7, 3500),
		// Đi bộ 9 km không thay được buổi chạy dài.
		walk,
	})
	if want := map[int]string{2: "main"}; !reflect.DeepEqual(got, want) {
		t.Fatalf("buổi khớp = %v, muốn %v", got, want)
	}
}
