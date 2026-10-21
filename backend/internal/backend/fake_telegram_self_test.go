package backend

import (
	"context"
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
