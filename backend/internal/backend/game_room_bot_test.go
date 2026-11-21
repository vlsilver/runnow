package backend

import (
	"strings"
	"testing"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

func TestMentionsName(t *testing.T) {
	for _, c := range []struct {
		text, name string
		want       bool
	}{
		{"cú đêm ơi, mấy giờ?", "Cú Đêm", true},
		{"Hỏi CÚ ĐÊM đi", "Cú Đêm", true},
		{"@Cú", "Cú", true},
		{"cú lừa", "Cú", true},
		{"cúđêm", "Cú", false},
		{"cúc áo", "Cú", false},
		{"bé bi", "Bi", true},
		{"bibi", "Bi", false},
		{"bi", "", false},
		{"quan tro oi, may gio chot?", "Quản trò", true},
		{"Hoi QUAN TRO di", "Quản trò", true},
		{"hoi cu dem di", "Cú Đêm", true},
		{"quản trọ ở đâu", "Quản trò", false},
		{"củ khoai", "Cú", false},
		{"quan troi oi", "Quản trò", false},
	} {
		if got := mentionsName(c.text, c.name); got != c.want {
			t.Errorf("mentionsName(%q, %q) = %v, muốn %v", c.text, c.name, got, c.want)
		}
	}
}

func TestRoomBotSettings(t *testing.T) {
	var c werewolf.Config
	if err := applyGameSettings(&c, map[string]any{}); err != nil || c.BotName != "Quản trò" || !strings.HasPrefix(c.BotPersona, "Bạn là quản trò vui tính") {
		t.Fatalf("mặc định: %q %q %v", c.BotName, c.BotPersona, err)
	}
	if err := applyGameSettings(&c, map[string]any{"botPersona": "  hay cà khịa "}); err != nil || c.BotPersona != "hay cà khịa" {
		t.Fatalf("tính cách: %q %v", c.BotPersona, err)
	}
	// App cũ còn gửi tên bot, kể cả rỗng để tắt bot: nhận nhưng ván vẫn có
	// Quản trò.
	for _, name := range []string{"  Bi  ", ""} {
		c = werewolf.Config{}
		if err := applyGameSettings(&c, map[string]any{"botName": name}); err != nil || c.BotName != "Quản trò" {
			t.Fatalf("app cũ gửi botName %q: %q %v", name, c.BotName, err)
		}
	}
	for _, bad := range []map[string]any{
		{"botName": strings.Repeat("a", 31)},
		{"botName": "Cú\nĐêm"},
		{"botName": 3.0},
		{"botPersona": strings.Repeat("ạ", 501)},
	} {
		if err := applyGameSettings(&c, bad); err == nil {
			t.Errorf("%v được nhận", bad)
		}
	}
}

// Màn tạo ván không còn ô tên bot; ô tính cách có các bản soạn sẵn vừa giới
// hạn, bản đầu là mặc định.
func TestRoomBotCreateOptions(t *testing.T) {
	var persona *GameSetting
	for _, s := range gameCreateSettings() {
		if s.Key == "botName" {
			t.Fatal("botName còn trên màn tạo ván")
		}
		if s.Key == "botPersona" {
			persona = &s
		}
	}
	if persona == nil || len(persona.Presets) != 6 {
		t.Fatalf("botPersona = %+v", persona)
	}
	if persona.Default != persona.Presets[0].Text || persona.Presets[0].Label != "Hài hước" {
		t.Fatalf("mặc định = %q", persona.Default)
	}
	for _, p := range persona.Presets {
		if n := len([]rune(p.Text)); n == 0 || n > roomBotPersonaMax {
			t.Errorf("%s: %d ký tự", p.Label, n)
		}
	}
	// Thiết lập của ván hiện tên tính cách thay vì cả lời dặn.
	got := setupLines(gameSetupFor(werewolf.Config{KmPerUnit: 2, BotName: "Quản trò", BotPersona: persona.Presets[1].Text}))
	if !strings.Contains(got, "= Tổng tài bá đạo") || strings.Contains(got, "lạnh lùng") {
		t.Fatalf("thiết lập:\n%s", got)
	}
}

// Quản trò đọc luật đúng cấu hình của ván: giờ, số người lên giàn, cách đếm
// phiếu, vai có trong ván và thiết lập km.
func TestRoomBotRulesFollowConfig(t *testing.T) {
	cfg := werewolf.Config{Ruleset: werewolf.RulesetKm, MaxHang: 1, Disabled: []werewolf.Role{werewolf.Cupid}, Extended: []werewolf.Role{werewolf.Elder},
		SkillKm: map[werewolf.Role]float64{werewolf.Seer: 3}}
	got := roomBotRules(cfg)
	for _, s := range []string{
		"10h bản tin đêm, đề cử tới 20h; tối đa 1 người nhiều đề cử nhất lên giàn",
		"Người lên giàn không bỏ phiếu ở phiên của mình",
		"- Tiên tri: Mỗi đêm soi một người",
		"Cần 3 km",
		"- Già làng: Phe Dân. Chịu được một lần bị sói cắn",
		"Treo tối đa mỗi vòng: 1 người",
	} {
		if !strings.Contains(got, s) {
			t.Errorf("thiếu %q trong:\n%s", s, got)
		}
	}
	for _, s := range []string{"- Cupid:", "- Kẻ ngốc:"} {
		if strings.Contains(got, s) {
			t.Errorf("vai không có trong ván vẫn nói %q:\n%s", s, got)
		}
	}
	if got != roomBotRules(cfg) {
		t.Error("luật đổi thứ tự giữa hai lần dựng")
	}
}
