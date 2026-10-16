package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

func TestClassifySend(t *testing.T) {
	api := func(status int, desc string) error {
		return &TelegramAPIError{Method: "sendMessage", Status: status, Code: status, Description: desc}
	}
	cases := []struct {
		name string
		err  error
		want sendOutcome
	}{
		{"ok", nil, outcomeSent},
		{"not modified", api(400, "Bad Request: message is not modified: specified new message content"), outcomeSent},
		{"400", api(400, "Bad Request: can't parse entities"), outcomeFailed},
		{"403", api(403, "Forbidden: bot was blocked by the user"), outcomeFailed},
		{"migrate", &TelegramAPIError{Status: 400, Code: 400, MigrateTo: -1009}, outcomeFailed},
		{"429", &TelegramAPIError{Status: 429, Code: 429, RetryAfter: 5}, outcomeLater},
		{"502", api(502, "Bad Gateway"), outcomeRetry},
		{"401", api(401, "Unauthorized"), outcomeRetry},
		{"mạng", fmt.Errorf("gửi: %w", context.DeadlineExceeded), outcomeRetry},
		{"bọc", fmt.Errorf("x: %w", api(403, "Forbidden")), outcomeFailed},
	}
	for _, c := range cases {
		if got := classifySend(c.err); got != c.want {
			t.Errorf("%s: %v, mong đợi %v", c.name, got, c.want)
		}
	}
}

func TestSplitTelegramText(t *testing.T) {
	if got := splitTelegramText("a\nb", 3); len(got) != 1 || got[0] != "a\nb" {
		t.Fatalf("vừa giới hạn mà vẫn tách: %q", got)
	}
	if got := splitTelegramText("aa\nbb\ncc", 5); strings.Join(got, "|") != "aa\nbb|cc" {
		t.Fatalf("tách theo dòng: %q", got)
	}
	// Dòng dài quá giới hạn thì cắt cứng; "ạ" là 1 đơn vị UTF-16, emoji là 2.
	if got := splitTelegramText("ạạạạạ", 2); strings.Join(got, "|") != "ạạ|ạạ|ạ" {
		t.Fatalf("cắt cứng: %q", got)
	}
	if got := splitTelegramText("🙂🙂🙂", 4); strings.Join(got, "|") != "🙂🙂|🙂" {
		t.Fatalf("UTF-16: %q", got)
	}
	// 100 dòng 99 ký tự: mỗi phần chứa được 40 dòng (40*99+39 = 3999), dòng thứ
	// 41 làm vượt 4096, nên ra 40 + 40 + 20.
	long := strings.Repeat(strings.Repeat("x", 99)+"\n", 100)
	parts := splitTelegramText(long, telegramTextLimit)
	if len(parts) != 3 || strings.Join(parts, "\n") != long {
		t.Fatalf("parts = %d", len(parts))
	}
	for _, p := range parts {
		if utf16Len(p) > telegramTextLimit {
			t.Fatalf("phần dài %d", utf16Len(p))
		}
	}
}

// Dòng gửi bù "<i>Gửi bù tin lúc 22:00 12/10</i>" dài 33 đơn vị UTF-16, cộng
// một dấu xuống dòng: phần đầu dài 4062 thì vừa khít 4096, dài 4063 thì dòng
// gửi bù thành phần riêng.
func TestWithLateLabel(t *testing.T) {
	at := time.Date(2026, 10, 12, 15, 0, 0, 0, time.UTC)
	label := "<i>Gửi bù tin lúc 22:00 12/10</i>"
	fit := strings.Repeat("x", 4062)
	if got := withLateLabel([]string{fit, "b"}, at); len(got) != 2 || got[0] != label+"\n"+fit || got[1] != "b" {
		t.Fatalf("vừa khít: %d phần", len(got))
	}
	over := fit + "x"
	if got := withLateLabel([]string{over}, at); len(got) != 2 || got[0] != label || got[1] != over {
		t.Fatalf("quá giới hạn: %d phần", len(got))
	}
}

func testRenderer() *outboxRenderer {
	players := []gamePlayerInfo{
		{uid: "w1", name: "An <Sói>", data: map[string]any{"tgUserId": "71"}},
		{uid: "w2", name: "Bình & Co", data: map[string]any{"tgUserId": int64(72)}},
		{uid: "s1", name: "Chi", data: map[string]any{"tgUserId": "73"}},
		{uid: "f1", name: "Giả", fake: true, data: map[string]any{}},
	}
	return &outboxRenderer{chatID: "-100g", threadID: 5, cfg: ww.Config{KmPerUnit: 2.5}, players: players, byUID: playerIndex(players)}
}

func renderOne(t *testing.T, r *outboxRenderer, key, tpl string, data any) outboxText {
	t.Helper()
	raw, err := json.Marshal(data)
	if err != nil {
		t.Fatal(err)
	}
	out, err := r.render(key, tpl, string(raw))
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func TestRenderStartAndCard(t *testing.T) {
	r := testRenderer()
	nightAt := time.Date(2026, 10, 15, 15, 0, 0, 0, time.UTC) // 22:00 giờ Việt Nam
	out := renderOne(t, r, chatGroup, tplStart, map[string]any{"nightAt": nightAt.Format(time.RFC3339), "players": 4})
	want := "<b>Ma Sói bắt đầu</b>\n4 người chơi: An &lt;Sói&gt;, Bình &amp; Co, Chi, Giả.\nĐêm 1 bắt đầu lúc 22:00 15/10. Bot đã nhắn riêng lá bài cho từng người."
	if out.chatID != "-100g" || out.threadID != 5 || len(out.parts) != 1 || out.parts[0] != want {
		t.Fatalf("start = %+v", out)
	}

	out = renderOne(t, r, dmChat("w1"), tplCard, map[string]any{"role": "wolf", "wolves": []string{"w1", "w2"}})
	want = "Lá bài của bạn trong ván Ma Sói:\n<b>Sói</b>\n" +
		"Đêm nào cả phe cũng chọn một người để cắn, từ 22h tới 0h. Lựa chọn bấm sau cùng của phe được tính. Tổng km của sói còn sống phải đủ 2.5 km cho mỗi sói.\n" +
		"Đồng đội: Bình &amp; Co."
	if out.chatID != "71" || out.threadID != 0 || out.parts[0] != want || out.markup != nil {
		t.Fatalf("card sói = %+v", out)
	}
	r.gameID = "g1"
	out = renderOne(t, r, dmChat("w1"), tplCard, map[string]any{"role": "wolf"})
	kb, _ := json.Marshal(out.markup)
	if string(kb) != `{"inline_keyboard":[[{"callback_data":"m1|g1|v","text":"Xem lại lá bài"}]]}` {
		t.Fatalf("nút lá bài = %s", kb)
	}
	r.gameID = ""
	out = renderOne(t, r, dmChat("w2"), tplCard, map[string]any{"role": "seer"})
	if out.chatID != "72" || strings.Contains(out.parts[0], "Đồng đội") || !strings.HasSuffix(out.parts[0], "Cần đủ 2.5 km.") {
		t.Fatalf("card tiên tri = %+v", out)
	}
	if out := renderOne(t, r, dmChat("f1"), tplCard, map[string]any{"role": "villager"}); out.skip != "no_telegram" {
		t.Fatalf("người giả = %+v", out)
	}
	if _, err := r.render(dmChat("s1"), tplCard, `{"role":"king"}`); err == nil {
		t.Fatal("vai lạ mà không lỗi")
	}
}

func TestRenderDigest(t *testing.T) {
	r := testRenderer()
	deadline := time.Date(2026, 10, 16, 10, 0, 0, 0, time.UTC) // 17:00 giờ Việt Nam
	out := renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/dawn", "round": 1, "phase": "day", "deadline": deadline.Format(time.RFC3339),
		"events": []ww.Event{{Kind: ww.EventDeath, UID: "w2", Role: ww.Wolf}},
	})
	want := "<b>Bản tin đêm 1</b>\nBình &amp; Co đã chết. Lá bài: Sói.\n\nTiếp theo: Ngày 1, đề cử, tới 17:00 16/10."
	if len(out.parts) != 1 || out.parts[0] != want {
		t.Fatalf("digest = %q", out.parts)
	}

	out = renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r2/trial", "round": 2, "phase": "ended",
		"events": []ww.Event{{Kind: ww.EventWinner, Team: ww.TeamVillage}},
		"roles":  map[string]string{"w1": "wolf", "w2": "wolf", "s1": "seer"},
	})
	want = "<b>Biểu quyết ngày 2</b>\nPhe Dân thắng.\n\nLá bài:\nAn &lt;Sói&gt;: Sói\nBình &amp; Co: Sói\nChi: Tiên tri"
	if out.parts[0] != want {
		t.Fatalf("digest kết thúc = %q", out.parts)
	}

	// Bước không có gì công khai (feed cũng bỏ) thì không gửi.
	if out := renderOne(t, r, chatGroup, tplDigest, map[string]any{"phaseKey": "r1/night", "round": 1, "phase": "dawn"}); out.skip != "empty" {
		t.Fatalf("digest rỗng = %+v", out)
	}
}

func TestRenderPrivatePromptAdminReminder(t *testing.T) {
	r := testRenderer()
	out := renderOne(t, r, dmChat("w1"), tplPrivate, map[string]any{"events": []ww.Event{
		{Kind: ww.EventVoid, UID: "w1", Action: ww.KindWolfBite, Reason: ww.VoidNoKm},
		{Kind: ww.EventWolvesTarget, UID: "s1"},
		{Kind: ww.EventLovers, UID: "w2", Role: ww.Wolf, Draw: true},
		{Kind: ww.EventDeath, UID: "w1", Cause: ww.CauseLover},
	}})
	want := "<b>Ma Sói: tin riêng</b>\nLựa chọn Cắn của bạn không được tính: chưa đủ km.\nPhe Sói chốt cắn Chi.\n" +
		"Cupid không ghép nên bot ghép thay. Bạn được ghép đôi với Bình &amp; Co, lá bài Sói. Một người chết thì người kia chết theo.\n" +
		"Bạn đã chết, chết theo người yêu."
	if out.parts[0] != want {
		t.Fatalf("private = %q", out.parts[0])
	}
	out = renderOne(t, r, dmChat("w1"), tplPrivate, map[string]any{"events": []ww.Event{{Kind: ww.EventWolvesTarget, Reason: ww.VoidNoKm}}})
	if out.parts[0] != "<b>Ma Sói: tin riêng</b>\nPhe Sói chưa đủ km nên đêm nay không cắn được ai." {
		t.Fatalf("private không cắn = %q", out.parts[0])
	}

	resumeAt := time.Date(2026, 10, 16, 3, 30, 0, 0, time.UTC)
	out = renderOne(t, r, chatGroup, tplAdmin, map[string]any{"action": "resume", "deadline": resumeAt.Format(time.RFC3339)})
	if out.parts[0] != "<b>Ván chạy tiếp</b>\nHạn kế tiếp: 10:30 16/10." {
		t.Fatalf("resume = %q", out.parts[0])
	}
	out = renderOne(t, r, chatGroup, tplAdmin, map[string]any{"action": "extend", "minutes": 30, "deadline": resumeAt.Format(time.RFC3339)})
	if out.parts[0] != "<b>Dời hạn</b>\nAdmin dời hạn lượt này thêm 30 phút. Hạn mới: 10:30 16/10." {
		t.Fatalf("extend = %q", out.parts[0])
	}
	out = renderOne(t, r, chatGroup, tplReminder, map[string]any{"reason": "vote"})
	if !strings.HasPrefix(out.parts[0], "<b>Nhắc biểu quyết</b>") {
		t.Fatalf("reminder = %q", out.parts[0])
	}

	if out := renderOne(t, r, chatGroup, tplTally, map[string]any{"kind": "vote"}); out.skip != "not_implemented" {
		t.Fatalf("tally = %+v", out)
	}
	for _, c := range [][2]string{{"nope", `{}`}, {tplAdmin, `{"action":"x"}`}, {tplReminder, `{"reason":"x"}`}, {tplStart, `{`}} {
		if _, err := r.render(chatGroup, c[0], c[1]); err == nil {
			t.Fatalf("%s %s: không lỗi", c[0], c[1])
		}
	}
	if _, err := (&outboxRenderer{}).render(chatGroup, tplAdmin, `{"action":"pause"}`); err == nil {
		t.Fatal("ván không có chatId mà không lỗi")
	}
}

// Lựa chọn của từng sói đi vào group Phe Sói (C2), không bao giờ vào group
// chung; chat key lạ thì lỗi chứ không rơi về group chung.
func TestRenderWolfPick(t *testing.T) {
	r := testRenderer()
	if out := renderOne(t, r, chatWolves, tplWolfPick, map[string]any{"uid": "w1", "target": "s1"}); out.skip != "no_chat" {
		t.Fatalf("chưa có group Phe Sói = %+v", out)
	}
	r.gameData = map[string]any{"wolfChatId": "-100w"}
	out := renderOne(t, r, chatWolves, tplWolfPick, map[string]any{"uid": "w1", "target": "s1"})
	if out.chatID != "-100w" || out.threadID != 0 || len(out.parts) != 1 || out.parts[0] != "<b>An &lt;Sói&gt;</b> chọn cắn <b>Chi</b>." {
		t.Fatalf("chọn cắn = %+v", out)
	}
	out = renderOne(t, r, chatWolves, tplWolfPick, map[string]any{"uid": "w2", "cleared": true})
	if out.parts[0] != "<b>Bình &amp; Co</b> bỏ chọn cắn." {
		t.Fatalf("bỏ chọn = %q", out.parts[0])
	}
	if _, err := r.render("lovers", tplAdmin, `{"action":"pause"}`); err == nil {
		t.Fatal("chat key lạ mà không lỗi")
	}
}

func TestTelegramSendTextAndErrors(t *testing.T) {
	tg := newFakeTelegram(t)
	s := tg.service("-1")
	id, err := s.SendText(context.Background(), TelegramText{ChatID: "-5", ThreadID: 9, Text: "<b>x</b>", HTML: true, Markup: map[string]any{"inline_keyboard": []any{}}})
	if err != nil || id != 1 {
		t.Fatalf("id = %d, err = %v", id, err)
	}
	p := tg.Calls("sendMessage")[0].Params
	if p["chat_id"] != "-5" || p["message_thread_id"] != float64(9) || p["parse_mode"] != "HTML" || p["reply_markup"] == nil {
		t.Fatalf("params = %v", p)
	}
	if _, err := s.SendText(context.Background(), TelegramText{ChatID: "-5", Text: "x"}); err != nil {
		t.Fatal(err)
	}
	if p := tg.Calls("sendMessage")[1].Params; p["parse_mode"] != nil || p["message_thread_id"] != nil || p["reply_markup"] != nil {
		t.Fatalf("params thừa: %v", p)
	}

	tg.Then("sendMessage", tgTooManyRequests(12), tgMigrated(-1009), tgReply{http.StatusBadGateway, "<html>bad gateway</html>"})
	var te *TelegramAPIError
	if _, err := s.SendText(context.Background(), TelegramText{ChatID: "-5", Text: "x"}); !errors.As(err, &te) || te.Status != 429 || te.RetryAfter != 12 {
		t.Fatalf("429: %v", err)
	}
	if _, err := s.SendText(context.Background(), TelegramText{ChatID: "-5", Text: "x"}); !errors.As(err, &te) || te.MigrateTo != -1009 || te.Status != 400 {
		t.Fatalf("migrate: %v", err)
	}
	if _, err := s.SendText(context.Background(), TelegramText{ChatID: "-5", Text: "x"}); !errors.As(err, &te) || te.Status != 502 || !strings.Contains(te.Description, "bad gateway") {
		t.Fatalf("502: %v", err)
	}

	tg.Then("editMessageText", tgBadRequest("Bad Request: message is not modified"))
	err = s.EditText(context.Background(), "-5", 7, "y", true, nil)
	if !errors.As(err, &te) || te.Status != 400 || classifySend(err) != outcomeSent {
		t.Fatalf("edit: %v", err)
	}
	if p := tg.Calls("editMessageText")[0].Params; p["message_id"] != float64(7) || p["parse_mode"] != "HTML" {
		t.Fatalf("edit params = %v", p)
	}
	if err := s.EditText(context.Background(), "-5", 7, "z", false, nil); err != nil {
		t.Fatal(err)
	}
}

// Lỗi mạng không được lộ token (TelegramService.do).
func TestTelegramSendTextRedactsToken(t *testing.T) {
	s := NewTelegramService("secret-token-123", "-1")
	s.apiBaseURL = "http://127.0.0.1:1"
	_, err := s.SendText(context.Background(), TelegramText{ChatID: "-5", Text: "x"})
	if err == nil || strings.Contains(err.Error(), "secret-token-123") || classifySend(err) != outcomeRetry {
		t.Fatalf("err = %v", err)
	}
}
