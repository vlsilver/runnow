package backend

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestModelTextHTML(t *testing.T) {
	cases := []struct{ in, html, plain string }{
		{
			"*   **NVL** hôm qua **8.3 km**, hôm nay **2.2 km**.",
			"• <b>NVL</b> hôm qua <b>8.3 km</b>, hôm nay <b>2.2 km</b>.",
			"• NVL hôm qua 8.3 km, hôm nay 2.2 km.",
		},
		{
			"**Gợi ý suy luận:** Sói <ăn chay> & Dân",
			"<b>Gợi ý suy luận:</b> Sói &lt;ăn chay&gt; &amp; Dân",
			"Gợi ý suy luận: Sói <ăn chay> & Dân",
		},
		{"## Kết quả **đêm qua**", "<b>Kết quả đêm qua</b>", "Kết quả đêm qua"},
		{"  - con", "  • con", "  • con"},
		{"tên nhat_2sg và 5*2 giữ nguyên", "tên nhat_2sg và 5*2 giữ nguyên", "tên nhat_2sg và 5*2 giữ nguyên"},
		{"chạy *nhẹ* thôi", "chạy <i>nhẹ</i> thôi", "chạy nhẹ thôi"},
		{"gõ `**/vai**` nhé", "gõ <code>**/vai**</code> nhé", "gõ **/vai** nhé"},
		{"xem [app](https://threei.run/a?b=1&c=2)", `xem <a href="https://threei.run/a?b=1&amp;c=2">app</a>`, "xem app (https://threei.run/a?b=1&c=2)"},
		{"---", "", ""},
		{"```\na<b\n```", "<pre>\na&lt;b\n</pre>", "a<b"},
		{"**chưa đóng", "**chưa đóng", "**chưa đóng"},
	}
	for _, c := range cases {
		if got := modelTextHTML(c.in); got != c.html {
			t.Errorf("html(%q)\n got %q\nwant %q", c.in, got, c.html)
		}
		if got := modelTextPlain(c.in); got != c.plain {
			t.Errorf("plain(%q)\n got %q\nwant %q", c.in, got, c.plain)
		}
	}
}

// parseCheckTelegram: Telegram giả, [reject] thì từ chối mọi tin parse_mode
// HTML như lỗi "can't parse entities"; ghi lại body từng lần gửi.
func parseCheckTelegram(t *testing.T, reject bool) (*TelegramService, *[]map[string]any) {
	t.Helper()
	var got []map[string]any
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		got = append(got, body)
		if reject && body["parse_mode"] == "HTML" {
			w.WriteHeader(http.StatusBadRequest)
			_, _ = w.Write([]byte(`{"ok":false,"error_code":400,"description":"Bad Request: can't parse entities: unclosed tag"}`))
			return
		}
		_, _ = w.Write([]byte(`{"ok":true,"result":{"message_id":7}}`))
	}))
	t.Cleanup(srv.Close)
	tg := NewTelegramService("tok", "-100")
	tg.apiBaseURL = srv.URL
	return tg, &got
}

func TestChatMessageSendsModelMarkdownAsHTML(t *testing.T) {
	tg, got := parseCheckTelegram(t, false)
	if err := tg.SendChatMessageInThread(context.Background(), "-100", 5, "*   **Đình** chạy **8.9 km**"); err != nil {
		t.Fatal(err)
	}
	if len(*got) != 1 || (*got)[0]["text"] != "• <b>Đình</b> chạy <b>8.9 km</b>" || (*got)[0]["parse_mode"] != "HTML" {
		t.Fatalf("gửi %v", *got)
	}
}

func TestModelTextFallsBackToPlainWhenTelegramRejectsHTML(t *testing.T) {
	tg, got := parseCheckTelegram(t, true)
	if err := tg.SendChatMessage(context.Background(), "-100", "**Đình** 8.9 km"); err != nil {
		t.Fatal(err)
	}
	id, err := sendModelText(context.Background(), tg, TelegramText{ChatID: "-100", Text: "**Đình** 8.9 km"})
	if err != nil || id != 7 {
		t.Fatalf("id %d err %v", id, err)
	}
	if len(*got) != 4 {
		t.Fatalf("mỗi tin phải gửi hai lần, được %d", len(*got))
	}
	for _, i := range []int{1, 3} {
		if b := (*got)[i]; b["text"] != "Đình 8.9 km" || b["parse_mode"] != nil {
			t.Fatalf("lần gửi lại %d: %v", i, b)
		}
	}
}
