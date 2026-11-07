//go:build emulator

package backend

import (
	"strings"
	"testing"
)

// roomBotEnv là startEnv có bot của ván chạy bằng model giả.
func roomBotEnv(t *testing.T, reply func(system, input string) (string, error)) (*startEnv, *fakeLearn, *GameRoomBot) {
	t.Helper()
	e := newStartEnv(t)
	llm := &fakeLearn{reply: reply}
	bot := NewGameRoomBot(e.store, llm)
	e.bot = NewBotServer(Config{GameInboundQueue: "game-inbound"}, &Dependencies{Firestore: e.store.db, Games: e.store, TelegramLinks: e.deps.TelegramLinks, Telegram: e.tg.service("-100psc"), EnqueueTask: e.publish, RoomBot: bot})
	return e, llm, bot
}

func (e *startEnv) createBotGame(settings map[string]any) string {
	e.t.Helper()
	r := e.call("boss", "POST", "/v1/games", map[string]any{"roles": map[string]bool{"cupid": false}, "settings": settings}, "")
	e.want(r, 201, "")
	return r.body["id"].(string)
}

// Gọi tên bot trong phòng chung thì bot trả lời bằng tính cách chủ phòng đặt,
// nhớ được qua các lượt; ván có Telegram thì 3i đăng câu đó vào group, ghi tên
// bot ở đầu. Không gọi tên thì bot im.
func TestEmulatorRoomBotAnswersWhenCalled(t *testing.T) {
	e, llm, _ := roomBotEnv(t, func(_, input string) (string, error) {
		if strings.Contains(input, "nhớ mình không") {
			return `{"reply":"Nhớ chứ","memory":"u01 hỏi giờ chơi"}`, nil
		}
		return `{"reply":"Chào cả nhà, 22h chia bài nha","memory":"u01 hỏi giờ chơi"}`, nil
	})
	id := e.createBotGame(map[string]any{"botName": "Cú Đêm", "botPersona": "Hay đùa, nói giọng miền Tây"})
	e.register(id, 1, 3)
	path := "/v1/games/" + id + "/chats/room"

	e.want(e.call(userOf(2), "POST", path, map[string]any{"text": "chiều nay mưa"}, ""), 200, "")
	if n := len(e.tasksTo("/tasks/game-room-bot")); n != 0 {
		t.Fatalf("không gọi tên mà bot vẫn có %d task", n)
	}
	e.want(e.call(userOf(1), "POST", path, map[string]any{"text": "cú đêm ơi, tối nay mấy giờ?"}, ""), 200, "")
	tasks := e.tasksTo("/tasks/game-room-bot")
	if len(tasks) != 1 || tasks[0].Queue != QueueBotInbound {
		t.Fatalf("task bot = %+v", tasks)
	}
	for range 2 { // lần hai là Cloud Tasks gửi lại
		if rec := e.runTask(tasks[0]); rec.Code != 200 {
			t.Fatalf("game-room-bot: %d %s", rec.Code, rec.Body)
		}
	}
	if len(llm.calls) != 1 {
		t.Fatalf("model được gọi %d lần, muốn 1", len(llm.calls))
	}
	c := llm.calls[0]
	if !strings.Contains(c.system, "Cú Đêm") || !strings.Contains(c.system, "miền Tây") || !strings.Contains(c.input, "chiều nay mưa") || !strings.Contains(c.input, "cú đêm ơi, tối nay mấy giờ?") {
		t.Fatalf("prompt thiếu tính cách hay tin phòng:\n%s\n---\n%s", c.system, c.input)
	}

	r := e.call(userOf(2), "GET", path, nil, "")
	e.want(r, 200, "")
	msgs := chatMessages(t, r)
	if len(msgs) != 3 || msgs[0]["name"] != "Cú Đêm" || msgs[0]["text"] != "Chào cả nhà, 22h chia bài nha" || msgs[0]["bot"] != true || msgs[0]["system"] != false {
		t.Fatalf("phòng chung = %s", r.raw)
	}
	if hint, _ := r.body["hint"].(string); !strings.Contains(hint, "Cú Đêm") {
		t.Fatalf("hint = %v", r.body["hint"])
	}

	for _, task := range e.tasksTo("/tasks/game-flush") {
		if rec := e.runTask(task); rec.Code != 200 {
			t.Fatalf("game-flush: %d %s", rec.Code, rec.Body)
		}
	}
	var said int
	for _, call := range e.tg.Calls("sendMessage") {
		if text, _ := call.Params["text"].(string); strings.Contains(text, "<b>Cú Đêm</b>") && strings.Contains(text, "22h chia bài nha") {
			said++
		}
	}
	if said != 1 {
		t.Fatalf("3i đăng thay bot %d lần, muốn 1: %+v", said, e.tg.Calls("sendMessage"))
	}

	e.want(e.call(userOf(3), "POST", path, map[string]any{"text": "Cú Đêm nhớ mình không"}, ""), 200, "")
	tasks = e.tasksTo("/tasks/game-room-bot")
	if rec := e.runTask(tasks[len(tasks)-1]); rec.Code != 200 {
		t.Fatalf("game-room-bot: %d %s", rec.Code, rec.Body)
	}
	if len(llm.calls) != 2 || !strings.Contains(llm.calls[1].input, "u01 hỏi giờ chơi") {
		t.Fatalf("lượt sau không có ký ức của lượt trước: %+v", llm.calls)
	}
}

// Ván không Telegram: bot chỉ nói trong app, outbox không có tin của bot.
func TestEmulatorRoomBotWithoutTelegram(t *testing.T) {
	e, _, _ := roomBotEnv(t, func(_, _ string) (string, error) { return `{"reply":"Có mình đây","memory":""}`, nil })
	id := e.createBotGame(map[string]any{"botName": "Cú", "telegram": false})
	e.register(id, 1, 1)
	e.want(e.call(userOf(1), "POST", "/v1/games/"+id+"/chats/room", map[string]any{"text": "Cú ơi"}, ""), 200, "")
	if rec := e.runTask(e.tasksTo("/tasks/game-room-bot")[0]); rec.Code != 200 {
		t.Fatalf("game-room-bot: %d %s", rec.Code, rec.Body)
	}
	r := e.call(userOf(1), "GET", "/v1/games/"+id+"/chats/room", nil, "")
	if msgs := chatMessages(t, r); len(msgs) != 2 || msgs[0]["text"] != "Có mình đây" {
		t.Fatalf("phòng chung = %s", r.raw)
	}
	if n := len(e.tasksTo("/tasks/game-flush")); n != 0 {
		t.Fatalf("ván không Telegram vẫn bắn %d task gửi tin", n)
	}
}

// Hết lượt trong ngày thì bot không gọi model, nói một câu nghỉ một lần.
func TestEmulatorRoomBotDailyCap(t *testing.T) {
	e, llm, bot := roomBotEnv(t, func(_, _ string) (string, error) { return `{"reply":"Ừ","memory":""}`, nil })
	bot.dailyReplies = 1
	id := e.createBotGame(map[string]any{"botName": "Cú", "telegram": false})
	e.register(id, 1, 3)
	path := "/v1/games/" + id + "/chats/room"
	for i := 1; i <= 3; i++ {
		e.want(e.call(userOf(i), "POST", path, map[string]any{"text": "Cú ơi"}, ""), 200, "")
		tasks := e.tasksTo("/tasks/game-room-bot")
		if rec := e.runTask(tasks[len(tasks)-1]); rec.Code != 200 {
			t.Fatalf("game-room-bot: %d %s", rec.Code, rec.Body)
		}
	}
	if len(llm.calls) != 1 {
		t.Fatalf("model được gọi %d lần khi trần là 1", len(llm.calls))
	}
	var texts []string
	for _, m := range chatMessages(t, e.call(userOf(1), "GET", path, nil, "")) {
		if m["bot"] == true {
			texts = append(texts, m["text"].(string))
		}
	}
	if len(texts) != 2 || texts[0] != roomBotRestReply || texts[1] != "Ừ" {
		t.Fatalf("tin của bot = %q", texts)
	}
}

// Không đặt tên thì ván không có bot: gọi gì cũng không có task.
func TestEmulatorRoomBotOffWithoutName(t *testing.T) {
	e, _, _ := roomBotEnv(t, func(_, _ string) (string, error) { return "", nil })
	id := e.createBotGame(map[string]any{"botName": ""})
	e.register(id, 1, 1)
	e.want(e.call(userOf(1), "POST", "/v1/games/"+id+"/chats/room", map[string]any{"text": "Cú Đêm ơi"}, ""), 200, "")
	if n := len(e.tasksTo("/tasks/game-room-bot")); n != 0 {
		t.Fatalf("ván không có bot vẫn có %d task", n)
	}
}
