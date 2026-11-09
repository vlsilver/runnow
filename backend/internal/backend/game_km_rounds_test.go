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

// Ngoài pha Ngày thì không Start được và lý do in đúng giờ của ván; ván thử
// không theo lịch thật nên được Start lúc nào cũng được.
func TestStartClosedOutsideDayPhase(t *testing.T) {
	vn := func(hour int) time.Time { return time.Date(2026, 10, 23, hour, 0, 0, 0, vietnam) }
	if got := startClosedReason(ww.Config{}, vn(12)); got != "" {
		t.Fatalf("trong pha Ngày: %q", got)
	}
	if got, want := startClosedReason(ww.Config{}, vn(23)), "Ván này chỉ bắt đầu được trong pha Ngày: 10h–20h."; got != want {
		t.Fatalf("mặc định: %q, muốn %q", got, want)
	}
	two := ww.Config{Schedule: &ww.Schedule{StartHour: 10, RoundHours: 12, Rounds: 2}}
	if got, want := startClosedReason(two, vn(12)), "Ván này chỉ bắt đầu được trong pha Ngày: 16h–21h, 4h–9h."; got != want {
		t.Fatalf("hai vòng: %q, muốn %q", got, want)
	}
	if got := startClosedReason(ww.Config{TestMode: true}, vn(23)); got != "" {
		t.Fatalf("ván thử: %q", got)
	}
}

// Ván không km nhiều vòng: lý do in đủ từng pha Ngày, luật không nhắc khung km,
// không có bảng km.
func TestNoKmRoundsStartAndRules(t *testing.T) {
	cfg := ww.Config{KmOff: true, Schedule: &ww.Schedule{StartHour: 6, RoundHours: 6, Rounds: 3}}
	at := time.Date(2026, 10, 23, 3, 0, 0, 0, vietnam)
	if got, want := startClosedReason(cfg, at), "Ván này chỉ bắt đầu được trong pha Ngày: 9h–11h30, 15h–17h30, 21h–23h30."; got != want {
		t.Fatalf("lý do = %q, muốn %q", got, want)
	}
	if rules := gameRulesFor(cfg); strings.Contains(rules, "24 tiếng trước") || strings.Contains(rules, "{kmWindow}") {
		t.Fatalf("luật ván không km = %q", rules)
	}
	st := ww.NewState(ww.Seed{1}, cfg, nil, msgStart)
	if tb := kmTable(map[string]any{"status": gameRunning}, st, &liveKm{AsOf: at}, at); tb != nil {
		t.Fatalf("ván không km có bảng km: %+v", tb)
	}
}
