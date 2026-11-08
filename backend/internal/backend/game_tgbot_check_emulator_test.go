//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Mở màn chọn thì app hẹn kiểm: bot hỏi Telegram trạng thái của nó ở từng
// group đã ghi. Group không còn thì biến khỏi danh sách, bị hạ quyền thì không
// còn admin. Gọi kiểm hai lần trong một phút chỉ hỏi Telegram một lần.
func TestEmulatorGameTgBotCheckRefreshesChats(t *testing.T) {
	e := newMybotEnv(t)
	tok := e.linkGameBot("an", "5001", 9001)
	for i, chat := range []int64{-100555, -100777, -100999} {
		e.child(9001, memberUpd(int64(i+1), chat, 5001, "administrator", "Nhóm"))
	}
	e.drain()
	hooks := len(e.tg.CallsBy(tok, "setWebhook"))

	// Firestore trả doc theo ID: -100555, -100777, -100999.
	e.tg.Then("getChatMember", tgBadRequest("Bad Request: chat not found"), memberReply("administrator"), memberReply("member"))
	e.want(e.call("an", "POST", "/v1/games/telegram/check", nil, ""), 202, "")
	e.want(e.call("an", "POST", "/v1/games/telegram/check", nil, ""), 202, "")
	e.drain()

	if n := len(e.tg.CallsBy(tok, "getChatMember")); n != 3 {
		t.Fatalf("getChatMember = %d lần, muốn 3", n)
	}
	if n := len(e.tg.CallsBy(tok, "setWebhook")); n != hooks+1 {
		t.Fatalf("setWebhook %d → %d, muốn đúng một lần kiểm", hooks, n)
	}
	chats := e.gameChats("an")
	if chats["-100555"] != nil {
		t.Fatalf("group không còn vẫn hiện: %v", chats)
	}
	if c := chats["-100777"]; c == nil || c["admin"] != true {
		t.Fatalf("group còn admin: %v", chats)
	}
	if c := chats["-100999"]; c == nil || c["admin"] != false {
		t.Fatalf("group bị hạ quyền vẫn là admin: %v", chats)
	}
}

// Group đang có ván chưa kết thúc thì danh sách chọn đánh dấu busy; ván kết
// thúc thì group rảnh lại.
func TestEmulatorGameTgBotMarksBusyChats(t *testing.T) {
	e := newMybotEnv(t)
	e.linkGameBot("an", "5001", 9001)
	e.child(9001, memberUpd(1, -100777, 5001, "administrator", "Nhóm chạy"))
	e.child(9001, memberUpd(2, -100999, 5001, "administrator", "Nhóm phụ"))
	e.child(9001, vanMsg(3, -100777, 5001, 42, "/van", "Ma Sói"))
	r := e.call("an", "POST", "/v1/games", map[string]any{"telegram": map[string]any{"chatId": "-100777", "threadId": 42}}, "")
	if r.status != 201 {
		t.Fatalf("tạo ván: %d %s", r.status, r.raw)
	}
	chats := e.gameChats("an")
	if chats["-100777"]["busy"] != true || chats["-100999"]["busy"] != false {
		t.Fatalf("busy = %v / %v", chats["-100777"]["busy"], chats["-100999"]["busy"])
	}
	if _, err := e.store.db.Doc("games/"+stringValue(r.body["id"])).Update(context.Background(), []firestore.Update{{Path: "status", Value: gameEnded}}); err != nil {
		t.Fatal(err)
	}
	if busy := e.gameChats("an")["-100777"]["busy"]; busy != false {
		t.Fatalf("ván kết thúc mà group vẫn busy")
	}
}

// Bot đang lỗi (Sync ghi setupError, vd bot đã bị xoá) thì không tạo được ván.
func TestEmulatorGameTgBotBrokenBotBlocksCreate(t *testing.T) {
	e := newMybotEnv(t)
	e.linkGameBot("an", "5001", 9001)
	e.child(9001, memberUpd(1, -100777, 5001, "administrator", "Nhóm chạy"))
	e.child(9001, vanMsg(2, -100777, 5001, 42, "/van", "Ma Sói"))
	seed(t, e.store.db, "gameBots/an", map[string]any{"botId": "9001", "username": "van_an_bot", "setupError": "Unauthorized"})
	r := e.call("an", "POST", "/v1/games", map[string]any{"telegram": map[string]any{"chatId": "-100777", "threadId": 42}}, "")
	if r.status != 422 || r.body["message"] != errGameBotBroken.Message {
		t.Fatalf("tạo ván với bot lỗi: %d %s", r.status, r.raw)
	}
}

// Bot ván gửi vào group của ván mà topic đã bị xoá thì topic biến khỏi danh
// sách chọn; group không còn hay bot bị kick thì cả group biến khỏi danh sách.
func TestEmulatorGameTgBotOutboxDropsGoneTarget(t *testing.T) {
	for _, c := range []struct {
		name      string
		reply     tgReply
		wantChat  bool
		wantTopic bool
	}{
		{"topic xoá", tgBadRequest("Bad Request: message thread not found"), true, false},
		{"bot bị kick", tgForbidden("Forbidden: bot was kicked from the supergroup chat"), false, false},
		{"lỗi khác", tgBadRequest("Bad Request: can't parse entities"), true, true},
	} {
		t.Run(c.name, func(t *testing.T) {
			e := newOutboxEnv(t)
			m := NewManagedBotService(e.db, e.tg.service(""), "Run3IBot", mybotRoot, "https://api.test", nil)
			e.store.gameBot = m.gameOutbox
			e.tg.addManaged(9001)
			seed(t, e.db, "managedBots/9001", map[string]any{"kind": managedKindGame, "uid": "an", "ownerTgId": int64(5001)})
			seed(t, e.db, "managedBots/9001/chats/-100g", map[string]any{"status": "administrator",
				"topics": map[string]any{"5": map[string]any{"name": "Ma Sói"}, "9": map[string]any{"name": "Khác"}}})
			if _, err := e.db.Doc("games/"+outboxGame).Update(context.Background(), []firestore.Update{{Path: "botId", Value: "9001"}, {Path: "testMode", Value: true}}); err != nil {
				t.Fatal(err)
			}
			e.write(gameMsg{ChatKey: chatGroup, Template: tplReminder, Data: map[string]any{
				"reason": werewolf.ReminderVote, "deadline": e.now().Add(time.Hour)}})
			e.tg.Then("sendMessage", c.reply)
			_, _ = e.flushCtx(context.Background())

			snap, err := e.db.Doc("managedBots/9001/chats/-100g").Get(context.Background())
			if err != nil {
				t.Fatal(err)
			}
			d := snap.Data()
			if inChat := d["status"] == "administrator"; inChat != c.wantChat {
				t.Fatalf("status = %v", d["status"])
			}
			topics, _ := d["topics"].(map[string]any)
			if _, ok := topics["5"]; ok != c.wantTopic {
				t.Fatalf("topics = %v", topics)
			}
			if _, ok := topics["9"]; ok != c.wantChat {
				t.Fatalf("topic khác bị gỡ sai: %v", topics)
			}
		})
	}
}
