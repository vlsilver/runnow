package backend

import (
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

func twoRoundsFrom(hour int) ww.Config {
	return ww.Config{Schedule: &ww.Schedule{StartHour: hour, RoundHours: 12, Rounds: 2}}
}

// Bảng km ván hai vòng: cột km đã chốt nói lần chốt gần nhất, cột đang gom tính
// từ 24 tiếng trước lần chốt tới.
func TestKmTableFollowsTheRoundFrame(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, twoRoundsFrom(22), nil, msgStart)
	data := map[string]any{"status": gameRunning}
	for _, c := range []struct {
		wall              time.Time
		last, today, note string
	}{
		{time.Date(2026, 10, 23, 8, 0, 0, 0, vietnam), "Hôm qua · chốt 22h", "Từ 10h qua · tới 08:00", "Km chốt lúc 10h,"},
		{time.Date(2026, 10, 23, 15, 40, 0, 0, vietnam), "Hôm nay · chốt 10h", "Từ 22h qua · tới 15:40", "Km chốt lúc 22h,"},
	} {
		live := &liveKm{AsOf: c.wall}
		tb := kmTable(data, st, live, c.wall)
		if tb.LastLabel != c.last || tb.TodayLabel != c.today || !strings.HasPrefix(tb.Note, c.note) {
			t.Fatalf("%s: %q | %q | %q", c.wall, tb.LastLabel, tb.TodayLabel, tb.Note)
		}
	}
}

// Luật nói một cách cho mọi ván: 24 tiếng trước giờ chốt.
func TestRulesTextFollowsKmFrame(t *testing.T) {
	two := gameRulesFor(twoRoundsFrom(22))
	if !strings.Contains(two, "24 tiếng trước giờ chốt") || strings.Contains(two, "hôm qua tới") || strings.Contains(two, "dùng chung km") {
		t.Fatalf("luật hai vòng = %q", two)
	}
	open6 := gameRulesFor(ww.Config{Schedule: &ww.Schedule{StartHour: 6, RoundHours: 24, Rounds: 1}})
	if !strings.Contains(open6, "24 tiếng trước giờ chốt") || strings.Contains(open6, "{kmWindow}") {
		t.Fatalf("luật mở 6h = %q", open6)
	}
	if bot := botVoteRulesFor(twoRoundsFrom(6), "2"); strings.Contains(bot, "{kmWindow}") || strings.Contains(bot, "22h hôm qua") {
		t.Fatalf("luật bot = %q", bot)
	}
}
