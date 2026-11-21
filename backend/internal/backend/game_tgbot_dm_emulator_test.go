//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// gameBotButtons: ván đang ở đêm 1 (buttonEnv) chuyển sang bot ván 9001. Trả
// service Managed Bots để gửi update vào webhook của bot ván.
func gameBotButtons(t *testing.T) (*buttonEnv, *ManagedBotService) {
	t.Helper()
	e := newButtonEnv(t)
	m := NewManagedBotService(e.db, e.tg.service(""), "Run3IBot", mybotRoot, "https://api.test", e.h.deps.EnqueueTask)
	e.h.deps.ManagedBots = m
	seed(t, e.db, "managedBots/9001", map[string]any{"kind": managedKindGame, "uid": "boss", "ownerTgId": int64(6999), "username": "van_boss_bot"})
	seedMerge(t, e.storeGame, map[string]any{"botId": "9001"})
	return e, m
}

// toGameBot chạy một update qua webhook của bot ván botID; trả response webhook.
func (e *buttonEnv) toGameBot(m *ManagedBotService, botID string, update map[string]any) map[string]any {
	e.t.Helper()
	raw, _ := json.Marshal(update)
	out, err := e.srv.routeChildUpdate(context.Background(), m, botID, raw)
	if err != nil {
		e.t.Fatalf("webhook bot %s: %v", botID, err)
	}
	return out
}

func cbUpd(updateID int64, tg, data string) map[string]any {
	return map[string]any{"update_id": updateID, "callback_query": map[string]any{
		"id": fmt.Sprintf("cq-%d", updateID), "from": map[string]any{"id": mustInt(tg)}, "data": data}}
}

// Nút của ván bot ván chỉ tính khi bấm trong tin của bot đó: bấm qua 3i thì
// báo nút của quản trò khác và không ghi gì; qua bot ván thì ghi lựa chọn.
// update_id đếm riêng từng bot, nên chặn bấm lại vẫn đúng trong một bot.
func TestEmulatorGameBotButtonsOnlyViaOwnBot(t *testing.T) {
	e, m := gameBotButtons(t)
	bite := e.btn(ww.KindWolfBite, opPick, "v1")
	w1 := e.storeGame.tg["w1"]

	if text, _ := e.press(w1, bite); text != buttonTexts.otherHost {
		t.Fatalf("bấm qua 3i = %q", text)
	}
	if n := e.actionCount(1, "w1"); n != 0 {
		t.Fatalf("bấm qua 3i vẫn ghi %d action", n)
	}
	if other := e.toGameBot(m, "9001", cbUpd(5, w1, bite)); other["text"] != "Đã chọn V1." {
		t.Fatalf("bấm qua bot ván = %v", other)
	}
	if n := e.actionCount(1, "w1"); n != 1 {
		t.Fatalf("bot ván ghi %d action", n)
	}

	seed(t, e.db, "managedBots/9002", map[string]any{"kind": managedKindGame, "uid": "an", "ownerTgId": int64(5001), "username": "van_an_bot"})
	if r := e.toGameBot(m, "9002", cbUpd(6, w1, bite)); r["text"] != buttonTexts.otherHost {
		t.Fatalf("bấm qua bot ván khác = %v", r)
	}
}

// Nhắn riêng bot ván thì ghi chat riêng đã mở; chặn bot thì ghi đã đóng. /vai
// ở bot ván chỉ trả lá bài của ván do bot đó quản trò.
func TestEmulatorGameBotDMAndCard(t *testing.T) {
	e, m := gameBotButtons(t)
	w1 := e.storeGame.tg["w1"]
	dmOpen := func() any {
		snap, err := e.db.Doc("managedBots/9001/dms/" + w1).Get(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		return snap.Data()["open"]
	}

	if r := e.toGameBot(m, "9001", dmUpd(1, mustInt(w1), "/start van")); r["text"] != gameBotStartText || r["chat_id"] != mustInt(w1) {
		t.Fatalf("/start = %v", r)
	}
	if dmOpen() != true {
		t.Fatal("/start chưa ghi chat riêng đã mở")
	}
	r := e.toGameBot(m, "9001", dmUpd(2, mustInt(w1), "/vai"))
	if text, _ := r["text"].(string); r["parse_mode"] != "HTML" || !strings.Contains(text, "<b>Sói</b>") {
		t.Fatalf("/vai ở bot ván = %v", r)
	}

	seed(t, e.db, "managedBots/9002", map[string]any{"kind": managedKindGame, "uid": "an", "ownerTgId": int64(5001), "username": "van_an_bot"})
	if r := e.toGameBot(m, "9002", dmUpd(3, mustInt(w1), "/vai")); r["text"] != "Bạn chưa ở trong ván Ma Sói nào của quản trò này." {
		t.Fatalf("/vai ở bot ván khác = %v", r)
	}
	if _, body := e.webhook(fmt.Sprintf(`{"update_id":4,"message":{"message_id":1,"text":"/vai","chat":{"id":%s,"type":"private"},"from":{"id":%s}}}`, w1, w1)); body["text"] != "Bạn chưa ở trong ván Ma Sói nào của quản trò này." {
		t.Fatalf("/vai ở 3i với ván bot ván = %v", body)
	}

	blocked := map[string]any{"update_id": 5, "my_chat_member": map[string]any{
		"chat":            map[string]any{"id": mustInt(w1), "type": "private"},
		"from":            map[string]any{"id": mustInt(w1), "is_bot": false, "first_name": "W1"},
		"date":            1,
		"old_chat_member": map[string]any{"status": "member", "user": map[string]any{"id": 9001, "is_bot": true}},
		"new_chat_member": map[string]any{"status": "kicked", "user": map[string]any{"id": 9001, "is_bot": true}},
	}}
	e.toGameBot(m, "9001", blocked)
	if dmOpen() != false {
		t.Fatal("chặn bot mà chat riêng vẫn mở")
	}
}
