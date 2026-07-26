package backend

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestTelegramActivityAlertSendsHTMLMessage(t *testing.T) {
	var capturedPath string
	var payload map[string]any
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path
		body, err := io.ReadAll(r.Body)
		if err != nil {
			t.Fatalf("read body: %v", err)
		}
		if err := json.Unmarshal(body, &payload); err != nil {
			t.Fatalf("unmarshal body: %v", err)
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer server.Close()

	service := NewTelegramService("token", "chat")
	service.apiBaseURL = server.URL
	fact := ActivityFact{
		StartedAt:           time.Date(2026, 7, 20, 6, 30, 0, 0, time.UTC),
		DistanceMeters:      5030,
		MovingTimeSeconds:   1812,
		ElevationGainMeters: 24,
	}
	if err := service.SendActivityAlert(context.Background(), "vlsilver", "Morning Run", fact, "https://example.test/activity", ""); err != nil {
		t.Fatalf("SendActivityAlert: %v", err)
	}

	if capturedPath != "/bottoken/sendMessage" {
		t.Fatalf("path = %s", capturedPath)
	}
	if payload["chat_id"] != "chat" {
		t.Fatalf("chat_id = %v", payload["chat_id"])
	}
	if payload["parse_mode"] != "HTML" {
		t.Fatalf("parse_mode = %v", payload["parse_mode"])
	}
	text, _ := payload["text"].(string)
	for _, want := range []string{"vlsilver", "Morning Run", "5.03 km", "30:12", "6:00 /km", "24 m"} {
		if !strings.Contains(text, want) {
			t.Fatalf("text missing %q:\n%s", want, text)
		}
	}
	// Lý do đổi từ ảnh PNG sang HTML: font bitmap của Go chỉ có ASCII nên
	// dấu tiếng Việt bị rụng hết. Giữ assert này để không quay lại vết cũ.
	if !strings.Contains(text, "hoàn thành") || !strings.Contains(text, "Quãng đường") {
		t.Fatalf("Vietnamese diacritics lost:\n%s", text)
	}
	markup, _ := json.Marshal(payload["reply_markup"])
	if !strings.Contains(string(markup), "https://example.test/activity") {
		t.Fatalf("reply_markup = %s", markup)
	}
	preview, _ := payload["link_preview_options"].(map[string]any)
	if preview["is_disabled"] != true {
		t.Fatalf("link preview not disabled: %v", payload["link_preview_options"])
	}
}

func TestTelegramMessageEscapesUserText(t *testing.T) {
	// Tên buổi chạy do user đặt và được nhúng thẳng vào HTML — không escape
	// thì một cái tên chứa thẻ sẽ làm Telegram từ chối cả tin nhắn.
	text := telegramActivityMessage("a<b>c", "<i>Run</i>", ActivityFact{DistanceMeters: 1000, MovingTimeSeconds: 300}, "ghê <b>vãi</b>")
	if strings.Contains(text, "<i>Run</i>") || !strings.Contains(text, "&lt;i&gt;Run&lt;/i&gt;") {
		t.Fatalf("activity name not escaped:\n%s", text)
	}
	if !strings.Contains(text, "a&lt;b&gt;c") {
		t.Fatalf("display name not escaped:\n%s", text)
	}
	// Câu bình luận do model sinh cũng nhúng vào HTML — phải escape.
	if strings.Contains(text, "<b>vãi</b>") || !strings.Contains(text, "ghê &lt;b&gt;vãi&lt;/b&gt;") {
		t.Fatalf("comment not escaped:\n%s", text)
	}
}

func TestTelegramMessageFallsBackWhenActivityNameEmpty(t *testing.T) {
	text := telegramActivityMessage("runner", "   ", ActivityFact{DistanceMeters: 1000, MovingTimeSeconds: 300}, "")
	if !strings.Contains(text, "Buổi chạy") {
		t.Fatalf("missing fallback name:\n%s", text)
	}
}

func TestActivityDetailURLPointsAtAppRoute(t *testing.T) {
	got := activityDetailURL("https://threei.run", "uid123", "987")
	if got != "https://threei.run/club/uid123/activity/987" {
		t.Fatalf("detail URL = %s", got)
	}
}

func TestTelegramActivityAlertSkipsWhenDisabled(t *testing.T) {
	service := NewTelegramService("", "")
	if err := service.SendActivityAlert(context.Background(), "runner", "Run", ActivityFact{}, "https://example.test", ""); err != nil {
		t.Fatalf("SendActivityAlert disabled = %v", err)
	}
}
