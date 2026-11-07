//go:build emulator

package backend

import (
	"context"
	"strings"
	"testing"
	"time"
)

const liveCardID = "runnow-1785619792289"

func liveCardEnv(t *testing.T) (*fakeTelegram, *ActivityService) {
	t.Helper()
	db := emulatorDB(t)
	tg := newFakeTelegram(t)
	acts := NewActivityService(db, nil, nil, nil, tg.service(testPscChat), "", "https://web.test")
	seed(t, db, "users/an", map[string]any{"profileVisibility": "public", "displayName": "An"})
	return tg, acts
}

func lastEdit(t *testing.T, tg *fakeTelegram) tgCall {
	t.Helper()
	edits := tg.Calls("editMessageText")
	if len(edits) == 0 {
		t.Fatal("thẻ chưa được sửa lần nào")
	}
	return edits[len(edits)-1]
}

// Cả buổi live chỉ có một tin: bắt đầu gửi thẻ, các mốc và về đích sửa thẻ.
// Mốc tới trễ không kéo số trên thẻ lùi lại, và gọi lại một sự kiện đã báo thì
// không sửa thêm.
func TestEmulatorLiveCardIsOneMessage(t *testing.T) {
	ctx := context.Background()
	tg, acts := liveCardEnv(t)
	announce := func(event string, meters, seconds float64, km int) {
		t.Helper()
		if err := acts.LiveAnnounce(ctx, "an", liveCardID, event, meters, seconds, km, ""); err != nil {
			t.Fatal(err)
		}
	}

	announce(liveEventStart, 400, 120, 0)
	sends := tg.Calls("sendMessage")
	if len(sends) != 1 {
		t.Fatalf("bắt đầu gửi %d tin", len(sends))
	}
	card := sends[0].Params
	text, _ := card["text"].(string)
	if card["parse_mode"] != "HTML" || !strings.HasPrefix(text, "<b>An</b> · 🟢 Đang chạy\n📏 0.40 km · ⏱ 02:00") {
		t.Fatalf("thẻ lúc bắt đầu = %v", card)
	}
	rows := card["reply_markup"].(map[string]any)["inline_keyboard"].([]any)
	cheers, open := rows[0].([]any), rows[1].([]any)
	if len(cheers) != 5 || cheers[1].(map[string]any)["text"] != "🔥" || cheers[1].(map[string]any)["callback_data"] != "l1|"+liveCardID+"|1" {
		t.Fatalf("hàng nút cổ vũ = %v", cheers)
	}
	if open[0].(map[string]any)["url"] != "https://web.test/live/"+liveCardID {
		t.Fatalf("nút mở live = %v", open)
	}

	announce(liveEventMilestone, 2000, 700, 2)
	edit := lastEdit(t, tg).Params
	if edit["message_id"] != float64(1) || !strings.Contains(edit["text"].(string), "📏 2.00 km · ⏱ 11:40 · ⚡ 5:50/km") {
		t.Fatalf("thẻ ở mốc 2km = %v", edit)
	}

	announce(liveEventMilestone, 1000, 330, 1)
	if text := lastEdit(t, tg).Params["text"].(string); !strings.Contains(text, "2.00 km") {
		t.Fatalf("mốc 1km tới trễ kéo thẻ lùi: %q", text)
	}

	announce(liveEventFinish, 2500, 900, 0)
	if text := lastEdit(t, tg).Params["text"].(string); !strings.HasPrefix(text, "<b>An</b> · 🏁 Về đích\n📏 2.50 km") {
		t.Fatalf("thẻ lúc về đích = %q", text)
	}
	edits := len(tg.Calls("editMessageText"))
	announce(liveEventFinish, 2500, 900, 0)
	announce(liveEventMilestone, 3000, 1000, 3)
	if text := lastEdit(t, tg).Params["text"].(string); !strings.Contains(text, "🏁 Về đích\n📏 2.50 km") {
		t.Fatalf("mốc sau về đích đổi thẻ: %q", text)
	}
	if got := len(tg.Calls("sendMessage")); got != 1 {
		t.Fatalf("cả buổi gửi %d tin, muốn 1", got)
	}
	if got := len(tg.Calls("editMessageText")); got != edits+1 {
		t.Fatalf("gọi lại về đích vẫn sửa thẻ: %d lần sửa, muốn %d", got, edits+1)
	}
}

// Topic Live Track bị xoá thì thẻ gửi lại ra General, và thẻ đó vẫn là thẻ
// được sửa ở các mốc sau.
func TestEmulatorLiveCardFallsBackWhenTopicGone(t *testing.T) {
	ctx := context.Background()
	tg, acts := liveCardEnv(t)
	seed(t, acts.db, "appConfig/telegram", map[string]any{"liveTrackThreadId": int64(liveTrackTopic)})
	tg.Then("sendMessage", tgBadRequest("Bad Request: message thread not found"))
	if err := acts.LiveAnnounce(ctx, "an", liveCardID, liveEventStart, 400, 120, 0, ""); err != nil {
		t.Fatal(err)
	}
	sends := tg.Calls("sendMessage")
	if len(sends) != 2 || sends[0].Params["message_thread_id"] != float64(liveTrackTopic) || sends[1].Params["message_thread_id"] != nil {
		t.Fatalf("gửi thẻ = %+v", sends)
	}
	if err := acts.LiveAnnounce(ctx, "an", liveCardID, liveEventMilestone, 2000, 700, 2, ""); err != nil {
		t.Fatal(err)
	}
	if got := len(tg.Calls("sendMessage")); got != 2 {
		t.Fatalf("mốc 2km gửi tin mới: %d tin", got)
	}
	if edit := lastEdit(t, tg).Params; edit["message_id"] != float64(1) {
		t.Fatalf("sửa thẻ = %v", edit)
	}
}

// Hai sự kiện tới khi thẻ chưa gửi xong: chỉ task đầu được gửi, task sau chỉ
// ghi nội dung. Task gửi chết quá liveCardSendLease thì sự kiện sau gửi lại.
func TestEmulatorLiveCardSendClaim(t *testing.T) {
	ctx := context.Background()
	db := emulatorDB(t)
	ref := db.Collection("liveAnnounceState").Doc(liveCardID)
	now := time.Date(2026, 11, 1, 6, 0, 0, 0, vietnam)
	claim := func(marker string, meters float64, at time.Time) (bool, bool) {
		t.Helper()
		claimed, send, err := claimLiveCardEvent(ctx, db, ref, marker, map[string]any{marker: true}, liveCardContent{name: "An", meters: meters}, at)
		if err != nil {
			t.Fatal(err)
		}
		return claimed, send
	}
	if claimed, send := claim("start", 400, now); !claimed || !send {
		t.Fatalf("sự kiện đầu: claimed=%v send=%v", claimed, send)
	}
	if claimed, send := claim("km-2", 2000, now.Add(5*time.Second)); !claimed || send {
		t.Fatalf("sự kiện khi đang gửi: claimed=%v send=%v", claimed, send)
	}
	if claimed, _ := claim("km-2", 2000, now.Add(6*time.Second)); claimed {
		t.Fatal("cùng sự kiện được claim hai lần")
	}
	if claimed, send := claim("km-4", 4000, now.Add(31*time.Second)); !claimed || !send {
		t.Fatalf("task gửi đã chết: claimed=%v send=%v", claimed, send)
	}
	card, _ := getData(ctx, ref)
	if c := card["card"].(map[string]any); c["meters"] != 4000.0 || c["version"] != int64(3) {
		t.Fatalf("state thẻ = %v", c)
	}
}

// Bấm emoji trên thẻ: tài khoản đã liên kết thì ghi cổ vũ như trong app và hẹn
// sửa thẻ; lần sửa sau hiện số đã bấm và trạng thái buổi live.
func TestEmulatorLiveCardCheerFromTelegram(t *testing.T) {
	ctx := context.Background()
	e := newMybotEnv(t)
	db := e.store.db
	acts := NewActivityService(db, nil, nil, nil, e.tg.service(testPscChat), "", "")
	seed(t, db, "users/an", map[string]any{"profileVisibility": "public", "displayName": "An"})
	linkUser(t, e.apiHarness, "cuong", "5001", true)
	if err := acts.LiveAnnounce(ctx, "an", liveCardID, liveEventStart, 400, 120, 0, ""); err != nil {
		t.Fatal(err)
	}
	press := func(updateID, from int64, data string) string {
		t.Helper()
		r := e.manager(map[string]any{"update_id": updateID, "callback_query": map[string]any{
			"id": "cq", "from": map[string]any{"id": from}, "data": data,
		}})
		if r.status != 200 || r.body["method"] != "answerCallbackQuery" {
			t.Fatalf("webhook = %d %s", r.status, r.raw)
		}
		return r.body["text"].(string)
	}
	fire := "l1|" + liveCardID + "|1"

	if got := press(201, 9999, fire); got != "Liên kết Telegram trong app 3i Run để cổ vũ nhé." {
		t.Fatalf("người chưa liên kết bấm: %q", got)
	}
	for id := int64(202); id <= 203; id++ {
		if got := press(id, 5001, fire); got != "Đã gửi 🔥 cho An" {
			t.Fatalf("Cường bấm 🔥: %q", got)
		}
	}
	if got := press(204, 5001, "l1|runnow-1|0"); got != "Buổi live này không còn nhận cổ vũ." {
		t.Fatalf("bấm thẻ không có trong state: %q", got)
	}
	if got := press(205, 5001, "l1|"+liveCardID+"|9"); got != "Nút này chưa dùng được." {
		t.Fatalf("nút hỏng: %q", got)
	}

	cheer := e.fsDoc("liveCheers/" + liveCardID + "/by/cuong")
	if cheer["uid"] != "cuong" || cheer["emoji"] != "🔥" || cheer["n"].(map[string]any)["🔥"] != int64(2) || cheer["at"] == nil {
		t.Fatalf("cổ vũ của Cường = %v", cheer)
	}
	if docs, _ := db.Collection("liveCheers").Doc(liveCardID).Collection("by").Documents(ctx).GetAll(); len(docs) != 1 {
		t.Fatal("người chưa liên kết vẫn ghi được cổ vũ")
	}
	refresh := e.tasksTo("/tasks/live-card")
	if len(refresh) == 0 || refresh[0].Queue != QueueBotInbound || refresh[0].ScheduleTime == nil || refresh[0].Payload.(map[string]any)["activityId"] != liveCardID {
		t.Fatalf("task sửa thẻ = %+v", refresh)
	}

	seed(t, db, "liveSessions/"+liveCardID, map[string]any{"status": "paused"})
	if err := acts.SyncLiveCard(ctx, liveCardID); err != nil {
		t.Fatal(err)
	}
	edit := lastEdit(t, e.tg).Params
	fireButton := edit["reply_markup"].(map[string]any)["inline_keyboard"].([]any)[0].([]any)[1].(map[string]any)
	if fireButton["text"] != "🔥 2" || !strings.HasPrefix(edit["text"].(string), "<b>An</b> · ⏸ Tạm dừng") {
		t.Fatalf("thẻ sau cổ vũ = %v", edit)
	}
}
