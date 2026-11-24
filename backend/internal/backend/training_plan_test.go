package backend

import (
	"reflect"
	"testing"
	"time"
)

func weekOfDays(first genPlanDay) []genPlanDay {
	days := []genPlanDay{first}
	for len(days) < 7 {
		days = append(days, genPlanDay{Type: "rest", Title: "Nghỉ", Purpose: "Hồi phục"})
	}
	return days
}

// Mục đích buổi tập đi theo buổi chạy vào doc; ngày nghỉ và chuỗi trắng thì
// không ghi, để app tự dùng câu chung theo loại bài.
func TestBuildTrainingPlanDocKeepsSessionPurpose(t *testing.T) {
	km := 5.0
	plan := genPlan{Days: append(
		weekOfDays(genPlanDay{Type: "easy", Title: "Chạy nhẹ", DistanceKm: &km, Purpose: "  Xây nền sức bền  "}),
		weekOfDays(genPlanDay{Type: "tempo", Title: "Tempo", DistanceKm: &km, Purpose: "   "})...,
	)}
	doc := buildTrainingPlanDoc("an", "Chạy 10km", goalSpec{}, plan, time.Now(), 0)
	days := doc["days"].([]map[string]any)
	if got := days[0]["purpose"]; got != "Xây nền sức bền" {
		t.Fatalf("purpose buổi chạy = %v", got)
	}
	if _, ok := days[1]["purpose"]; ok {
		t.Fatalf("ngày nghỉ có purpose: %v", days[1])
	}
	if _, ok := days[7]["purpose"]; ok {
		t.Fatalf("purpose trắng vẫn được ghi: %v", days[7])
	}
}

// Chủ đề tuần chỉ vào doc khi model trả đủ đúng số tuần.
func TestBuildTrainingPlanDocWeekThemesMustMatchWeeks(t *testing.T) {
	two := append(weekOfDays(genPlanDay{Type: "easy", Title: "a"}), weekOfDays(genPlanDay{Type: "race", Title: "b"})...)
	doc := buildTrainingPlanDoc("an", "g", goalSpec{}, genPlan{Days: two, WeekThemes: []string{" Xây nền ", "Về đích"}}, time.Now(), 0)
	if got := doc["weekThemes"]; !reflect.DeepEqual(got, []string{"Xây nền", "Về đích"}) {
		t.Fatalf("weekThemes = %v", got)
	}
	doc = buildTrainingPlanDoc("an", "g", goalSpec{}, genPlan{Days: two, WeekThemes: []string{"Xây nền"}}, time.Now(), 0)
	if _, ok := doc["weekThemes"]; ok {
		t.Fatalf("thiếu chủ đề mà vẫn ghi: %v", doc["weekThemes"])
	}
}
