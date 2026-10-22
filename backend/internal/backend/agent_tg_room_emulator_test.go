//go:build emulator

package backend

import (
	"context"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

const tgRoomThread = 77

func topicMsg(updateID, from int64, thread int64, text string) map[string]any {
	msg := map[string]any{
		"message_id": updateID, "text": text,
		"chat": map[string]any{"id": mustInt(testPscChat), "type": "supergroup"},
		"from": map[string]any{"id": from, "is_bot": false, "first_name": "Ai đó"},
	}
	if thread != 0 {
		msg["message_thread_id"], msg["is_topic_message"] = thread, true
	}
	return map[string]any{"update_id": updateID, "message": msg}
}

func pscMemberUpd(updateID, botID int64, newStatus string) map[string]any {
	return map[string]any{"update_id": updateID, "my_chat_member": map[string]any{
		"chat":            map[string]any{"id": mustInt(testPscChat), "type": "supergroup", "title": "PSC"},
		"from":            map[string]any{"id": 5002, "is_bot": false, "first_name": "An"},
		"new_chat_member": map[string]any{"status": newStatus},
	}}
}

func (e *mybotEnv) roomMessages(room string) []map[string]any {
	e.t.Helper()
	docs, err := e.store.db.Collection("agentRooms").Doc(room).Collection("messages").OrderBy("seq", firestore.Asc).Documents(context.Background()).GetAll()
	if err != nil {
		e.t.Fatal(err)
	}
	var out []map[string]any
	for _, d := range docs {
		out = append(out, d.Data())
	}
	return out
}

// botMsgTask là task bot-message mới nhất (3i ghi hay trả lời tin group).
func (e *mybotEnv) botMsgTask() botMessageTask {
	e.t.Helper()
	tasks := e.tasksTo("/tasks/bot-message")
	if len(tasks) == 0 {
		e.t.Fatal("không có task bot-message")
	}
	return tasks[len(tasks)-1].Payload.(botMessageTask)
}

// Topic Phòng bot từ đầu tới cuối: admin đặt topic, bot con vào PSC, tin của
// người vào phòng tg-psc (không vào phòng main), bot vào PSC trả lời bằng chính
// bot con của nó trong đúng topic, 3i chỉ ghi chứ không trả lời. Telegram gửi
// lại update hay task chạy lại thì không ghi đôi, không gửi đôi.
func TestEmulatorTelegramRoomEndToEnd(t *testing.T) {
	e := newMybotEnv(t)
	cuongTok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	anTok := e.linkBot("an", "5002", 8002, "Sóc", 11)

	// Chưa đặt topic: tin trong topic là tin group thường của 3i.
	e.manager(topicMsg(100, 5002, tgRoomThread, "chào"))
	if len(e.roomMessages(agentTelegramRoom)) != 0 || e.botMsgTask().IsQuestion {
		t.Fatalf("chưa đặt topic mà vào phòng: %v", e.roomMessages(agentTelegramRoom))
	}

	// Chỉ admin đặt được; đặt trong General thì bị từ chối.
	if r := e.manager(topicMsg(101, 5001, tgRoomThread, "/phongbot")); r.body["text"] != "Lệnh này chỉ dành cho admin." {
		t.Fatalf("/phongbot của người thường: %s", r.raw)
	}
	if r := e.manager(topicMsg(102, 5002, 0, "/phongbot")); !strings.Contains(r.body["text"].(string), "không phải General") {
		t.Fatalf("/phongbot ở General: %s", r.raw)
	}
	if e.fsDoc("agentState/config")["tgRoomThreadId"] != nil {
		t.Fatal("lệnh bị từ chối mà vẫn đặt topic")
	}
	r := e.manager(topicMsg(103, 5002, tgRoomThread, "/phongbot@Run3IBot"))
	if !strings.HasPrefix(r.body["text"].(string), "Topic này giờ là Phòng bot") || r.body["message_thread_id"] != float64(tgRoomThread) {
		t.Fatalf("/phongbot của admin: %s", r.raw)
	}
	if got := e.fsDoc("agentState/config")["tgRoomThreadId"]; got != int64(tgRoomThread) {
		t.Fatalf("tgRoomThreadId = %v", got)
	}

	// Chỉ bot của Cường vào PSC; đổi username sau đó vẫn giữ là đang ở PSC.
	e.child(8001, pscMemberUpd(200, 8001, "member"))
	e.manager(managedUpd(12, 5001, 8001, "bot_cuong_moi"))
	e.drain()
	if tg := telegramOf(e.fsDoc("agents/cuong")); tg["inPsc"] != true || tg["username"] != "bot_cuong_moi" {
		t.Fatalf("agents/cuong.telegram = %v", tg)
	}
	me := e.call("cuong", "GET", "/v1/agents/me", nil, "")
	if tg, _ := me.body["telegram"].(map[string]any); tg["inPsc"] != true || tg["pscJoinUrl"] != "https://t.me/bot_cuong_moi?startgroup=psc" {
		t.Fatalf("me.telegram = %s", me.raw)
	}

	// An nhắn trong topic, có nhắc 3i: vào phòng tg-psc, 3i chỉ ghi.
	e.llm.script = append(e.llm.script, llmText("Chào An, chạy chưa?"))
	sent := len(e.tasks)
	if r := e.manager(topicMsg(300, 5002, tgRoomThread, "@Run3IBot chào cả nhà")); r.status != 200 || r.body != nil {
		t.Fatalf("tin trong topic: %d %s", r.status, r.raw)
	}
	if task := e.botMsgTask(); task.IsQuestion || task.RawText != "@Run3IBot chào cả nhà" || task.ThreadID != tgRoomThread {
		t.Fatalf("3i trả lời trong Phòng bot: %+v", task)
	}
	// Telegram gửi lại đúng update: vẫn một tin, task cùng TaskID.
	e.manager(topicMsg(300, 5002, tgRoomThread, "@Run3IBot chào cả nhà"))
	msgs := e.roomMessages(agentTelegramRoom)
	if len(msgs) != 1 || msgs[0]["uid"] != "an" || msgs[0]["channel"] != agentChannelTelegram {
		t.Fatalf("phòng tg-psc = %v", msgs)
	}
	turns := e.tasks[sent:]
	var turnIDs []string
	for _, p := range turns {
		if p.HandlerPath == "/tasks/agent-turn" {
			turnIDs = append(turnIDs, p.TaskID)
		}
	}
	if len(turnIDs) != 2 || turnIDs[0] != turnIDs[1] {
		t.Fatalf("task agent-turn sau update lặp = %v", turnIDs)
	}
	e.drain()

	// Chỉ Cú Mèo (đang ở PSC) nói, bằng bot con của Cường, đúng topic.
	sends := e.tg.CallsBy(cuongTok, "sendMessage")
	if len(sends) != 1 || sends[0].Params["chat_id"] != testPscChat || sends[0].Params["message_thread_id"] != float64(tgRoomThread) || sends[0].Params["text"] != "Chào An, chạy chưa?" {
		t.Fatalf("bot con của Cường gửi = %+v", sends)
	}
	if len(e.tg.CallsBy(anTok, "sendMessage")) != 0 || len(e.llm.calls) != 1 {
		t.Fatalf("bot chưa vào PSC vẫn nói: llm=%d calls=%+v", len(e.llm.calls), e.tg.Calls("sendMessage"))
	}
	if msgs := e.roomMessages(agentTelegramRoom); len(msgs) != 2 || msgs[1]["uid"] != "cuong" || msgs[1]["kind"] != agentKindAgent {
		t.Fatalf("phòng tg-psc sau lượt bot = %v", msgs)
	}
	// Task lượt đó chạy lại: không gửi thêm tin.
	e.mustRun("/tasks/agent-turn", agentTurnTask{RoomID: agentTelegramRoom, AfterSeq: 1})
	e.drain()
	if n := len(e.tg.CallsBy(cuongTok, "sendMessage")); n != 1 {
		t.Fatalf("chạy lại lượt gửi %d tin", n)
	}
	// Phòng main trong app không có gì.
	if room := e.call("an", "GET", "/v1/agents/room", nil, ""); len(messages(t, room)) != 0 {
		t.Fatalf("phòng main = %s", room.raw)
	}

	// Topic khác của PSC: 3i như cũ, câu hỏi vẫn là câu hỏi.
	e.manager(topicMsg(301, 5002, 5, "@Run3IBot mai mưa không"))
	if task := e.botMsgTask(); !task.IsQuestion || len(e.roomMessages(agentTelegramRoom)) != 2 {
		t.Fatalf("topic khác: %+v", task)
	}

	// Bot của Cường bị kick khỏi PSC: thôi nói ở topic.
	e.child(8001, pscMemberUpd(201, 8001, "kicked"))
	if tg := telegramOf(e.fsDoc("agents/cuong")); tg["inPsc"] != false {
		t.Fatalf("sau kick: %v", tg)
	}
	e.tick(time.Minute)
	e.manager(topicMsg(302, 5002, tgRoomThread, "còn ai không"))
	e.drain()
	if len(e.llm.calls) != 1 || len(e.tg.Calls("sendMessage")) != 1 {
		t.Fatalf("bot đã rời PSC vẫn nói: llm=%d", len(e.llm.calls))
	}

	// Admin tắt Phòng bot: topic thành topic thường.
	e.manager(topicMsg(303, 5002, tgRoomThread, "/phongbot tat"))
	if e.fsDoc("agentState/config")["tgRoomThreadId"] != nil {
		t.Fatal("/phongbot tat không tắt")
	}
}

// Phòng bot đang bật thì lúc bot con nối xong, 3i gửi chủ link đưa bot vào PSC
// ngay trong DM. Phòng tắt, update gửi lại, hay bot đã ở PSC thì không mời.
func TestEmulatorTelegramRoomInvitesNewBot(t *testing.T) {
	e := newMybotEnv(t)
	e.linkBot("an", "5002", 8002, "Sóc", 10) // phòng tắt: linkExisting đòi body rỗng
	if me := e.call("an", "GET", "/v1/agents/me", nil, ""); strings.Contains(string(me.raw), "pscJoinUrl") {
		t.Fatalf("phòng tắt mà app có link vào PSC: %s", me.raw)
	}
	ctx := context.Background()
	if _, err := e.store.db.Doc("agentState/config").Set(ctx, map[string]any{"tgRoomThreadId": tgRoomThread}, firestore.MergeAll); err != nil {
		t.Fatal(err)
	}

	e.createBot("cuong", "Cú Mèo", "")
	linkUser(t, e.apiHarness, "cuong", "5001", true)
	e.tg.addManaged(8001)
	invite := func(id int64, bot int64, username string) apiResp {
		t.Helper()
		r := e.manager(managedUpd(id, 5001, bot, username))
		e.drain()
		return r
	}
	r := invite(20, 8001, "bot_cuong")
	if r.body["text"] != managedPscInvite+"https://t.me/bot_cuong?startgroup=psc" || r.body["chat_id"] != float64(5001) || r.body["method"] != "sendMessage" {
		t.Fatalf("lời mời: %s", r.raw)
	}
	if r := invite(20, 8001, "bot_cuong"); r.body != nil {
		t.Fatalf("update gửi lại vẫn mời: %s", r.raw)
	}
	// Đã ở PSC thì đổi username không mời nữa.
	e.child(8001, pscMemberUpd(30, 8001, "member"))
	if r := invite(21, 8001, "bot_cuong_moi"); r.body != nil {
		t.Fatalf("bot đã ở PSC vẫn mời: %s", r.raw)
	}
	// Chủ thay bot khác: bot mới chưa ở PSC nên mời lại.
	e.tg.addManaged(8003)
	if r := invite(22, 8003, "bot_cuong_hai"); r.body["text"] != managedPscInvite+"https://t.me/bot_cuong_hai?startgroup=psc" {
		t.Fatalf("bot mới không được mời: %s", r.raw)
	}
}

// Người chưa đủ điều kiện nhắn trong topic: tin không vào phòng, 3i nhắc một
// lần mỗi ngày (reply đúng tin, đúng topic), hôm sau nhắc lại.
func TestEmulatorTelegramRoomHintsOncePerDay(t *testing.T) {
	e := newMybotEnv(t)
	seed(t, e.store.db, "agentState/config", map[string]any{"memberUids": []any{"cuong"}, "tgRoomThreadId": tgRoomThread})
	linkUser(t, e.apiHarness, "dung", "5004", true) // liên kết nhưng ngoài allowlist

	cases := []struct {
		from int64
		hint string
	}{{5999, tgRoomNoLinkHint}, {5004, tgRoomDisabledHint}}
	for i, c := range cases {
		id := int64(400 + 10*i)
		r := e.manager(topicMsg(id, c.from, tgRoomThread, "alo"))
		if r.body["text"] != c.hint || r.body["message_thread_id"] != float64(tgRoomThread) {
			t.Fatalf("lần đầu của %d: %s", c.from, r.raw)
		}
		if rp, _ := r.body["reply_parameters"].(map[string]any); rp["message_id"] != float64(id) {
			t.Fatalf("nhắc không reply đúng tin: %s", r.raw)
		}
		e.tick(time.Minute)
		if r := e.manager(topicMsg(id+1, c.from, tgRoomThread, "alo nữa")); r.body != nil {
			t.Fatalf("nhắc lần hai trong ngày: %s", r.raw)
		}
	}
	if len(e.roomMessages(agentTelegramRoom)) != 0 || len(e.tasksTo("/tasks/agent-turn")) != 0 {
		t.Fatalf("tin của người chưa đủ điều kiện vào phòng: %v", e.roomMessages(agentTelegramRoom))
	}
	e.tick(24 * time.Hour)
	if r := e.manager(topicMsg(450, 5999, tgRoomThread, "alo")); r.body["text"] != tgRoomNoLinkHint {
		t.Fatalf("hôm sau không nhắc lại: %s", r.raw)
	}
}
