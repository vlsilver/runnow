package backend

import (
	"testing"
	"time"
)

func TestLiveCardStatus(t *testing.T) {
	now := time.Date(2026, 11, 1, 6, 0, 0, 0, vietnam)
	cases := []struct {
		name    string
		card    map[string]any
		session map[string]any
		want    string
	}{
		{"chưa có buổi live", map[string]any{}, nil, "🟢 Đang chạy"},
		{"đang chạy, vừa cập nhật", map[string]any{}, map[string]any{"status": "running", "updatedAt": now.Add(-2 * time.Minute)}, "🟢 Đang chạy"},
		{"đang chạy, quá 3 phút không cập nhật", map[string]any{}, map[string]any{"status": "running", "updatedAt": now.Add(-4 * time.Minute)}, "⚪ Mất tín hiệu"},
		{"tạm dừng", map[string]any{}, map[string]any{"status": "paused", "updatedAt": now.Add(-10 * time.Minute)}, "⏸ Tạm dừng"},
		{"app đã dừng live", map[string]any{}, map[string]any{"status": "finished"}, "⚪ Đã dừng live"},
		{"đã về đích", map[string]any{"finished": true}, map[string]any{"status": "paused"}, "🏁 Về đích"},
	}
	for _, c := range cases {
		if got := liveCardStatus(c.card, c.session, now); got != c.want {
			t.Errorf("%s: %q, muốn %q", c.name, got, c.want)
		}
	}
}

func TestParseLiveCheer(t *testing.T) {
	id, emoji, ok := parseLiveCheer("l1|runnow-1785619792289|4")
	if !ok || id != "runnow-1785619792289" || emoji != "🏁" {
		t.Fatalf("parse = %q %q %v", id, emoji, ok)
	}
	for _, data := range []string{"l1|runnow-1|5", "l1|runnow-1|-1", "l1|run/now|0", "l2|runnow-1|0", "m1|g|v", "l1|runnow-1"} {
		if _, _, ok := parseLiveCheer(data); ok {
			t.Errorf("%q phải bị từ chối", data)
		}
	}
	if len(liveCheerData("runnow-1785619792289", 4)) > 64 {
		t.Fatal("callback_data quá 64 byte")
	}
}
