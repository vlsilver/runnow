package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// webhookCall chạy một update qua serveTelegramUpdate với publisher giả, trả
// status, body và các task đã enqueue.
func webhookCall(t *testing.T, cfg Config, raw string, publish taskPublishFunc) (int, map[string]any, []PublishTask) {
	t.Helper()
	var got []PublishTask
	if publish == nil {
		publish = func(_ context.Context, p PublishTask) (string, error) {
			got = append(got, p)
			return "created", nil
		}
	}
	s := &Server{config: cfg}
	rec := httptest.NewRecorder()
	s.serveTelegramUpdate(context.Background(), rec, []byte(raw), publish)
	var body map[string]any
	if rec.Body.Len() > 0 {
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Fatalf("body không phải JSON: %q", rec.Body.String())
		}
	}
	return rec.Code, body, got
}

var testBotCfg = Config{TelegramBotUsername: "Run3IBot", GameInboundQueue: "game-inbound"}

const groupMention = `{"update_id":10,"message":{"message_id":1,"text":"@Run3IBot hi","chat":{"id":-100,"type":"supergroup"},"from":{"id":5,"first_name":"A"}}}`

// Lỗi tạm thời của Cloud Tasks (đã retry trong Publish mà vẫn hỏng) thì trả 5xx
// để Telegram gửi lại; TaskID theo update_id nên lần gửi lại không tạo trùng.
func TestWebhookTransientEnqueueErrorReturns5xx(t *testing.T) {
	code, _, _ := webhookCall(t, testBotCfg, groupMention, func(context.Context, PublishTask) (string, error) {
		return "", status.Error(codes.Unavailable, "tasks down")
	})
	if code < 500 {
		t.Fatalf("status = %d, mong đợi 5xx", code)
	}
}

// Lỗi cấu hình (queue không có, thiếu quyền) thì gửi lại cũng hỏng y vậy: trả
// 200 để Telegram không gửi lại mãi, kẹt cả các update sau.
func TestWebhookPermanentEnqueueErrorReturns200(t *testing.T) {
	code, _, _ := webhookCall(t, testBotCfg, groupMention, func(context.Context, PublishTask) (string, error) {
		return "", status.Error(codes.NotFound, "queue not found")
	})
	if code != 200 {
		t.Fatalf("status = %d, mong đợi 200", code)
	}
}

func TestWebhookPanicReturns200(t *testing.T) {
	code, _, _ := webhookCall(t, testBotCfg, groupMention, func(context.Context, PublishTask) (string, error) {
		panic("bug")
	})
	if code != 200 {
		t.Fatalf("status = %d, mong đợi 200", code)
	}
}

func TestWebhookCallbackAnsweredInlineWithoutEnqueue(t *testing.T) {
	code, body, tasks := webhookCall(t, testBotCfg, `{"update_id":11,"callback_query":{"id":"cq-1","from":{"id":5},"data":"x"}}`, nil)
	if code != 200 || body["method"] != "answerCallbackQuery" || body["callback_query_id"] != "cq-1" || body["text"] == "" {
		t.Fatalf("code=%d body=%v", code, body)
	}
	if len(tasks) != 0 {
		t.Fatalf("bấm nút không được enqueue sang LLM: %v", tasks)
	}
}

func TestWebhookCommandsAnsweredInlineWithoutLLM(t *testing.T) {
	cases := []struct{ name, raw string }{
		{"/vai trong DM", `{"update_id":12,"message":{"message_id":1,"text":"/vai","chat":{"id":42,"type":"private"},"from":{"id":42}}}`},
		{"/vai@bot trong group", `{"update_id":13,"message":{"message_id":1,"text":"/vai@run3ibot","chat":{"id":-100,"type":"supergroup"},"from":{"id":5}}}`},
		{"/start kèm mã", `{"update_id":14,"message":{"message_id":1,"text":"/start abc123","chat":{"id":42,"type":"private"},"from":{"id":42}}}`},
	}
	for _, c := range cases {
		code, body, tasks := webhookCall(t, testBotCfg, c.raw, nil)
		if code != 200 || body["method"] != "sendMessage" || body["text"] == "" {
			t.Fatalf("%s: code=%d body=%v", c.name, code, body)
		}
		if len(tasks) != 0 {
			t.Fatalf("%s: không được enqueue: %v", c.name, tasks)
		}
	}
}

// /vai gõ trong topic thì câu trả lời cố định cũng phải vào đúng topic.
func TestWebhookCommandReplyStaysInTopic(t *testing.T) {
	_, body, _ := webhookCall(t, testBotCfg, `{"update_id":15,"message":{"message_id":9,"message_thread_id":7,"is_topic_message":true,"text":"/vai","chat":{"id":-100,"type":"supergroup"},"from":{"id":5}}}`, nil)
	if body["message_thread_id"] != float64(7) {
		t.Fatalf("thiếu thread: %v", body)
	}
}

// Những lệnh không phải của mình hoặc không có mã thì đi đường cũ, sang LLM.
func TestWebhookOtherCommandsKeepOldPath(t *testing.T) {
	cases := []string{
		`{"update_id":16,"message":{"message_id":1,"text":"/start","chat":{"id":42,"type":"private"},"from":{"id":42}}}`,
		`{"update_id":17,"message":{"message_id":1,"text":"/vai@BotKhac","chat":{"id":-100,"type":"supergroup"},"from":{"id":5}}}`,
		groupMention,
	}
	for _, raw := range cases {
		code, body, tasks := webhookCall(t, testBotCfg, raw, nil)
		if code != 200 || body != nil {
			t.Fatalf("%s: code=%d body=%v", raw, code, body)
		}
		if len(tasks) != 1 || tasks[0].Queue != QueueBotInbound || tasks[0].HandlerPath != "/tasks/bot-message" {
			t.Fatalf("%s: phải enqueue bot-message như cũ, được %v", raw, tasks)
		}
	}
}

func TestWebhookMembershipGoesToGameInbound(t *testing.T) {
	raws := []string{
		`{"update_id":20,"chat_member":{"chat":{"id":-100},"new_chat_member":{"status":"left"}}}`,
		`{"update_id":21,"chat_join_request":{"chat":{"id":-100},"from":{"id":5}}}`,
		`{"update_id":22,"message":{"message_id":3,"chat":{"id":-100,"type":"supergroup"},"from":{"id":5},"left_chat_member":{"id":5}}}`,
		`{"update_id":23,"message":{"message_id":1,"chat":{"id":-5,"type":"group"},"from":{"id":5},"migrate_to_chat_id":-1009}}`,
	}
	for _, raw := range raws {
		_, _, tasks := webhookCall(t, testBotCfg, raw, nil)
		if len(tasks) != 1 || tasks[0].Queue != QueueGameInbound || tasks[0].HandlerPath != "/tasks/game-update" {
			t.Fatalf("%s: được %v", raw, tasks)
		}
		p := tasks[0].Payload.(gameUpdateTask)
		if string(p.Raw) != raw {
			t.Fatalf("payload phải là nguyên update: %s", p.Raw)
		}
	}
	// Chưa cấu hình queue (trước I2) thì bỏ qua, không enqueue vào queue rỗng.
	_, _, tasks := webhookCall(t, Config{TelegramBotUsername: "Run3IBot"}, raws[0], nil)
	if len(tasks) != 0 {
		t.Fatalf("chưa có GAME_INBOUND_QUEUE mà vẫn enqueue: %v", tasks)
	}
}

func TestChatMemberInChat(t *testing.T) {
	cases := map[TelegramChatMember]bool{
		{Status: "creator"}:                     true,
		{Status: "administrator"}:               true,
		{Status: "member"}:                      true,
		{Status: "restricted", IsMember: true}:  true,
		{Status: "restricted", IsMember: false}: false,
		{Status: "left"}:                        false,
		{Status: "kicked"}:                      false,
		{Status: "lạ", IsMember: true}:          false,
	}
	for m, want := range cases {
		if got := m.InChat(); got != want {
			t.Errorf("%+v: InChat=%v, mong đợi %v", m, got, want)
		}
	}
}

func TestMembershipUserIDs(t *testing.T) {
	cases := []struct {
		raw  string
		want []int64
	}{
		{`{"update_id":1,"chat_member":{"chat":{"id":-100},"from":{"id":1},"new_chat_member":{"status":"left","user":{"id":5}}}}`, []int64{5}},
		{`{"update_id":2,"message":{"chat":{"id":42,"type":"private"},"from":{"id":42},"text":"/start abc"}}`, []int64{42}},
		// Tin dịch vụ trong group: lấy người vào/rời, không lấy người thêm (from).
		{`{"update_id":3,"message":{"chat":{"id":-100,"type":"supergroup"},"from":{"id":1},"new_chat_members":[{"id":5},{"id":5},{"id":6,"is_bot":true}]}}`, []int64{5}},
		{`{"update_id":4,"my_chat_member":{"chat":{"id":-100},"new_chat_member":{"status":"administrator","user":{"id":9,"is_bot":true}}}}`, nil},
	}
	for _, c := range cases {
		if got := membershipUserIDs([]byte(c.raw)); fmt.Sprint(got) != fmt.Sprint(c.want) {
			t.Errorf("%s: được %v, mong đợi %v", c.raw, got, c.want)
		}
	}
}
