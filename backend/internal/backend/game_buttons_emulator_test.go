//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"strconv"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// buttonEnv: ván thật đang ở đêm 1 lúc 23h (runningAPIGame), webhook api thật,
// bộ gửi outbox gửi sang fake Telegram.
type buttonEnv struct {
	*storeGame
	h        *apiHarness
	srv      *Server
	tg       *fakeTelegram
	tasks    []PublishTask
	updateID int64
}

func newButtonEnv(t *testing.T) *buttonEnv {
	t.Helper()
	g, h := runningAPIGame(t)
	return buttonEnvFor(t, g, h)
}

func buttonEnvFor(t *testing.T, g *storeGame, h *apiHarness) *buttonEnv {
	t.Helper()
	e := &buttonEnv{storeGame: g, h: h, tg: newFakeTelegram(t), updateID: 100}
	h.deps.EnqueueTask = func(_ context.Context, p PublishTask) (string, error) {
		e.tasks = append(e.tasks, p)
		return "created", nil
	}
	e.srv = &Server{config: Config{GameInboundQueue: "game-inbound"}, deps: h.deps}
	e.flush() // gửi lá bài và prompt của đêm 1, ghi message_id của prompt
	return e
}

func (e *buttonEnv) flush() FlushResult {
	e.t.Helper()
	res, err := e.store.FlushGame(context.Background(), e.id, e.tg.service(testPscChat), time.Now)
	if err != nil || res.Failed != 0 {
		e.t.Fatalf("flush = %+v, %v", res, err)
	}
	return res
}

// webhook chạy một update qua serveTelegramUpdate của api; trả status và body.
func (e *buttonEnv) webhook(raw string) (int, map[string]any) {
	e.t.Helper()
	return e.webhookCtx(context.Background(), raw)
}

func (e *buttonEnv) webhookCtx(ctx context.Context, raw string) (int, map[string]any) {
	e.t.Helper()
	rec := httptest.NewRecorder()
	e.srv.serveTelegramUpdate(ctx, rec, []byte(raw), e.h.deps.EnqueueTask)
	var body map[string]any
	if rec.Body.Len() > 0 {
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			e.t.Fatalf("body không phải JSON: %q", rec.Body.String())
		}
	}
	return rec.Code, body
}

// press bấm nút data bằng tg, với update_id mới; trả chữ toast và có phải hộp
// thoại không.
func (e *buttonEnv) press(tg, data string) (string, bool) {
	e.t.Helper()
	e.updateID++
	return e.pressAs(e.updateID, tg, data)
}

func (e *buttonEnv) pressAs(updateID int64, tg, data string) (string, bool) {
	e.t.Helper()
	raw, _ := json.Marshal(map[string]any{"update_id": updateID, "callback_query": map[string]any{
		"id": fmt.Sprintf("cq-%d", updateID), "from": map[string]any{"id": mustInt(tg)}, "data": data,
	}})
	code, body := e.webhook(string(raw))
	if code != 200 || body["method"] != "answerCallbackQuery" || body["callback_query_id"] != fmt.Sprintf("cq-%d", updateID) {
		e.t.Fatalf("webhook = %d %v", code, body)
	}
	text, _ := body["text"].(string)
	return text, body["show_alert"] == true
}

// btn là callback_data của nút trong lượt hiện tại; idx là vị trí theo uid đã sort.
func (e *buttonEnv) btn(kind ww.Kind, op string, uids ...string) string {
	e.t.Helper()
	st := e.state()
	pos := positions(st)
	var idx []int
	for _, uid := range uids {
		idx = append(idx, pos[uid])
	}
	data, err := gameButton{GameID: e.id, TurnKey: turnKey(st), Kind: kind, Op: op, Idx: idx}.data()
	if err != nil {
		e.t.Fatal(err)
	}
	return data
}

// lastDM là call cuối gửi hoặc sửa tin trong DM của uid.
func (e *buttonEnv) lastDM(uid string) tgCall {
	e.t.Helper()
	var last tgCall
	for _, c := range e.tg.Calls("") {
		if c.Params["chat_id"] == e.storeGame.tg[uid] {
			last = c
		}
	}
	if last.Method == "" {
		e.t.Fatalf("%s chưa nhận tin nào", uid)
	}
	return last
}

func buttonsOf(c tgCall) []string {
	var out []string
	kb, _ := c.Params["reply_markup"].(map[string]any)
	rows, _ := kb["inline_keyboard"].([]any)
	for _, row := range rows {
		for _, b := range row.([]any) {
			out = append(out, b.(map[string]any)["text"].(string))
		}
	}
	return out
}

func (e *buttonEnv) promptID(uid string, kind ww.Kind) float64 {
	e.t.Helper()
	snap, err := e.db.Doc("games/" + e.id + "/outboxChats/dm:" + uid).Get(context.Background())
	if err != nil {
		e.t.Fatal(err)
	}
	p := anyMap(anyMap(snap.Data()["prompts"])[string(kind)])
	if p["turnKey"] != turnKey(e.state()) {
		e.t.Fatalf("prompt %s/%s = %v", uid, kind, p)
	}
	return float64(number(p["messageId"]))
}

func (e *buttonEnv) flushTasks() int {
	n := 0
	for _, p := range e.tasks {
		if p.HandlerPath == "/tasks/game-flush" {
			n++
		}
	}
	return n
}

// W2: prompt đêm 1 có nút; soi phải bấm Chốt mới tính, kết quả hiện trong hộp
// thoại, tin DM được sửa theo từng bước và hết nút khi đã chốt.
func TestEmulatorButtonSeerPeekConfirmFlow(t *testing.T) {
	e := newButtonEnv(t)
	prompt := e.lastDM("seer")
	if prompt.Method != "sendMessage" || !strings.HasPrefix(prompt.Params["text"].(string), "<b>Tới lượt bạn: Soi</b>") {
		t.Fatalf("prompt soi = %v", prompt)
	}
	// Không có nút tự soi; tên lấy từ publicProfiles.
	if b := buttonsOf(prompt); len(b) != 9 || strings.Contains(strings.Join(b, ","), "SEER") {
		t.Fatalf("nút soi = %v", b)
	}
	id := e.promptID("seer", ww.KindSeerPeek)
	seer := e.storeGame.tg["seer"]

	if text, alert := e.press(seer, e.btn(ww.KindSeerPeek, opPick, "w1")); text != "Bấm Chốt để xác nhận." || alert {
		t.Fatalf("bấm chọn = %q %v", text, alert)
	}
	if n := e.flushTasks(); n != 1 {
		t.Fatalf("game-flush được enqueue %d lần", n)
	}
	e.flush()
	edit := e.lastDM("seer")
	if edit.Method != "editMessageText" || edit.Params["message_id"] != id ||
		!strings.Contains(edit.Params["text"].(string), "Bạn chọn W1. Chọn rồi không đổi được. Chắc chưa?") ||
		strings.Join(buttonsOf(edit), ",") != "Chốt,Chọn lại" {
		t.Fatalf("tin chờ chốt = %v", edit)
	}
	if mine := e.actionCount(1, "seer"); mine != 0 {
		t.Fatalf("chưa chốt mà đã ghi %d action", mine)
	}

	if text, alert := e.press(seer, e.btn(ww.KindSeerPeek, opConfirm, "w1")); text != "W1 là Sói." || !alert {
		t.Fatalf("chốt = %q %v", text, alert)
	}
	e.flush()
	edit = e.lastDM("seer")
	if edit.Method != "editMessageText" || !strings.HasSuffix(edit.Params["text"].(string), "\nĐã chốt: W1.") || len(buttonsOf(edit)) != 0 {
		t.Fatalf("tin đã chốt = %v", edit)
	}
	// Bấm lại nút cũ: soi một lần mỗi đêm.
	if text, _ := e.press(seer, e.btn(ww.KindSeerPeek, opConfirm, "v1")); text != "Bạn đã dùng lượt này rồi." {
		t.Fatalf("soi lần hai = %q", text)
	}
}

func (e *buttonEnv) actionCount(round int, uid string) int {
	e.t.Helper()
	docs, err := e.db.Collection("games/"+e.id+"/rounds/"+fmt.Sprint(round)+"/actions").Where("uid", "==", uid).Documents(context.Background()).GetAll()
	if err != nil {
		e.t.Fatal(err)
	}
	return len(docs)
}

// Tin sửa bị lỗi rồi được gửi bù: vẫn sửa đúng prompt, không chèn dòng gửi bù
// vào prompt.
func TestEmulatorButtonRetriedChoiceEditsPrompt(t *testing.T) {
	e := newButtonEnv(t)
	if text, _ := e.press(e.storeGame.tg["w1"], e.btn(ww.KindWolfBite, opPick, "v1")); text != "Đã chọn V1." {
		t.Fatalf("cắn = %q", text)
	}
	e.tg.Then("editMessageText", tgBadRequest("Bad Request: can't parse entities"))
	if res, err := e.store.FlushGame(context.Background(), e.id, e.tg.service(testPscChat), time.Now); err != nil || res.Failed != 1 {
		t.Fatalf("flush = %+v, %v", res, err)
	}
	if n, err := e.store.AdminRetryOutbox(context.Background(), e.id, "boss", time.Now()); err != nil || n != 1 {
		t.Fatalf("retry = %d, %v", n, err)
	}
	e.flush()
	last := e.lastDM("w1")
	if text := last.Params["text"].(string); last.Method != "editMessageText" || last.Params["message_id"] != e.promptID("w1", ww.KindWolfBite) ||
		strings.Contains(text, "Gửi bù") || !strings.Contains(text, "\nĐang chọn: V1.\n") {
		t.Fatalf("DM = %v", last)
	}
}

// C2: mỗi lần một sói chọn, đổi hay bỏ chọn cắn (qua nút hay app), chat Phe
// Sói trong app nhận một tin hệ thống theo đúng thứ tự. Hành động khác không
// vào chat, và lựa chọn của sói không bao giờ ra Telegram ngoài DM của chính
// người chọn.
func TestEmulatorWolfPicksPostToWolfChat(t *testing.T) {
	e := newButtonEnv(t)
	if text, _ := e.press(e.storeGame.tg["w1"], e.btn(ww.KindWolfBite, opPick, "v1")); text != "Đã chọn V1." {
		t.Fatalf("w1 cắn = %q", text)
	}
	if text, _ := e.press(e.storeGame.tg["w2"], e.btn(ww.KindWolfBite, opPick, "v2")); text != "Đã chọn V2." {
		t.Fatalf("w2 cắn = %q", text)
	}
	if text, _ := e.press(e.storeGame.tg["seer"], e.btn(ww.KindSeerPeek, opPick, "w1")); text != "Bấm Chốt để xác nhận." {
		t.Fatalf("soi = %q", text)
	}
	// Bỏ chọn mà vẫn gửi kèm targets thì vẫn là bỏ chọn.
	e.h.want(e.h.call("w1", "POST", "/v1/games/"+e.id+"/actions", map[string]any{"kind": "wolf_bite", "clear": true, "targets": []string{"v2"}}, ""), 200, "")
	e.h.want(e.h.call("w1", "POST", "/v1/games/"+e.id+"/actions", map[string]any{"kind": "wolf_bite", "targets": []string{"v3"}}, ""), 200, "")
	e.flush()

	r := e.h.call("w2", "GET", "/v1/games/"+e.id+"/chats/wolves", nil, "")
	e.h.want(r, 200, "")
	var got []string
	for _, m := range chatMessages(t, r) {
		if m["system"] != true {
			t.Fatalf("tin không phải hệ thống: %v", m)
		}
		got = append(got, m["text"].(string))
	}
	want := []string{"W1 chọn cắn V3.", "W1 bỏ chọn cắn.", "W2 chọn cắn V2.", "W1 chọn cắn V1."}
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("chat Phe Sói = %q", got)
	}
	// Mỗi sói được báo một lần cho lựa chọn của sói kia; các lần sau còn trong 10 phút.
	if got := strings.Join(chatPings(t, e.storeGame), "|"); got != `dm:w1 {"chat":"wolves"}|dm:w2 {"chat":"wolves"}` {
		t.Fatalf("ping = %q", got)
	}
	for _, c := range e.tg.Calls("") {
		text, _ := c.Params["text"].(string)
		if strings.Contains(text, " chọn cắn ") || strings.Contains(text, "bỏ chọn cắn") {
			t.Fatalf("lựa chọn của sói ra Telegram: %v", c.Params)
		}
	}
}

// W2 "Xong khi": chọn chéo kênh thì tin DM cuối cùng hiện đúng lựa chọn đang lưu.
func TestEmulatorButtonCrossChannelShowsStoredChoice(t *testing.T) {
	e := newButtonEnv(t)
	w1 := e.storeGame.tg["w1"]
	if text, _ := e.press(w1, e.btn(ww.KindWolfBite, opPick, "v1")); text != "Đã chọn V1." {
		t.Fatalf("cắn qua nút = %q", text)
	}
	// Sau đó đổi trong app: bản có receivedAt muộn hơn thắng.
	r := e.h.call("w1", "POST", "/v1/games/"+e.id+"/actions", map[string]any{"kind": "wolf_bite", "targets": []string{"v2"}}, "")
	e.h.want(r, 200, "")
	e.flush()
	last := e.lastDM("w1")
	if last.Method != "editMessageText" || !strings.Contains(last.Params["text"].(string), "\nĐang chọn: V2.\n") {
		t.Fatalf("DM sau khi đổi trong app = %v", last)
	}
	if b := strings.Join(buttonsOf(last), ","); !strings.Contains(b, "✅ V2") || strings.Contains(b, "✅ V1") {
		t.Fatalf("nút = %s", b)
	}
	// Telegram gửi lại cú bấm cũ (update_id nhỏ hơn bản đã lưu) thì không ghi đè.
	if text, _ := e.pressAs(e.updateID, w1, e.btn(ww.KindWolfBite, opPick, "v1")); text != buttonTexts.kept {
		t.Fatalf("gửi lại = %q", text)
	}
	stored := e.data("games/" + e.id + "/rounds/1/actions/w1_wolf_bite")
	if ts := anyList(stored["targets"]); len(ts) != 1 || ts[0] != "v2" {
		t.Fatalf("action đang lưu = %v", stored)
	}
}

func (e *buttonEnv) data(path string) map[string]any {
	e.t.Helper()
	snap, err := e.db.Doc(path).Get(context.Background())
	if err != nil {
		e.t.Fatal(err)
	}
	return snap.Data()
}

// W2 "Xong khi": mỗi loại nút sai đều trả toast đúng lý do.
func TestEmulatorButtonRejectsWithReason(t *testing.T) {
	e := newButtonEnv(t)
	seer, guard := e.storeGame.tg["seer"], e.storeGame.tg["guard"]
	stale, _ := gameButton{GameID: e.id, TurnKey: "r0", Kind: ww.KindSeerPeek, Op: opPick, Idx: []int{0}}.data()
	outside, _ := gameButton{GameID: e.id, TurnKey: turnKey(e.state()), Kind: ww.KindGuard, Op: opPick, Idx: []int{99}}.data()
	justOutside, _ := gameButton{GameID: e.id, TurnKey: turnKey(e.state()), Kind: ww.KindGuard, Op: opPick, Idx: []int{len(e.state().Players)}}.data()
	linkUser(t, e.h, "stranger", "777", true)
	cases := []struct{ name, tg, data, want string }{
		{"nút lạ", seer, "x", "Nút này chưa dùng được."},
		{"tg chưa liên kết", "555", e.btn(ww.KindGuard, opPick, "v1"), "Tài khoản Telegram này chưa liên kết với RunNow."},
		{"người ngoài ván", "777", e.btn(ww.KindGuard, opPick, "v1"), buttonTexts.notPlayer},
		{"nút của lượt trước", seer, stale, buttonTexts.stale},
		{"người ngoài danh sách", guard, outside, buttonTexts.badTarget},
		{"vị trí ngay sau người cuối", guard, justOutside, buttonTexts.badTarget},
		{"bảo vệ chọn hai người", guard, e.btn(ww.KindGuard, opPick, "v1", "v2"), buttonTexts.badTarget},
		{"sai vai", seer, e.btn(ww.KindGuard, opPick, "v1"), "Vai của bạn không làm được việc này."},
		{"ván không có", seer, "m1|nope|r1/night|g|t|0", buttonTexts.gone},
	}
	for _, c := range cases {
		if text, _ := e.press(c.tg, c.data); text != c.want {
			t.Fatalf("%s: %q, mong đợi %q", c.name, text, c.want)
		}
	}
	if n := e.flushTasks(); n != 0 {
		t.Fatalf("nút bị từ chối mà vẫn enqueue %d game-flush", n)
	}

	// Soi ra Dân; đã soi rồi thì bấm Chọn cũng bị từ chối ngay, không hỏi chốt.
	if text, alert := e.press(seer, e.btn(ww.KindSeerPeek, opConfirm, "v1")); text != "V1 là Dân." || !alert {
		t.Fatalf("soi dân = %q %v", text, alert)
	}
	if text, _ := e.press(seer, e.btn(ww.KindSeerPeek, opPick, "w1")); text != "Bạn đã dùng lượt này rồi." {
		t.Fatalf("chọn soi lần hai = %q", text)
	}

	// Người đã chết: sửa state cho bảo vệ chết rồi bấm nút đang mở.
	st := e.state()
	st.Players["guard"].Alive = false
	raw, _ := json.Marshal(st)
	seed(t, e.db, "games/"+e.id+"/secret/state", map[string]any{"state": string(raw), "phaseKey": st.PhaseKey()})
	if text, _ := e.press(guard, e.btn(ww.KindGuard, opPick, "v1")); text != "Bạn đã chết." {
		t.Fatalf("người chết bấm = %q", text)
	}
	card, _ := gameButton{GameID: e.id, Op: opCard}.data()
	if text, _ := e.press(guard, card); text != "Lá bài của bạn: Bảo vệ. Bạn đã chết." {
		t.Fatalf("lá bài người chết = %q", text)
	}

	// Ván đã kết thúc hay đã huỷ.
	for _, s := range []string{gameEnded, gameCancelled} {
		seedMerge(t, e.storeGame, map[string]any{"status": s})
		if text, _ := e.press(seer, e.btn(ww.KindSeerPeek, opPick, "w1")); text != buttonTexts.ended {
			t.Fatalf("%s: %q", s, text)
		}
	}
}

// /vai trong DM trả lá bài ngay trong response webhook; nút "Xem lại lá bài"
// trong tin lá bài hiện hộp thoại. Người không phải sói không thấy tên sói.
func TestEmulatorVaiCommandAndCardButton(t *testing.T) {
	e := newButtonEnv(t)
	vai := func(tg string) map[string]any {
		e.updateID++
		code, body := e.webhook(fmt.Sprintf(`{"update_id":%d,"message":{"message_id":1,"text":"/vai","chat":{"id":%s,"type":"private"},"from":{"id":%s}}}`, e.updateID, tg, tg))
		if code != 200 || body["method"] != "sendMessage" {
			t.Fatalf("/vai = %d %v", code, body)
		}
		return body
	}
	body := vai(e.storeGame.tg["w1"])
	if body["parse_mode"] != "HTML" || !strings.Contains(body["text"].(string), "\n<b>Sói</b>\n") || !strings.HasSuffix(body["text"].(string), "Đồng đội: W2.") {
		t.Fatalf("/vai sói = %v", body)
	}
	if text := vai(e.storeGame.tg["seer"])["text"].(string); !strings.Contains(text, "<b>Tiên tri</b>") || strings.Contains(text, "W1") || strings.Contains(text, "Đồng đội") {
		t.Fatalf("/vai tiên tri = %q", text)
	}
	if text := vai("555")["text"].(string); !strings.HasPrefix(text, "Tài khoản Telegram này chưa liên kết") {
		t.Fatalf("/vai chưa liên kết = %q", text)
	}
	linkUser(t, e.h, "stranger", "777", true)
	if text := vai("777")["text"].(string); text != "Bạn chưa ở trong ván Ma Sói nào." {
		t.Fatalf("/vai người ngoài = %q", text)
	}

	card, _ := gameButton{GameID: e.id, Op: opCard}.data()
	var cardMsg tgCall
	for _, c := range e.tg.Calls("sendMessage") {
		if c.Params["chat_id"] == e.storeGame.tg["v1"] && strings.HasPrefix(c.Params["text"].(string), "Lá bài của bạn") {
			cardMsg = c
		}
	}
	if b := buttonsOf(cardMsg); len(b) != 1 || b[0] != "Xem lại lá bài" {
		t.Fatalf("tin lá bài = %v", cardMsg)
	}
	if text, alert := e.press(e.storeGame.tg["w2"], card); text != "Lá bài của bạn: Sói. Đồng đội: W1." || !alert {
		t.Fatalf("xem lá bài sói = %q %v", text, alert)
	}
	if text, _ := e.press(e.storeGame.tg["v1"], card); text != "Lá bài của bạn: Dân." {
		t.Fatalf("xem lá bài dân = %q", text)
	}

	// Firestore lỗi tạm thời (ở đây là hết hạn context) thì webhook trả 5xx để
	// Telegram gửi lại, cả với /vai lẫn với nút.
	expired, cancel := context.WithDeadline(context.Background(), time.Now().Add(-time.Second))
	defer cancel()
	tg := e.storeGame.tg["v1"]
	for name, raw := range map[string]string{
		"/vai": fmt.Sprintf(`{"update_id":900,"message":{"message_id":1,"text":"/vai","chat":{"id":%s,"type":"private"},"from":{"id":%s}}}`, tg, tg),
		"nút":  fmt.Sprintf(`{"update_id":901,"callback_query":{"id":"cq-901","from":{"id":%s},"data":%q}}`, tg, card),
	} {
		if code, body := e.webhookCtx(expired, raw); code != 503 || body != nil {
			t.Fatalf("%s khi Firestore lỗi tạm thời = %d %v", name, code, body)
		}
	}

	// Ván đã kết thúc thì /vai không còn lá bài.
	seedMerge(t, e.storeGame, map[string]any{"status": gameEnded})
	if text := vai(e.storeGame.tg["w1"])["text"].(string); text != "Bạn chưa ở trong ván Ma Sói nào." {
		t.Fatalf("/vai sau khi hết ván = %q", text)
	}
}

// cupidGame: như newStoreGame nhưng v4 là Cupid, giờ ván là 10h sáng ngày
// Start (setup, Cupid đang chọn).
func cupidGame(t *testing.T) (*storeGame, *apiHarness) {
	t.Helper()
	db := emulatorDB(t)
	ctx := context.Background()
	g := &storeGame{t: t, db: db, store: NewGameStore(db, testPscChat), tg: map[string]string{}}
	g.store.frameKm = func(_ context.Context, _ string, end time.Time) (FrameKm, error) {
		return FrameKm{FrameEnd: end, OfficialMeters: 5000, Meters: 5000, Source: "official"}, nil
	}
	id, err := g.store.CreateGame(ctx, NewGameInput{CreatedBy: "admin", ChatID: "-100"}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	g.id = id
	roles := storeRoles()
	roles["v4"] = ww.Cupid
	for i, uid := range sortedPlayers(ww.NewState(ww.Seed{}, ww.Config{}, roles, msgStart)) {
		tg := strconv.Itoa(910000 + i)
		g.tg[uid] = tg
		seed(t, db, "games/"+id+"/players/"+uid, map[string]any{"uid": uid, "tgUserId": tg})
		seed(t, db, "tgLinks/"+tg, map[string]any{"uid": uid, "inPsc": true})
		seed(t, db, "publicProfiles/"+uid, map[string]any{"displayName": strings.ToUpper(uid)})
	}
	g.start = ww.NewState(ww.Seed{3}, ww.Config{}, roles, msgStart)
	if err := g.store.StartGame(ctx, id, g.start, msgStart); err != nil {
		t.Fatal(err)
	}
	seedMerge(t, g, map[string]any{"clockOffsetNs": int64(msgStart.Add(time.Hour).Sub(time.Now()))})
	return g, newAPIHarness(t, g.store)
}

// Cupid chọn hai người bằng hai lần bấm, chọn lại được, rồi phải bấm Chốt. Tin
// sửa ghi sau khi ván đã sang lượt khác thì bỏ, không sửa prompt cũ.
func TestEmulatorButtonCupidPicksTwoThenConfirms(t *testing.T) {
	g, h := cupidGame(t)
	e := buttonEnvFor(t, g, h)
	cupid := g.tg["v4"]
	if p := e.lastDM("v4"); p.Method != "sendMessage" || !strings.HasPrefix(p.Params["text"].(string), "<b>Tới lượt bạn: Ghép đôi</b>") || len(buttonsOf(p)) != 10 {
		t.Fatalf("prompt Cupid = %v", p)
	}
	kicks := e.flushTasks()
	edit := func() tgCall {
		t.Helper()
		// Mỗi cú bấm có ghi tin đều phải enqueue game-flush.
		if n := e.flushTasks(); n != kicks+1 {
			t.Fatalf("game-flush được enqueue %d lần", n-kicks)
		}
		kicks++
		e.flush()
		c := e.lastDM("v4")
		if c.Method != "editMessageText" || c.Params["message_id"] != e.promptID("v4", ww.KindCupidPair) {
			t.Fatalf("không sửa prompt: %v", c)
		}
		// Vẽ theo giờ ván (10h sáng ngày Start), không theo giờ thật.
		if text := c.Params["text"].(string); strings.Contains(text, "Chưa bấm được") {
			t.Fatalf("vẽ theo giờ thật: %q", text)
		}
		return c
	}

	if text, _ := e.press(cupid, e.btn(ww.KindCupidPair, opPick, "v1")); text != buttonTexts.more {
		t.Fatalf("chọn người đầu = %q", text)
	}
	c := edit()
	if last := e.lastOutbox("v4"); last["template"] != tplChoice || number(last["editedId"]) != number(c.Params["message_id"]) {
		t.Fatalf("outbox tin sửa = %v", last)
	}
	if b := strings.Join(buttonsOf(c), ","); !strings.Contains(c.Params["text"].(string), "Đã chọn V1. Chọn thêm một người.") || strings.Contains(b, "V1,") || !strings.HasSuffix(b, "Chọn lại") {
		t.Fatalf("sau người đầu = %q %s", c.Params["text"], b)
	}
	if text, _ := e.press(cupid, e.btn(ww.KindCupidPair, opReset)); text != buttonTexts.reset {
		t.Fatalf("chọn lại = %q", text)
	}
	if c := edit(); strings.Contains(c.Params["text"].(string), "Đã chọn") || len(buttonsOf(c)) != 10 {
		t.Fatalf("sau chọn lại = %v", c)
	}
	if text, _ := e.press(cupid, e.btn(ww.KindCupidPair, opPick, "v1", "w1")); text != buttonTexts.confirm {
		t.Fatalf("chọn đủ hai = %q", text)
	}
	if c := edit(); !strings.Contains(c.Params["text"].(string), "Bạn chọn V1 và W1.") || strings.Join(buttonsOf(c), ",") != "Chốt,Chọn lại" {
		t.Fatalf("chờ chốt = %v", c)
	}
	if e.actionCount(1, "v4") != 0 {
		t.Fatal("chưa chốt mà đã ghi action")
	}
	if text, _ := e.press(cupid, e.btn(ww.KindCupidPair, opConfirm, "v1", "w1")); text != "Đã chọn V1 và W1." {
		t.Fatalf("chốt = %q", text)
	}
	if c := edit(); !strings.HasSuffix(c.Params["text"].(string), "\nĐã chốt: V1 và W1.") || len(buttonsOf(c)) != 0 {
		t.Fatalf("đã chốt = %v", c)
	}
	// Chốt thiếu người (data bị sửa) thì không ghi gì.
	if text, _ := e.press(cupid, e.btn(ww.KindCupidPair, opConfirm, "v1")); text != buttonTexts.badTarget {
		t.Fatalf("chốt một người = %q", text)
	}

	// Tin sửa cho kind chưa từng có prompt (prompt gửi lỗi, DM bị chặn) thì bỏ,
	// không gửi tin mới.
	ctx := context.Background()
	if err := g.store.queuePrompt(ctx, g.id, "w1", ww.KindSeerPeek, nil); err != nil {
		t.Fatal(err)
	}
	e.flush()
	if last := e.lastOutbox("w1"); last["template"] != tplChoice || last["status"] != outboxSkipped || last["skipReason"] != "no_prompt" {
		t.Fatalf("tin sửa không có prompt = %v", last)
	}

	// Chạy qua 22h rồi 0h mà chưa gửi, sau đó admin tạm dừng ván. Prompt soi
	// và prompt bình thuốc vẫn thuộc vòng 1 nhưng ván đang pause nên bỏ
	// (closed). Tin sửa prompt Cupid ghi lúc này sửa prompt thành đã đóng.
	// AdvanceGame cộng clockOffsetNs vào giờ truyền vào; bỏ offset để chạy đúng mốc.
	seedMerge(t, g, map[string]any{"clockOffsetNs": int64(0)})
	g.advance(time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam))
	g.advance(time.Date(2026, 10, 16, 0, 0, 0, 0, vietnam))
	if pk := g.state().PhaseKey(); pk != "r1/dawn" {
		t.Fatalf("sau 0h: %s", pk)
	}
	if err := g.store.AdminPause(ctx, g.id, "admin", time.Now()); err != nil {
		t.Fatal(err)
	}
	if err := g.store.queuePrompt(ctx, g.id, "v4", ww.KindCupidPair, nil); err != nil {
		t.Fatal(err)
	}
	e.flush()
	if c := e.lastDM("v4"); c.Method != "editMessageText" || c.Params["message_id"] != e.promptID("v4", ww.KindCupidPair) ||
		!strings.HasSuffix(c.Params["text"].(string), "\nLượt này đã đóng.") || len(buttonsOf(c)) != 0 {
		t.Fatalf("sửa prompt Cupid lúc pause = %v", c)
	}
	for _, c := range []struct {
		uid  string
		kind ww.Kind
		want string
	}{{"seer", ww.KindSeerPeek, "closed"}, {"witch", ww.KindWitchPoison, "closed"}} {
		p := e.outboxWhere(c.uid, func(m map[string]any) bool {
			return m["template"] == tplPrompt && strings.Contains(stringValue(m["data"]), `"`+string(c.kind)+`"`)
		})
		if p["status"] != outboxSkipped || p["skipReason"] != c.want {
			t.Fatalf("prompt %s = %v", c.kind, p)
		}
	}
}

// Nút DM gắn với vòng chứ không với phase: tiên tri chưa soi lúc 22h thì sau 0h
// vẫn bấm được nút của tin gửi lúc 22h, và tin sửa vẫn sửa đúng tin đó.
func TestEmulatorButtonSeerNightButtonWorksAfterMidnight(t *testing.T) {
	e := newButtonEnv(t)
	peek := e.btn(ww.KindSeerPeek, opPick, "w1")
	promptID := e.promptID("seer", ww.KindSeerPeek)
	e.advanceTo(time.Date(2026, 10, 16, 0, 0, 0, 0, vietnam))
	e.flush()
	if pk := e.state().PhaseKey(); pk != "r1/dawn" {
		t.Fatalf("sau 0h: %s", pk)
	}
	if id := e.promptID("seer", ww.KindSeerPeek); id != promptID {
		t.Fatalf("0h gửi lại prompt soi: %v → %v", promptID, id)
	}
	seer := e.storeGame.tg["seer"]
	if text, _ := e.press(seer, peek); text != buttonTexts.confirm {
		t.Fatalf("nút soi của tin 22h lúc 0h30 = %q", text)
	}
	e.flush()
	if c := e.lastDM("seer"); c.Method != "editMessageText" || c.Params["message_id"] != promptID || !strings.Contains(c.Params["text"].(string), "Bạn chọn W1.") {
		t.Fatalf("tin sửa = %v", c)
	}
	if text, alert := e.press(seer, e.btn(ww.KindSeerPeek, opConfirm, "w1")); text != "W1 là Sói." || !alert {
		t.Fatalf("chốt soi = %q", text)
	}
}

// Sang vòng mới thì mọi thứ của vòng cũ bị chặn, kể cả khi kind cùng tên đang
// mở: nút (lúc đọc và trong transaction), prompt chưa kịp gửi, tin sửa prompt cũ.
func TestEmulatorButtonOldRoundIsStale(t *testing.T) {
	e := newButtonEnv(t)
	guard := e.storeGame.tg["guard"]
	oldGuard := e.btn(ww.KindGuard, opPick, "v1")
	e.advanceTo(time.Date(2026, 10, 16, 0, 0, 0, 0, vietnam)) // prompt phù thuỷ vòng 1, chưa gửi
	if err := e.store.queuePrompt(context.Background(), e.id, "guard", ww.KindGuard, nil); err != nil {
		t.Fatal(err)
	}
	e.advanceTo(time.Date(2026, 10, 16, 22, 0, 0, 0, vietnam))
	if pk := e.state().PhaseKey(); pk != "r2/night" {
		t.Fatalf("chưa sang vòng 2: %s", pk)
	}
	e.flush()
	for _, c := range []struct {
		uid, tpl, kind string
	}{{"witch", tplPrompt, "witch_poison"}, {"guard", tplChoice, "guard"}} {
		m := e.outboxWhere(c.uid, func(m map[string]any) bool {
			return m["template"] == c.tpl && strings.Contains(stringValue(m["data"]), `"`+c.kind+`"`)
		})
		if m["status"] != outboxSkipped || m["skipReason"] != "stale" {
			t.Fatalf("%s %s vòng 1 = %v", c.uid, c.tpl, m)
		}
	}
	if text, _ := e.press(guard, oldGuard); text != buttonTexts.stale {
		t.Fatalf("nút bảo vệ vòng 1 ở vòng 2 = %q", text)
	}

	// Bước chốt chen vào giữa lúc đọc state và lúc ghi: nút vòng 2 bấm đúng lúc
	// ván sang vòng 3, nơi bảo vệ cũng đang mở.
	newGuard := e.btn(ww.KindGuard, opPick, "v1")
	e.store.beforeSubmit = func() { e.advanceTo(time.Date(2026, 10, 17, 22, 0, 0, 0, vietnam)) }
	defer func() { e.store.beforeSubmit = nil }()
	if text, _ := e.press(guard, newGuard); text != buttonTexts.stale {
		t.Fatalf("nút vòng 2 khi vừa sang vòng 3 = %q", text)
	}
	if pk := e.state().PhaseKey(); pk != "r3/night" {
		t.Fatalf("chưa sang vòng 3: %s", pk)
	}
	if n := e.actionCount(3, "guard") + e.actionCount(2, "guard"); n != 0 {
		t.Fatalf("bảo vệ có %d action", n)
	}
}

// outboxWhere là tin cuối (seq lớn nhất) trong DM của uid thoả match.
func (e *buttonEnv) outboxWhere(uid string, match func(map[string]any) bool) map[string]any {
	e.t.Helper()
	docs, err := e.db.Collection("games/"+e.id+"/outbox").Where("chatKey", "==", "dm:"+uid).Documents(context.Background()).GetAll()
	if err != nil {
		e.t.Fatal(err)
	}
	var last map[string]any
	for _, d := range docs {
		if m := d.Data(); match(m) && (last == nil || number(m["seq"]) > number(last["seq"])) {
			last = m
		}
	}
	if last == nil {
		e.t.Fatalf("dm:%s không có tin cần tìm", uid)
	}
	return last
}

func (e *buttonEnv) lastOutbox(uid string) map[string]any {
	e.t.Helper()
	return e.outboxWhere(uid, func(map[string]any) bool { return true })
}

// Phù thuỷ dùng bình cứu bằng nút; prompt bình cứu không phải tin cuối của
// lượt gửi mà message_id vẫn được ghi. Rồi bước chốt 10h chen vào giữa lúc đọc
// state và lúc ghi action: transaction kiểm luật trên state mới nên từ chối,
// không ghi gì.
func TestEmulatorButtonWitchSaveAndPhaseRace(t *testing.T) {
	e := newButtonEnv(t)
	if text, _ := e.press(e.storeGame.tg["w1"], e.btn(ww.KindWolfBite, opPick, "v1")); text != "Đã chọn V1." {
		t.Fatalf("cắn = %q", text)
	}
	e.advanceTo(time.Date(2026, 10, 16, 0, 0, 0, 0, vietnam))
	e.flush()
	saveID, poisonID := e.promptID("witch", ww.KindWitchSave), e.promptID("witch", ww.KindWitchPoison)
	if saveID == 0 || saveID == poisonID {
		t.Fatalf("prompt bình cứu %v, bình độc %v", saveID, poisonID)
	}
	witch := e.storeGame.tg["witch"]
	if text, _ := e.press(witch, e.btn(ww.KindWitchSave, opPick)); text != "Đã dùng bình cứu." {
		t.Fatalf("bình cứu = %q", text)
	}
	e.flush()
	if c := e.lastDM("witch"); c.Method != "editMessageText" || c.Params["message_id"] != saveID ||
		!strings.HasSuffix(c.Params["text"].(string), "\nBạn đã dùng bình cứu.") || len(buttonsOf(c)) != 0 {
		t.Fatalf("tin bình cứu = %v", c)
	}

	poison := e.btn(ww.KindWitchPoison, opPick, "w1")
	e.store.beforeSubmit = func() { e.advanceTo(time.Date(2026, 10, 16, 10, 0, 0, 0, vietnam)) }
	defer func() { e.store.beforeSubmit = nil }()
	if text, _ := e.press(witch, poison); text != rejectText(ww.KindWitchPoison, ww.ErrPhaseClosed) {
		t.Fatalf("bình độc khi lượt vừa chốt = %q", text)
	}
	if pk := e.state().PhaseKey(); pk != "r1/day" {
		t.Fatalf("bước chốt chưa chạy: %s", pk)
	}
	if n := e.actionCount(1, "witch"); n != 1 {
		t.Fatalf("phù thuỷ có %d action, mong đợi chỉ bình cứu", n)
	}
}

// advanceTo chạy các bước tới mốc giờ ván at, rồi để giờ ván ở at + 30 phút.
func (e *buttonEnv) advanceTo(at time.Time) {
	e.t.Helper()
	// AdvanceGame cộng clockOffsetNs vào giờ truyền vào.
	seedMerge(e.t, e.storeGame, map[string]any{"clockOffsetNs": int64(0)})
	e.advance(at)
	seedMerge(e.t, e.storeGame, map[string]any{"clockOffsetNs": int64(at.Add(30 * time.Minute).Sub(time.Now()))})
}
