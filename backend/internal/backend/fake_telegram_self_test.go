package backend

import (
	"context"
	"errors"
	"strings"
	"testing"
)

// Fake phải trả lỗi theo kịch bản rồi quay về ok, và ghi đủ tham số của cả
// JSON lẫn multipart, không thì test của T6/W2 dựa trên nó sẽ xanh sai.
func TestFakeTelegramScriptsErrorsThenRecordsEveryCall(t *testing.T) {
	tg := newFakeTelegram(t)
	tg.Then("sendMessage", tgTooManyRequests(7), tgForbidden("Forbidden: bot was blocked by the user"))
	svc := tg.service("-100")
	ctx := context.Background()

	for _, want := range []string{"status=429", "status=403", ""} {
		err := svc.SendChatMessageInThread(ctx, "-100", 42, "chào")
		if want == "" && err != nil || want != "" && (err == nil || !strings.Contains(err.Error(), want)) {
			t.Fatalf("lỗi = %v, mong đợi %q", err, want)
		}
	}
	if err := svc.SendPhotoInThread(ctx, "-100", 42, []byte("png"), "ảnh"); err != nil {
		t.Fatal(err)
	}

	msgs := tg.Calls("sendMessage")
	if len(msgs) != 3 || msgs[2].Params["text"] != "chào" || msgs[2].Params["message_thread_id"] != float64(42) {
		t.Fatalf("sendMessage = %+v", msgs)
	}
	photo := tg.Calls("sendPhoto")
	if len(photo) != 1 || photo[0].Params["message_thread_id"] != "42" || photo[0].Params["caption"] != "ảnh" || !strings.HasPrefix(photo[0].Params["photo"].(string), "file:") {
		t.Fatalf("sendPhoto = %+v", photo)
	}
	if len(tg.Calls("")) != 4 {
		t.Fatalf("tổng số call = %d", len(tg.Calls("")))
	}
}

func TestFakeTelegramRejectsWrongToken(t *testing.T) {
	tg := newFakeTelegram(t)
	svc := NewTelegramService("token-khac", "-100")
	svc.apiBaseURL = tg.URL
	if err := svc.SendChatMessage(context.Background(), "-100", "x"); err == nil || !strings.Contains(err.Error(), "status=404") {
		t.Fatalf("lỗi = %v", err)
	}
	if n := len(tg.Calls("")); n != 0 {
		t.Fatalf("call sai token vẫn được ghi: %d", n)
	}
}

// withToken phải gọi bằng token của bot con, không phải token gốc; token đã bị
// thay thì fake trả 401 như Telegram, để test bỏ cache token bắt được.
func TestTelegramWithTokenCallsAsChildBot(t *testing.T) {
	tg := newFakeTelegram(t)
	old := tg.addManaged(77)
	child := tg.service("").withToken(old)
	ctx := context.Background()
	if _, err := child.SendText(ctx, TelegramText{ChatID: "5", Text: "chào"}); err != nil {
		t.Fatal(err)
	}
	if got := tg.CallsBy(old, "sendMessage"); len(got) != 1 || got[0].Params["chat_id"] != "5" {
		t.Fatalf("call của bot con = %+v", tg.Calls(""))
	}
	if n := len(tg.CallsBy(fakeTelegramToken, "")); n != 0 {
		t.Fatalf("token gốc bị dùng %d lần", n)
	}
	tg.addManaged(77)
	_, err := child.SendText(ctx, TelegramText{ChatID: "5", Text: "chào"})
	var te *TelegramAPIError
	if !errors.As(err, &te) || te.Status != 401 {
		t.Fatalf("token cũ: lỗi = %v", err)
	}
}
