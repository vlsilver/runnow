package backend

import (
	"encoding/json"
	"testing"
)

// mention dựng update qua JSON thay vì gõ tay struct ẩn — thêm field vào
// TelegramUpdate sau này không làm vỡ test.
func mention(text string) TelegramUpdate {
	raw := `{"message":{"message_id":1,"text":` + mustJSON(text) +
		`,"chat":{"id":-100123,"type":"supergroup"},"from":{"id":5,"username":"tester"}}}`
	var u TelegramUpdate
	if err := json.Unmarshal([]byte(raw), &u); err != nil {
		panic(err)
	}
	return u
}

func mustJSON(s string) string {
	b, _ := json.Marshal(s)
	return string(b)
}

// mentionRaw cho phép test dựng update tuỳ ý (reply, private, text_mention).
func mentionRaw(t *testing.T, messageJSON string) TelegramUpdate {
	t.Helper()
	var u TelegramUpdate
	if err := json.Unmarshal([]byte(`{"message":`+messageJSON+`}`), &u); err != nil {
		t.Fatalf("dung update: %v", err)
	}
	return u
}

func TestBotAnswersWhenMentioned(t *testing.T) {
	chatID, q, ok := botQuestion(mention("@RunBot tuần này ai chạy nhiều nhất"), "RunBot")
	if !ok {
		t.Fatal("phải nhận là câu hỏi cho bot")
	}
	if chatID != "-100123" {
		t.Fatalf("chatID = %q", chatID)
	}
	if q != "tuần này ai chạy nhiều nhất" {
		t.Fatalf("question = %q — phải bỏ tên bot", q)
	}
}

func TestBotIgnoresGroupChatterWithoutMention(t *testing.T) {
	// Đây là ràng buộc quan trọng nhất: privacy mode đang bật nên Telegram
	// không đẩy tin thường về, nhưng nếu cấu hình BotFather bị đổi thì bot
	// sẽ nhận hết — lúc đó lớp lọc này là thứ duy nhất chặn nó trả lời mọi
	// câu trong group và đốt sạch quota.
	if _, _, ok := botQuestion(mention("mai ai chạy không anh em"), "RunBot"); ok {
		t.Fatal("không được trả lời tin nhắn không nhắc tới bot")
	}
}

func TestBotMentionIsCaseInsensitive(t *testing.T) {
	_, q, ok := botQuestion(mention("@runBOT top tháng này"), "RunBot")
	if !ok || q != "top tháng này" {
		t.Fatalf("ok=%v question=%q", ok, q)
	}
}

func TestBotIgnoresBareMention(t *testing.T) {
	if _, _, ok := botQuestion(mention("@RunBot"), "RunBot"); ok {
		t.Fatal("nhắc tên suông mà không hỏi gì thì bỏ qua")
	}
}

func TestBotAnswersEveryMessageInPrivateChat(t *testing.T) {
	u := mentionRaw(t, `{"text":"ai chạy nhiều nhất","chat":{"id":42,"type":"private"}}`)
	_, q, ok := botQuestion(u, "RunBot")
	if !ok || q != "ai chạy nhiều nhất" {
		t.Fatalf("ok=%v question=%q", ok, q)
	}
}

func TestBotAnswersReplyToItsOwnMessage(t *testing.T) {
	u := mentionRaw(t, `{"text":"thế còn tháng thì sao","chat":{"id":-100,"type":"group"},"reply_to_message":{"from":{"is_bot":true,"username":"RunBot"}}}`)
	if _, q, ok := botQuestion(u, "RunBot"); !ok || q != "thế còn tháng thì sao" {
		t.Fatalf("ok=%v question=%q", ok, q)
	}
}

func TestBotIgnoresReplyToAnotherPerson(t *testing.T) {
	u := mentionRaw(t, `{"text":"chuẩn luôn","chat":{"id":-100,"type":"group"},"reply_to_message":{"from":{"is_bot":false,"username":"someone"}}}`)
	if _, _, ok := botQuestion(u, "RunBot"); ok {
		t.Fatal("reply cho người khác không phải hỏi bot")
	}
}

func TestBotAnswersTextMention(t *testing.T) {
	// Telegram chèn tên hiển thị "3i" thay vì "@RunBot" và gắn username vào
	// entity.user — đây chính là ca làm bot im lặng trong group thật.
	u := mentionRaw(t, `{"text":"3i ai đứng nhất tuần này","chat":{"id":-100,"type":"group"},"entities":[{"type":"text_mention","offset":0,"length":2,"user":{"username":"RunBot","is_bot":true}}]}`)
	_, q, ok := botQuestion(u, "RunBot")
	if !ok {
		t.Fatal("phải nhận ra text_mention")
	}
	if q != "ai đứng nhất tuần này" {
		t.Fatalf("question = %q — phải bỏ tên bot", q)
	}
}

func TestSlowestPaceSortsLast(t *testing.T) {
	// Pace ngược chiều mọi tiêu chí khác: nhỏ hơn là nhanh hơn. Và người
	// chưa có pace (0) phải nằm cuối chứ không được coi như nhanh nhất.
	rows := []memberRow{
		{Name: "chua co pace", paceSeconds: 0},
		{Name: "cham", paceSeconds: 400},
		{Name: "nhanh", paceSeconds: 300},
	}
	if err := sortMembers(rows, "pace"); err != nil {
		t.Fatal(err)
	}
	got := []string{rows[0].Name, rows[1].Name, rows[2].Name}
	want := []string{"nhanh", "cham", "chua co pace"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("thu tu = %v, mong doi %v", got, want)
		}
	}
}

func TestSortByDistanceDescending(t *testing.T) {
	rows := []memberRow{{Name: "a", DistanceKm: 10}, {Name: "b", DistanceKm: 30}, {Name: "c", DistanceKm: 20}}
	if err := sortMembers(rows, "distance"); err != nil {
		t.Fatal(err)
	}
	if rows[0].Name != "b" || rows[2].Name != "a" {
		t.Fatalf("thu tu sai: %v", rows)
	}
}

func TestUnknownMetricRejected(t *testing.T) {
	if err := sortMembers(nil, "calories"); err == nil {
		t.Fatal("metric lạ phải báo lỗi để model biết mà sửa, không im lặng trả sai")
	}
}

func TestPeriodFieldMapping(t *testing.T) {
	for input, want := range map[string]string{
		"week": "currentWeek", "": "currentWeek",
		"month": "currentMonth", "rolling7": "rollingSevenDays",
	} {
		got, _, err := periodField(input)
		if err != nil || got != want {
			t.Fatalf("periodField(%q) = %q, %v", input, got, err)
		}
	}
	if _, _, err := periodField("year"); err == nil {
		t.Fatal("period không hỗ trợ phải báo lỗi")
	}
}

func TestHistoryReversedToChronological(t *testing.T) {
	// Firestore trả mới nhất trước; sau khi dựng phải là cũ→mới.
	newestFirst := []map[string]any{
		{"role": "model", "text": "đáp 2"},
		{"role": "user", "text": "hỏi 2", "name": "Linh"},
		{"role": "model", "text": "đáp 1"},
		{"role": "user", "text": "hỏi 1", "name": "Minh"},
	}
	c := buildHistoryContents(newestFirst)
	if len(c) != 4 {
		t.Fatalf("len = %d", len(c))
	}
	if c[0].Parts[0].Text != "Minh: hỏi 1" {
		t.Fatalf("đầu chuỗi = %q, phải là câu cũ nhất kèm tên", c[0].Parts[0].Text)
	}
	if c[3].Parts[0].Text != "đáp 2" {
		t.Fatalf("cuối chuỗi = %q, phải là câu mới nhất", c[3].Parts[0].Text)
	}
}

func TestHistoryTrimsLeadingModelTurn(t *testing.T) {
	// Cắt 50 tin có thể rơi vào giữa cặp, để lượt model lên đầu — Gemini từ
	// chối. Phải cắt bỏ tới khi mở đầu bằng user.
	newestFirst := []map[string]any{
		{"role": "user", "text": "hỏi mới", "name": "A"},
		{"role": "model", "text": "đáp mồ côi"}, // lượt model cụt ở đầu (sau khi đảo)
	}
	c := buildHistoryContents(newestFirst)
	if len(c) != 1 || c[0].Role != "user" {
		t.Fatalf("phải cắt lượt model mồ côi ở đầu, còn: %+v", c)
	}
}

func TestHistorySkipsEmptyAndBadRoles(t *testing.T) {
	rows := []map[string]any{
		{"role": "user", "text": "ok", "name": "A"},
		{"role": "system", "text": "nên bỏ"},
		{"role": "user", "text": ""},
	}
	c := buildHistoryContents(rows)
	if len(c) != 1 || c[0].Parts[0].Text != "A: ok" {
		t.Fatalf("chỉ giữ lượt hợp lệ, còn: %+v", c)
	}
}
