package backend

import (
	"fmt"
	"slices"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// cardLines viết thẻ luật thành từng dòng "khối | nhãn | nội dung" để so nguyên.
func cardLines(cfg ww.Config) []string {
	var out []string
	for _, s := range gameRulesCardFor(cfg) {
		for _, it := range s.Items {
			out = append(out, fmt.Sprintf("%s | %s | %s", s.Title, it.Label, it.Value))
		}
	}
	return out
}

// Lịch gốc: đêm 22h, chốt đêm 10h, lên giàn 20h, chốt ngày 22h (spec luật).
func TestRulesCardDefaultGame(t *testing.T) {
	want := []string{
		"Một vòng | 22h–10h | Dùng kỹ năng",
		"Một vòng | 10h–20h | Đề cử, tối đa 3 người lên giàn",
		"Một vòng | 20h–22h | Biểu quyết Treo hay Tha",
		"Một vòng | 22h | Chốt phiếu và km",
		"Km | Tính km | 24 tiếng tới lúc chốt phiếu hoặc dùng kỹ năng",
		"Km | Km quyết định | Dùng kỹ năng và bỏ phiếu",
		"Lộ bài | Bị treo | Chỉ lộ phe",
		"Lộ bài | Chết cách khác | Lật bài",
		"Thắng khi | Phe Dân | Hết sói",
		"Thắng khi | Phe Sói | Số sói bằng số người còn lại",
		"Thắng khi | Cặp đôi | Chỉ còn hai người họ",
	}
	if got := cardLines(ww.Config{}); !slices.Equal(got, want) {
		t.Fatalf("thẻ luật:\n%q\nmuốn:\n%q", got, want)
	}
	var layouts []string
	for _, s := range gameRulesCardFor(ww.Config{}) {
		layouts = append(layouts, s.Layout)
	}
	if want := []string{"timeline", "", "tiles", "tiles"}; !slices.Equal(layouts, want) {
		t.Fatalf("layout = %q, muốn %q", layouts, want)
	}
}

// Ván nhiều vòng: mỗi vòng trong ngày có lịch riêng, thiếu vòng nào là người
// chơi không biết giờ của vòng đó. Giờ tính tay từ 22h + 1h/5h/5h/1h và
// 10h + 2h/4h/5h/1h.
func TestRulesCardListsEveryRound(t *testing.T) {
	cfg := ww.Config{Schedule: &ww.Schedule{
		StartHour: 22, RoundHours: 12, Rounds: 2,
		Phases:      []int{60, 300, 300, 60},
		RoundPhases: [][]int{{60, 300, 300, 60}, {120, 240, 300, 60}},
	}}
	want := []string{
		"Một vòng |  | Mỗi ngày 2 vòng, mỗi vòng 12 tiếng, mở lúc 22h, 10h.",
		"Một vòng | 22h–4h\n10h–16h | Dùng kỹ năng",
		"Một vòng | 4h–9h\n16h–21h | Đề cử, tối đa 3 người lên giàn",
		"Một vòng | 9h–10h\n21h–22h | Biểu quyết Treo hay Tha",
		"Một vòng | 10h\n22h | Chốt phiếu và km",
	}
	if got := cardLines(cfg)[:len(want)]; !slices.Equal(got, want) {
		t.Fatalf("thẻ luật:\n%q\nmuốn:\n%q", got, want)
	}
	if got := gameRulesCardFor(cfg)[1].Title; got != "Km" {
		t.Errorf("khối sau lịch vòng = %q, muốn Km", got)
	}
}

func TestRulesCardFollowsConfig(t *testing.T) {
	for _, c := range []struct {
		name    string
		cfg     ww.Config
		has     []string
		hasNot  []string
		noKmBox bool
	}{
		{name: "giới hạn người lên giàn", cfg: ww.Config{MaxHang: 1},
			has: []string{"Một vòng | 10h–20h | Đề cử, tối đa 1 người lên giàn"}},
		{name: "mỗi người một phiếu", cfg: ww.Config{Vote: ww.VoteFlat},
			has: []string{"Km | Km quyết định | Dùng kỹ năng", "Km | Phiếu | Phiếu nào cũng tính"}},
		{name: "top km 2 phiếu", cfg: ww.Config{Vote: ww.VoteTop, TopVoters: 2},
			has: []string{"Km | Km quyết định | Dùng kỹ năng", "Km | Phiếu | Không ai mất phiếu", "Km | 2 phiếu | 2 người chạy nhiều nhất, đủ 1 km"}},
		{name: "top km nhiều phiếu", cfg: ww.Config{Ruleset: ww.RulesetKm, Vote: ww.VoteCut, TopVoters: 2, TopWeight: 3},
			has: []string{"Km | Km quyết định | Dùng kỹ năng và bỏ phiếu", "Km | 3 phiếu | 2 người chạy nhiều nhất, đủ 1 km"}},
		{name: "top km theo số phiếu đặt riêng", cfg: ww.Config{Vote: ww.VoteTop, TopVoters: 2, TopWeight: 3},
			has: []string{"Km | 3 phiếu | 2 người chạy nhiều nhất, đủ 1 km"}, hasNot: []string{"Km | 2 phiếu | 2 người chạy nhiều nhất, đủ 1 km"}},
		{name: "mỗi người một phiếu thì không có nhóm nhiều phiếu", cfg: ww.Config{Vote: ww.VoteFlat, TopVoters: 2, TopWeight: 3},
			hasNot: []string{"Km | 3 phiếu | 2 người chạy nhiều nhất, đủ 1 km"}},
		{name: "luật km phân định bằng phiếu", cfg: ww.Config{Ruleset: ww.RulesetKm},
			has: []string{"Km | Bằng phiếu | Tổng km cao hơn thắng, rồi bốc thăm"}},
		{name: "tắt km", cfg: ww.Config{KmOff: true, Ruleset: ww.RulesetKm},
			has: []string{"Một vòng | 22h | Chốt phiếu"}, hasNot: []string{"Một vòng | 22h | Chốt phiếu và km"}, noKmBox: true},
		{name: "tắt Cupid", cfg: ww.Config{Disabled: []ww.Role{ww.Cupid}},
			hasNot: []string{"Thắng khi | Cặp đôi | Chỉ còn hai người họ"}},
		{name: "ba vòng có km", cfg: ww.Config{Schedule: &ww.Schedule{StartHour: 22, RoundHours: 8, Rounds: 3}},
			has: []string{
				"Một vòng |  | Mỗi ngày 3 vòng, mỗi vòng 8 tiếng, mở lúc 22h, 6h, 14h.",
				"Km | Tính km | 24 tiếng tới lúc chốt phiếu hoặc dùng kỹ năng",
			}},
		{name: "một vòng ngắn không km", cfg: ww.Config{KmOff: true, Schedule: &ww.Schedule{StartHour: 20, RoundHours: 2, Rounds: 1}},
			has: []string{"Một vòng |  | Mỗi ngày một vòng 2 tiếng, mở lúc 20h."}, noKmBox: true},
	} {
		t.Run(c.name, func(t *testing.T) {
			got := cardLines(c.cfg)
			for _, s := range c.has {
				if !slices.Contains(got, s) {
					t.Errorf("thiếu %q trong %q", s, got)
				}
			}
			for _, s := range c.hasNot {
				if slices.Contains(got, s) {
					t.Errorf("thừa %q trong %q", s, got)
				}
			}
			hasKm := slices.ContainsFunc(gameRulesCardFor(c.cfg), func(s GameSetupSection) bool { return s.Title == "Km" })
			if hasKm == c.noKmBox {
				t.Errorf("khối Km = %v", hasKm)
			}
		})
	}
}
