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
	"os"
	"os/exec"
	"sort"
	"strings"
	"sync"
	"testing"
	"time"
)

// startEnv là api thật (token của Auth emulator) cộng bot thật với Telegram giả.
// Task game-start được bắt lại; deliver thì chuyển ngay sang bot như Cloud Tasks.
type startEnv struct {
	*apiHarness
	tg  *fakeTelegram
	bot http.Handler

	mu         sync.Mutex
	tasks      []PublishTask
	publishErr error
	deliver    bool
}

func newStartEnv(t *testing.T) *startEnv {
	t.Helper()
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	e := &startEnv{apiHarness: h, tg: newFakeTelegram(t)}
	h.cfg.GameInboundQueue = "game-inbound"
	h.deps.EnqueueTask = e.publish
	h.srv = NewAPIServer(h.cfg, h.deps)
	e.bot = NewBotServer(Config{GameInboundQueue: "game-inbound"}, &Dependencies{Firestore: db, Games: h.store, TelegramLinks: h.deps.TelegramLinks, Telegram: e.tg.service("-100psc"), EnqueueTask: e.publish})
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}})
	return e
}

func (e *startEnv) publish(_ context.Context, task PublishTask) (string, error) {
	e.mu.Lock()
	if e.publishErr != nil {
		e.mu.Unlock()
		return "", e.publishErr
	}
	e.tasks = append(e.tasks, task)
	deliver := e.deliver
	e.mu.Unlock()
	if deliver {
		if rec := e.runTask(task); rec.Code != 200 {
			return "", fmt.Errorf("bot trả %d: %s", rec.Code, rec.Body)
		}
	}
	return "created", nil
}

func (e *startEnv) runTask(task PublishTask) *httptest.ResponseRecorder {
	body, _ := json.Marshal(task.Payload)
	rec := httptest.NewRecorder()
	e.bot.ServeHTTP(rec, httptest.NewRequest("POST", task.HandlerPath, bytes.NewReader(body)))
	return rec
}

func (e *startEnv) taskList() []PublishTask {
	e.mu.Lock()
	defer e.mu.Unlock()
	return append([]PublishTask(nil), e.tasks...)
}

// tasksTo là các task đã enqueue tới route path.
func (e *startEnv) tasksTo(path string) []PublishTask {
	var out []PublishTask
	for _, t := range e.taskList() {
		if t.HandlerPath == path {
			out = append(out, t)
		}
	}
	return out
}

func tgOf(i int) string { return fmt.Sprint(7000 + i) }

func userOf(i int) string { return fmt.Sprintf("u%02d", i) }

// register liên kết rồi đăng ký người thứ from..to, theo đúng thứ tự đó.
func (e *startEnv) register(id string, from, to int) {
	e.t.Helper()
	for i := from; i <= to; i++ {
		linkUser(e.t, e.apiHarness, userOf(i), tgOf(i), true)
		e.want(e.call(userOf(i), "POST", "/v1/games/"+id+"/registration", nil, ""), 200, "")
	}
}

func (e *startEnv) createGame() string {
	e.t.Helper()
	r := e.call("boss", "POST", "/v1/games", map[string]any{"roles": map[string]bool{"cupid": false}}, "")
	e.want(r, 201, "")
	return r.body["id"].(string)
}

func memberReply(status string) tgReply {
	return tgReply{200, `{"ok":true,"result":{"status":"` + status + `","user":{"id":1}}}`}
}

func (e *startEnv) game(id string) map[string]any {
	e.t.Helper()
	d, err := e.store.db.Collection("games").Doc(id).Get(context.Background())
	if err != nil {
		e.t.Fatal(err)
	}
	return d.Data()
}

func (e *startEnv) exists(path string) bool {
	e.t.Helper()
	_, err := e.store.db.Doc(path).Get(context.Background())
	return err == nil
}

// L2 "Xong khi": tạo → đăng ký → dryRun → Start; người bị loại đúng lý do,
// user thường gọi start thì 403.
func TestEmulatorGameStartThroughBot(t *testing.T) {
	e := newStartEnv(t)
	id := e.createGame()
	e.register(id, 1, 13)
	// u12 huỷ liên kết sau khi đăng ký; u13 đã rời PSC theo cờ đang lưu.
	if _, err := e.store.db.Doc("telegramLinks/u12").Delete(context.Background()); err != nil {
		t.Fatal(err)
	}
	seed(t, e.store.db, "tgLinks/"+tgOf(13), map[string]any{"uid": "u13", "inPsc": false})
	seed(t, e.store.db, "tgLinks/"+tgOf(1), map[string]any{"uid": "u01", "inPsc": true, "username": "an01"})
	// u03 đổi sang tg khác sau khi đăng ký: Start phải chụp tg mới.
	linkUser(t, e.apiHarness, "u03", "8003", true)

	e.want(e.call("u01", "POST", "/v1/games/"+id+"/start?dryRun=true", nil, ""), 403, "not_admin")
	e.want(e.call("u01", "POST", "/v1/games/"+id+"/start", nil, ""), 403, "not_admin")
	e.want(e.call("boss", "POST", "/v1/games/nope/start?dryRun=true", nil, ""), 404, "not_found")

	r := e.call("boss", "POST", "/v1/games/"+id+"/start?dryRun=true", nil, "")
	e.want(r, 200, "")
	var preview StartPreview
	if err := json.Unmarshal(r.raw, &preview); err != nil {
		t.Fatal(err)
	}
	// 11 người, tắt Cupid: 3 sói, Tiên tri, Bảo vệ, Phù thuỷ, 5 dân.
	// -18 + 7 + 3 + 4 + 5 = 1.
	if preview.Count != 11 || !preview.CanStart || preview.BalanceScore == nil || *preview.BalanceScore != 1 {
		t.Fatalf("preview = %s", r.raw)
	}
	if len(preview.WillExclude) != 2 || preview.WillExclude[0].UID != "u12" || preview.WillExclude[0].Reason != "not_linked" ||
		preview.WillExclude[1].UID != "u13" || preview.WillExclude[1].Reason != "not_in_psc" || preview.WillExclude[1].ReasonLabel == "" {
		t.Fatalf("willExclude = %+v", preview.WillExclude)
	}
	if preview.Players[0].UID != "u01" || preview.Players[0].TgUsername != "an01" {
		t.Fatalf("players[0] = %+v", preview.Players[0])
	}
	if e.game(id)["status"] != gameRegistering || len(e.taskList()) != 0 {
		t.Fatal("dryRun mà đổi ván hoặc enqueue")
	}

	r = e.call("boss", "POST", "/v1/games/"+id+"/start", nil, "")
	e.want(r, 202, "")
	tasks := e.taskList()
	if len(tasks) != 1 || tasks[0].Queue != QueueGameInbound || tasks[0].HandlerPath != "/tasks/game-start" ||
		tasks[0].TaskID != StableTaskID("gamestart", []any{id, int64(1)}) || r.body["attempt"] != float64(1) {
		t.Fatalf("task = %+v, body %s", tasks, r.raw)
	}
	if e.game(id)["status"] != gameStarting {
		t.Fatal("chưa sang starting")
	}
	// Đang chia bài thì không ai đăng ký hay rút được nữa.
	linkUser(t, e.apiHarness, "u14", tgOf(14), true)
	e.want(e.call("u14", "POST", "/v1/games/"+id+"/registration", nil, ""), 409, "phase_closed")
	e.want(e.call("u02", "DELETE", "/v1/games/"+id+"/registration", nil, ""), 409, "phase_closed")

	// Bot hỏi Telegram cho 12 người đã liên kết (u12 thì không), theo thứ tự đăng
	// ký: u05 vừa rời PSC, u13 đã vào lại.
	var replies []tgReply
	for i := 1; i <= 11; i++ {
		if i == 5 {
			replies = append(replies, memberReply("left"))
		} else {
			replies = append(replies, memberReply("member"))
		}
	}
	e.tg.Then("getChatMember", append(replies, memberReply("member"))...)
	rec := e.runTask(tasks[0])
	if rec.Code != 200 {
		t.Fatalf("game-start: %d %s", rec.Code, rec.Body)
	}
	var out StartOutcome
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if out.Result != "started" || out.Players != 11 || len(out.Excluded) != 2 || out.Excluded[0].UID != "u05" || out.Excluded[1].UID != "u12" {
		t.Fatalf("outcome = %s", rec.Body)
	}
	calls := e.tg.Calls("getChatMember")
	if len(calls) != 12 || calls[0].Params["chat_id"] != "-100psc" || calls[2].Params["user_id"] != float64(8003) || calls[11].Params["user_id"] != float64(7013) {
		t.Fatalf("getChatMember = %v", calls)
	}
	g := e.game(id)
	if g["status"] != gameRunning || g["playerCount"] != int64(11) || g["startError"] != nil {
		t.Fatalf("game = %v", g)
	}
	if e.exists("games/"+id+"/players/u05") || e.exists("games/"+id+"/players/u12") || !e.exists("games/"+id+"/players/u13") {
		t.Fatal("người bị loại còn trong ván, hoặc người đạt bị xoá")
	}
	if p, err := e.store.db.Doc("games/" + id + "/players/u03").Get(context.Background()); err != nil || p.Data()["tgUserId"] != int64(8003) {
		t.Fatalf("players/u03 không chụp tg mới: %v", p.Data())
	}
	if d, err := e.store.db.Doc("tgLinks/" + tgOf(5)).Get(context.Background()); err != nil || d.Data()["inPsc"] != false {
		t.Fatal("bot không ghi lại inPsc mới hỏi được")
	}
	sg := &storeGame{t: t, db: e.store.db, store: e.store, id: id}
	st := sg.state()
	if len(st.Players) != 11 || st.Players["u05"] != nil || st.Players["u13"] == nil {
		t.Fatalf("state có %d người", len(st.Players))
	}
	replayMatches(t, sg)

	// Task chạy lại (Cloud Tasks giao hai lần) thì không hỏi Telegram, không chia lại.
	rec = e.runTask(tasks[0])
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code != 200 || out.Result != "skipped" || len(e.tg.Calls("getChatMember")) != 12 {
		t.Fatalf("chạy lại: %d %s", rec.Code, rec.Body)
	}
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 409, "game_running")
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start?dryRun=true", nil, ""), 409, "game_running")
}

// Bot thấy không đủ 10 người thì đưa ván về đăng ký và ghi lý do cho admin;
// Start lại thì có TaskID mới.
func TestEmulatorGameStartRevertsWhenTooFew(t *testing.T) {
	e := newStartEnv(t)
	id := e.createGame()
	e.register(id, 1, 9)
	r := e.call("boss", "POST", "/v1/games/"+id+"/start", nil, "")
	e.want(r, 422, "not_enough_players")
	if r.body["count"] != float64(9) || e.game(id)["status"] != gameRegistering || len(e.taskList()) != 0 {
		t.Fatalf("thiếu người mà vẫn đi tiếp: %s", r.raw)
	}

	e.register(id, 10, 10)
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
	e.tg.Then("getChatMember", memberReply("kicked"))
	for i := 0; i < 9; i++ {
		e.tg.Then("getChatMember", memberReply("member"))
	}
	rec := e.runTask(e.taskList()[0])
	var out StartOutcome
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code != 200 || out.Result != "reverted" || out.Players != 9 {
		t.Fatalf("game-start: %d %s", rec.Code, rec.Body)
	}
	g := e.game(id)
	se, _ := g["startError"].(map[string]any)
	if g["status"] != gameRegistering || se["code"] != "not_enough_players" || !e.exists("games/"+id+"/players/u01") {
		t.Fatalf("game = %v", g)
	}
	if e.exists("games/" + id + "/secret/state") {
		t.Fatal("trả về đăng ký mà đã chia vai")
	}
	d := e.call("boss", "GET", "/v1/games/"+id, nil, "")
	if errBody, _ := d.body["startError"].(map[string]any); errBody["code"] != "not_enough_players" || d.body["status"] != gameRegistering {
		t.Fatalf("admin không thấy startError: %s", d.raw)
	}
	if d := e.call("u02", "GET", "/v1/games/"+id, nil, ""); d.body["startError"] != nil {
		t.Fatalf("người chơi thấy startError: %s", d.raw)
	}

	// Mở đăng ký lại; Start lần hai có TaskID khác lần một.
	e.register(id, 11, 11)
	r = e.call("boss", "POST", "/v1/games/"+id+"/start", nil, "")
	e.want(r, 202, "")
	tasks := e.taskList()
	if len(tasks) != 2 || r.body["attempt"] != float64(2) || tasks[1].TaskID == tasks[0].TaskID {
		t.Fatalf("tasks = %+v", tasks)
	}
	if e.game(id)["startError"] != nil {
		t.Fatal("Start lại mà còn startError cũ")
	}
}

// Telegram lỗi thì task retry: ván giữ starting, không xoá ai. Enqueue lỗi thì
// admin bấm lại được.
func TestEmulatorGameStartTelegramAndEnqueueErrors(t *testing.T) {
	e := newStartEnv(t)
	id := e.createGame()
	e.register(id, 1, 10)

	e.publishErr = errors.New("cloud tasks unavailable")
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 500, "")
	if e.game(id)["status"] != gameStarting {
		t.Fatal("enqueue lỗi thì ván nằm ở starting, chờ admin bấm lại")
	}
	e.publishErr = nil
	r := e.call("boss", "POST", "/v1/games/"+id+"/start", nil, "")
	e.want(r, 202, "")
	if r.body["attempt"] != float64(2) {
		t.Fatalf("attempt = %v", r.body["attempt"])
	}

	e.tg.Then("getChatMember", memberReply("member"), tgTooManyRequests(1))
	rec := e.runTask(e.taskList()[0])
	if rec.Code < 500 {
		t.Fatalf("lỗi Telegram phải retry: %d %s", rec.Code, rec.Body)
	}
	if e.game(id)["status"] != gameStarting || !e.exists("games/"+id+"/players/u02") || e.exists("games/"+id+"/secret/state") {
		t.Fatal("lỗi Telegram mà đã đổi ván")
	}

	// Payload hỏng thì 204, không retry mãi.
	rec = httptest.NewRecorder()
	e.bot.ServeHTTP(rec, httptest.NewRequest("POST", "/tasks/game-start", bytes.NewReader([]byte(`{"gameId":1}`))))
	if rec.Code != 204 {
		t.Fatalf("payload hỏng: %d", rec.Code)
	}
}

// Chưa cấu hình queue thì 503 và không đổi ván.
func TestEmulatorGameStartWithoutQueueIs503(t *testing.T) {
	e := newStartEnv(t)
	e.cfg.GameInboundQueue = ""
	e.srv = NewAPIServer(e.cfg, e.deps)
	id := e.createGame()
	e.register(id, 1, 10)
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 503, "tasks_unavailable")
	if e.game(id)["status"] != gameRegistering {
		t.Fatal("503 mà đã sang starting")
	}
}

// Huỷ lúc đang chia bài: task game-start chạy sau thì thôi, không hỏi Telegram.
func TestEmulatorGameCancel(t *testing.T) {
	e := newStartEnv(t)
	id := e.createGame()
	e.register(id, 1, 10)
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
	e.want(e.call("u01", "POST", "/v1/games/"+id+"/admin/cancel", nil, ""), 403, "not_admin")
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/admin/cancel", nil, ""), 200, "")

	rec := e.runTask(e.taskList()[0])
	var out StartOutcome
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	if rec.Code != 200 || out.Result != "skipped" || len(e.tg.Calls("getChatMember")) != 0 {
		t.Fatalf("game-start sau khi huỷ: %d %s", rec.Code, rec.Body)
	}
	g := e.game(id)
	if g["status"] != gameCancelled || g["cancelledBy"] != "boss" || g["eventSeq"] != int64(1) {
		t.Fatalf("game = %v", g)
	}
	ob, err := e.store.db.Doc("games/" + id + "/outbox/group_1").Get(context.Background())
	if err != nil || ob.Data()["template"] != tplAdmin || ob.Data()["data"] != `{"action":"cancel"}` {
		t.Fatalf("outbox: %v %v", err, ob.Data())
	}
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/admin/cancel", nil, ""), 409, "invalid_state")
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/admin/pause", nil, ""), 409, "invalid_state")
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 409, "game_running")
	if d := e.call("u01", "GET", "/v1/games/"+id, nil, ""); d.body["status"] != gameCancelled {
		t.Fatalf("detail: %s", d.raw)
	}
	// Huỷ xong thì tạo được ván mới.
	e.createGame()
}

// Pause/resume ván đang chạy: hành động bị chặn khi pause, không ghi feed, group
// nhận tin admin, replay events vẫn ra đúng state.
func TestEmulatorGamePauseResume(t *testing.T) {
	g, h := runningAPIGame(t)
	path := "/v1/games/" + g.id
	feedBefore := g.count("feed")
	h.want(h.call("v1", "POST", path+"/admin/pause", nil, ""), 403, "not_admin")
	h.want(h.call("boss", "POST", path+"/admin/resume", nil, ""), 409, "invalid_state")
	h.want(h.call("boss", "POST", path+"/admin/pause", nil, ""), 200, "")
	if !g.state().Paused {
		t.Fatal("state chưa pause")
	}
	if d := h.call("v1", "GET", path, nil, ""); d.body["status"] != "paused" {
		t.Fatalf("detail: %s", d.raw)
	}
	h.want(h.call("seer", "POST", path+"/actions", map[string]any{"kind": "seer_peek", "targets": []string{"w1"}}, ""), 409, "paused")
	h.want(h.call("boss", "POST", path+"/admin/pause", nil, ""), 409, "invalid_state")

	h.want(h.call("boss", "POST", path+"/admin/resume", nil, ""), 200, "")
	st := g.state()
	if st.Paused {
		t.Fatal("state chưa resume")
	}
	if d := h.call("v1", "GET", path, nil, ""); d.body["status"] != gameRunning {
		t.Fatalf("detail: %s", d.raw)
	}
	h.want(h.call("seer", "POST", path+"/actions", map[string]any{"kind": "seer_peek", "targets": []string{"w1"}}, ""), 200, "")
	if g.count("feed") != feedBefore {
		t.Fatal("pause/resume ghi vào feed")
	}
	docs, err := g.db.Collection("games").Doc(g.id).Collection("outbox").Where("template", "==", tplAdmin).Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	sort.Slice(docs, func(i, j int) bool { return number(docs[i].Data()["seq"]) < number(docs[j].Data()["seq"]) })
	var templates []string
	for _, d := range docs {
		templates = append(templates, d.Data()["data"].(string))
	}
	wantResume, _ := json.Marshal(map[string]any{"action": "resume", "deadline": st.Deadline().UTC().Format(time.RFC3339)})
	if len(templates) != 2 || templates[0] != `{"action":"pause"}` || templates[1] != string(wantResume) {
		t.Fatalf("outbox admin = %v", templates)
	}
	replayMatches(t, g)
}

// runSmoke chạy scripts/game_smoke.sh với api thật qua HTTP.
func (e *startEnv) runSmoke(env ...string) (string, error) {
	srv := httptest.NewServer(e.srv)
	defer srv.Close()
	cmd := exec.Command("bash", "../../scripts/game_smoke.sh")
	cmd.Env = append(os.Environ(), append([]string{"BASE_URL=" + srv.URL, "POLL_SECONDS=4"}, env...)...)
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// L2 "Xong khi": script curl trong repo chạy đủ luồng tạo → đăng ký → dryRun →
// Start trên ván thử (admin, một người thật, 8 người giả), có hai ca âm.
func TestEmulatorGameSmokeScript(t *testing.T) {
	e := newStartEnv(t)
	e.deliver = true
	setConfig(t, e.apiHarness, map[string]any{"adminUids": []any{"boss"}, "testerUids": []any{"u01"}})
	linkUser(t, e.apiHarness, "boss", "6999", true)
	linkUser(t, e.apiHarness, "u01", tgOf(1), true)
	e.tg.Then("getChatMember", memberReply("member"), memberReply("member"))
	out, err := e.runSmoke("ADMIN_TOKEN="+e.token("boss"), "OUTSIDER_TOKEN="+e.token("u99"),
		"PLAYER_TOKENS="+e.token("u01"), "TEST_CHAT_ID=-100test", "CANCEL_AT_END=1")
	if err != nil {
		t.Fatalf("script lỗi: %v\n%s", err, out)
	}
	for _, want := range []string{"đã đăng ký 2 người thật", "not_admin\nnot_found", "count=10 canStart=true", "status=running", "admin nhận vai: ", "OK"} {
		if !strings.Contains(out, want) {
			t.Fatalf("output thiếu %q:\n%s", want, out)
		}
	}
	tasks := e.tasksTo("/tasks/game-start")
	if len(tasks) != 1 || len(e.tg.Calls("getChatMember")) != 2 {
		t.Fatalf("tasks = %d, getChatMember = %d", len(tasks), len(e.tg.Calls("getChatMember")))
	}
	id := tasks[0].Payload.(gameStartTask).GameID
	if g := e.game(id); g["status"] != gameCancelled || g["testMode"] != true {
		t.Fatalf("game = %v", g)
	}
}

// Script phải fail khi API trả mã khác mong đợi, và khi bot trả ván về đăng ký;
// không in OK cho xong.
func TestEmulatorGameSmokeScriptFails(t *testing.T) {
	e := newStartEnv(t)
	setConfig(t, e.apiHarness, map[string]any{"adminUids": []any{}})
	out, err := e.runSmoke("ADMIN_TOKEN="+e.token("boss"), "OUTSIDER_TOKEN="+e.token("u99"), "TEST_CHAT_ID=-100test")
	if err == nil || !strings.Contains(out, "FAIL POST /v1/games: 403, mong đợi 201") || strings.Contains(out, "OK") {
		t.Fatalf("err = %v\n%s", err, out)
	}

	// dryRun thấy đủ người theo inPsc đang lưu, nhưng lúc chia bài admin đã rời PSC.
	setConfig(t, e.apiHarness, map[string]any{"adminUids": []any{"boss"}})
	linkUser(t, e.apiHarness, "boss", "6999", true)
	e.deliver = true
	e.tg.Then("getChatMember", memberReply("left"))
	out, err = e.runSmoke("ADMIN_TOKEN="+e.token("boss"), "OUTSIDER_TOKEN="+e.token("u99"), "TEST_CHAT_ID=-100test")
	if err == nil || !strings.Contains(out, "FAIL bot chưa chia bài xong") || !strings.Contains(out, "not_enough_players") || strings.Contains(out, "OK") {
		t.Fatalf("err = %v\n%s", err, out)
	}
}

// Hai task game-start chồng nhau (Cloud Tasks giao lại, admin bấm Start hai lần).
// Dựng xen kẽ bằng cách chạy trọn task B ngay lúc task A hỏi Telegram lần đầu.
func TestEmulatorRunStartRaces(t *testing.T) {
	cases := []struct {
		name         string
		inner, outer bool // người chơi có ở PSC theo B, theo A
		wantStatus   string
	}{
		// B chia bài trước; A cũng đủ người nhưng thấy ván đã chạy thì thôi.
		{"B chia bài trước", true, true, gameRunning},
		// B thiếu người nên trả về đăng ký; A đủ người cũng không được chia từ registering.
		{"B trả về đăng ký", false, true, gameRegistering},
		// B đã chia bài; A thiếu người cũng không được kéo ván đang chạy về đăng ký.
		{"A thiếu người sau khi B chia", true, false, gameRunning},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			e := newStartEnv(t)
			id := e.createGame()
			e.register(id, 1, 10)
			e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
			first := true
			outer := func(ctx context.Context, _ int64) (bool, error) {
				if first {
					first = false
					inner := func(context.Context, int64) (bool, error) { return c.inner, nil }
					if _, err := e.store.RunStart(ctx, id, inner, time.Now()); err != nil {
						return false, err
					}
				}
				return c.outer, nil
			}
			out, err := e.store.RunStart(context.Background(), id, outer, time.Now())
			if err != nil || out.Result != "skipped" {
				t.Fatalf("task A: %+v, %v", out, err)
			}
			if g := e.game(id); g["status"] != c.wantStatus {
				t.Fatalf("status = %v", g["status"])
			}
		})
	}
}

// Ván thử ép vai không vừa bộ của bảng 1.2: chạy lại task cũng vậy, nên bot trả
// ván về đăng ký với deal_failed thay vì retry mãi.
func TestEmulatorGameStartDealFailedReverts(t *testing.T) {
	e := newStartEnv(t)
	linkUser(t, e.apiHarness, "boss", "6999", true)
	r := e.call("boss", "POST", "/v1/games", map[string]any{"testMode": true, "chatId": "-100test"}, "")
	e.want(r, 201, "")
	id := r.body["id"].(string)
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/registration", nil, ""), 200, "")
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/admin/fake-players", map[string]any{"count": 9}, ""), 200, "")
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/admin/roles", map[string]any{"roles": map[string]string{"fake-01": "wolf", "fake-02": "wolf", "fake-03": "wolf"}}, ""), 200, "")
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
	e.tg.Then("getChatMember", memberReply("member"))
	rec := e.runTask(e.taskList()[0])
	var out StartOutcome
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	se, _ := e.game(id)["startError"].(map[string]any)
	if rec.Code != 200 || out.Result != "reverted" || se["code"] != "deal_failed" || e.game(id)["status"] != gameRegistering {
		t.Fatalf("%d %s, startError %v", rec.Code, rec.Body, se)
	}
}
