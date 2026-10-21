//go:build emulator

package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Q1b: trình giả lập cả ván. 16 người chơi đi qua api thật (app) và webhook
// thật (nút Telegram), bot thật chạy game-advance, flush và schedule-tick, Telegram
// giả ghi lại mọi tin. Giờ ván do test điều khiển bằng clockOffsetNs, nên một ván
// 14 vòng chạy trong vài chục giây.
//
// Bot thật không đóng vai người chơi được (Telegram không cho bot bấm nút hay đọc
// tin của bot khác), nên người chơi là các update callback_query dựng tay, giống
// hệt update Telegram gửi tới webhook.
type simEnv struct {
	*startEnv
	g       *storeGame
	srv     *Server // webhook của api
	update  atomic.Int64
	retries atomic.Int64 // số lần webhook trả 503 và "Telegram" gửi lại
	// bursts là tổng thời gian các lượt bấm dồn. Mọi cú bấm đọc rồi ghi chung
	// outboxChats của topic (tin tally), nên transaction tranh nhau, bị Aborted
	// và chờ backoff 1s, 2s, 4s… của client; thời gian dao động theo jitter.
	bursts time.Duration

	wolves, villagers []string
	seer, guard       string
	witch, hunter     string
}

const simPlayers = 16

// simRounds là số vòng ván giả lập chạy rồi admin huỷ, vì ván không giới hạn
// số vòng và kịch bản dưới không để phe nào thắng.
const simRounds = 14

func newSimEnv(t *testing.T) *simEnv {
	t.Helper()
	e := &simEnv{startEnv: newStartEnv(t)}
	e.update.Store(1000)
	e.deliver = true // task chạy ngay như Cloud Tasks; task hẹn giờ thì test tự chạy
	e.store.frameKm = func(_ context.Context, _ string, end time.Time) (FrameKm, error) {
		return FrameKm{FrameEnd: end, OfficialMeters: 5000, Meters: 5000, Source: "official"}, nil
	}
	e.srv = &Server{config: e.cfg, deps: e.deps}

	id := e.createGame()
	e.register(id, 1, simPlayers)
	for range simPlayers {
		e.tg.Then("getChatMember", memberReply("member"))
	}
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
	e.g = &storeGame{t: t, db: e.store.db, store: e.store, id: id, tg: map[string]string{}}
	for i := 1; i <= simPlayers; i++ {
		e.g.tg[userOf(i)] = tgOf(i)
	}

	st := e.g.state()
	if st.Phase != ww.PhaseSetup || len(st.Players) != simPlayers {
		t.Fatalf("sau Start: phase %s, %d người", st.Phase, len(st.Players))
	}
	for _, uid := range sortedPlayers(st) {
		switch st.Players[uid].Role {
		case ww.Wolf:
			e.wolves = append(e.wolves, uid)
		case ww.Villager:
			e.villagers = append(e.villagers, uid)
		case ww.Seer:
			e.seer = uid
		case ww.Guard:
			e.guard = uid
		case ww.Witch:
			e.witch = uid
		case ww.Hunter:
			e.hunter = uid
		}
	}
	// 16 người, tắt Cupid: 3 sói, 4 vai đặc biệt, 9 dân.
	if len(e.wolves) != 3 || len(e.villagers) != 9 || e.seer == "" || e.guard == "" || e.witch == "" || e.hunter == "" {
		t.Fatalf("chia vai: sói %v, dân %v", e.wolves, e.villagers)
	}
	return e
}

// setClock đặt giờ ván thành at cho cả api lẫn bot.
func (e *simEnv) setClock(at time.Time) {
	seedMerge(e.t, e.g, map[string]any{"clockOffsetNs": int64(time.Until(at))})
}

// due là game-advance đã hẹn cho lượt hiện tại: bot phải tự hẹn sau mỗi bước.
func (e *simEnv) due() PublishTask {
	e.t.Helper()
	want := StableTaskID("gameadv", e.g.id+e.g.state().TaskKey())
	tasks := e.tasksTo("/tasks/game-advance")
	for i := len(tasks) - 1; i >= 0; i-- {
		if tasks[i].TaskID == want {
			return tasks[i]
		}
	}
	e.t.Fatalf("chưa hẹn game-advance cho %s", e.g.state().TaskKey())
	return PublishTask{}
}

// fire chạy task game-advance đã hẹn khi giờ ván tới NextAt + 30s, như Cloud
// Tasks; gửi hết outbox; rồi đặt giờ ván vào giữa lượt mới để người chơi bấm.
func (e *simEnv) fire() *ww.State {
	e.t.Helper()
	task, at := e.due(), e.g.state().NextAt()
	e.setClock(at.Add(advanceDelay))
	rec := e.runTask(task)
	var out AdvanceResult
	if rec.Code != 200 || json.Unmarshal(rec.Body.Bytes(), &out) != nil || out.Steps != 1 {
		e.t.Fatalf("game-advance lúc %s: %d %s", vnTime(at), rec.Code, rec.Body)
	}
	e.drain()
	e.setClock(at.Add(time.Minute))
	return e.g.state()
}

// drain gửi nốt outbox; không được còn tin lỗi.
func (e *simEnv) drain() {
	e.t.Helper()
	for range 5 {
		pending, err := e.store.HasPendingOutbox(context.Background(), e.g.id)
		if err != nil {
			e.t.Fatal(err)
		}
		if !pending {
			e.noFailed()
			return
		}
		if rec := e.runTask(gameFlushTaskFor(e.g.id, time.Time{})); rec.Code != 200 {
			e.t.Fatalf("flush: %d %s", rec.Code, rec.Body)
		}
	}
	e.t.Fatal("outbox vẫn còn tin chờ sau 5 lần flush")
}

func (e *simEnv) outbox() *firestore.CollectionRef {
	return e.store.gameRef(e.g.id).Collection("outbox")
}

func (e *simEnv) noFailed() {
	e.t.Helper()
	docs, err := e.outbox().Where("status", "==", outboxFailed).Documents(context.Background()).GetAll()
	if err != nil {
		e.t.Fatal(err)
	}
	for _, d := range docs {
		if d.Data()["retriedAs"] == nil {
			e.t.Fatalf("tin lỗi %s: %v", d.Ref.ID, d.Data()["error"])
		}
	}
}

func (e *simEnv) nextUpdate() int64 { return e.update.Add(1) }

// openVote đặt giờ ván qua 20h: biểu quyết mở từ đây, engine không có mốc 20h.
func (e *simEnv) openVote(st *ww.State) {
	e.setClock(st.NightAt.Add(22*time.Hour + time.Minute))
}

// press gửi update callback_query vào webhook của api. Webhook trả 503 (lỗi
// Firestore tạm thời) thì gửi lại đúng update đó, như Telegram làm.
func (e *simEnv) press(updateID int64, uid, data string) string {
	e.t.Helper()
	raw, _ := json.Marshal(map[string]any{"update_id": updateID, "callback_query": map[string]any{
		"id": fmt.Sprintf("cq-%d", updateID), "from": map[string]any{"id": mustInt(e.g.tg[uid])}, "data": data,
	}})
	for attempt := 0; ; attempt++ {
		rec := httptest.NewRecorder()
		e.srv.serveTelegramUpdate(context.Background(), rec, raw, e.deps.EnqueueTask)
		if rec.Code == 503 && attempt < 10 {
			e.retries.Add(1)
			continue
		}
		var body map[string]any
		if rec.Code != 200 || json.Unmarshal(rec.Body.Bytes(), &body) != nil || body["callback_query_id"] != fmt.Sprintf("cq-%d", updateID) {
			e.t.Errorf("webhook cho %s: %d %s", uid, rec.Code, rec.Body)
			return ""
		}
		text, _ := body["text"].(string)
		return text
	}
}

// btn là callback_data của nút trong lượt hiện tại. Với vote, idx là vị trí
// trong voteChoices.
func (e *simEnv) btn(kind ww.Kind, op string, idx ...int) string {
	e.t.Helper()
	data, err := gameButton{GameID: e.g.id, TurnKey: turnKey(e.g.state()), Kind: kind, Op: op, Idx: idx}.data()
	if err != nil {
		e.t.Fatal(err)
	}
	return data
}

func (e *simEnv) pos(uid string) int { return positions(e.g.state())[uid] }

// app gửi hành động qua API của app.
func (e *simEnv) app(uid string, body map[string]any) {
	e.t.Helper()
	e.want(e.call(uid, "POST", "/v1/games/"+e.g.id+"/actions", body, ""), 200, "")
}

// action là doc action của uid ở vòng hiện tại.
func (e *simEnv) action(uid string, kind ww.Kind) map[string]any {
	e.t.Helper()
	d, err := e.g.ref(fmt.Sprintf("rounds/%d/actions/%s_%s", e.g.state().Round, uid, kind)).Get(context.Background())
	if err != nil {
		e.t.Fatalf("action %s/%s: %v", uid, kind, err)
	}
	return d.Data()
}

func (e *simEnv) target(uid string, kind ww.Kind) string {
	ts, _ := e.action(uid, kind)["targets"].([]any)
	if len(ts) != 1 {
		return ""
	}
	return ts[0].(string)
}

func (e *simEnv) alive() []string {
	st := e.g.state()
	var out []string
	for _, uid := range sortedPlayers(st) {
		if st.Players[uid].Alive {
			out = append(out, uid)
		}
	}
	return out
}

func (e *simEnv) events() int { return e.g.count("events") }

// burst: mọi uid bấm cùng lúc, mỗi người một update mới. Như trên prod, webhook
// chỉ enqueue game-flush; queue game-inbound chạy tối đa 2 task cùng lúc (I2),
// nên các task flush được gom lại và chạy sau, 2 task một lúc.
func (e *simEnv) burst(uids []string, data func(uid string) string) map[string]string {
	e.mu.Lock()
	from := len(e.tasks)
	e.deliver = false
	e.mu.Unlock()
	defer e.dispatch(from, 2)

	var mu sync.Mutex
	toasts := map[string]string{}
	var wg sync.WaitGroup
	start := make(chan struct{})
	for _, uid := range uids {
		upd, d := e.nextUpdate(), data(uid)
		wg.Add(1)
		go func() {
			defer wg.Done()
			<-start
			text := e.press(upd, uid, d)
			mu.Lock()
			toasts[uid] = text
			mu.Unlock()
		}()
	}
	t0, r0 := time.Now(), e.retries.Load()
	close(start)
	wg.Wait()
	e.bursts += time.Since(t0)
	e.t.Logf("%d người bấm cùng lúc: %s, webhook trả 503 %d lần", len(uids), time.Since(t0).Round(time.Millisecond), e.retries.Load()-r0)
	return toasts
}

// dispatch bật lại deliver rồi chạy các game-flush gửi ngay đã enqueue từ task
// thứ from, tối đa n task cùng lúc.
func (e *simEnv) dispatch(from, n int) {
	e.mu.Lock()
	e.deliver = true
	var flushes []PublishTask
	for _, task := range e.tasks[from:] {
		if task.HandlerPath == "/tasks/game-flush" && task.ScheduleTime == nil {
			flushes = append(flushes, task)
		}
	}
	e.mu.Unlock()
	sem := make(chan struct{}, n)
	var wg sync.WaitGroup
	for _, task := range flushes {
		wg.Add(1)
		sem <- struct{}{}
		go func() {
			defer func() { <-sem; wg.Done() }()
			if rec := e.runTask(task); rec.Code != 200 {
				e.t.Errorf("flush: %d %s", rec.Code, rec.Body)
			}
		}()
	}
	wg.Wait()
}

// sentSince là các sendMessage từ call thứ from, theo chat và nội dung.
func (e *simEnv) sentSince(from int) map[string]int {
	out := map[string]int{}
	for _, c := range e.tg.Calls("")[from:] {
		if c.Method == "sendMessage" {
			out[fmt.Sprint(c.Params["chat_id"], "|", c.Params["text"])]++
		}
	}
	return out
}

// TestEmulatorGameSimulation là "Xong khi" của Q1b: một lệnh chạy hết ván 14
// vòng dưới 1 phút, replay events ra đúng state, và các kịch bản dưới đây có kết
// quả mong đợi viết trước, ghi ngay ở chỗ chạy kịch bản.
func TestEmulatorGameSimulation(t *testing.T) {
	began := time.Now()
	e := newSimEnv(t)
	w0, w1, w2 := e.wolves[0], e.wolves[1], e.wolves[2]
	v := e.villagers

	// Start đã kick game-advance và nó hẹn 22h: setup → đêm 1.
	st := e.fire()
	if st.Phase != ww.PhaseNight || st.Round != 1 {
		t.Fatalf("22h: phase %s vòng %d", st.Phase, st.Round)
	}

	// Vòng 1, đêm. Bấm chéo kênh: w0 chọn v0 qua app rồi đổi sang v1 qua nút; w1
	// chọn v1 qua nút; w2 không chọn. Mong đợi: 0h khoá v1.
	e.app(w0, map[string]any{"kind": "wolf_bite", "targets": []string{v[0]}})
	if text := e.press(e.nextUpdate(), w1, e.btn(ww.KindWolfBite, opPick, e.pos(v[1]))); !strings.HasPrefix(text, "Đã chọn ") {
		t.Fatalf("w1 cắn = %q", text)
	}
	e.press(e.nextUpdate(), w0, e.btn(ww.KindWolfBite, opPick, e.pos(v[1])))
	if got := e.target(w0, ww.KindWolfBite); got != v[1] {
		t.Fatalf("w0 đổi qua nút mà action còn %s", got)
	}
	// Tiên tri chọn qua nút (chờ Chốt), soi qua app, rồi mới bấm Chốt. Mong đợi:
	// app soi được, nút Chốt báo đã dùng lượt.
	if text := e.press(e.nextUpdate(), e.seer, e.btn(ww.KindSeerPeek, opPick, e.pos(w2))); text != "Bấm Chốt để xác nhận." {
		t.Fatalf("soi chọn = %q", text)
	}
	e.app(e.seer, map[string]any{"kind": "seer_peek", "targets": []string{w2}})
	if text := e.press(e.nextUpdate(), e.seer, e.btn(ww.KindSeerPeek, opConfirm, e.pos(w2))); text != "Bạn đã dùng lượt này rồi." {
		t.Fatalf("Chốt sau khi soi qua app = %q", text)
	}
	e.app(e.guard, map[string]any{"kind": "guard", "targets": []string{v[2]}})

	if st = e.fire(); st.Phase != ww.PhaseDawn || st.Bitten != v[1] {
		t.Fatalf("0h: phase %s, bị cắn %q, mong đợi %s", st.Phase, st.Bitten, v[1])
	}
	// Rạng sáng: phù thuỷ cứu qua app. Mong đợi: 10h không ai chết.
	e.app(e.witch, map[string]any{"kind": "witch_save"})
	if st = e.fire(); st.Phase != ww.PhaseDay || len(e.alive()) != simPlayers || st.SavePotion {
		t.Fatalf("10h: phase %s, còn %d người, bình cứu %v", st.Phase, len(e.alive()), st.SavePotion)
	}

	// Ngày 1. Telegram gửi lại update: v3 đề cử v4 (update cũ) rồi cả 16 người
	// đề cử cùng một giây (v3 đổi sang w0); sau đó Telegram giao lại update cũ.
	// Mong đợi: đủ 16 đề cử, không ai lỗi; update cũ không đổi lựa chọn của v3.
	stale := e.nextUpdate()
	e.press(stale, v[3], e.btn(ww.KindNominate, opPick, e.pos(v[4])))
	toasts := e.burst(e.alive(), func(uid string) string {
		if uid == w0 {
			return e.btn(ww.KindNominate, opPick, e.pos(v[4]))
		}
		return e.btn(ww.KindNominate, opPick, e.pos(w0))
	})
	for uid, text := range toasts {
		if !strings.HasPrefix(text, "Đã chọn ") {
			t.Errorf("%s đề cử = %q", uid, text)
		}
	}
	if text := e.press(stale, v[3], e.btn(ww.KindNominate, opPick, e.pos(v[4]))); text != "Đã nhận lựa chọn mới hơn của bạn." {
		t.Fatalf("update giao lại = %q", text)
	}
	if got := e.target(v[3], ww.KindNominate); got != w0 {
		t.Fatalf("update cũ đổi đề cử của v3 thành %s", got)
	}
	e.drain()
	// Hai sói cắn, soi, bảo vệ, cứu, 16 đề cử. Chọn soi mà chưa Chốt thì chưa ghi.
	acts, err := e.store.gameRef(e.g.id).Collection("rounds").Doc(fmt.Sprint(st.Round)).Collection("actions").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if n := len(acts); n != 2+3+simPlayers {
		t.Fatalf("vòng 1 có %d action", n)
	}

	e.fire() // 15h nhắc đề cử
	if st = e.fire(); st.Phase != ww.PhaseTrial || st.Nominee != w0 {
		t.Fatalf("17h: phase %s, lên giàn %q", st.Phase, st.Nominee)
	}
	// 15 người còn lại cùng bấm Treo một lúc. Mong đợi: 22h w0 bị treo.
	var voters []string
	for _, uid := range e.alive() {
		if uid != w0 {
			voters = append(voters, uid)
		}
	}
	e.openVote(st)
	e.burst(voters, func(string) string { return e.btn(ww.KindVote, opPick, 0) })
	for _, uid := range voters {
		if c := e.action(uid, ww.KindVote)["choice"]; c != ww.ChoiceHang {
			t.Fatalf("phiếu của %s = %v", uid, c)
		}
	}
	e.drain()
	e.fire() // 21h nhắc biểu quyết
	if st = e.fire(); st.Round != 2 || st.Phase != ww.PhaseNight || st.Players[w0].Alive || len(e.alive()) != simPlayers-1 {
		t.Fatalf("22h ngày 1: vòng %d %s, w0 sống %v, còn %d", st.Round, st.Phase, st.Players[w0].Alive, len(e.alive()))
	}

	// Vòng 2 → 14: sói không cắn, tiên tri soi qua nút, bảo vệ qua app, ban ngày
	// một người đề cử qua app và ba người bấm Tha. Mong đợi: không ai chết, chưa
	// phe nào thắng nên hết vòng 14 ván vẫn chạy sang vòng 15.
	for st.Round <= simRounds {
		if st.Phase == ww.PhaseEnded {
			t.Fatalf("vòng %d: ván kết thúc, thắng %q", st.Round, st.Winner)
		}
		r := st.Round
		switch {
		case st.Phase == ww.PhaseNight && st.Hunter == nil:
			peek := e.alive()[(r*5)%len(e.alive())]
			if peek == e.seer {
				peek = w1
			}
			e.press(e.nextUpdate(), e.seer, e.btn(ww.KindSeerPeek, opPick, e.pos(peek)))
			e.press(e.nextUpdate(), e.seer, e.btn(ww.KindSeerPeek, opConfirm, e.pos(peek)))
			guarded := v[0] // không bảo vệ lại người đêm trước; tick trễ làm lỡ một đêm
			if st.LastGuarded == guarded {
				guarded = v[1]
			}
			e.app(e.guard, map[string]any{"kind": "guard", "targets": []string{guarded}})
		case st.Phase == ww.PhaseDay && st.Reminded != st.PhaseKey():
			e.app(v[2], map[string]any{"kind": "nominate", "targets": []string{v[3+r%3]}})
		case st.Phase == ww.PhaseTrial && st.Reminded != st.PhaseKey():
			e.openVote(st)
			for _, uid := range []string{v[0], v[1], e.hunter} {
				e.app(uid, map[string]any{"kind": "vote", "choice": ww.ChoiceSpare})
			}
		}

		switch {
		case r == 3 && st.Phase == ww.PhaseTrial && st.Reminded == st.PhaseKey():
			st = e.lateTick()
		case r == 5 && st.Phase == ww.PhaseTrial && st.Reminded == st.PhaseKey():
			st = e.doubleTick()
		case r == 7 && st.Phase == ww.PhaseTrial && st.Reminded == st.PhaseKey():
			st = e.flushErrors()
		case r == 9 && st.Phase == ww.PhaseDay && st.Reminded != st.PhaseKey():
			st = e.redeployBot()
		default:
			st = e.fire()
		}
		if len(e.alive()) != simPlayers-1 {
			t.Fatalf("vòng %d %s: còn %d người", st.Round, st.Phase, len(e.alive()))
		}
	}
	if st.Winner != "" || st.Round != simRounds+1 || st.Phase != ww.PhaseNight || e.game(e.g.id)["status"] != gameRunning {
		t.Fatalf("sau vòng %d: thắng %q, vòng %d %s, status %v", simRounds, st.Winner, st.Round, st.Phase, e.game(e.g.id)["status"])
	}
	e.due() // vẫn hẹn mốc kế của vòng 15

	// Ván kẹt thì admin huỷ: từ đó game-advance không hẹn mốc nào nữa.
	e.want(e.call("boss", "POST", "/v1/games/"+e.g.id+"/admin/cancel", nil, ""), 200, "")
	n := len(e.scheduled())
	e.post("/tasks/game-advance", gameAdvanceTask{GameID: e.g.id})
	if len(e.scheduled()) != n || e.game(e.g.id)["status"] != gameCancelled {
		t.Fatalf("ván đã huỷ mà game-advance vẫn hẹn mốc kế, status %v", e.game(e.g.id)["status"])
	}

	replayMatches(t, e.g)
	e.drain()
	// Tiêu chí 1 phút tính phần ván, không tính lượt bấm dồn: thời gian tranh
	// chấp ở đó là số đo của kịch bản, đã log riêng.
	elapsed := time.Since(began)
	t.Logf("ván %d vòng: %d event, %d call Telegram, %d lần webhook 503, %s (bấm dồn %s)", simRounds, e.events(), len(e.tg.Calls("")), e.retries.Load(), elapsed.Round(time.Millisecond), e.bursts.Round(time.Millisecond))
	if elapsed-e.bursts > time.Minute {
		t.Errorf("chạy hết ván mất %s ngoài lượt bấm dồn, quá 1 phút", elapsed-e.bursts)
	}
}

func (e *simEnv) scheduled() []PublishTask {
	var out []PublishTask
	for _, t := range e.tasksTo("/tasks/game-advance") {
		if t.ScheduleTime != nil {
			out = append(out, t)
		}
	}
	return out
}

func (e *simEnv) post(path string, payload any) {
	e.t.Helper()
	body, _ := json.Marshal(payload)
	rec := httptest.NewRecorder()
	e.bot.ServeHTTP(rec, httptest.NewRequest("POST", path, bytes.NewReader(body)))
	if rec.Code != 200 {
		e.t.Fatalf("%s: %d %s", path, rec.Code, rec.Body)
	}
}

// lateTick: task 22h bị mất và tick tới trễ 3 giờ (1h sáng). Mong đợi: một tick
// chạy bù đủ hai bước 22h và 0h, rồi hẹn đúng mốc 10h.
func (e *simEnv) lateTick() *ww.State {
	e.t.Helper()
	e.due() // task 22h có hẹn, nhưng Cloud Tasks làm mất
	before, at := e.events(), e.g.state().NextAt()
	e.setClock(at.Add(3 * time.Hour))
	e.post("/tasks/schedule-tick", map[string]any{})
	e.drain()
	st := e.g.state()
	if e.events()-before != 2 || st.Phase != ww.PhaseDawn || st.Round != 4 || st.Bitten != "" {
		e.t.Fatalf("tick trễ: %d event, %s vòng %d, cắn %q", e.events()-before, st.Phase, st.Round, st.Bitten)
	}
	if next := st.NextAt().In(vietnam); next.Hour() != 10 {
		e.t.Fatalf("tick trễ hẹn %s", vnTime(next))
	}
	e.due()
	return st
}

// doubleTick: task 22h mất, hai tick chạy cùng lúc. Mong đợi: chỉ một bước, mỗi
// tin của bước đó tới Telegram đúng một lần.
func (e *simEnv) doubleTick() *ww.State {
	e.t.Helper()
	before, calls, at := e.events(), len(e.tg.Calls("")), e.g.state().NextAt()
	e.setClock(at.Add(5 * time.Minute))
	var wg sync.WaitGroup
	for range 2 {
		wg.Add(1)
		go func() {
			defer wg.Done()
			rec := httptest.NewRecorder()
			e.bot.ServeHTTP(rec, httptest.NewRequest("POST", "/tasks/schedule-tick", bytes.NewReader([]byte("{}"))))
			if rec.Code != 200 {
				e.t.Errorf("tick đôi: %d %s", rec.Code, rec.Body)
			}
		}()
	}
	wg.Wait()
	e.drain()
	st := e.g.state()
	if e.events()-before != 1 || st.Phase != ww.PhaseNight || st.Round != 6 {
		e.t.Fatalf("tick đôi: %d event, %s vòng %d", e.events()-before, st.Phase, st.Round)
	}
	sent := e.sentSince(calls)
	if len(sent) == 0 {
		e.t.Fatal("tick đôi mà không gửi tin nào")
	}
	for k, n := range sent {
		if n != 1 {
			e.t.Fatalf("tick đôi gửi %d lần: %s", n, k)
		}
	}
	e.setClock(at.Add(time.Minute))
	return st
}

// flushErrors: Telegram trả 429 (retry_after 1) cho tin đầu tiên và 400 cho tin
// thứ hai của bước 22h. Mong đợi: lượt gửi đầu ghi 1 tin lỗi và hẹn một
// game-flush sau retry_after; chạy task đó thì chat bị 429 gửi tiếp; admin
// retry-outbox thì tin lỗi được gửi bù và ghi sent; ngoài hai tin bị lỗi (lần lỗi
// cũng tới Telegram), không tin nào tới hai lần.
func (e *simEnv) flushErrors() *ww.State {
	e.t.Helper()
	flushes := len(e.tasksTo("/tasks/game-flush"))
	calls := len(e.tg.Calls(""))
	e.tg.Then("sendMessage", tgTooManyRequests(1), tgBadRequest("Bad Request: can't parse entities"))
	task, at := e.due(), e.g.state().NextAt()
	e.setClock(at.Add(advanceDelay))
	if rec := e.runTask(task); rec.Code != 200 {
		e.t.Fatalf("game-advance: %d %s", rec.Code, rec.Body)
	}
	var retry *PublishTask
	for _, task := range e.tasksTo("/tasks/game-flush")[flushes:] {
		if task.ScheduleTime != nil {
			retry = &task
		}
	}
	failed, err := e.outbox().Where("status", "==", outboxFailed).Documents(context.Background()).GetAll()
	if err != nil {
		e.t.Fatal(err)
	}
	if retry == nil || len(failed) != 1 {
		e.t.Fatalf("429/400: task hẹn %v, %d tin lỗi", retry, len(failed))
	}
	if pending, _ := e.store.HasPendingOutbox(context.Background(), e.g.id); !pending {
		e.t.Fatal("chat bị 429 mà không còn tin chờ")
	}
	time.Sleep(time.Until(*retry.ScheduleTime))
	if rec := e.runTask(*retry); rec.Code != 200 {
		e.t.Fatalf("flush hẹn lại: %d %s", rec.Code, rec.Body)
	}
	if pending, _ := e.store.HasPendingOutbox(context.Background(), e.g.id); pending {
		e.t.Fatal("chạy flush hẹn lại mà vẫn còn tin chờ")
	}
	r := e.call("boss", "POST", "/v1/games/"+e.g.id+"/admin/retry-outbox", nil, "")
	e.want(r, 200, "")
	if r.body["requeued"] != float64(1) {
		e.t.Fatalf("retry-outbox = %s", r.raw)
	}
	e.drain()
	again, err := e.outbox().Doc(failed[0].Ref.ID).Get(context.Background())
	if err != nil {
		e.t.Fatal(err)
	}
	retried, _ := again.Data()["retriedAs"].(string)
	if d, err := e.outbox().Doc(retried).Get(context.Background()); err != nil || d.Data()["status"] != outboxSent {
		e.t.Fatalf("tin gửi bù %q: %v", retried, err)
	}
	twice := 0
	for k, n := range e.sentSince(calls) {
		if n > 2 {
			e.t.Fatalf("gửi %d lần: %s", n, k)
		}
		if n == 2 {
			twice++
		}
	}
	if twice > 2 {
		e.t.Fatalf("%d tin tới Telegram hai lần", twice)
	}
	st := e.g.state()
	e.setClock(at.Add(time.Minute))
	return st
}

// redeployBot: bot cũ kick flush cho mốc 15h rồi chết giữa lúc gửi, sau khi
// Telegram đã nhận tin mà trước khi ghi sent. Bản bot mới lên, lease 60 giây
// của bot cũ hết hạn. Mong đợi: bot mới gửi lại đúng tin đó (Telegram không có
// idempotency key nên người nhận thấy hai lần, 3.4 chấp nhận), các tin khác một
// lần; task 17h do bot cũ hẹn vẫn chạy được trên bot mới.
func (e *simEnv) redeployBot() *ww.State {
	e.t.Helper()
	e.deliver = false
	task, at := e.due(), e.g.state().NextAt()
	e.setClock(at.Add(advanceDelay))
	if rec := e.runTask(task); rec.Code != 200 {
		e.t.Fatalf("game-advance 15h: %d %s", rec.Code, rec.Body)
	}
	flushes := e.tasksTo("/tasks/game-flush")
	kick := flushes[len(flushes)-1]

	calls := len(e.tg.Calls(""))
	ctx, die := context.WithCancel(context.Background())
	var once sync.Once
	e.tg.OnCall(func(c tgCall) {
		if c.Method == "sendMessage" {
			once.Do(die)
		}
	})
	_, _ = e.store.FlushGame(ctx, e.g.id, e.tg.service("-100psc"), time.Now)
	e.tg.OnCall(nil)
	sending, err := e.outbox().Where("status", "==", outboxSending).Documents(context.Background()).GetAll()
	if err != nil {
		e.t.Fatal(err)
	}
	if len(sending) != 1 {
		e.t.Fatalf("bot cũ chết để lại %d tin đang gửi", len(sending))
	}
	// 60 giây trôi qua: lease của bot cũ hết hạn.
	chat := e.g.ref("outboxChats/" + sending[0].Data()["chatKey"].(string))
	if _, err := chat.Set(context.Background(), map[string]any{"leaseUntil": time.Now().Add(-time.Second)}, firestore.MergeAll); err != nil {
		e.t.Fatal(err)
	}

	e.bot = NewBotServer(Config{GameInboundQueue: "game-inbound"}, &Dependencies{Firestore: e.store.db, Games: e.store, TelegramLinks: e.deps.TelegramLinks, Telegram: e.tg.service("-100psc"), EnqueueTask: e.publish})
	e.deliver = true
	if rec := e.runTask(kick); rec.Code != 200 {
		e.t.Fatalf("bot mới flush: %d %s", rec.Code, rec.Body)
	}
	e.drain()
	sent := e.sentSince(calls)
	twice := 0
	for k, n := range sent {
		switch n {
		case 1:
		case 2:
			twice++
		default:
			e.t.Fatalf("gửi %d lần: %s", n, k)
		}
	}
	if twice != 1 {
		e.t.Fatalf("%d tin gửi hai lần, mong đợi đúng tin đang gửi lúc bot chết", twice)
	}
	if d, err := sending[0].Ref.Get(context.Background()); err != nil || d.Data()["status"] != outboxSent {
		e.t.Fatalf("tin đang gửi lúc bot chết chưa sent: %v", err)
	}
	e.setClock(at.Add(time.Minute))
	st := e.g.state()
	if st.Reminded != st.PhaseKey() {
		e.t.Fatal("mốc 15h chưa nhắc")
	}
	return st
}
