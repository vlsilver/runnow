//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"errors"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// sentReply là một lần bot gọi hàm gửi câu trả lời ra kênh ngoài app.
type sentReply struct {
	uid, channel string
	reply        AgentMessage
}

// channelEnv thêm vào agentEnv lối vào của kênh Telegram (PostChannelDM,
// PostRoomMessage trên api) và hàm gửi câu trả lời giả.
type channelEnv struct {
	*agentEnv
	api     *Server
	sent    []sentReply
	sendErr error
}

func newChannelEnv(t *testing.T) *channelEnv {
	t.Helper()
	c := &channelEnv{agentEnv: newAgentEnv(t)}
	c.api = &Server{config: c.cfg, deps: c.deps}
	c.brain.SetChannelReply(func(_ context.Context, uid, channel string, reply AgentMessage) error {
		c.sent = append(c.sent, sentReply{uid: uid, channel: channel, reply: reply})
		return c.sendErr
	})
	return c
}

// tgDM là tin chủ nhắn bot trên Telegram, trả seq trong tgdm.
func (c *channelEnv) tgDM(uid, text string) int64 {
	c.t.Helper()
	msg, err := c.api.PostChannelDM(context.Background(), uid, agentChannelTelegram, text)
	if err != nil {
		c.t.Fatalf("PostChannelDM %s: %v", uid, err)
	}
	return msg.Seq
}

// inPsc gắn bot con đang ở PSC cho uid: ở tg-psc chỉ những bot này được nói
// (telegramRoomAgents).
func (c *channelEnv) inPsc(uid, botID string) {
	c.t.Helper()
	tg := map[string]any{"botId": botID, "username": "bot_" + uid, "inPsc": true}
	if _, err := c.store.db.Doc("agents/"+uid).Update(context.Background(), []firestore.Update{{Path: "telegram", Value: tg}}); err != nil {
		c.t.Fatal(err)
	}
}

func (c *channelEnv) lastTask(path string) PublishTask {
	c.t.Helper()
	tasks := c.tasksTo(path)
	if len(tasks) == 0 {
		c.t.Fatalf("không có task %s", path)
	}
	return tasks[len(tasks)-1]
}

func (c *channelEnv) col(path string) []map[string]any {
	c.t.Helper()
	docs, err := c.store.db.Collection(path).OrderBy("seq", firestore.Asc).Documents(context.Background()).GetAll()
	if err != nil {
		c.t.Fatal(err)
	}
	out := make([]map[string]any, len(docs))
	for i, d := range docs {
		out[i] = d.Data()
	}
	return out
}

// sameReply so hai lần gửi; giờ so bằng Equal vì đọc lại từ Firestore thì
// time.Time mang múi giờ khác.
func sameReply(a, b sentReply) bool {
	return a.uid == b.uid && a.channel == b.channel && a.reply.Seq == b.reply.Seq && a.reply.Role == b.reply.Role && a.reply.Text == b.reply.Text && a.reply.At.Equal(b.reply.At)
}

func contentTexts(call fakeCall) []string {
	var out []string
	for _, c := range call.contents {
		out = append(out, c.Parts[0].Text)
	}
	return out
}

// App và Telegram là hai cuộc chat riêng của cùng một bot: seq, lịch sử gửi
// model và tin hiện ra tách riêng; bộ nhớ chủ dạy thì dùng chung, kể cả mục
// thêm từ tin cùng seq ở hai kênh.
func TestEmulatorAgentTelegramDMChannel(t *testing.T) {
	c := newChannelEnv(t)
	c.createBot("an", "Sóc", "Lắm mồm")

	// App: tin 1, bot nhớ "trail".
	c.want(c.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "Mình mê trail"}, ""), 200, "")
	appTask := c.lastTask("/tasks/agent-dm")
	c.llm.script = []*genai.GenerateContentResponse{llmCall("remember", map[string]any{"text": "Chủ mê trail"}), llmText("ok app")}
	c.mustRun("/tasks/agent-dm", appTask.Payload)

	// Telegram: seq riêng bắt đầu từ 1, task khác ID với tin 1 của app.
	c.tick(time.Second)
	if seq := c.tgDM("an", "vl giày gì êm"); seq != 1 {
		t.Fatalf("seq Telegram phải tính riêng từ 1, được %d", seq)
	}
	tgTask := c.lastTask("/tasks/agent-dm")
	if p := tgTask.Payload.(agentDMTask); p.Channel != agentChannelTelegram || p.Seq != 1 || tgTask.TaskID == appTask.TaskID {
		t.Fatalf("task Telegram: %+v id %s, app id %s", p, tgTask.TaskID, appTask.TaskID)
	}
	c.llm.script = []*genai.GenerateContentResponse{llmCall("remember", map[string]any{"text": "Chủ đi giày Pegasus"}), llmText("Pegasus nhé")}
	c.mustRun("/tasks/agent-dm", tgTask.Payload)
	tgCall := c.llm.calls[2]
	if got := contentTexts(tgCall); len(got) != 1 || got[0] != "** giày gì êm" {
		t.Fatalf("Telegram chỉ được gửi lịch sử của chính nó, đã che từ tục: %q", got)
	}
	if !strings.Contains(tgCall.system, "Chủ mê trail") {
		t.Fatal("bot trên Telegram không biết điều chủ dạy trong app")
	}
	if len(c.sent) != 1 || !sameReply(c.sent[0], sentReply{uid: "an", channel: agentChannelTelegram, reply: AgentMessage{Seq: 2, Role: agentRoleAgent, Text: "Pegasus nhé", At: c.clock}}) {
		t.Fatalf("hàm gửi Telegram: %+v", c.sent)
	}
	tg := c.col("agents/an/tgdm")
	if len(tg) != 2 || tg[0]["channel"] != agentChannelTelegram || tg[1]["channel"] != agentChannelTelegram || tg[1]["text"] != "Pegasus nhé" {
		t.Fatalf("tgdm: %v", tg)
	}

	// Mục nhớ từ tin 1 của hai kênh không ghi đè nhau.
	mems, err := c.deps.Agents.Memories(context.Background(), "an")
	if err != nil {
		t.Fatal(err)
	}
	if len(mems) != 2 || mems[0].ID != "dm1-1" || mems[0].Text != "Chủ mê trail" || mems[1].ID != "tg1-1" || mems[1].Text != "Chủ đi giày Pegasus" {
		t.Fatalf("bộ nhớ sau khi dạy ở hai kênh: %+v", mems)
	}

	// App không thấy tin Telegram, và bot trong app biết điều dạy qua Telegram.
	r := c.call("an", "GET", "/v1/agents/me/dm", nil, "")
	if msgs := messages(t, r); len(msgs) != 2 || msgs[0]["text"] != "ok app" || msgs[1]["text"] != "Mình mê trail" || r.body["waiting"] != false {
		t.Fatalf("GET dm của app lẫn tin Telegram: %s", r.raw)
	}
	c.tick(time.Second)
	c.want(c.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "Mai chạy đâu"}, ""), 200, "")
	c.llm.script = []*genai.GenerateContentResponse{llmText("Đi trail")}
	c.mustRun("/tasks/agent-dm", c.lastTask("/tasks/agent-dm").Payload)
	appCall := c.llm.calls[len(c.llm.calls)-1]
	if got := contentTexts(appCall); strings.Join(got, "|") != "Mình mê trail|ok app|Mai chạy đâu" {
		t.Fatalf("app chỉ được gửi lịch sử app: %q", got)
	}
	if !strings.Contains(appCall.system, "Chủ đi giày Pegasus") {
		t.Fatal("bot trong app không biết điều chủ dạy qua Telegram")
	}
	if len(c.sent) != 1 {
		t.Fatalf("câu trả lời trong app không được đi qua hàm gửi Telegram: %+v", c.sent)
	}

	// Task Telegram chạy lại: không gọi model, không ghi thêm, gửi lại đúng câu cũ.
	calls := len(c.llm.calls)
	c.mustRun("/tasks/agent-dm", tgTask.Payload)
	if len(c.llm.calls) != calls || len(c.col("agents/an/tgdm")) != 2 || len(c.sent) != 2 || !sameReply(c.sent[1], c.sent[0]) {
		t.Fatalf("chạy lại task Telegram: calls %d→%d, sent %+v", calls, len(c.llm.calls), c.sent)
	}

	// Gửi lỗi sau khi đã ghi: task 5xx, chạy lại thì gửi đúng câu đó, không gọi model.
	c.tick(time.Second)
	seq := c.tgDM("an", "còn đó không")
	c.sendErr = errors.New("telegram 502")
	c.llm.script = []*genai.GenerateContentResponse{llmText("còn")}
	if code := c.runTask("/tasks/agent-dm", c.lastTask("/tasks/agent-dm").Payload); code < 500 {
		t.Fatalf("gửi Telegram lỗi mà task trả %d", code)
	}
	c.sendErr = nil
	calls = len(c.llm.calls)
	c.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: seq, Channel: agentChannelTelegram})
	if last := c.sent[len(c.sent)-1]; len(c.llm.calls) != calls || last.reply.Seq != seq+1 || last.reply.Text != "còn" {
		t.Fatalf("gửi lại sau lỗi: calls %d→%d, %+v", calls, len(c.llm.calls), last)
	}

	// Chưa gắn hàm gửi thì kênh Telegram chỉ ghi Firestore.
	c.brain.SetChannelReply(nil)
	c.tick(time.Second)
	seq = c.tgDM("an", "ê")
	c.llm.script = []*genai.GenerateContentResponse{llmText("ơi")}
	c.mustRun("/tasks/agent-dm", c.lastTask("/tasks/agent-dm").Payload)
	if tg = c.col("agents/an/tgdm"); tg[len(tg)-1]["text"] != "ơi" || int64(number(c.doc("agents/an")["tgAnsweredSeq"])) != seq {
		t.Fatalf("không có hàm gửi: %v", tg[len(tg)-1])
	}
}

// Trần câu trả lời mỗi ngày đếm chung cho app và Telegram.
func TestEmulatorAgentDMDailyCapShared(t *testing.T) {
	c := newChannelEnv(t)
	c.createBot("an", "Sóc", "")
	if _, err := c.store.db.Doc("agents/an").Update(context.Background(), []firestore.Update{{Path: "dmDay", Value: vnDay(c.clock)}, {Path: "dmDayCount", Value: agentDMBaseDaily - 1}}); err != nil {
		t.Fatal(err)
	}
	c.tgDM("an", "câu cuối hôm nay")
	c.llm.script = []*genai.GenerateContentResponse{llmText("ok")}
	c.mustRun("/tasks/agent-dm", c.lastTask("/tasks/agent-dm").Payload)
	if got := int64(number(c.doc("agents/an")["dmDayCount"])); got != agentDMBaseDaily {
		t.Fatalf("Telegram phải đếm vào trần chung: dmDayCount %d", got)
	}

	c.tick(time.Second)
	c.want(c.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "còn nói được không"}, ""), 200, "")
	calls := len(c.llm.calls)
	c.mustRun("/tasks/agent-dm", c.lastTask("/tasks/agent-dm").Payload)
	if msgs := messages(t, c.call("an", "GET", "/v1/agents/me/dm", nil, "")); len(c.llm.calls) != calls || msgs[0]["text"] != noRunDMLimitReply {
		t.Fatalf("app phải hết trần sau khi Telegram dùng câu cuối: %v", msgs[0])
	}

	// Ngược lại, hết trần thì Telegram cũng nhận câu nghỉ và câu đó vẫn được gửi.
	c.tick(time.Second)
	c.tgDM("an", "thế còn đây")
	c.mustRun("/tasks/agent-dm", c.lastTask("/tasks/agent-dm").Payload)
	if last := c.sent[len(c.sent)-1]; len(c.llm.calls) != calls || last.reply.Text != noRunDMLimitReply {
		t.Fatalf("Telegram khi hết trần: %+v", last)
	}
}

// Kênh Telegram qua cùng cổng với app: chưa đồng ý AI thì không ghi gì.
func TestEmulatorAgentTelegramDMConsent(t *testing.T) {
	c := newChannelEnv(t)
	c.createBot("an", "Sóc", "")
	c.setOpen(true)
	seed(t, c.store.db, "agents/dung", map[string]any{"name": "Dê", "inRoom": true})
	_, err := c.api.PostChannelDM(context.Background(), "dung", agentChannelTelegram, "chào")
	if !errors.Is(err, errAgentConsentRequired) {
		t.Fatalf("chưa đồng ý mà PostChannelDM trả %v", err)
	}
	if len(c.col("agents/dung/tgdm")) != 0 || len(c.tasksTo("/tasks/agent-dm")) != 0 {
		t.Fatal("chưa đồng ý mà vẫn ghi tin hoặc hẹn task")
	}
}

// Task agent-dm không có channel (bản trước enqueue) chạy như kênh app; payload
// kênh app không mang field channel để bot bản trước còn giải mã được.
func TestEmulatorAgentDMTaskWithoutChannel(t *testing.T) {
	c := newChannelEnv(t)
	c.createBot("an", "Sóc", "")
	c.want(c.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 200, "")
	raw, err := json.Marshal(c.lastTask("/tasks/agent-dm").Payload)
	if err != nil {
		t.Fatal(err)
	}
	if string(raw) != `{"uid":"an","seq":1}` {
		t.Fatalf("payload kênh app đổi dạng: %s", raw)
	}
	c.llm.script = []*genai.GenerateContentResponse{llmText("chào chủ")}
	c.mustRun("/tasks/agent-dm", map[string]any{"uid": "an", "seq": 1})
	if msgs := messages(t, c.call("an", "GET", "/v1/agents/me/dm", nil, "")); len(msgs) != 2 || msgs[0]["text"] != "chào chủ" || len(c.sent) != 0 {
		t.Fatalf("task không có channel: %v, sent %+v", msgs, c.sent)
	}
	if code := c.runTask("/tasks/agent-dm", map[string]any{"uid": "an", "seq": 1, "channel": "zalo"}); code != 204 {
		t.Fatalf("kênh lạ: %d", code)
	}
}

// Phòng tg-psc chạy độc lập với phòng main: seq, chuỗi bot, trần ngày và đoạn
// chat gửi model đều riêng. Task không có roomID là phòng main.
func TestEmulatorAgentTelegramRoom(t *testing.T) {
	c := newChannelEnv(t)
	c.createBot("an", "Sóc", "")
	c.createBot("binh", "Mèo", "")
	ctx := context.Background()
	c.inPsc("an", "9001")
	c.inPsc("binh", "9002")

	c.want(c.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Chào app"}, ""), 200, "")
	mainTask := c.lastTask("/tasks/agent-turn")
	raw, _ := json.Marshal(mainTask.Payload)
	if string(raw) != `{"afterSeq":1}` {
		t.Fatalf("payload phòng main đổi dạng: %s", raw)
	}
	seq, err := c.api.PostRoomMessage(ctx, agentTelegramRoom, "cuong", "Chào topic vl")
	if err != nil || seq != 1 {
		t.Fatalf("PostRoomMessage tg-psc: seq %d, %v", seq, err)
	}
	tgTask := c.lastTask("/tasks/agent-turn")
	if p := tgTask.Payload.(agentTurnTask); p.RoomID != agentTelegramRoom || p.AfterSeq != 1 || tgTask.TaskID == mainTask.TaskID || !tgTask.ScheduleTime.Equal(c.clock.Add(agentFirstTurnDelay)) {
		t.Fatalf("task tg-psc: %+v id %s, main id %s", p, tgTask.TaskID, mainTask.TaskID)
	}

	// Lượt bot ở tg-psc chỉ đọc đoạn chat của tg-psc và hẹn lượt kế đúng phòng.
	c.llm.script = []*genai.GenerateContentResponse{llmText("Chào Cường")}
	c.mustRun("/tasks/agent-turn", tgTask.Payload)
	if chat := contentTexts(c.llm.calls[0])[0]; !strings.Contains(chat, "Chào topic **") || strings.Contains(chat, "Chào app") {
		t.Fatalf("đoạn chat gửi model của tg-psc: %s", chat)
	}
	tgMsgs := c.col("agentRooms/tg-psc/messages")
	if len(tgMsgs) != 2 || tgMsgs[0]["channel"] != agentChannelTelegram || tgMsgs[1]["channel"] != agentChannelTelegram || tgMsgs[1]["uid"] != "an" {
		t.Fatalf("tin tg-psc: %v", tgMsgs)
	}
	if next := c.lastTask("/tasks/agent-turn").Payload.(agentTurnTask); next.RoomID != agentTelegramRoom || next.AfterSeq != 2 {
		t.Fatalf("lượt kế tg-psc: %+v", next)
	}
	if main := c.doc("agentRooms/main"); int64(number(main["seq"])) != 1 || int64(number(main["chain"])) != 0 {
		t.Fatalf("lượt ở tg-psc đụng tới phòng main: %v", main)
	}
	if msgs := messages(t, c.call("binh", "GET", "/v1/agents/room", nil, "")); len(msgs) != 1 || msgs[0]["text"] != "Chào app" {
		t.Fatalf("GET room của app lẫn tin tg-psc: %v", msgs)
	}

	// Chuỗi tg-psc chạm trần: tg-psc im, main vẫn nói (task không roomID là main).
	if _, err := c.store.db.Doc("agentRooms/tg-psc").Update(ctx, []firestore.Update{{Path: "chain", Value: agentChainMax}}); err != nil {
		t.Fatal(err)
	}
	calls := len(c.llm.calls)
	c.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 2, RoomID: agentTelegramRoom})
	if len(c.llm.calls) != calls {
		t.Fatal("chuỗi tg-psc đã đủ mà bot vẫn nói")
	}
	c.llm.script = []*genai.GenerateContentResponse{llmText("Chào app nhé")}
	c.mustRun("/tasks/agent-turn", map[string]any{"afterSeq": 1})
	mainMsgs := c.col("agentRooms/main/messages")
	if len(mainMsgs) != 2 || mainMsgs[1]["text"] != "Chào app nhé" || mainMsgs[1]["channel"] != agentChannelApp {
		t.Fatalf("task không roomID phải chạy ở main: %v", mainMsgs)
	}
	if next := c.lastTask("/tasks/agent-turn").Payload.(agentTurnTask); next.RoomID != "" || next.AfterSeq != 2 {
		t.Fatalf("lượt kế của main: %+v", next)
	}

	// Trần ngày của main hết: main im, tg-psc (tin người mới reset chuỗi) vẫn nói.
	if _, err := c.store.db.Doc("agentRooms/main").Update(ctx, []firestore.Update{{Path: "day", Value: vnDay(c.clock)}, {Path: "dayCount", Value: agentRoomDailyMax}}); err != nil {
		t.Fatal(err)
	}
	calls = len(c.llm.calls)
	c.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 2})
	if len(c.llm.calls) != calls {
		t.Fatal("main hết trần ngày mà bot vẫn nói")
	}
	c.tick(time.Second)
	if seq, err = c.api.PostRoomMessage(ctx, agentTelegramRoom, "cuong", "Ai chạy không"); err != nil || seq != 3 {
		t.Fatalf("tin người thứ hai ở tg-psc: %d %v", seq, err)
	}
	c.llm.script = []*genai.GenerateContentResponse{llmText("Mình chạy")}
	c.mustRun("/tasks/agent-turn", c.lastTask("/tasks/agent-turn").Payload)
	if room := c.doc("agentRooms/tg-psc"); int64(number(room["seq"])) != 4 || int64(number(room["chain"])) != 1 || int64(number(room["dayCount"])) != 2 {
		t.Fatalf("tg-psc phải nói được và đếm trần riêng: %v", room)
	}

	if code := c.runTask("/tasks/agent-turn", map[string]any{"afterSeq": 1, "roomID": "lạ"}); code != 204 {
		t.Fatalf("phòng lạ: %d", code)
	}
	if _, err := c.api.PostRoomMessage(ctx, "lạ", "cuong", "x"); err == nil {
		t.Fatal("ghi được vào phòng không có trong danh sách")
	}
}

// Xoá tài khoản gỡ tin của người đó ở mọi phòng bot (kể cả phòng chỉ còn
// subcollection), báo cáo ở mọi phòng, và chat riêng của mọi kênh.
func TestEmulatorAgentAccountDeleteChannels(t *testing.T) {
	c := newChannelEnv(t)
	c.createBot("cuong", "Cú", "")
	c.createBot("an", "Sóc", "")
	c.inPsc("cuong", "9001")
	ctx := context.Background()

	c.want(c.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "main của Cường"}, ""), 200, "")
	c.want(c.call("an", "POST", "/v1/agents/room", map[string]any{"text": "main của An"}, ""), 200, "")
	for _, m := range []struct{ uid, text string }{{"cuong", "tg của Cường"}, {"an", "Cú ơi, tg của An"}} {
		if _, err := c.api.PostRoomMessage(ctx, agentTelegramRoom, m.uid, m.text); err != nil {
			t.Fatal(err)
		}
	}
	// Bot của Cường nói ở tg-psc: tin mang uid chủ.
	c.llm.script = []*genai.GenerateContentResponse{llmText("Cú đây")}
	c.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 2, RoomID: agentTelegramRoom})
	if tg := c.col("agentRooms/tg-psc/messages"); len(tg) != 3 || tg[2]["uid"] != "cuong" {
		t.Fatalf("muốn bot của Cường nói ở tg-psc: %v", tg)
	}
	if _, err := c.deps.Agents.ReportRoom(ctx, agentTelegramRoom, "cuong", 2, false, c.clock); err != nil {
		t.Fatal(err)
	}
	if _, err := c.deps.Agents.ReportRoom(ctx, agentTelegramRoom, "an", 1, false, c.clock); err != nil {
		t.Fatal(err)
	}
	c.tgDM("cuong", "chat Telegram")
	// Phòng cũ không còn doc phòng, chỉ còn tin.
	seed(t, c.store.db, "agentRooms/cu/messages/0000000001", map[string]any{"seq": 1, "kind": agentKindHuman, "uid": "cuong", "text": "phòng cũ"})

	accounts := &AccountService{db: c.store.db, auth: c.auth, oauth: &OAuthService{db: c.store.db}}
	for i := 0; i < 2; i++ {
		if err := accounts.Delete(ctx, "cuong"); err != nil {
			t.Fatal(err)
		}
	}
	for _, room := range []string{"main", "tg-psc", "cu"} {
		docs, err := c.store.db.Collection("agentRooms/"+room+"/messages").Where("uid", "==", "cuong").Documents(ctx).GetAll()
		if err != nil {
			t.Fatal(err)
		}
		if len(docs) != 0 {
			t.Fatalf("phòng %s còn %d tin của Cường", room, len(docs))
		}
	}
	if main, tg := c.col("agentRooms/main/messages"), c.col("agentRooms/tg-psc/messages"); len(main) != 1 || main[0]["uid"] != "an" || len(tg) != 1 || tg[0]["uid"] != "an" {
		t.Fatalf("xoá nhầm tin của An: main %v, tg %v", main, tg)
	}
	if reports, err := c.store.db.Collection("agentRooms/tg-psc/reports").Documents(ctx).GetAll(); err != nil || len(reports) != 0 {
		t.Fatalf("còn báo cáo ở tg-psc: %d %v", len(reports), err)
	}
	if len(c.col("agents/cuong/tgdm")) != 0 || len(c.col("agents/cuong/dm")) != 0 || len(c.doc("agents/cuong")) != 0 {
		t.Fatal("còn bot hoặc chat riêng của Cường")
	}
}
