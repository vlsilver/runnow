package backend

import (
	"fmt"
	"slices"
	"strings"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// gameRulesCardFor là thẻ Luật chơi của app: mỗi dòng một ý, theo cấu hình ván.
// Chi tiết (đề cử bằng nhau, đếm phiếu, ngoại lệ từng vai) vẫn ở gameRulesFor,
// chuỗi đó cũng là luật đưa cho bot nên không rút gọn được.
func gameRulesCardFor(cfg werewolf.Config) []GameSetupSection {
	out := []GameSetupSection{{Title: "Một vòng", Layout: setupLayoutTimeline, Items: cardRound(cfg)}}
	if km := cardKm(cfg); len(km) > 0 {
		out = append(out, GameSetupSection{Title: "Km", Items: km})
	}
	win := []GameSetupItem{
		{Key: "winVillage", Icon: "village", Label: teamLabels[werewolf.TeamVillage], Value: "Hết sói"},
		{Key: "winWolf", Icon: "teamWolf", Label: teamLabels[werewolf.TeamWolves], Value: "Số sói bằng số người còn lại"},
	}
	if !slices.Contains(cfg.Disabled, werewolf.Cupid) {
		win = append(win, GameSetupItem{Key: "winLovers", Icon: "lovers", Label: teamLabels[werewolf.TeamLovers], Value: "Chỉ còn hai người họ"})
	}
	return append(out,
		GameSetupSection{Title: "Lộ bài", Layout: setupLayoutTiles, Items: []GameSetupItem{
			{Key: "revealDeath", Icon: "teamWolf", Label: "Khi chết", Value: "Chỉ lộ phe"},
			{Key: "revealEnd", Icon: "reveal", Label: "Hết ván", Value: "Lật bài tất cả"},
		}},
		GameSetupSection{Title: "Thắng khi", Layout: setupLayoutTiles, Items: win})
}

// cardRound là các mốc của một vòng. Ván nhiều vòng mỗi vòng có thể có giờ pha
// riêng: mỗi mốc liệt kê giờ của từng vòng, mỗi vòng một dòng, theo thứ tự mở.
func cardRound(cfg werewolf.Config) []GameSetupItem {
	starts := cfg.RoundStarts()
	clocks := make([]werewolf.RoundClock, len(starts))
	for i, hour := range starts {
		clocks[i] = cfg.Clock(time.Date(2026, 1, 1, hour, 0, 0, 0, vietnam))
	}
	lines := func(line func(werewolf.RoundClock) string) string {
		out := make([]string, len(clocks))
		for i, k := range clocks {
			out[i] = line(k)
		}
		return strings.Join(out, "\n")
	}
	span := func(from, to time.Time) string { return hm(from) + "–" + hm(to) }
	closing := "Chốt phiếu và km"
	if cfg.KmOff {
		closing = "Chốt phiếu"
	}
	items := []GameSetupItem{
		{Key: "night", Icon: "night", Label: lines(func(k werewolf.RoundClock) string { return span(k.Night, k.Dawn) }), Value: "Dùng kỹ năng"},
		{Key: "nominate", Icon: "day", Label: lines(func(k werewolf.RoundClock) string { return span(k.Dawn, k.NominateClose) }), Value: fmt.Sprintf("Đề cử, tối đa %d người lên giàn", cfg.NomineeSeats())},
		{Key: "trial", Icon: "trial", Label: lines(func(k werewolf.RoundClock) string { return span(k.NominateClose, k.Close) }), Value: "Biểu quyết Treo hay Tha"},
		{Key: "close", Icon: "close", Label: lines(func(k werewolf.RoundClock) string { return hm(k.Close) }), Value: closing},
	}
	if line := cardSchedule(cfg); line != "" {
		items = append([]GameSetupItem{{Key: "schedule", Value: line}}, items...)
	}
	return items
}

// cardSchedule là câu lịch của ván không theo lịch gốc, rỗng với lịch gốc.
func cardSchedule(cfg werewolf.Config) string {
	if scheduleText(cfg) == scheduleDefaultText {
		return ""
	}
	starts := cfg.RoundStarts()
	hours := make([]string, len(starts))
	for i, h := range starts {
		hours[i] = itoa(h) + "h"
	}
	s := cfg.Schedule
	if s.Rounds == 1 {
		return fmt.Sprintf("Mỗi ngày một vòng %d tiếng, mở lúc %s.", s.RoundHours, hours[0])
	}
	return fmt.Sprintf("Mỗi ngày %d vòng, mỗi vòng %d tiếng, mở lúc %s.",
		s.Rounds, s.RoundHours, strings.Join(hours, ", "))
}

// cardKm rỗng khi ván tắt km: lúc đó bằng phiếu cũng không có km để xét.
func cardKm(cfg werewolf.Config) []GameSetupItem {
	if cfg.KmOff {
		return nil
	}
	decides := "Dùng kỹ năng"
	if cfg.VoteMode() == werewolf.VoteCut {
		decides = "Dùng kỹ năng và bỏ phiếu"
	}
	items := []GameSetupItem{
		{Key: "kmWindow", Icon: "km", Label: "Tính km", Value: "24 tiếng tới lúc chốt phiếu hoặc dùng kỹ năng"},
		{Key: "kmDecides", Icon: "skill", Label: "Km quyết định", Value: decides},
	}
	switch cfg.VoteMode() {
	case werewolf.VoteFlat:
		items = append(items, GameSetupItem{Key: "votes", Icon: "vote", Label: "Phiếu", Value: "Phiếu nào cũng tính"})
	case werewolf.VoteTop:
		items = append(items, GameSetupItem{Key: "votes", Icon: "vote", Label: "Phiếu", Value: "Không ai mất phiếu"})
	}
	if weight := cardTopWeight(cfg); weight > 0 {
		items = append(items, GameSetupItem{Key: "topWeight", Icon: "vote", Label: fmt.Sprintf("%d phiếu", weight),
			Value: fmt.Sprintf("%s chạy nhiều nhất, đủ %s km", topVotersText(cfg), formatKm(kmPerUnit(cfg)))})
	}
	if cfg.KmTie() {
		items = append(items, GameSetupItem{Key: "tie", Icon: "tie", Label: "Bằng phiếu", Value: "Tổng km cao hơn thắng, rồi bốc thăm"})
	}
	return items
}

// cardTopWeight là số phiếu của nhóm chạy nhiều nhất, 0 khi không có nhóm đó.
// VoteTop không đặt TopWeight thì nhóm đó được 2 phiếu.
func cardTopWeight(cfg werewolf.Config) int {
	switch {
	case cfg.VoteMode() == werewolf.VoteFlat:
		return 0
	case cfg.TopWeight > 0:
		return cfg.TopWeight
	case cfg.VoteMode() == werewolf.VoteTop:
		return 2
	}
	return 0
}
