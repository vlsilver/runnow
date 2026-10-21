//go:build emulator

package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strconv"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// mybotEnv là agentEnv với MyBot trên Telegram bật: 3i (token gốc của fake
// Telegram) là bot quản lý. Task chạy bằng drain, khử trùng theo TaskID như
// Cloud Tasks.
type mybotEnv struct {
	*agentEnv
	tg   *fakeTelegram
	m    *ManagedBotService
	ran  map[string]bool
	done int
}

const mybotRoot = "root-secret"

var mybotTaskPaths = map[string]bool{"/tasks/managed-bot-sync": true, "/tasks/managed-send": true, "/tasks/agent-dm": true, "/tasks/agent-turn": true}

// mybotConfig là cấu hình webhook 3i như prod, cờ AGENT_TELEGRAM_BOTS tắt.
func mybotConfig(base Config) Config {
	base.TelegramWebhookSecret, base.TelegramBotUsername, base.TelegramChatID = mybotRoot, "Run3IBot", testPscChat
	base.WebBaseURL, base.PublicBaseURL = "https://threei.run", "https://api.test"
	return base
}

func newMybotEnv(t *testing.T) *mybotEnv {
	t.Helper()
	e := &mybotEnv{agentEnv: newAgentEnv(t), tg: newFakeTelegram(t), ran: map[string]bool{}}
	cfg := mybotConfig(e.cfg)
	cfg.AgentTelegramBots = true
	if !cfg.MybotEnabled() {
		t.Fatal("cấu hình test chưa bật MyBot")
	}
	e.m = NewManagedBotService(e.store.db, e.tg.service(""), cfg.TelegramBotUsername, mybotRoot, cfg.PublicBaseURL, e.publish)
	e.m.now = func() time.Time { return e.clock }
	e.m.chatID = cfg.TelegramChatID
	e.deps.ManagedBots = e.m
	e.srv = NewAPIServer(cfg, e.deps)
	e.brain.SetChannelReply(e.m.channelReply)
	e.brain.SetRoomOut(e.m.roomOut)
	e.bot = NewBotServer(cfg, &Dependencies{Firestore: e.store.db, Agents: e.deps.Agents, AgentBrain: e.brain, EnqueueTask: e.publish, Now: e.deps.Now, ManagedBots: e.m})
	return e
}

// drain chạy mọi task MyBot và agent-dm đã xếp, kể cả task do task sinh ra.
func (e *mybotEnv) drain() {
	e.t.Helper()
	for e.done < len(e.tasks) {
		p := e.tasks[e.done]
		e.done++
		if !mybotTaskPaths[p.HandlerPath] {
			continue
		}
		if p.TaskID != "" {
			if e.ran[p.TaskID] {
				continue
			}
			e.ran[p.TaskID] = true
		}
		if code := e.runTask(p.HandlerPath, p.Payload); code != 200 && code != 204 {
			e.t.Fatalf("%s %+v: status %d", p.HandlerPath, p.Payload, code)
		}
	}
}

func (e *agentEnv) hook(path, secret string, update map[string]any) apiResp {
	e.t.Helper()
	b, _ := json.Marshal(update)
	r := httptest.NewRequest("POST", path, bytes.NewReader(b))
	if secret != "" {
		r.Header.Set("X-Telegram-Bot-Api-Secret-Token", secret)
	}
	w := httptest.NewRecorder()
	e.srv.ServeHTTP(w, r)
	out := apiResp{status: w.Code, raw: w.Body.Bytes()}
	_ = json.Unmarshal(out.raw, &out.body)
	return out
}

// manager gửi update tới webhook của 3i, như Telegram gửi update managed_bot.
func (e *mybotEnv) manager(update map[string]any) apiResp {
	e.t.Helper()
	return e.hook("/v1/telegram/webhook", mybotRoot, update)
}

func (e *mybotEnv) child(botID int64, update map[string]any) apiResp {
	e.t.Helper()
	id := strconv.FormatInt(botID, 10)
	return e.hook("/v1/telegram/managed/"+id+"/webhook", e.m.childSecret(id), update)
}

// fsDoc đọc một doc; không có thì nil (khác doc, trả map rỗng).
func (e *agentEnv) fsDoc(path string) map[string]any {
	e.t.Helper()
	snap, err := e.store.db.Doc(path).Get(context.Background())
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		e.t.Fatal(err)
	}
	return snap.Data()
}

func managedUpd(updateID, ownerTg, botID int64, username string) map[string]any {
	return map[string]any{"update_id": updateID, "managed_bot": map[string]any{
		"user": map[string]any{"id": ownerTg, "is_bot": false, "first_name": "Chủ"},
		"bot":  map[string]any{"id": botID, "is_bot": true, "first_name": "Bot", "username": username},
	}}
}

func dmUpd(updateID, from int64, text string) map[string]any {
	return map[string]any{"update_id": updateID, "message": map[string]any{
		"message_id": updateID, "text": text,
		"chat": map[string]any{"id": from, "type": "private"},
		"from": map[string]any{"id": from, "is_bot": false, "first_name": "Ai đó"},
	}}
}

// linkBot: uid liên kết tg, tạo MyBot tên name, rồi tạo bot con botID trên
// Telegram. Trả token bot con.
func (e *mybotEnv) linkBot(uid, tg string, botID int64, name string, updateID int64) string {
	e.t.Helper()
	e.createBot(uid, name, "")
	return e.linkExisting(uid, tg, botID, updateID)
}

// linkExisting như linkBot cho uid đã có agents/{uid}.
func (e *mybotEnv) linkExisting(uid, tg string, botID int64, updateID int64) string {
	e.t.Helper()
	linkUser(e.t, e.apiHarness, uid, tg, true)
	tok := e.tg.addManaged(botID)
	if r := e.manager(managedUpd(updateID, mustInt(tg), botID, "bot_"+uid)); r.status != 200 || r.body != nil {
		e.t.Fatalf("managed_bot: %d %s", r.status, r.raw)
	}
	e.drain()
	return tok
}

func telegramOf(agent map[string]any) map[string]any {
	tg, _ := agent["telegram"].(map[string]any)
	return tg
}

// Cờ tắt: webhook bot con 404, update managed_bot tới 3i chỉ log, GET
// /v1/agents/me giữ đúng các field cũ. Cờ bật: chỉ thêm đúng field telegram.
func TestEmulatorMybotOffAndMeIsAdditive(t *testing.T) {
	e := newAgentEnv(t)
	e.srv = NewAPIServer(mybotConfig(e.cfg), e.deps)
	e.createBot("cuong", "Cú Mèo", "")
	linkUser(t, e.apiHarness, "cuong", "5001", true)
	if r := e.hook("/v1/telegram/managed/8001/webhook", webhookHMAC(mybotRoot, "managed:8001"), dmUpd(1, 5001, "alo")); r.status != 404 {
		t.Fatalf("webhook bot con khi tắt: %d", r.status)
	}
	if r := e.hook("/v1/telegram/webhook", mybotRoot, managedUpd(2, 5001, 8001, "bot_cuong")); r.status != 200 || r.body != nil {
		t.Fatalf("managed_bot khi tắt: %d %s", r.status, r.raw)
	}
	if e.fsDoc("managedBots/8001") != nil || telegramOf(e.fsDoc("agents/cuong")) != nil || len(e.tasks) != 0 {
		t.Fatalf("tắt mà vẫn nối bot: tasks=%+v", e.tasks)
	}
	off := e.call("cuong", "GET", "/v1/agents/me", nil, "")
	if _, ok := off.body["telegram"]; ok || off.status != 200 {
		t.Fatalf("tắt mà có telegram: %s", off.raw)
	}

	on := newMybotEnv(t)
	on.createBot("cuong", "Cú Mèo", "")
	r := on.call("cuong", "GET", "/v1/agents/me", nil, "")
	tg, _ := r.body["telegram"].(map[string]any)
	// Username gợi ý đã có test bảng riêng; ở đây chỉ chốt link trỏ về 3i.
	want := "https://t.me/newbot/Run3IBot/" + suggestBotUsername("Cú Mèo", "cuong") + "?name=C%C3%BA%20M%C3%A8o"
	if tg["linked"] != false || tg["createUrl"] != want || tg["botUsername"] != nil {
		t.Fatalf("bật: %s, mong đợi createUrl %s", r.raw, want)
	}
	delete(r.body, "telegram")
	if !reflect.DeepEqual(r.body, off.body) {
		t.Fatalf("bật làm đổi field cũ:\n%s\n%s", r.raw, off.raw)
	}
}

// Update khác của 3i vẫn đi đường cũ khi MyBot bật; tin dịch vụ
// managed_bot_created chỉ log, không thành tin hỏi 3i.
func TestEmulatorMybotKeepsOtherThreeIUpdates(t *testing.T) {
	e := newMybotEnv(t)
	created := map[string]any{"update_id": 3, "message": map[string]any{"message_id": 3,
		"chat": map[string]any{"id": 5001, "type": "private"}, "from": map[string]any{"id": 5001},
		"managed_bot_created": map[string]any{"bot": map[string]any{"id": 8001, "is_bot": true, "username": "x_bot"}}}}
	if r := e.manager(created); r.status != 200 || r.body != nil || len(e.tasks) != 0 {
		t.Fatalf("managed_bot_created: %d %s tasks=%d", r.status, r.raw, len(e.tasks))
	}
	start := map[string]any{"update_id": 4, "message": map[string]any{"message_id": 4, "text": "/start ma-sai",
		"chat": map[string]any{"id": 5001, "type": "private"}, "from": map[string]any{"id": 5001, "first_name": "A"}}}
	if r := e.manager(start); r.status != 200 || !strings.Contains(fmt.Sprint(r.body["text"]), "Mã liên kết không đúng") {
		t.Fatalf("/start của 3i đổi hành vi: %d %s", r.status, r.raw)
	}
	if r := e.hook("/v1/telegram/webhook", "sai", managedUpd(1, 1, 2, "x")); r.status != 401 {
		t.Fatalf("webhook 3i sai secret: %d", r.status)
	}
}

func TestEmulatorMybotLinkSetsUpChildOnce(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)

	bot := e.fsDoc("managedBots/8001")
	if bot["uid"] != "cuong" || bot["username"] != "bot_cuong" || tgIDString(bot["ownerTgId"]) != "5001" {
		t.Fatalf("managedBots/8001 = %v", bot)
	}
	link := telegramOf(e.fsDoc("agents/cuong"))
	if link["botId"] != "8001" || link["username"] != "bot_cuong" || link["setupAt"] == nil || link["setupError"] != nil {
		t.Fatalf("agents/cuong.telegram = %v", link)
	}
	hooks := e.tg.CallsBy(tok, "setWebhook")
	if len(hooks) != 1 {
		t.Fatalf("setWebhook = %+v", e.tg.Calls(""))
	}
	p := hooks[0].Params
	if p["url"] != "https://api.test/v1/telegram/managed/8001/webhook" || p["secret_token"] != webhookHMAC(mybotRoot, "managed:8001") ||
		!reflect.DeepEqual(p["allowed_updates"], []any{"message", "my_chat_member"}) {
		t.Fatalf("setWebhook params = %v", p)
	}
	if n := e.tg.CallsBy(tok, "setMyName"); len(n) != 1 || n[0].Params["name"] != "Cú Mèo" {
		t.Fatalf("setMyName = %+v", n)
	}
	if d := e.tg.CallsBy(tok, "setMyDescription"); len(d) != 1 || !strings.Contains(d[0].Params["description"].(string), "Cường") {
		t.Fatalf("setMyDescription = %+v", d)
	}
	r := e.call("cuong", "GET", "/v1/agents/me", nil, "")
	if tg, _ := r.body["telegram"].(map[string]any); tg["linked"] != true || tg["botUsername"] != "bot_cuong" {
		t.Fatalf("me sau khi nối: %s", r.raw)
	}

	// Telegram gửi lại đúng update: không ghi gì, không gọi Telegram thêm.
	e.tick(time.Minute)
	e.manager(managedUpd(10, 5001, 8001, "bot_cuong"))
	e.drain()
	if again := e.fsDoc("managedBots/8001"); !reflect.DeepEqual(again, bot) {
		t.Fatalf("update lặp đổi doc:\n%v\n%v", again, bot)
	}
	if again := telegramOf(e.fsDoc("agents/cuong")); !reflect.DeepEqual(again, link) {
		t.Fatalf("update lặp đổi agents.telegram:\n%v\n%v", again, link)
	}
	if n := len(e.tg.Calls("setWebhook")); n != 1 {
		t.Fatalf("update lặp gọi setWebhook %d lần", n)
	}

	// Đổi tên trong app: đặt lại tên bot con, mô tả không đổi thì không gọi lại.
	e.createBot("cuong", "Cú Đêm", "")
	e.drain()
	if n := e.tg.CallsBy(tok, "setMyName"); len(n) != 2 || n[1].Params["name"] != "Cú Đêm" {
		t.Fatalf("đổi tên: setMyName = %+v", n)
	}
	if n := len(e.tg.Calls("setMyDescription")); n != 1 {
		t.Fatalf("đổi tên gọi setMyDescription %d lần", n)
	}
}

func TestEmulatorMybotRejectsUnlinkedOwner(t *testing.T) {
	e := newMybotEnv(t)
	e.tg.addManaged(8002)
	r := e.manager(managedUpd(20, 5999, 8002, "la_bot"))
	if r.status != 200 || r.body["method"] != "sendMessage" || r.body["chat_id"] != float64(5999) || r.body["text"] != managedNoLinkReply {
		t.Fatalf("tg chưa liên kết: %d %s", r.status, r.raw)
	}
	// Đã liên kết mà chưa tạo MyBot: cũng không nối, vì ghi agents/{uid} lúc
	// này là đẻ ra bot rỗng.
	linkUser(t, e.apiHarness, "binh", "5002", true)
	r = e.manager(managedUpd(21, 5002, 8002, "la_bot"))
	if r.body["text"] != managedNoAgentReply {
		t.Fatalf("chưa tạo MyBot: %s", r.raw)
	}
	if e.fsDoc("managedBots/8002") != nil || e.fsDoc("agents/binh") != nil || len(e.tasks) != 0 {
		t.Fatalf("ghi khi không được nối: bot=%v agent=%v tasks=%d", e.fsDoc("managedBots/8002"), e.fsDoc("agents/binh"), len(e.tasks))
	}
}

// Bot mới thắng: bot cũ ghi replacedAt và bị gỡ webhook; tin nhắn tới bot cũ
// không vào chat của chủ nữa.
func TestEmulatorMybotSecondBotReplacesFirst(t *testing.T) {
	e := newMybotEnv(t)
	oldTok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	newTok := e.tg.addManaged(8003)
	e.manager(managedUpd(11, 5001, 8003, "bot_cuong_2"))
	e.drain()
	if old := e.fsDoc("managedBots/8001"); old["replacedAt"] == nil {
		t.Fatalf("bot cũ = %v", old)
	}
	if link := telegramOf(e.fsDoc("agents/cuong")); link["botId"] != "8003" {
		t.Fatalf("agents.telegram = %v", link)
	}
	if len(e.tg.CallsBy(oldTok, "deleteWebhook")) != 1 || len(e.tg.CallsBy(newTok, "setWebhook")) != 1 {
		t.Fatalf("calls = %+v", e.tg.Calls(""))
	}
	e.child(8001, dmUpd(30, 5001, "còn đó không"))
	if tgdm := e.fsDoc("agents/cuong")["tgSeq"]; tgdm != nil {
		t.Fatalf("tin tới bot cũ vào tgdm: tgSeq=%v", tgdm)
	}
}

// Bot đổi chủ trên Telegram: chủ mới đã liên kết thì bot chuyển sang uid mới;
// chủ mới chưa liên kết thì bot rời chủ cũ và bị gỡ webhook.
func TestEmulatorMybotOwnerChange(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	linkUser(t, e.apiHarness, "an", "5003", true)
	e.createBot("an", "Sóc", "")
	e.manager(managedUpd(12, 5003, 8001, "bot_cuong"))
	e.drain()
	if b := e.fsDoc("managedBots/8001"); b["uid"] != "an" || tgIDString(b["ownerTgId"]) != "5003" || b["replacedAt"] != nil {
		t.Fatalf("sau đổi chủ = %v", b)
	}
	if telegramOf(e.fsDoc("agents/cuong")) != nil || telegramOf(e.fsDoc("agents/an"))["botId"] != "8001" {
		t.Fatalf("cuong=%v an=%v", e.fsDoc("agents/cuong")["telegram"], e.fsDoc("agents/an")["telegram"])
	}
	if n := e.tg.CallsBy(tok, "setMyName"); len(n) != 2 || n[1].Params["name"] != "Sóc" {
		t.Fatalf("tên theo chủ mới: %+v", n)
	}

	r := e.manager(managedUpd(13, 5999, 8001, "bot_cuong"))
	e.drain()
	if r.body["text"] != managedNoLinkReply || e.fsDoc("managedBots/8001")["replacedAt"] == nil || telegramOf(e.fsDoc("agents/an")) != nil {
		t.Fatalf("chủ mới chưa liên kết: %s bot=%v", r.raw, e.fsDoc("managedBots/8001"))
	}
	if len(e.tg.CallsBy(tok, "deleteWebhook")) != 1 {
		t.Fatalf("không gỡ webhook: %+v", e.tg.Calls("deleteWebhook"))
	}
}

func TestEmulatorMybotChildWebhookAuthAndStrangers(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	if r := e.hook("/v1/telegram/managed/8001/webhook", "sai", dmUpd(40, 5001, "x")); r.status != 401 {
		t.Fatalf("sai secret: %d", r.status)
	}
	// Secret của bot này không mở được webhook của bot khác.
	if r := e.hook("/v1/telegram/managed/8003/webhook", e.m.childSecret("8001"), dmUpd(40, 5001, "x")); r.status != 401 {
		t.Fatalf("secret bot khác: %d", r.status)
	}
	// Bot không có bản ghi mà secret đúng: hẹn Sync để gỡ webhook.
	if r := e.child(9999, dmUpd(41, 5001, "x")); r.status != 200 {
		t.Fatalf("bot lạ: %d", r.status)
	}
	if last := e.tasks[len(e.tasks)-1]; last.HandlerPath != "/tasks/managed-bot-sync" || last.Payload.(managedSyncTask).BotID != "9999" {
		t.Fatalf("bot lạ không hẹn gỡ webhook: %+v", last)
	}
	e.drain()
	if n := len(e.tg.CallsBy(fakeTelegramToken, "getManagedBotToken")); n != 2 {
		t.Fatalf("getManagedBotToken = %d", n)
	}

	// Người lạ nhắn hai lần cùng update: một câu cố định, không gọi model.
	before := len(e.tasksTo("/tasks/managed-send"))
	for i := 0; i < 2; i++ {
		if r := e.child(8001, dmUpd(42, 7777, "ê bot")); r.status != 200 {
			t.Fatalf("người lạ: %d %s", r.status, r.raw)
		}
	}
	if n := len(e.tasksTo("/tasks/managed-send")) - before; n != 1 {
		t.Fatalf("update lặp xếp %d tin", n)
	}
	e.drain()
	sent := e.tg.CallsBy(tok, "sendMessage")
	if len(sent) != 1 || sent[0].Params["chat_id"] != "7777" || sent[0].Params["text"] != managedStrangerReply {
		t.Fatalf("sendMessage = %+v", sent)
	}
	if len(e.llm.calls) != 0 || e.fsDoc("agents/cuong")["tgSeq"] != nil {
		t.Fatalf("người lạ tới được model: %d lần gọi", len(e.llm.calls))
	}
}

// Luồng đầy đủ: chủ nhắn bot con → tgdm → agent-dm kênh telegram → câu trả
// lời → đúng một sendMessage từ bot con, kể cả khi task chạy lại và Telegram
// gửi lại update.
func TestEmulatorMybotOwnerDMRoundTrip(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	e.llm.script = []*genai.GenerateContentResponse{llmText("Chào chủ, mình đây")}
	for i := 0; i < 2; i++ {
		if r := e.child(8001, dmUpd(50, 5001, "alo")); r.status != 200 {
			t.Fatalf("chủ nhắn: %d %s", r.status, r.raw)
		}
	}
	dm := e.tasksTo("/tasks/agent-dm")
	if len(dm) != 1 || dm[0].Payload.(agentDMTask).Channel != agentChannelTelegram {
		t.Fatalf("agent-dm = %+v", dm)
	}
	if e.fsDoc("agents/cuong/tgdm/"+seqDocID(2)) != nil {
		t.Fatal("update lặp ghi tin thứ hai vào tgdm")
	}
	if app := e.fsDoc("agents/cuong")["dmSeq"]; app != nil {
		t.Fatalf("tin Telegram vào chat app: dmSeq=%v", app)
	}
	e.drain()
	if len(e.llm.calls) != 1 || !strings.Contains(e.llm.calls[0].system, "trên Telegram") {
		t.Fatalf("model: %d lần gọi", len(e.llm.calls))
	}
	e.mustRun("/tasks/agent-dm", dm[0].Payload)
	for _, s := range e.tasksTo("/tasks/managed-send") {
		e.mustRun("/tasks/managed-send", s.Payload)
	}
	e.drain()
	sent := e.tg.CallsBy(tok, "sendMessage")
	if len(sent) != 1 || sent[0].Params["chat_id"] != "5001" || sent[0].Params["text"] != "Chào chủ, mình đây" {
		t.Fatalf("sendMessage = %+v", sent)
	}
	if len(e.llm.calls) != 1 {
		t.Fatalf("task chạy lại gọi model %d lần", len(e.llm.calls))
	}
}

// Mỗi lỗi đã biết của PostChannelDM ra một câu cố định qua bot con, không hẹn
// lượt model nào cho tin đó.
func TestEmulatorMybotOwnerDMErrorReplies(t *testing.T) {
	for _, c := range []struct {
		name  string
		setup func(t *testing.T, e *mybotEnv) (owner int64)
		text  string
		want  string
	}{
		{"disabled", func(t *testing.T, e *mybotEnv) int64 {
			e.linkBot("cuong", "5001", 8001, "Cú", 10)
			seed(t, e.store.db, "agentState/config", map[string]any{"memberUids": []any{}})
			return 5001
		}, "alo", "Bạn chưa được mời dùng MyBot. Mở app 3i Run để xem: https://threei.run"},
		{"consent", func(t *testing.T, e *mybotEnv) int64 {
			seed(t, e.store.db, "agentState/config", map[string]any{"open": true, "memberUids": []any{"cuong"}})
			seed(t, e.store.db, "agents/dung", map[string]any{"name": "Dê"})
			e.linkExisting("dung", "5004", 8001, 10)
			return 5004
		}, "alo", "Bạn cần đồng ý cho bot gửi dữ liệu tới AI trong app 3i Run trước: https://threei.run"},
		{"not_found", func(t *testing.T, e *mybotEnv) int64 {
			e.linkBot("cuong", "5001", 8001, "Cú", 10)
			if _, err := e.store.db.Doc("agents/cuong").Delete(context.Background()); err != nil {
				t.Fatal(err)
			}
			return 5001
		}, "alo", "Bạn chưa tạo MyBot trong app 3i Run: https://threei.run"},
		{"text", func(t *testing.T, e *mybotEnv) int64 {
			e.linkBot("cuong", "5001", 8001, "Cú", 10)
			return 5001
		}, "", managedTextReply},
		{"too_fast", func(t *testing.T, e *mybotEnv) int64 {
			e.linkBot("cuong", "5001", 8001, "Cú", 10)
			if r := e.child(8001, dmUpd(60, 5001, "tin đầu")); r.status != 200 || len(e.tasksTo("/tasks/agent-dm")) != 1 {
				t.Fatalf("tin đầu: %d", r.status)
			}
			return 5001
		}, "tin hai", managedTooFastReply},
	} {
		t.Run(c.name, func(t *testing.T) {
			e := newMybotEnv(t)
			owner := c.setup(t, e)
			dms, sends := len(e.tasksTo("/tasks/agent-dm")), e.tasksTo("/tasks/managed-send")
			if r := e.child(8001, dmUpd(61, owner, c.text)); r.status != 200 {
				t.Fatalf("status %d %s", r.status, r.raw)
			}
			after := e.tasksTo("/tasks/managed-send")
			if len(after) != len(sends)+1 || len(e.tasksTo("/tasks/agent-dm")) != dms {
				t.Fatalf("managed-send %d→%d, agent-dm %d→%d", len(sends), len(after), dms, len(e.tasksTo("/tasks/agent-dm")))
			}
			e.mustRun("/tasks/managed-send", after[len(after)-1].Payload)
			sent := e.tg.Calls("sendMessage")
			if len(sent) != 1 || sent[0].Params["text"] != c.want || sent[0].Params["chat_id"] != strconv.FormatInt(owner, 10) {
				t.Fatalf("sendMessage = %+v", sent)
			}
		})
	}
}

// Lỗi khác (enqueue agent-dm hỏng) thì 5xx và bỏ khoá update, để lần Telegram
// gửi lại được xử lý chứ không bị coi là trùng.
func TestEmulatorMybotOwnerDMOtherErrorRetries(t *testing.T) {
	e := newMybotEnv(t)
	e.linkBot("cuong", "5001", 8001, "Cú", 10)
	ok := e.deps.EnqueueTask
	e.deps.EnqueueTask = func(ctx context.Context, p PublishTask) (string, error) {
		if p.HandlerPath == "/tasks/agent-dm" {
			return "", errors.New("cloud tasks hỏng")
		}
		return ok(ctx, p)
	}
	if r := e.child(8001, dmUpd(70, 5001, "alo")); r.status != http.StatusServiceUnavailable {
		t.Fatalf("lỗi lạ: %d", r.status)
	}
	e.deps.EnqueueTask = ok
	e.tick(2 * time.Second)
	if r := e.child(8001, dmUpd(70, 5001, "alo")); r.status != 200 {
		t.Fatalf("gửi lại: %d", r.status)
	}
	if dm := e.tasksTo("/tasks/agent-dm"); len(dm) != 1 {
		t.Fatalf("gửi lại không enqueue agent-dm: %+v", dm)
	}
	// Lần đầu đã ghi tin rồi mới hỏng ở enqueue, nên lần gửi lại ghi tin thứ
	// hai; bot trả lời gộp một lần (đã chấp nhận, xem PostChannelDM).
	if seq := e.fsDoc("agents/cuong")["tgSeq"]; seq != int64(2) {
		t.Fatalf("tgSeq = %v", seq)
	}
}

// Bản 1 (chưa có T7): bị thêm vào group nào ngoài PSC thì rời ngay, không nói gì.
func TestEmulatorMybotLeavesGroupsExceptPSC(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkBot("cuong", "5001", 8001, "Cú", 10)
	join := func(updateID int64, chat string) map[string]any {
		return map[string]any{"update_id": updateID, "my_chat_member": map[string]any{
			"chat": map[string]any{"id": mustInt(chat), "type": "supergroup", "title": "G"},
			"from": map[string]any{"id": 6000}, "new_chat_member": map[string]any{"status": "member"},
		}}
	}
	e.child(8001, join(80, "-100777"))
	e.child(8001, join(81, testPscChat))
	e.drain()
	left := e.tg.CallsBy(tok, "leaveChat")
	if len(left) != 1 || left[0].Params["chat_id"] != "-100777" || len(e.tg.Calls("sendMessage")) != 0 {
		t.Fatalf("leaveChat = %+v, sendMessage = %+v", left, e.tg.Calls("sendMessage"))
	}
}

// Token bot con đổi (401): bỏ cache, lấy token mới một lần rồi gửi được.
func TestEmulatorMybotRefetchesTokenOn401(t *testing.T) {
	e := newMybotEnv(t)
	oldTok := e.linkBot("cuong", "5001", 8001, "Cú", 10)
	newTok := e.tg.addManaged(8001)
	e.child(8001, dmUpd(90, 7777, "ê"))
	e.drain()
	if len(e.tg.CallsBy(oldTok, "sendMessage")) != 1 || len(e.tg.CallsBy(newTok, "sendMessage")) != 1 || len(e.tg.Calls("getManagedBotToken")) != 2 {
		t.Fatalf("calls = %+v", e.tg.Calls(""))
	}
	key := "upd-90"
	if out := e.fsDoc("managedBots/8001/tgOutbox/" + key); out["status"] != outboxSent {
		t.Fatalf("outbox = %v", out)
	}
}

// Xoá tài khoản (chạy trên api, không có token 3i): xoá bản ghi rồi hẹn Sync
// để bot service gỡ webhook.
func TestEmulatorMybotAccountDeleteRemovesBot(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkBot("cuong", "5001", 8001, "Cú", 10)
	e.child(8001, dmUpd(95, 7777, "ê"))
	e.drain()
	accounts := &AccountService{db: e.store.db, managed: e.m}
	if err := accounts.deleteManagedBots(context.Background(), "cuong"); err != nil {
		t.Fatal(err)
	}
	if e.fsDoc("managedBots/8001") != nil || e.fsDoc("managedBots/8001/tgOutbox/upd-95") != nil {
		t.Fatal("còn bản ghi bot con")
	}
	if len(e.tg.CallsBy(tok, "deleteWebhook")) != 0 {
		t.Fatal("xoá tài khoản gọi Telegram trực tiếp")
	}
	e.drain()
	if len(e.tg.CallsBy(tok, "deleteWebhook")) != 1 {
		t.Fatalf("không gỡ webhook: %+v", e.tg.Calls(""))
	}
	if r := e.child(8001, dmUpd(96, 5001, "alo")); r.status != 200 || e.fsDoc("agents/cuong")["tgSeq"] != nil {
		t.Fatalf("bot đã xoá vẫn nhận tin: %d", r.status)
	}
}
