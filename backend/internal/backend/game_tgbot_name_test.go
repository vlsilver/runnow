package backend

import (
	"testing"
	"time"
)

// Username gợi ý theo ngày tạo giờ VN: 18:00 UTC ngày 7 đã là ngày 8 ở VN.
func TestGameBotUsername(t *testing.T) {
	for at, want := range map[string]string{
		"2026-11-07T18:00:00Z": "quantro_3irun_08112026_bot",
		"2026-11-07T16:59:00Z": "quantro_3irun_07112026_bot",
	} {
		now, _ := time.Parse(time.RFC3339, at)
		if got := gameBotUsername(now); got != want {
			t.Errorf("%s: %q, muốn %q", at, got, want)
		}
	}
}
