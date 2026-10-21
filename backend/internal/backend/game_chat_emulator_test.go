//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

func chatMessages(t *testing.T, r apiResp) []map[string]any {
	t.Helper()
	raw, _ := r.body["messages"].([]any)
	out := make([]map[string]any, len(raw))
	for i, m := range raw {
		out[i], _ = m.(map[string]any)
	}
	return out
}

// Chat Phe Sói: sói gửi, sói kia đọc kèm tên người gửi; người ngoài phe nhận
// 404 như chat không tồn tại, để không đoán được ai là sói.
func TestEmulatorGameChatWolves(t *testing.T) {
	g, h := runningAPIGame(t)
	path := "/v1/games/" + g.id + "/chats/wolves"
	h.want(h.call("w1", "POST", path, map[string]any{"text": "  cắn seer nhé  "}, ""), 200, "")

	r := h.call("w2", "GET", path, nil, "")
	h.want(r, 200, "")
	msgs := chatMessages(t, r)
	if len(msgs) != 1 || msgs[0]["text"] != "cắn seer nhé" || msgs[0]["uid"] != "w1" || msgs[0]["name"] != "W1" || msgs[0]["system"] == true {
		t.Fatalf("messages = %s", r.raw)
	}
	if r.body["canSend"] != true || r.body["label"] != "Phe Sói" {
		t.Fatalf("chat = %s", r.raw)
	}

	h.want(h.call("v1", "GET", path, nil, ""), 404, "chat_not_found")
	h.want(h.call("v1", "POST", path, map[string]any{"text": "xin vào"}, ""), 404, "chat_not_found")
	h.want(h.call("w1", "GET", "/v1/games/"+g.id+"/chats/lovers", nil, ""), 404, "chat_not_found")
	h.want(h.call("w1", "GET", "/v1/games/"+g.id+"/chats/group", nil, ""), 404, "chat_not_found")
}

func meChats(t *testing.T, h *apiHarness, id, uid string) string {
	t.Helper()
	r := h.call(uid, "GET", "/v1/games/"+id+"/me", nil, "")
	h.want(r, 200, "")
	raw, ok := r.body["chats"].([]any)
	if !ok {
		t.Fatalf("/me của %s thiếu chats: %s", uid, r.raw)
	}
	var out []string
	for _, c := range raw {
		m := c.(map[string]any)
		out = append(out, fmt.Sprintf("%s:%s:%v", m["key"], m["label"], m["canSend"]))
	}
	return strings.Join(out, "|")
}

// /me liệt kê chat của người gọi để app vẽ lối vào; người yêu là sói thì có cả
// hai chat. Chat Cặp đôi kín như chat Phe Sói.
func TestEmulatorGameChatLoversAndMe(t *testing.T) {
	g, h := runningAPIGame(t)
	editState(t, g, func(st *ww.State) { st.Lovers = []string{"seer", "w1"} })
	for uid, want := range map[string]string{
		"w1":   "wolves:Phe Sói:true|lovers:Cặp đôi:true",
		"w2":   "wolves:Phe Sói:true",
		"seer": "lovers:Cặp đôi:true",
		"v1":   "",
	} {
		if got := meChats(t, h, g.id, uid); got != want {
			t.Fatalf("/me chats của %s = %q, mong đợi %q", uid, got, want)
		}
	}
	path := "/v1/games/" + g.id + "/chats/lovers"
	h.want(h.call("seer", "POST", path, map[string]any{"text": "anh đây"}, ""), 200, "")
	if msgs := chatMessages(t, h.call("w1", "GET", path, nil, "")); len(msgs) != 1 || msgs[0]["text"] != "anh đây" {
		t.Fatalf("lovers = %v", msgs)
	}
	h.want(h.call("w2", "GET", path, nil, ""), 404, "chat_not_found")

	editState(t, g, func(st *ww.State) { st.Players["seer"].Alive = false })
	if got := meChats(t, h, g.id, "seer"); got != "lovers:Cặp đôi:false" {
		t.Fatalf("/me chats của người yêu đã chết = %q", got)
	}

	// Phe chỉ còn một sói (theo vai, không theo sống chết) thì không có chat.
	editState(t, g, func(st *ww.State) { st.Players["w2"].Role = ww.Villager })
	if got := meChats(t, h, g.id, "w1"); got != "lovers:Cặp đôi:true" {
		t.Fatalf("/me chats của sói duy nhất = %q", got)
	}
	h.want(h.call("w1", "GET", "/v1/games/"+g.id+"/chats/wolves", nil, ""), 404, "chat_not_found")
}

// editState sửa state trong secret doc, cho các ca khó dựng bằng luật chơi.
func editState(t *testing.T, g *storeGame, edit func(*ww.State)) {
	t.Helper()
	st := g.state()
	edit(st)
	raw, err := json.Marshal(st)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := secretRef(g.store.gameRef(g.id)).Set(context.Background(), map[string]any{"state": string(raw)}, firestore.MergeAll); err != nil {
		t.Fatal(err)
	}
}

func chatPings(t *testing.T, g *storeGame) []string {
	t.Helper()
	docs, err := g.db.Collection("games").Doc(g.id).Collection("outbox").Where("template", "==", tplChatPing).Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, d := range docs {
		out = append(out, d.Data()["chatKey"].(string)+" "+d.Data()["data"].(string))
	}
	sort.Strings(out)
	return out
}

// Tin mới báo DM cho thành viên khác, mỗi người tối đa một lần mỗi 10 phút, và
// không báo người vừa tự gửi trong 10 phút đó (họ đang mở chat).
func TestEmulatorGameChatPings(t *testing.T) {
	g, _ := runningAPIGame(t)
	ctx := context.Background()
	t0 := time.Now()
	post := func(uid string, at time.Time, wantPing bool) {
		t.Helper()
		pinged, err := g.store.PostChat(ctx, g.id, chatWolves, "tin của "+uid, GameViewer{UID: uid}, at)
		if err != nil || pinged != wantPing {
			t.Fatalf("%s gửi lúc +%s: pinged = %v, %v", uid, at.Sub(t0), pinged, err)
		}
	}
	post("w1", t0, true)
	if got := chatPings(t, g); strings.Join(got, "|") != `dm:w2 {"chat":"wolves"}` {
		t.Fatalf("ping = %q", got)
	}
	post("w1", t0.Add(2*time.Second), false)
	post("w2", t0.Add(3*time.Second), false)
	post("w1", t0.Add(9*time.Minute), false)
	post("w1", t0.Add(11*time.Minute), true)
	if n := len(chatPings(t, g)); n != 2 {
		t.Fatalf("có %d ping, mong đợi 2", n)
	}
	// w2 được báo lần cuối lúc +11m, đã quá 10 phút, nhưng vừa tự gửi lúc +20m.
	post("w2", t0.Add(20*time.Minute), false)
	post("w1", t0.Add(22*time.Minute), false)
	// Sói đã chết không cần được gọi dậy.
	editState(t, g, func(st *ww.State) { st.Players["w2"].Alive = false })
	post("w1", t0.Add(45*time.Minute), false)
}

// Trang đầu là 30 tin mới nhất, cursor tải tiếp phần cũ hơn tới hết.
func TestEmulatorGameChatPages(t *testing.T) {
	g, h := runningAPIGame(t)
	t0 := time.Now()
	for i := 1; i <= 32; i++ {
		if _, err := g.store.PostChat(context.Background(), g.id, chatWolves, fmt.Sprint(i), GameViewer{UID: "w1"}, t0.Add(time.Duration(i)*time.Second)); err != nil {
			t.Fatal(err)
		}
	}
	path := "/v1/games/" + g.id + "/chats/wolves"
	first := h.call("w2", "GET", path, nil, "")
	msgs := chatMessages(t, first)
	if len(msgs) != 30 || msgs[0]["text"] != "32" || msgs[29]["text"] != "3" || first.body["cursor"] != "3" {
		t.Fatalf("trang đầu: %d tin, %v … %v, cursor %v", len(msgs), msgs[0]["text"], msgs[len(msgs)-1]["text"], first.body["cursor"])
	}
	next := h.call("w2", "GET", path+"?cursor=3", nil, "")
	if msgs := chatMessages(t, next); len(msgs) != 2 || msgs[0]["text"] != "2" || msgs[1]["text"] != "1" || next.body["cursor"] != nil {
		t.Fatalf("trang sau = %s", next.raw)
	}
	h.want(h.call("w2", "GET", path+"?cursor=x", nil, ""), 400, "")
}

// Poll bằng after lấy tin mới hơn seq app đang có, bắt đầu từ tin ngay sau
// seq đó, để app vắng mặt lâu (nền, mất mạng) vẫn lấp được hết đoạn giữa.
func TestEmulatorGameChatAfter(t *testing.T) {
	g, h := runningAPIGame(t)
	t0 := time.Now()
	for i := 1; i <= 35; i++ {
		if _, err := g.store.PostChat(context.Background(), g.id, chatWolves, fmt.Sprint(i), GameViewer{UID: "w1"}, t0.Add(time.Duration(i)*time.Second)); err != nil {
			t.Fatal(err)
		}
	}
	path := "/v1/games/" + g.id + "/chats/wolves"
	r := h.call("w2", "GET", path+"?after=2", nil, "")
	msgs := chatMessages(t, r)
	if len(msgs) != 30 || msgs[0]["text"] != "32" || msgs[29]["text"] != "3" || r.body["hasNewer"] != true || r.body["cursor"] != nil {
		t.Fatalf("after=2: %d tin, %v … %v, %s", len(msgs), msgs[0]["text"], msgs[len(msgs)-1]["text"], r.raw)
	}
	r = h.call("w2", "GET", path+"?after=32", nil, "")
	if msgs := chatMessages(t, r); len(msgs) != 3 || msgs[0]["text"] != "35" || msgs[2]["text"] != "33" || r.body["hasNewer"] != false {
		t.Fatalf("after=32 = %s", r.raw)
	}
	if r := h.call("w2", "GET", path+"?after=35", nil, ""); len(chatMessages(t, r)) != 0 || r.body["hasNewer"] != false {
		t.Fatalf("after=35 = %s", r.raw)
	}
	h.want(h.call("w2", "GET", path+"?after=-1", nil, ""), 400, "")
	h.want(h.call("w2", "GET", path+"?after=1&cursor=5", nil, ""), 400, "")
}

// Sói đã chết và mọi người khi ván đã hết thì vẫn đọc được nhưng không gửi được.
// Tin trống, tin quá dài và tin gửi dồn trong một giây bị từ chối, không ghi.
func TestEmulatorGameChatSendRules(t *testing.T) {
	g, h := runningAPIGame(t)
	path := "/v1/games/" + g.id + "/chats/wolves"
	h.want(h.call("w1", "POST", path, map[string]any{"text": "   "}, ""), 400, "invalid_text")
	h.want(h.call("w1", "POST", path, map[string]any{"text": strings.Repeat("ó", 1001)}, ""), 400, "invalid_text")
	h.want(h.call("w1", "POST", path, map[string]any{"text": strings.Repeat("ó", 1000)}, ""), 200, "")
	h.want(h.call("w1", "POST", path, map[string]any{"text": "dồn"}, ""), 429, "too_fast")
	h.want(h.call("w2", "POST", path, map[string]any{"text": "w2 thì vẫn gửi được"}, ""), 200, "")
	if n := len(chatMessages(t, h.call("w1", "GET", path, nil, ""))); n != 2 {
		t.Fatalf("có %d tin, mong đợi 2", n)
	}

	editState(t, g, func(st *ww.State) { st.Players["w1"].Alive = false })
	h.want(h.call("w1", "POST", path, map[string]any{"text": "ma sói"}, ""), 403, "chat_read_only")
	if r := h.call("w1", "GET", path, nil, ""); r.status != 200 || r.body["canSend"] != false || len(chatMessages(t, r)) != 2 {
		t.Fatalf("sói chết đọc chat = %d %s", r.status, r.raw)
	}

	editState(t, g, func(st *ww.State) { st.Phase = ww.PhaseEnded })
	h.want(h.call("w2", "POST", path, map[string]any{"text": "hết ván"}, ""), 403, "chat_read_only")
	if r := h.call("w2", "GET", path, nil, ""); r.status != 200 || r.body["canSend"] != false {
		t.Fatalf("hết ván đọc chat = %d %s", r.status, r.raw)
	}
}

// Huỷ ván chỉ đổi status của game, state engine vẫn đang chạy dở. Chat vẫn
// phải chỉ còn đọc, và không bắn DM báo tin cho một ván đã chết.
func TestEmulatorGameChatCancelledReadOnly(t *testing.T) {
	g, h := runningAPIGame(t)
	if err := g.store.AdminCancel(context.Background(), g.id, "admin", time.Now()); err != nil {
		t.Fatal(err)
	}
	path := "/v1/games/" + g.id + "/chats/wolves"
	h.want(h.call("w1", "POST", path, map[string]any{"text": "còn ai không"}, ""), 403, "chat_read_only")
	if r := h.call("w1", "GET", path, nil, ""); r.status != 200 || r.body["canSend"] != false {
		t.Fatalf("ván huỷ đọc chat = %d %s", r.status, r.raw)
	}
	if got := meChats(t, h, g.id, "w1"); got != "wolves:Phe Sói:false" {
		t.Fatalf("/me chats sau khi huỷ = %q", got)
	}
	if got := chatPings(t, g); len(got) != 0 {
		t.Fatalf("ping sau khi huỷ = %q", got)
	}
}

// App Store 1.2: từ tục bị che lúc ghi; người chơi báo cáo được một tin (admin
// nhận DM ngay, kèm nội dung và ai báo) và chặn được người gửi. Tin của người
// bị chặn vẫn giữ seq trong trang nhưng ẩn chữ, để poll after không kẹt.
func TestEmulatorGameChatReportAndBlock(t *testing.T) {
	g, h := runningAPIGame(t)
	tg := newFakeTelegram(t)
	h.deps.Telegram = tg.service(testPscChat)
	seed(t, g.db, "telegramLinks/boss", map[string]any{"tgUserId": "5000"})
	seed(t, g.db, "tgLinks/5000", map[string]any{"uid": "boss"})
	path := "/v1/games/" + g.id + "/chats/wolves"
	h.want(h.call("w1", "POST", path, map[string]any{"text": "đm cắn seer"}, ""), 200, "")
	msgs := chatMessages(t, h.call("w2", "GET", path, nil, ""))
	if len(msgs) != 1 || msgs[0]["text"] != "** cắn seer" {
		t.Fatalf("tin đã lọc = %v", msgs)
	}
	seq := msgs[0]["seq"]

	h.want(h.call("w2", "POST", path+"/reports", map[string]any{"seq": seq}, ""), 200, "")
	var dms []string
	for _, c := range tg.Calls("sendMessage") {
		if c.Params["chat_id"] == "5000" {
			dms = append(dms, c.Params["text"].(string))
		}
	}
	if len(dms) != 1 || !strings.Contains(dms[0], "W2 báo cáo tin của W1") || !strings.Contains(dms[0], "** cắn seer") {
		t.Fatalf("DM admin = %q", dms)
	}
	// Chỉ báo cáo thì chưa chặn.
	if msgs := chatMessages(t, h.call("w2", "GET", path, nil, "")); msgs[0]["hidden"] == true {
		t.Fatalf("chưa chặn mà tin bị ẩn: %v", msgs)
	}

	h.want(h.call("w2", "POST", path+"/reports", map[string]any{"seq": seq, "block": true}, ""), 200, "")
	if msgs := chatMessages(t, h.call("w2", "GET", path, nil, "")); len(msgs) != 1 || msgs[0]["hidden"] != true || msgs[0]["text"] != "" || msgs[0]["seq"] != seq {
		t.Fatalf("w2 đã chặn w1 mà thấy %v", msgs)
	}
	if msgs := chatMessages(t, h.call("w1", "GET", path, nil, "")); msgs[0]["hidden"] == true {
		t.Fatalf("người bị chặn không thấy tin của chính mình: %v", msgs)
	}
	if got := chatPings(t, g); len(got) != 1 {
		t.Fatalf("ping = %q", got)
	}

	h.want(h.call("w1", "POST", path+"/reports", map[string]any{"seq": seq}, ""), 400, "invalid_request")
	h.want(h.call("w2", "POST", path+"/reports", map[string]any{"seq": 999}, ""), 404, "message_not_found")
	h.want(h.call("v1", "POST", path+"/reports", map[string]any{"seq": seq}, ""), 404, "chat_not_found")
}
