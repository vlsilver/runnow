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
	} {
		if got := mentionsName(c.text, c.name); got != c.want {
			t.Errorf("mentionsName(%q, %q) = %v, muốn %v", c.text, c.name, got, c.want)
		}
	}
}

func TestRoomBotSettings(t *testing.T) {
	var c werewolf.Config
	if err := applyGameSettings(&c, map[string]any{}); err != nil || c.BotName != "Cú Đêm" || c.BotPersona != "" {
		t.Fatalf("mặc định: %q %q %v", c.BotName, c.BotPersona, err)
	}
	if err := applyGameSettings(&c, map[string]any{"botName": "  Bi  ", "botPersona": "hay cà khịa"}); err != nil || c.BotName != "Bi" || c.BotPersona != "hay cà khịa" {
		t.Fatalf("đặt tên: %q %q %v", c.BotName, c.BotPersona, err)
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
