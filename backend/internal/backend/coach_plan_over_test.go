package backend

import (
	"testing"
	"time"
)

func TestCoachPlanOver(t *testing.T) {
	// 15/11/2026 23:30 giờ Việt Nam, tức 16:30 UTC.
	lastNight := time.Date(2026, 11, 15, 16, 30, 0, 0, time.UTC)
	// 16/11/2026 00:30 giờ Việt Nam, vẫn là 15/11 theo UTC.
	nextDay := time.Date(2026, 11, 15, 17, 30, 0, 0, time.UTC)
	plan := map[string]any{"targetDate": "2026-11-15"}
	if coachPlanOver(plan, lastNight) {
		t.Fatal("ngày đích vẫn là ngày tập, chưa được tính kết thúc")
	}
	if !coachPlanOver(plan, nextDay) {
		t.Fatal("qua ngày đích theo giờ Việt Nam thì phải tính kết thúc")
	}
	ended := map[string]any{"targetDate": "2026-11-15", "endedAt": lastNight}
	if !coachPlanOver(ended, lastNight.AddDate(0, 0, -5)) {
		t.Fatal("chủ đã kết thúc thì hết chạy dù chưa tới ngày đích")
	}
	if coachPlanOver(map[string]any{}, nextDay) {
		t.Fatal("giáo án thiếu ngày đích thì không tự tính kết thúc")
	}
}
