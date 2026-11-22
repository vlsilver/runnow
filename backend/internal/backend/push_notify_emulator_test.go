//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"testing"
	"time"
)

func sentTokens(f *fakePushSender) []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []string
	for _, m := range f.sent {
		out = append(out, m.Token)
	}
	return out
}

func lastSent(t *testing.T, f *fakePushSender) (title string, data map[string]string) {
	t.Helper()
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.sent) == 0 {
		t.Fatal("chưa gửi push nào")
	}
	m := f.sent[len(f.sent)-1]
	return m.Notification.Title, m.Data
}

func prefsView(t *testing.T, r apiResp) PushPrefsView {
	t.Helper()
	if r.status != 200 {
		t.Fatalf("status %d %s", r.status, r.raw)
	}
	var v PushPrefsView
	if err := json.Unmarshal(r.raw, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

// Tắt một nhóm thì không nhận push của nhóm đó, vẫn nhận nhóm khác; nhóm lạ bị
// từ chối mà cài đặt cũ giữ nguyên.
func TestEmulatorPushPrefsFilterByGroup(t *testing.T) {
	h := newRoomHarness(t)
	push, sender := newFakePush(h.store.db)
	h.deps.Push = push
	h.want(h.call("u1", "PUT", "/v1/push-token", map[string]any{"token": "tok-u1", "platform": "ios"}, ""), 200, "")

	view := prefsView(t, h.call("u1", "GET", "/v1/me/push-prefs", nil, ""))
	if len(view.Groups) != 5 || !view.Groups[0].On || view.Groups[0].ID != "live" {
		t.Fatalf("mặc định phải bật hết: %+v", view)
	}
	view = prefsView(t, h.call("u1", "PUT", "/v1/me/push-prefs", map[string]any{"off": []string{"live", "live"}}, ""))
	if view.Groups[0].On || !view.Groups[1].On {
		t.Fatalf("chỉ live tắt: %+v", view)
	}
	h.want(h.call("u1", "PUT", "/v1/me/push-prefs", map[string]any{"off": []string{"spam"}}, ""), 400, "")

	ctx := context.Background()
	if err := push.Send(ctx, []string{"u1"}, pushNote{Title: "live", Data: map[string]string{"kind": livePushKind}}); err != nil {
		t.Fatal(err)
	}
	if err := push.Send(ctx, []string{"u1"}, pushNote{Title: "room", Data: map[string]string{"kind": "room_request"}}); err != nil {
		t.Fatal(err)
	}
	if got := sentTokens(sender); len(got) != 1 {
		t.Fatalf("live đã tắt mà vẫn gửi, hoặc room bị chặn: %v", got)
	}
	if title, _ := lastSent(t, sender); title != "room" {
		t.Fatalf("push gửi đi phải là room, được %q", title)
	}
}

// Live: cả club nhận trừ người chạy và người đã tắt live; buổi không cho club
// xem hay đã về đích thì không báo.
func TestEmulatorLivePushToClub(t *testing.T) {
	h := newRoomHarness(t)
	push, sender := newFakePush(h.store.db)
	h.deps.Push = push
	for _, uid := range []string{"runner", "fan", "quiet"} {
		h.want(h.call(uid, "PUT", "/v1/push-token", map[string]any{"token": "tok-" + uid, "platform": "android"}, ""), 200, "")
	}
	h.want(h.call("quiet", "PUT", "/v1/me/push-prefs", map[string]any{"off": []string{"live"}}, ""), 200, "")
	seed(t, h.store.db, "publicProfiles/runner", map[string]any{"nickname": "Nâu", "profileVisibility": "public"})
	seed(t, h.store.db, "liveSessions/act1", map[string]any{"ownerUid": "runner", "visibility": "club", "status": "running"})

	ctx, db := context.Background(), h.store.db
	if err := DeliverLivePush(ctx, db, push, livePushTask{UID: "runner", ActivityID: "act1"}); err != nil {
		t.Fatal(err)
	}
	if got := sentTokens(sender); len(got) != 1 || got[0] != "tok-fan" {
		t.Fatalf("chỉ fan nhận, được %v", got)
	}
	// Task chạy lại (Cloud Tasks gửi lại, app báo start lần nữa) thì không báo
	// thêm lần nào.
	if err := DeliverLivePush(ctx, db, push, livePushTask{UID: "runner", ActivityID: "act1"}); err != nil {
		t.Fatal(err)
	}
	if got := sentTokens(sender); len(got) != 1 {
		t.Fatalf("một buổi chỉ báo một lần, được %v", got)
	}
	title, data := lastSent(t, sender)
	if title != "Nâu đang chạy live" || data["sessionId"] != "act1" || data["kind"] != livePushKind {
		t.Fatalf("nội dung sai: %q %v", title, data)
	}

	seed(t, h.store.db, "liveSessions/act2", map[string]any{"ownerUid": "runner", "visibility": "private", "status": "running"})
	seed(t, h.store.db, "liveSessions/act3", map[string]any{"ownerUid": "runner", "visibility": "club", "status": "finished"})
	for _, id := range []string{"act2", "act3", "missing"} {
		if err := DeliverLivePush(ctx, db, push, livePushTask{UID: "runner", ActivityID: id}); err != nil {
			t.Fatal(err)
		}
	}
	if got := sentTokens(sender); len(got) != 1 {
		t.Fatalf("buổi riêng tư, đã xong hay không có thì không báo: %v", got)
	}
}

// Top 3: hạng 2, 3 không quà nhận push hạng của mình; hạng 1 có quà (đã có push
// quà) và hạng 4 thì không.
func TestEmulatorRankTopPush(t *testing.T) {
	h := newRoomHarness(t)
	push, sender := newFakePush(h.store.db)
	h.deps.Push = push
	entries := []map[string]any{
		{"uid": "a", "rank": 1, "reward": map[string]any{"name": "Áo"}},
		{"uid": "b", "rank": 2},
		{"uid": "c", "rank": 3},
		{"uid": "d", "rank": 4},
	}
	if got := rankTopPushUIDs(entries); len(got) != 2 || got[0] != "b" || got[1] != "c" {
		t.Fatalf("người nhận top 3: %v", got)
	}
	boardID := "week_2026-11-16_run"
	raw := make([]any, len(entries))
	for i, e := range entries {
		raw[i] = e
	}
	seed(t, h.store.db, "rankBoards/"+boardID, map[string]any{"entries": raw})
	for _, uid := range []string{"a", "b", "d"} {
		h.want(h.call(uid, "PUT", "/v1/push-token", map[string]any{"token": "tok-" + uid, "platform": "ios"}, ""), 200, "")
		if err := DeliverRankTopPush(context.Background(), h.store.db, push, rankTopPushTask{BoardID: boardID, UID: uid}); err != nil {
			t.Fatal(err)
		}
	}
	if got := sentTokens(sender); len(got) != 1 || got[0] != "tok-b" {
		t.Fatalf("chỉ b nhận: %v", got)
	}
	if title, data := lastSent(t, sender); title != "Bạn hạng 2 BXH tuần chạy bộ" || data["boardId"] != boardID {
		t.Fatalf("nội dung sai: %q %v", title, data)
	}
}

// Đã trao: SetGiven chỉ báo marked ở lần ghi givenAt; push đi khi còn chờ nhận,
// người trúng đã bấm nhận thì thôi.
func TestEmulatorGiftGivenPush(t *testing.T) {
	h := newRoomHarness(t)
	push, sender := newFakePush(h.store.db)
	h.deps.Push = push
	ctx, db := context.Background(), h.store.db
	now := time.Date(2026, 11, 22, 3, 0, 0, 0, time.UTC)
	h.want(h.call("win", "PUT", "/v1/push-token", map[string]any{"token": "tok-win", "platform": "ios"}, ""), 200, "")

	seed(t, h.store.db, "gameState/config", map[string]any{"adminUids": []any{"admin"}})
	board := "month_2026-10-01_run"
	seed(t, h.store.db, "users/win/rankCards/"+board, map[string]any{"reward": map[string]any{"name": "Áo 3i", "givenAt": nil, "receivedAt": nil}})
	rewards := NewRankRewardService(db, nil)
	marked, err := rewards.SetGiven(ctx, "admin", board, "win", true, now)
	if err != nil || !marked {
		t.Fatalf("lần trao đầu phải marked: %v %v", marked, err)
	}
	if marked, err := rewards.SetGiven(ctx, "admin", board, "win", true, now.Add(time.Minute)); err != nil || marked {
		t.Fatalf("bấm lại không được báo lần nữa: %v %v", marked, err)
	}
	if err := DeliverGiftGivenPush(ctx, db, push, giftGivenTask(giftFromRank, board, "win", now)); err != nil {
		t.Fatal(err)
	}
	if title, data := lastSent(t, sender); title != "Áo 3i đã được trao cho bạn" || data["boardId"] != board || data["kind"] != giftGivenPushKind {
		t.Fatalf("nội dung sai: %q %v", title, data)
	}
	if err := rewards.MarkReceived(ctx, "win", board, now.Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := DeliverGiftGivenPush(ctx, db, push, giftGivenTask(giftFromRank, board, "win", now)); err != nil {
		t.Fatal(err)
	}
	if got := sentTokens(sender); len(got) != 1 {
		t.Fatalf("đã nhận rồi thì không báo: %v", got)
	}

	seed(t, h.store.db, "contractGifts/k1", map[string]any{
		"creatorUid": "owner",
		"items":      []any{map[string]any{"id": "i1", "name": "Tất chạy", "slots": 1}},
		"winners":    []any{map[string]any{"uid": "win", "itemId": "i1", "givenAt": nil, "receivedAt": nil}},
	})
	gifts := NewContractGiftService(db, nil)
	if marked, err := gifts.SetGiven(ctx, "owner", "k1", "win", true, now); err != nil || !marked {
		t.Fatalf("quà kèo trao lần đầu phải marked: %v %v", marked, err)
	}
	if err := DeliverGiftGivenPush(ctx, db, push, giftGivenTask(giftFromContract, "k1", "win", now)); err != nil {
		t.Fatal(err)
	}
	if title, data := lastSent(t, sender); title != "Tất chạy đã được trao cho bạn" || data["contractId"] != "k1" {
		t.Fatalf("nội dung quà kèo sai: %q %v", title, data)
	}
}
