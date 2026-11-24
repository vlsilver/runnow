package backend

import (
	"strings"
	"testing"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Ngày thiếu dữ liệu theo giờ chỉ có một tổng: tổng đó tính cho ngày chiếm nhiều
// giờ hơn trong khung 24 tiếng, theo giờ chốt của ván, không theo 22h của lịch gốc.
func TestDayTotalFollowsCloseHour(t *testing.T) {
	yesterday := &stepDayKm{DistanceMeters: 5000}
	today := &stepDayKm{DistanceMeters: 3000}
	for _, c := range []struct {
		name  string
		close int
		want  float64
	}{
		{"chốt 22h, ngày chốt chiếm 22 tiếng", 22, 3000},
		{"chốt 15h, ngày chốt chiếm 15 tiếng", 15, 3000},
		{"chốt 12h, bằng nhau thì lấy ngày chốt", 12, 3000},
		{"chốt 11h, hôm trước chiếm 13 tiếng", 11, 5000},
		{"chốt 6h, hôm trước chiếm 18 tiếng", 6, 5000},
		{"chốt 0h, cả khung là hôm trước", 0, 5000},
	} {
		t.Run(c.name, func(t *testing.T) {
			end := time.Date(2026, 10, 16, c.close, 0, 0, 0, vietnam)
			got, err := computeFrameKm(end.Add(-24*time.Hour), end, nil, yesterday, today)
			if err != nil {
				t.Fatal(err)
			}
			if got.Meters != c.want {
				t.Fatalf("km = %v, mong đợi %v", got.Meters, c.want)
			}
		})
	}
}

// Tin nhắc chưa có hạn thì không in giờ của lịch gốc: ván có thể chốt giờ khác.
func TestReminderWithoutDeadlineNamesNoHour(t *testing.T) {
	for _, reason := range []string{werewolf.ReminderNominate, werewolf.ReminderVote} {
		text, err := reminderText(reason, time.Time{})
		if err != nil {
			t.Fatal(err)
		}
		if strings.Contains(text, "20h") || strings.Contains(text, "22h") || !strings.Contains(text, "sắp đóng") {
			t.Fatalf("%s: %q", reason, text)
		}
	}
}

// Mô tả ô cài đặt và bộ ván có sẵn không được khẳng định giờ chốt: giờ do ván đặt.
func TestCreateFormTextsNameNoCloseHour(t *testing.T) {
	for i, key := range []string{"a", "b", "c", "d"} {
		if d := phaseSetting(i, key, "x", "").Description; strings.Contains(d, "22h") {
			t.Fatalf("ô pha %d: %q", i, d)
		}
	}
	for _, p := range gamePresets {
		for _, line := range p.Details {
			if strings.Contains(line, "22h") {
				t.Fatalf("bộ %s: %q", p.Key, line)
			}
		}
	}
}
