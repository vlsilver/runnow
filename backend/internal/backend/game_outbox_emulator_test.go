//go:build emulator

package backend

import (
	"context"
	"errors"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// outboxEnv: một ván có group -100g (topic 5) và hai người chơi có Telegram,
// tin outbox ghi bằng đúng stepWrite.writeOutbox, Telegram giả, đồng hồ giả.
type outboxEnv struct {
	t     *testing.T
	db    *firestore.Client
	store *GameStore
	tg    *fakeTelegram

	mu    sync.Mutex // clock bị hook của fake Telegram đổi từ goroutine khác
	clock time.Time
}

func (e *outboxEnv) now() time.Time {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.clock
}

func (e *outboxEnv) advance(d time.Duration) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.clock = e.clock.Add(d)
}

const outboxGame = "g1"

func newOutboxEnv(t *testing.T) *outboxEnv {
	t.Helper()
	db := emulatorDB(t)
	e := &outboxEnv{t: t, db: db, store: NewGameStore(db, testPscChat), tg: newFakeTelegram(t),
		clock: time.Date(2026, 10, 12, 15, 0, 0, 0, time.UTC)}
	seed(t, db, "games/"+outboxGame, map[string]any{"chatId": "-100g", "threadId": int64(5), "config": "{}", "status": gameRunning})
	seed(t, db, "games/"+outboxGame+"/players/u1", map[string]any{"name": "An <b>&", "tgUserId": "71", "registeredAt": e.clock})
	seed(t, db, "games/"+outboxGame+"/players/u2", map[string]any{"name": "Bình", "tgUserId": int64(72), "registeredAt": e.clock.Add(time.Second)})
	return e
}

// write ghi msgs như một lần chốt.
func (e *outboxEnv) write(msgs ...gameMsg) {
	e.t.Helper()
	if err := e.writeErr(msgs...); err != nil {
		e.t.Fatal(err)
	}
}

// writeErr như write nhưng trả lỗi, để gọi được từ goroutine khác.
func (e *outboxEnv) writeErr(msgs ...gameMsg) error {
	game := e.db.Collection("games").Doc(outboxGame)
	return e.db.RunTransaction(context.Background(), func(ctx context.Context, tx *firestore.Transaction) error {
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		w := stepWrite{tx: tx, game: game, msgs: msgs, chats: chats, wall: e.now()}
		return w.writeOutbox(1)
	})
}

func (e *outboxEnv) flushCtx(ctx context.Context) (FlushResult, error) {
	return e.store.FlushGame(ctx, outboxGame, e.tg.service("-100psc"), e.now)
}

func (e *outboxEnv) flush() FlushResult {
	e.t.Helper()
	res, err := e.flushCtx(context.Background())
	if err != nil {
		e.t.Fatal(err)
	}
	return res
}

func (e *outboxEnv) doc(path string) map[string]any {
	e.t.Helper()
	d, err := e.db.Doc("games/" + outboxGame + "/" + path).Get(context.Background())
	if err != nil {
		e.t.Fatalf("%s: %v", path, err)
	}
	return d.Data()
}

// sent trả chữ của các sendMessage theo thứ tự gọi.
func (e *outboxEnv) sent() []string {
	var out []string
	for _, c := range e.tg.Calls("sendMessage") {
		out = append(out, c.Params["text"].(string))
	}
	return out
}

func adminMsg(action string) gameMsg {
	return gameMsg{ChatKey: chatGroup, Template: tplAdmin, Data: map[string]any{"action": action}}
}

// noteMsg là một tin riêng có chữ phân biệt theo kind. Không dùng prompt: prompt
// đọc state của ván lúc gửi (W2), còn ván ở đây chỉ có outbox.
func noteMsg(key string, kind werewolf.Kind) gameMsg {
	return gameMsg{ChatKey: key, Template: tplPrivate, Data: map[string]any{"events": []werewolf.Event{
		{Kind: werewolf.EventVoid, Action: kind, Reason: werewolf.VoidNoKm},
	}}}
}

// Gửi đúng chat, đúng topic, theo seq; ghi messageId; hết tin thì tắt pending.
func TestEmulatorOutboxSendsInOrder(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("cancel"), noteMsg(dmChat("u2"), werewolf.KindGuard))

	res := e.flush()
	if res.Sent != 3 || res.Failed != 0 || !res.RetryAt.IsZero() {
		t.Fatalf("res = %+v", res)
	}
	calls := e.tg.Calls("sendMessage")
	if len(calls) != 3 {
		t.Fatalf("calls = %v", calls)
	}
	for i, c := range calls {
		if c.Params["parse_mode"] != "HTML" {
			t.Fatalf("call %d thiếu parse_mode: %v", i, c.Params)
		}
	}
	pause, cancel := -1, -1
	for i, c := range calls {
		text := c.Params["text"].(string)
		switch {
		case strings.Contains(text, "Ván tạm dừng"):
			pause = i
		case strings.Contains(text, "Ván đã huỷ"):
			cancel = i
		case strings.Contains(text, "Bảo vệ"):
			if c.Params["chat_id"] != "72" || c.Params["message_thread_id"] != nil {
				t.Fatalf("DM gửi sai chỗ: %v", c.Params)
			}
		default:
			t.Fatalf("tin lạ: %q", text)
		}
	}
	if pause < 0 || cancel < pause {
		t.Fatalf("thứ tự group sai: pause=%d cancel=%d", pause, cancel)
	}
	for _, i := range []int{pause, cancel} {
		if calls[i].Params["chat_id"] != "-100g" || calls[i].Params["message_thread_id"] != float64(5) {
			t.Fatalf("group gửi sai chỗ: %v", calls[i].Params)
		}
	}
	// Fake cấp message_id theo thứ tự nhận: call thứ i có id i+1.
	m1, m2 := e.doc("outbox/group_1"), e.doc("outbox/group_2")
	if m1["status"] != outboxSent || m2["status"] != outboxSent ||
		!sameIDs(m1["messageIds"], int64(pause+1)) || !sameIDs(m2["messageIds"], int64(cancel+1)) {
		t.Fatalf("outbox = %v / %v", m1, m2)
	}
	chat := e.doc("outboxChats/group")
	if chat["pending"] != false || chat["lastSentSeq"] != int64(2) || chat["leaseOwner"] != nil || chat["leaseUntil"] != nil {
		t.Fatalf("chat = %v", chat)
	}
	// Lượt sau không gửi lại gì.
	if res := e.flush(); res.Sent != 0 || len(e.tg.Calls("sendMessage")) != 3 {
		t.Fatalf("lượt hai gửi lại: %+v", res)
	}
}

func sameIDs(v any, want ...int64) bool {
	ids, ok := v.([]any)
	if !ok || len(ids) != len(want) {
		return false
	}
	for i, id := range ids {
		if id != want[i] {
			return false
		}
	}
	return true
}

// Hai bộ gửi chạy cùng lúc: chỉ một bên giữ lease, mỗi tin đi đúng một lần,
// đúng thứ tự. Bên kia hoặc thấy lease (thì có RetryAt), hoặc tới lúc chat đã
// gửi xong, tuỳ emulator xếp lượt transaction.
func TestEmulatorOutboxParallelFlushersSendOnce(t *testing.T) {
	e := newOutboxEnv(t)
	kinds := []werewolf.Kind{werewolf.KindWolfBite, werewolf.KindSeerPeek, werewolf.KindGuard, werewolf.KindWitchSave, werewolf.KindWitchPoison}
	var msgs []gameMsg
	for _, k := range kinds {
		msgs = append(msgs, noteMsg(chatGroup, k))
	}
	e.write(msgs...)
	e.tg.OnCall(func(tgCall) { time.Sleep(30 * time.Millisecond) })

	var wg sync.WaitGroup
	results, errs := make([]FlushResult, 2), make([]error, 2)
	for i := range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			results[i], errs[i] = e.flushCtx(context.Background())
		}()
	}
	wg.Wait()
	if errs[0] != nil || errs[1] != nil {
		t.Fatal(errs)
	}
	winner, loser := results[0], results[1]
	if winner.Sent == 0 {
		winner, loser = loser, winner
	}
	if winner.Sent != 5 || loser.Sent != 0 {
		t.Fatalf("results = %+v", results)
	}
	texts := e.sent()
	if len(texts) != 5 {
		t.Fatalf("gửi %d tin, mong đợi 5", len(texts))
	}
	for i, k := range kinds {
		if !strings.Contains(texts[i], "Lựa chọn "+actionTexts[k].label+" của bạn") {
			t.Fatalf("tin %d = %q, mong đợi %s", i, texts[i], k)
		}
	}
}

// Crash sau khi Telegram đã nhận tin mà chưa kịp ghi sent: lease còn hạn thì
// không ai đụng vào chat; hết hạn thì tin đó được gửi lại đúng một lần.
func TestEmulatorOutboxCrashBeforeSentResendsOnce(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("cancel"))
	ctx, cancel := context.WithCancel(context.Background())
	e.tg.OnCall(func(tgCall) {
		cancel()
		time.Sleep(50 * time.Millisecond)
	})
	if _, err := e.flushCtx(ctx); err == nil {
		t.Fatal("bộ gửi chết giữa chừng mà không báo lỗi")
	}
	e.tg.OnCall(nil)
	if m := e.doc("outbox/group_1"); m["status"] != outboxSending {
		t.Fatalf("group_1 = %v", m)
	}

	res := e.flush()
	if res.Sent != 0 || !res.RetryAt.Equal(e.now().Add(outboxLease)) || len(e.sent()) != 1 {
		t.Fatalf("lease còn hạn mà vẫn gửi: %+v, %d tin", res, len(e.sent()))
	}
	e.advance(outboxLease + time.Second)
	if res := e.flush(); res.Sent != 2 {
		t.Fatalf("res = %+v", res)
	}
	texts := e.sent()
	if len(texts) != 3 || !strings.Contains(texts[0], "tạm dừng") || texts[1] != texts[0] || !strings.Contains(texts[2], "huỷ") {
		t.Fatalf("texts = %q", texts)
	}
	if m := e.doc("outbox/group_1"); m["status"] != outboxSent || m["attempts"] != int64(2) {
		t.Fatalf("group_1 = %v", m)
	}
}

// 400 (kể cả group đã đổi ID) và tin không render được đều đánh failed rồi
// gửi tin sau.
func TestEmulatorOutboxBadRequestDoesNotBlock(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("resume"), gameMsg{ChatKey: chatGroup, Template: "nope", Data: map[string]any{}}, adminMsg("cancel"))
	e.tg.Then("sendMessage", tgBadRequest("Bad Request: can't parse entities"), tgMigrated(-1009))

	res := e.flush()
	if res.Sent != 1 || res.Failed != 3 || len(e.sent()) != 3 {
		t.Fatalf("res = %+v, %d tin", res, len(e.sent()))
	}
	m1, m2, m3, m4 := e.doc("outbox/group_1"), e.doc("outbox/group_2"), e.doc("outbox/group_3"), e.doc("outbox/group_4")
	if m1["status"] != outboxFailed || m1["errorStatus"] != int64(400) || m1["migrateTo"] != nil || m1["dmBlocked"] != nil {
		t.Fatalf("group_1 = %v", m1)
	}
	if m2["status"] != outboxFailed || m2["migrateTo"] != int64(-1009) {
		t.Fatalf("group_2 = %v", m2)
	}
	if m3["status"] != outboxFailed || !strings.Contains(stringValue(m3["error"]), "template lạ") {
		t.Fatalf("group_3 = %v", m3)
	}
	if m4["status"] != outboxSent || !strings.Contains(e.sent()[2], "huỷ") {
		t.Fatalf("group_4 = %v", m4)
	}
	if chat := e.doc("outboxChats/group"); chat["pending"] != false || chat["lastSentSeq"] != int64(4) {
		t.Fatalf("chat = %v", chat)
	}
}

// DM bị chặn (403) đánh dmOk=false cho M1; DM tới được thì dmOk=true lại.
// Người chơi không có Telegram thì bỏ tin, không gọi API.
func TestEmulatorOutboxDMBlockedMarksPlayer(t *testing.T) {
	e := newOutboxEnv(t)
	seed(t, e.db, "games/"+outboxGame+"/players/u3", map[string]any{"name": "Chi"})
	e.write(noteMsg(dmChat("u1"), werewolf.KindGuard), noteMsg(dmChat("u3"), werewolf.KindGuard))
	e.tg.Then("sendMessage", tgForbidden("Forbidden: bot was blocked by the user"))

	if res := e.flush(); res.Failed != 1 || res.Skipped != 1 || len(e.sent()) != 1 {
		t.Fatalf("res = %+v, %d tin", res, len(e.sent()))
	}
	if c := e.tg.Calls("sendMessage")[0]; c.Params["chat_id"] != "71" {
		t.Fatalf("DM gửi sai chỗ: %v", c.Params)
	}
	if p := e.doc("players/u1"); p["dmOk"] != false {
		t.Fatalf("u1 = %v", p)
	}
	if m := e.doc("outbox/dm:u3_1"); m["status"] != outboxSkipped || m["skipReason"] != "no_telegram" {
		t.Fatalf("dm:u3_1 = %v", m)
	}

	e.write(noteMsg(dmChat("u1"), werewolf.KindSeerPeek))
	if res := e.flush(); res.Sent != 1 {
		t.Fatalf("res = %+v", res)
	}
	if p := e.doc("players/u1"); p["dmOk"] != true {
		t.Fatalf("u1 = %v", p)
	}
}

// 400 "message is not modified" tính là đã gửi.
func TestEmulatorOutboxNotModifiedCountsAsSent(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("cancel"))
	e.tg.Then("sendMessage", tgBadRequest("Bad Request: message is not modified: specified new message content and reply markup are exactly the same"))

	if res := e.flush(); res.Sent != 2 || res.Failed != 0 {
		t.Fatalf("res = %+v", res)
	}
	if m := e.doc("outbox/group_1"); m["status"] != outboxSent {
		t.Fatalf("group_1 = %v", m)
	}
}

// 5xx giữ tin ở pending và dừng cả chat: tin sau không được vượt lên trước.
func TestEmulatorOutboxServerErrorKeepsOrder(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("cancel"))
	e.tg.Then("sendMessage", tgReply{502, `{"ok":false,"error_code":502,"description":"Bad Gateway"}`})

	if _, err := e.flushCtx(context.Background()); err == nil {
		t.Fatal("5xx mà không báo lỗi để task retry")
	}
	if len(e.sent()) != 1 {
		t.Fatalf("gửi %d tin sau lỗi 5xx", len(e.sent()))
	}
	m1, chat := e.doc("outbox/group_1"), e.doc("outboxChats/group")
	if m1["status"] != outboxPending || m1["lastError"] == nil || chat["pending"] != true || chat["leaseOwner"] != nil {
		t.Fatalf("group_1 = %v, chat = %v", m1, chat)
	}
	if res := e.flush(); res.Sent != 2 {
		t.Fatalf("res = %+v", res)
	}
	texts := e.sent()
	if len(texts) != 3 || texts[1] != texts[0] || !strings.Contains(texts[2], "huỷ") {
		t.Fatalf("texts = %q", texts)
	}
}

// 429: không gửi gì trước retry_after, báo mốc để hẹn lại, tới mốc thì gửi tiếp.
func TestEmulatorOutboxTooManyRequestsWaits(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("cancel"))
	e.tg.Then("sendMessage", tgTooManyRequests(7))
	retryAt := e.now().Add(7 * time.Second)

	res, err := e.flushCtx(context.Background())
	if err != nil || res.Sent != 0 || !res.RetryAt.Equal(retryAt) {
		t.Fatalf("res = %+v, err = %v", res, err)
	}
	if m := e.doc("outbox/group_1"); m["status"] != outboxPending {
		t.Fatalf("group_1 = %v", m)
	}
	e.advance(3 * time.Second)
	if res := e.flush(); res.Sent != 0 || !res.RetryAt.Equal(retryAt) || len(e.sent()) != 1 {
		t.Fatalf("gửi trước retry_after: %+v", res)
	}
	e.advance(5 * time.Second)
	if res := e.flush(); res.Sent != 2 || !res.RetryAt.IsZero() {
		t.Fatalf("res = %+v", res)
	}
	if chat := e.doc("outboxChats/group"); chat["retryAt"] != nil || chat["pending"] != false {
		t.Fatalf("chat = %v", chat)
	}
}

// Tin ghi xen vào lúc bộ gửi đang gửi tin cuối vẫn được gửi ngay trong lượt đó.
func TestEmulatorOutboxWriteDuringFlush(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"))
	var once sync.Once
	writeErr := make(chan error, 1)
	e.tg.OnCall(func(tgCall) {
		once.Do(func() { writeErr <- e.writeErr(adminMsg("cancel")) })
	})
	if res := e.flush(); res.Sent != 2 {
		t.Fatalf("res = %+v", res)
	}
	if err := <-writeErr; err != nil {
		t.Fatal(err)
	}
	if chat := e.doc("outboxChats/group"); chat["pending"] != false || chat["lastSentSeq"] != int64(2) {
		t.Fatalf("chat = %v", chat)
	}
}

// Route bot: gặp 429 thì hẹn một lượt game-flush đúng mốc, có TaskID; payload
// lạ thì 204 cho task thôi retry.
func TestEmulatorGameFlushRouteSchedulesRetry(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"))
	e.tg.Then("sendMessage", tgTooManyRequests(30))
	var tasks []PublishTask
	bot := NewBotServer(Config{GameInboundQueue: "game-inbound"}, &Dependencies{Firestore: e.db, Games: e.store, Telegram: e.tg.service("-100psc"),
		EnqueueTask: func(_ context.Context, task PublishTask) (string, error) {
			tasks = append(tasks, task)
			return "created", nil
		}})
	before := time.Now()
	rec := httptest.NewRecorder()
	bot.ServeHTTP(rec, httptest.NewRequest("POST", "/tasks/game-flush", strings.NewReader(`{"gameId":"g1"}`)))
	after := time.Now()
	if rec.Code != 200 || len(tasks) != 1 {
		t.Fatalf("%d %s, tasks = %v", rec.Code, rec.Body, tasks)
	}
	task := tasks[0]
	if task.HandlerPath != "/tasks/game-flush" || task.Queue != QueueGameInbound || task.TaskID == "" ||
		task.Payload != (gameFlushTask{GameID: outboxGame}) || task.ScheduleTime == nil ||
		task.ScheduleTime.Before(before.Add(31*time.Second).Truncate(time.Millisecond)) || task.ScheduleTime.After(after.Add(31*time.Second)) {
		t.Fatalf("task = %+v", task)
	}

	rec = httptest.NewRecorder()
	bot.ServeHTTP(rec, httptest.NewRequest("POST", "/tasks/game-flush", strings.NewReader(`{"gameId":"g1","x":1}`)))
	if rec.Code != 204 || len(tasks) != 1 {
		t.Fatalf("payload lạ: %d, tasks = %d", rec.Code, len(tasks))
	}
}

// Luồng thật: Start qua bot thì group nhận tin mở ván, từng người nhận lá bài
// (sói thấy đồng đội); admin pause qua api thì group nhận tin tạm dừng.
func TestEmulatorStartSendsCardsThroughFlush(t *testing.T) {
	e := newStartEnv(t)
	e.deliver = true
	id := e.createGame()
	e.register(id, 1, 10)
	for range 10 {
		e.tg.Then("getChatMember", memberReply("member"))
	}
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
	if e.game(id)["status"] != gameRunning {
		t.Fatalf("game = %v", e.game(id))
	}
	sec, err := e.store.db.Doc("games/" + id + "/secret/state").Get(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	st, err := decodeState(sec.Data())
	if err != nil {
		t.Fatal(err)
	}

	var group []tgCall
	cards := map[string]string{}
	for _, c := range e.tg.Calls("sendMessage") {
		if c.Params["chat_id"] == testPscChat {
			group = append(group, c)
			continue
		}
		cards[c.Params["chat_id"].(string)] = c.Params["text"].(string)
	}
	if len(group) != 1 || !strings.Contains(group[0].Params["text"].(string), "10 người chơi") {
		t.Fatalf("group = %v", group)
	}
	if len(cards) != 10 {
		t.Fatalf("cards = %d", len(cards))
	}
	for i := 1; i <= 10; i++ {
		text, ok := cards[tgOf(i)]
		if !ok || !strings.HasPrefix(text, "Lá bài của bạn trong ván Ma Sói:\n<b>"+roleLabels[st.Players[userOf(i)].Role]+"</b>") {
			t.Fatalf("lá bài của %s = %q", userOf(i), text)
		}
		if wolf := st.Players[userOf(i)].Role == werewolf.Wolf; wolf != strings.Contains(text, "Đồng đội:") {
			t.Fatalf("lá bài của %s (sói=%v) = %q", userOf(i), wolf, text)
		}
	}

	e.want(e.call("boss", "POST", "/v1/games/"+id+"/admin/pause", nil, ""), 200, "")
	calls := e.tg.Calls("sendMessage")
	if last := calls[len(calls)-1]; last.Params["chat_id"] != testPscChat || !strings.Contains(last.Params["text"].(string), "Ván tạm dừng") {
		t.Fatalf("tin cuối = %v", last.Params)
	}
}

// Bộ gửi chậm tới mức lease hết hạn và bộ gửi khác đã lấy chat: bên chậm dừng
// ngay, không ghi kết quả và không gửi tiếp tin sau.
func TestEmulatorOutboxLostLeaseStops(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("cancel"))
	var fired atomic.Bool
	var other FlushResult
	otherErr := make(chan error, 1)
	e.tg.OnCall(func(tgCall) {
		if fired.CompareAndSwap(false, true) {
			e.advance(outboxLease + time.Second)
			var err error
			other, err = e.flushCtx(context.Background())
			otherErr <- err
		}
	})
	if _, err := e.flushCtx(context.Background()); !errors.Is(err, errLeaseLost) {
		t.Fatalf("err = %v, mong đợi mất lease", err)
	}
	if err := <-otherErr; err != nil || other.Sent != 2 {
		t.Fatalf("bên lấy lại: %+v, %v", other, err)
	}
	// pause đi hai lần (bên chậm và bên lấy lại, chấp nhận theo 3.4), cancel một lần.
	texts := e.sent()
	if len(texts) != 3 || texts[1] != texts[0] || !strings.Contains(texts[2], "huỷ") {
		t.Fatalf("texts = %q", texts)
	}
}

// Chat dài: gửi xong mỗi tin lại gia hạn lease, nên bộ gửi khác chạy lúc đã quá
// 60 giây kể từ lúc claim vẫn thấy chat đang bận.
func TestEmulatorOutboxLeaseRenewedPerMessage(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("resume"), adminMsg("cancel"))
	var n atomic.Int32
	var other FlushResult
	otherErr := make(chan error, 1)
	e.tg.OnCall(func(tgCall) {
		e.advance(40 * time.Second)
		// Lần gửi thứ hai ở T+80: quá lease lúc claim (T+60), còn trong lease đã
		// gia hạn sau tin đầu (T+40+60).
		if n.Add(1) == 2 {
			var err error
			other, err = e.flushCtx(context.Background())
			otherErr <- err
		}
	})
	if res := e.flush(); res.Sent != 3 {
		t.Fatalf("res = %+v", res)
	}
	if err := <-otherErr; err != nil || other.Sent != 0 || other.RetryAt.IsZero() {
		t.Fatalf("bên kia: %+v, %v", other, err)
	}
	if len(e.sent()) != 3 {
		t.Fatalf("gửi %d tin", len(e.sent()))
	}
}

// Lỗi tạm thời ở một chat không chặn các chat khác của ván.
func TestEmulatorOutboxChatErrorDoesNotBlockOthers(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(noteMsg(dmChat("u1"), werewolf.KindGuard), adminMsg("pause"))
	// Chat được duyệt theo ID: dm:u1 trước group.
	e.tg.Then("sendMessage", tgReply{502, `{"ok":false,"error_code":502,"description":"Bad Gateway"}`})
	if _, err := e.flushCtx(context.Background()); err == nil {
		t.Fatal("5xx mà không báo lỗi")
	}
	if m := e.doc("outbox/dm:u1_1"); m["status"] != outboxPending {
		t.Fatalf("dm:u1_1 = %v", m)
	}
	if m := e.doc("outbox/group_1"); m["status"] != outboxSent {
		t.Fatalf("group_1 = %v", m)
	}
}

// Chat còn cờ pending mà đã hết tin thì tắt cờ, không lỗi.
func TestEmulatorOutboxStalePendingClears(t *testing.T) {
	e := newOutboxEnv(t)
	seed(t, e.db, "games/"+outboxGame+"/outboxChats/group", map[string]any{"chatKey": "group", "nextSeq": int64(3), "lastSentSeq": int64(2), "pending": true})
	if res := e.flush(); res.Sent != 0 || len(e.sent()) != 0 {
		t.Fatalf("res = %+v", res)
	}
	if chat := e.doc("outboxChats/group"); chat["pending"] != false {
		t.Fatalf("chat = %v", chat)
	}
}

func (e *outboxEnv) retry() int {
	e.t.Helper()
	n, err := e.store.AdminRetryOutbox(context.Background(), outboxGame, "boss", e.now())
	if err != nil {
		e.t.Fatal(err)
	}
	return n
}

// Retry xếp tin failed thành tin mới ở cuối chat, theo đúng thứ tự cũ, có dòng
// gửi bù với giờ tin gốc. Tin cũ giữ failed và trỏ sang tin mới, nên gọi lại
// không xếp đôi.
func TestEmulatorOutboxRetryRequeuesFailed(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("cancel"), noteMsg(dmChat("u1"), werewolf.KindGuard))
	// Chat được duyệt theo ID: dm:u1 trước group.
	e.tg.Then("sendMessage", tgForbidden("Forbidden: bot was blocked by the user"), tgBadRequest("Bad Request: chat not found"), tgBadRequest("Bad Request: chat not found"))
	if res := e.flush(); res.Failed != 3 {
		t.Fatalf("res = %+v", res)
	}
	e.advance(2 * time.Hour)
	e.write(adminMsg("resume"))
	e.flush()

	if n := e.retry(); n != 3 {
		t.Fatalf("requeued = %d", n)
	}
	for old, want := range map[string]string{"group_1": "group_4", "group_2": "group_5", "dm:u1_1": "dm:u1_2"} {
		o, m := e.doc("outbox/"+old), e.doc("outbox/"+want)
		if o["status"] != outboxFailed || o["retriedAs"] != want || !timeValue(o["retriedAt"]).Equal(e.now()) {
			t.Fatalf("%s = %v", old, o)
		}
		if m["status"] != outboxPending || m["retryOf"] != old || m["template"] != o["template"] || m["data"] != o["data"] ||
			m["eventSeq"] != o["eventSeq"] || !timeValue(m["origAt"]).Equal(timeValue(o["createdAt"])) {
			t.Fatalf("%s = %v", want, m)
		}
	}
	if n := e.retry(); n != 0 {
		t.Fatalf("gọi lại xếp thêm %d tin", n)
	}

	if res := e.flush(); res.Sent != 3 {
		t.Fatalf("res = %+v", res)
	}
	texts := e.sent()[4:]
	late := "<i>Gửi bù tin lúc 22:00 12/10</i>\n"
	if len(texts) != 3 || !strings.HasPrefix(texts[0], late) || !strings.Contains(texts[0], "Bảo vệ") ||
		!strings.HasPrefix(texts[1], late+"<b>Ván tạm dừng") || !strings.HasPrefix(texts[2], late+"<b>Ván đã huỷ") {
		t.Fatalf("texts = %q", texts)
	}
	if !strings.HasPrefix(e.sent()[3], "<b>Ván chạy tiếp") {
		t.Fatalf("tin thường có dòng gửi bù: %q", e.sent()[3])
	}
}

// Nhiều tin (hơn 500 lần ghi trong một transaction) vẫn xếp đủ, đúng thứ tự
// seq. Tin gửi bù rồi lại lỗi thì lần sau vẫn ghi giờ của tin gốc đầu tiên.
func TestEmulatorOutboxRetryManyKeepsOrder(t *testing.T) {
	e := newOutboxEnv(t)
	first := e.now().Add(-5 * time.Hour)
	const total = 260
	for i := 1; i <= total; i++ {
		m := map[string]any{"chatKey": chatGroup, "seq": int64(i), "template": tplAdmin, "data": `{"action":"pause"}`,
			"status": outboxFailed, "eventSeq": int64(i), "createdAt": e.now()}
		if i == 1 {
			m["origAt"], m["retryOf"] = first, "group_0"
		}
		seed(t, e.db, "games/"+outboxGame+"/outbox/group_"+strconv.Itoa(i), m)
	}
	seed(t, e.db, "games/"+outboxGame+"/outboxChats/group", map[string]any{"chatKey": chatGroup, "nextSeq": int64(total + 1), "lastSentSeq": int64(total)})

	if n := e.retry(); n != total {
		t.Fatalf("requeued = %d", n)
	}
	for i := 1; i <= total; i++ {
		m := e.doc("outbox/group_" + strconv.Itoa(total+i))
		if m["retryOf"] != "group_"+strconv.Itoa(i) || m["seq"] != int64(total+i) || m["eventSeq"] != int64(i) {
			t.Fatalf("group_%d = %v", total+i, m)
		}
	}
	if at := timeValue(e.doc("outbox/group_" + strconv.Itoa(total+1))["origAt"]); !at.Equal(first) {
		t.Fatalf("origAt = %v", at)
	}
	if c := e.doc("outboxChats/group"); c["nextSeq"] != int64(2*total+1) || c["pending"] != true {
		t.Fatalf("chat = %v", c)
	}
}

// Hai admin bấm retry cùng lúc: mỗi tin chỉ được xếp lại một lần.
func TestEmulatorOutboxRetryParallelOnce(t *testing.T) {
	e := newOutboxEnv(t)
	e.write(adminMsg("pause"), adminMsg("cancel"))
	e.tg.Then("sendMessage", tgBadRequest("Bad Request: chat not found"), tgBadRequest("Bad Request: chat not found"))
	e.flush()

	var wg sync.WaitGroup
	ns, errs := make([]int, 2), make([]error, 2)
	for i := range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			ns[i], errs[i] = e.store.AdminRetryOutbox(context.Background(), outboxGame, "boss", e.now())
		}()
	}
	wg.Wait()
	if errs[0] != nil || errs[1] != nil || ns[0]+ns[1] != 2 {
		t.Fatalf("ns = %v, errs = %v", ns, errs)
	}
	if c := e.doc("outboxChats/group"); c["nextSeq"] != int64(5) {
		t.Fatalf("chat = %v", c)
	}
}

// Mỗi lần ghi qua api đều giao bot một lượt gửi ngay (3.2 bước 5); luật từ chối
// thì không có gì để gửi.
func TestEmulatorGameWritesKickFlush(t *testing.T) {
	g := newTestModeGame(t)
	g.setKm(0, 5)
	// api dùng giờ thật; lệch đồng hồ ván cho giờ ván lúc này đúng bằng g.wall.
	seedMerge(t, g.storeGame, map[string]any{"clockOffsetNs": int64(g.wall.Sub(time.Now()))})
	h := newAPIHarness(t, g.store)
	var mu sync.Mutex
	var tasks []PublishTask
	h.cfg.GameInboundQueue = "game-inbound"
	h.deps.EnqueueTask = func(_ context.Context, task PublishTask) (string, error) {
		mu.Lock()
		defer mu.Unlock()
		tasks = append(tasks, task)
		return "created", nil
	}
	h.srv = NewAPIServer(h.cfg, h.deps)
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}})
	flushes := func() int {
		mu.Lock()
		defer mu.Unlock()
		n := 0
		for _, task := range tasks {
			if task.HandlerPath == "/tasks/game-flush" && task.Queue == QueueGameInbound && task.TaskID == "" && task.ScheduleTime == nil &&
				task.Payload == (gameFlushTask{GameID: g.id}) {
				n++
			}
		}
		return n
	}
	path := "/v1/games/" + g.id
	adv := h.call("boss", "POST", path+"/admin/advance", map[string]any{"expectedKey": stringValue(g.public()["taskKey"])}, "")
	h.want(adv, 200, "")
	if flushes() != 1 {
		t.Fatalf("advance: tasks = %v", tasks)
	}
	// admin/advance hẹn luôn game-advance cho mốc kế tiếp mà nó trả về (I5).
	nextAt, _ := time.Parse(time.RFC3339Nano, stringValue(adv.body["nextAt"]))
	var scheduled []PublishTask
	for _, task := range tasks {
		if task.HandlerPath == "/tasks/game-advance" {
			scheduled = append(scheduled, task)
		}
	}
	if len(scheduled) != 1 || scheduled[0].ScheduleTime == nil || !scheduled[0].ScheduleTime.Equal(nextAt.Add(30*time.Second)) ||
		scheduled[0].TaskID != StableTaskID("gameadv", g.id+stringValue(adv.body["taskKey"])) {
		t.Fatalf("game-advance = %+v, body %s", scheduled, adv.raw)
	}
	h.want(h.call("boss", "POST", path+"/admin/act-as", map[string]any{"uid": "fake-01", "kind": "seer_peek", "targets": []string{"r2"}}, ""), 422, "not_your_role")
	if flushes() != 1 {
		t.Fatalf("bị từ chối mà vẫn giao gửi: %v", tasks)
	}
	h.want(h.call("boss", "POST", path+"/admin/act-as", map[string]any{"uid": "fake-01", "kind": "wolf_bite", "targets": []string{"r2"}}, ""), 200, "")
	if flushes() != 2 {
		t.Fatalf("act-as: tasks = %v", tasks)
	}

	h.want(h.call("v1", "POST", path+"/admin/retry-outbox", nil, ""), 403, "not_admin")
	h.want(h.call("boss", "POST", "/v1/games/nope/admin/retry-outbox", nil, ""), 404, "")
	if flushes() != 2 {
		t.Fatalf("retry bị từ chối mà vẫn giao gửi: %v", tasks)
	}
	seed(t, g.db, "games/"+g.id+"/outbox/group_99", map[string]any{"chatKey": chatGroup, "seq": int64(99), "template": tplAdmin,
		"data": `{"action":"pause"}`, "status": outboxFailed, "eventSeq": int64(1), "createdAt": g.wall})
	r := h.call("boss", "POST", path+"/admin/retry-outbox", nil, "")
	h.want(r, 200, "")
	if !strings.Contains(string(r.raw), `"requeued":1`) || flushes() != 3 {
		t.Fatalf("retry: %s, tasks = %v", r.raw, tasks)
	}
}
