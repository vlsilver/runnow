//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Chủ ván (admin "an") đã có MyBot nối Telegram. Bấm Tạo bot cho ván rồi tạo
// bot trên Telegram: bot mới là bot ván, MyBot giữ nguyên.
func TestEmulatorGameTgBotLinksBesideMybot(t *testing.T) {
	e := newMybotEnv(t)
	e.createBot("an", "Cú Mèo", "")
	e.linkExisting("an", "5001", 8001, 10)

	r := e.call("an", "POST", "/v1/games/telegram/bot", nil, "")
	if r.status != 200 || !strings.HasPrefix(stringValue(r.body["createUrl"]), "https://t.me/newbot/Run3IBot/") {
		t.Fatalf("tạo bot ván: %d %s", r.status, r.raw)
	}
	tok := e.tg.addManaged(9001)
	if r := e.manager(managedUpd(11, 5001, 9001, "van_an_bot")); r.status != 200 || r.body != nil {
		t.Fatalf("managed_bot: %d %s", r.status, r.raw)
	}
	e.drain()

	if b := e.fsDoc("managedBots/9001"); b["kind"] != "game" || b["uid"] != "an" {
		t.Fatalf("managedBots/9001 = %v", b)
	}
	if my := telegramOf(e.fsDoc("agents/an")); my["botId"] != "8001" {
		t.Fatalf("MyBot bị thay: %v", my)
	}
	if old := e.fsDoc("managedBots/8001"); old["replacedAt"] != nil {
		t.Fatalf("MyBot bị gỡ: %v", old)
	}
	hooks := e.tg.CallsBy(tok, "setWebhook")
	if len(hooks) != 1 || hooks[0].Params["url"] != "https://api.test/v1/telegram/managed/9001/webhook" {
		t.Fatalf("setWebhook bot ván = %+v", hooks)
	}
	st := e.call("an", "GET", "/v1/games/telegram", nil, "")
	bot, _ := st.body["bot"].(map[string]any)
	if st.status != 200 || bot["username"] != "van_an_bot" {
		t.Fatalf("trạng thái: %d %s", st.status, st.raw)
	}
}

// linkGameBot: admin uid liên kết tg rồi tạo bot ván botID. Trả token bot.
func (e *mybotEnv) linkGameBot(uid, tg string, botID int64) string {
	e.t.Helper()
	linkUser(e.t, e.apiHarness, uid, tg, true)
	if r := e.call(uid, "POST", "/v1/games/telegram/bot", nil, ""); r.status != 200 {
		e.t.Fatalf("tạo bot ván: %d %s", r.status, r.raw)
	}
	tok := e.tg.addManaged(botID)
	e.manager(managedUpd(botID, mustInt(tg), botID, "van_"+uid+"_bot"))
	e.drain()
	return tok
}

func memberUpd(updateID, chatID, from int64, status, title string) map[string]any {
	return map[string]any{"update_id": updateID, "my_chat_member": map[string]any{
		"chat":            map[string]any{"id": chatID, "type": "supergroup", "title": title, "is_forum": true},
		"from":            map[string]any{"id": from, "is_bot": false, "first_name": "Ai đó"},
		"date":            1,
		"old_chat_member": map[string]any{"status": "left", "user": map[string]any{"id": 1, "is_bot": true}},
		"new_chat_member": map[string]any{"status": status, "user": map[string]any{"id": 1, "is_bot": true}},
	}}
}

// gameChats là các group trong GET /v1/games/telegram, theo chatId.
func (e *mybotEnv) gameChats(uid string) map[string]map[string]any {
	e.t.Helper()
	r := e.call(uid, "GET", "/v1/games/telegram", nil, "")
	if r.status != 200 {
		e.t.Fatalf("trạng thái: %d %s", r.status, r.raw)
	}
	out := map[string]map[string]any{}
	list, _ := r.body["chats"].([]any)
	for _, c := range list {
		m, _ := c.(map[string]any)
		out[stringValue(m["chatId"])] = m
	}
	return out
}

// Group chỉ được ghi khi chính chủ thêm bot; người khác thêm thì bot rời.
// Bot bị kick thì group biến khỏi danh sách.
func TestEmulatorGameTgBotRecordsOwnerGroups(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkGameBot("an", "5001", 9001)

	e.child(9001, memberUpd(1, -100777, 5001, "administrator", "Nhóm chạy"))
	e.child(9001, memberUpd(2, -100999, 5001, "member", "Nhóm phụ"))
	e.child(9001, memberUpd(3, -100888, 5999, "administrator", "Nhóm lạ"))
	e.drain()

	chats := e.gameChats("an")
	if c := chats["-100777"]; c["title"] != "Nhóm chạy" || c["admin"] != true || c["forum"] != true {
		t.Fatalf("group của chủ: %v", chats)
	}
	if c := chats["-100999"]; c == nil || c["admin"] != false {
		t.Fatalf("group chưa cho admin: %v", chats)
	}
	if chats["-100888"] != nil {
		t.Fatalf("group người lạ thêm bot vẫn được ghi: %v", chats)
	}
	leaves := e.tg.CallsBy(tok, "leaveChat")
	if len(leaves) != 1 || leaves[0].Params["chat_id"] != "-100888" {
		t.Fatalf("leaveChat = %+v", leaves)
	}

	e.child(9001, memberUpd(4, -100777, 5002, "kicked", "Nhóm chạy"))
	if e.gameChats("an")["-100777"] != nil {
		t.Fatalf("bị kick vẫn còn trong danh sách")
	}
}

// vanMsg là tin trong group; thread khác 0 là tin trong topic tên topic.
func vanMsg(updateID, chatID, from, thread int64, text, topic string) map[string]any {
	msg := map[string]any{"message_id": updateID, "text": text,
		"chat": map[string]any{"id": chatID, "type": "supergroup", "title": "Nhóm chạy", "is_forum": true},
		"from": map[string]any{"id": from, "is_bot": false, "first_name": "Ai đó"}}
	if thread != 0 {
		msg["message_thread_id"], msg["is_topic_message"] = thread, true
		msg["reply_to_message"] = map[string]any{"message_id": thread, "message_thread_id": thread,
			"forum_topic_created": map[string]any{"name": topic, "icon_color": 7322096}}
	}
	return map[string]any{"update_id": updateID, "message": msg}
}

// Topic chỉ được ghi khi chủ gõ /van ngay trong topic đó, ở group đã ghi.
// Bot trả lời vào đúng topic, nên tin trả lời tới nơi là bằng chứng bot gửi
// được vào đó.
func TestEmulatorGameTgBotConfirmsTopicByCommand(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkGameBot("an", "5001", 9001)
	e.child(9001, memberUpd(1, -100777, 5001, "administrator", "Nhóm chạy"))

	e.child(9001, vanMsg(2, -100777, 5001, 42, "/van", "Ma Sói"))
	e.child(9001, vanMsg(2, -100777, 5001, 42, "/van", "Ma Sói")) // Telegram gửi lại
	e.child(9001, vanMsg(3, -100777, 5999, 43, "/van", "Chém gió"))
	e.child(9001, vanMsg(4, -100777, 5001, 44, "chào cả nhà", "Chạy bộ"))
	e.child(9001, vanMsg(5, -100777, 5001, 0, "/van@van_an_bot", ""))
	e.child(9001, vanMsg(6, -100555, 5001, 7, "/van", "Nhóm chưa ghi"))
	e.drain()

	topics, _ := e.gameChats("an")["-100777"]["topics"].([]any)
	got := map[float64]any{}
	for _, x := range topics {
		m, _ := x.(map[string]any)
		got[m["threadId"].(float64)] = m["name"]
	}
	if len(got) != 2 || got[42] != "Ma Sói" || got[0] != nil {
		t.Fatalf("topics = %v", topics)
	}
	if _, ok := got[0]; !ok {
		t.Fatalf("General chưa được ghi: %v", topics)
	}
	sent := e.tg.CallsBy(tok, "sendMessage")
	if len(sent) != 2 {
		t.Fatalf("sendMessage = %+v", sent)
	}
	threads := map[any]bool{}
	for _, c := range sent {
		if c.Params["chat_id"] != "-100777" {
			t.Fatalf("trả lời sai group: %+v", c.Params)
		}
		threads[c.Params["message_thread_id"]] = true
	}
	if !threads[float64(42)] || !threads[nil] {
		t.Fatalf("trả lời sai topic: %+v", sent)
	}
}

// Tạo ván vào group riêng: chỉ nhận group bot ván đang làm admin và topic chủ
// đã /van. Ván ghi botId để outbox gửi bằng bot ván.
func TestEmulatorGameTgBotCreateChecksTarget(t *testing.T) {
	e := newMybotEnv(t)
	game := func(chat string, thread int64) map[string]any {
		return map[string]any{"telegram": map[string]any{"chatId": chat, "threadId": thread}}
	}
	e.want(e.call("an", "POST", "/v1/games", game("-100777", 42), ""), 422, "telegram_bot")

	e.linkGameBot("an", "5001", 9001)
	e.child(9001, memberUpd(1, -100777, 5001, "administrator", "Nhóm chạy"))
	e.child(9001, memberUpd(2, -100999, 5001, "member", "Nhóm phụ"))
	e.child(9001, vanMsg(3, -100777, 5001, 42, "/van", "Ma Sói"))
	e.child(9001, vanMsg(4, -100999, 5001, 0, "/van", ""))

	e.want(e.call("an", "POST", "/v1/games", game("-100888", 0), ""), 422, "telegram_chat")
	e.want(e.call("an", "POST", "/v1/games", game("-100999", 0), ""), 422, "telegram_chat")
	e.want(e.call("an", "POST", "/v1/games", game("-100777", 43), ""), 422, "telegram_topic")
	e.want(e.call("an", "POST", "/v1/games", game("-100777", 0), ""), 422, "telegram_topic")

	r := e.call("an", "POST", "/v1/games", game("-100777", 42), "")
	if r.status != 201 {
		t.Fatalf("tạo ván: %d %s", r.status, r.raw)
	}
	g := e.fsDoc("games/" + stringValue(r.body["id"]))
	if g["chatId"] != "-100777" || g["threadId"] != int64(42) || g["botId"] != "9001" {
		t.Fatalf("games = %v", g)
	}
}

// Ván có botId: tin group đi bằng bot ván vào đúng group và topic của ván, bỏ
// nút callback (callback tới webhook bot ván, bản này chưa xử lý); tin riêng
// vẫn đi bằng 3i.
func TestEmulatorGameTgBotOutboxSendsGroupViaGameBot(t *testing.T) {
	e := newOutboxEnv(t)
	m := NewManagedBotService(e.db, e.tg.service(""), "Run3IBot", mybotRoot, "https://api.test", nil)
	e.store.groupBot = m.gameOutbox
	tok := e.tg.addManaged(9001)
	seed(t, e.db, "managedBots/9001", map[string]any{"kind": managedKindGame, "uid": "an", "ownerTgId": int64(5001)})
	if _, err := e.db.Doc("games/"+outboxGame).Update(context.Background(), []firestore.Update{
		{Path: "botId", Value: "9001"}, {Path: "testMode", Value: true}}); err != nil {
		t.Fatal(err)
	}
	reminder := gameMsg{ChatKey: chatGroup, Template: tplReminder, Data: map[string]any{
		"reason": werewolf.ReminderVote, "deadline": e.now().Add(time.Hour)}}
	e.write(reminder, noteMsg(dmChat("u1"), werewolf.KindGuard))
	if res := e.flush(); res.Sent != 2 {
		t.Fatalf("flush = %+v", res)
	}

	group := e.tg.CallsBy(tok, "sendMessage")
	if len(group) != 1 {
		t.Fatalf("bot ván gửi = %+v", e.tg.Calls("sendMessage"))
	}
	p := group[0].Params
	if p["chat_id"] != "-100g" || p["message_thread_id"] != float64(5) || p["reply_markup"] != nil {
		t.Fatalf("tin group = %v", p)
	}
	dm := e.tg.CallsBy(fakeTelegramToken, "sendMessage")
	if len(dm) != 1 || dm[0].Params["chat_id"] != "71" {
		t.Fatalf("3i gửi = %+v", dm)
	}
}

// Ván ở group riêng: người chơi không cần ở PSC để đăng ký, không bị loại vì
// PSC; lúc Start bot ván hỏi Telegram ai còn ở group của ván, 3i không hỏi gì.
func TestEmulatorGameTgBotStartChecksGameGroup(t *testing.T) {
	e := newStartEnv(t)
	m := NewManagedBotService(e.store.db, e.tg.service("-100psc"), "Run3IBot", mybotRoot, "https://api.test", e.publish)
	e.store.groupBot = m.gameOutbox
	e.bot = NewBotServer(Config{GameInboundQueue: "game-inbound"}, &Dependencies{Firestore: e.store.db, Games: e.store,
		TelegramLinks: e.deps.TelegramLinks, Telegram: e.tg.service("-100psc"), EnqueueTask: e.publish, ManagedBots: m})
	tok := e.tg.addManaged(9001)
	seed(t, e.store.db, "gameBots/boss", map[string]any{"botId": "9001", "username": "van_boss_bot"})
	seed(t, e.store.db, "managedBots/9001", map[string]any{"kind": managedKindGame, "uid": "boss", "ownerTgId": int64(6999), "username": "van_boss_bot"})
	seed(t, e.store.db, "managedBots/9001/chats/-100777", map[string]any{"status": "administrator", "topics": map[string]any{"42": map[string]any{"name": "Ma Sói"}}})
	r := e.call("boss", "POST", "/v1/games", map[string]any{"roles": map[string]bool{"cupid": false},
		"telegram": map[string]any{"chatId": "-100777", "threadId": 42}}, "")
	e.want(r, 201, "")
	id := r.body["id"].(string)
	for i := 1; i <= 12; i++ {
		linkUser(t, e.apiHarness, userOf(i), tgOf(i), false)
		e.want(e.call(userOf(i), "POST", "/v1/games/"+id+"/registration", nil, ""), 200, "")
	}

	r = e.call("boss", "POST", "/v1/games/"+id+"/start?dryRun=true", nil, "")
	var preview StartPreview
	if err := json.Unmarshal(r.raw, &preview); err != nil || len(preview.WillExclude) != 0 || preview.Count != 12 {
		t.Fatalf("preview = %s", r.raw)
	}
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
	var replies []tgReply
	for i := 1; i <= 12; i++ {
		st := "member"
		if i == 5 {
			st = "left"
		}
		replies = append(replies, memberReply(st))
	}
	e.tg.Then("getChatMember", replies...)
	rec := e.runTask(e.tasksTo("/tasks/game-start")[0])
	var out StartOutcome
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code != 200 || out.Result != "started" || len(out.Excluded) != 1 || out.Excluded[0].UID != "u05" || out.Excluded[0].Reason != "not_in_group" {
		t.Fatalf("game-start: %d %s", rec.Code, rec.Body)
	}
	asked := e.tg.CallsBy(tok, "getChatMember")
	if len(asked) != 12 || asked[0].Params["chat_id"] != "-100777" || len(e.tg.CallsBy(fakeTelegramToken, "getChatMember")) != 0 {
		t.Fatalf("getChatMember = %+v", e.tg.Calls("getChatMember"))
	}
}

// Ván của bot ván không ở PSC: inPsc false không làm ai rời ván; mất liên kết
// (xoá tài khoản) thì vẫn tính là rời.
func TestEmulatorGameTgBotLeftIgnoresPsc(t *testing.T) {
	g := newStoreGame(t)
	ctx := context.Background()
	if _, err := g.db.Doc("games/"+g.id).Update(ctx, []firestore.Update{{Path: "botId", Value: "9001"}}); err != nil {
		t.Fatal(err)
	}
	seed(t, g.db, "tgLinks/"+g.tg["v2"], map[string]any{"uid": "v2", "inPsc": false})
	if _, err := g.db.Doc("tgLinks/" + g.tg["w1"]).Delete(ctx); err != nil {
		t.Fatal(err)
	}
	night := g.start.NightAt
	g.advance(night.Add(time.Minute))
	g.advance(night.Add(12*time.Hour + time.Minute))
	st := g.state()
	if p := st.Players["v2"]; p.Cause == werewolf.CauseLeft {
		t.Fatalf("v2 = %+v, ván bot ván không xét PSC", p)
	}
	if p := st.Players["w1"]; p.Alive || p.Cause != werewolf.CauseLeft {
		t.Fatalf("w1 = %+v, mất liên kết thì vẫn rời", p)
	}
}
