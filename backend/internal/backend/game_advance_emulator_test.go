//go:build emulator

package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// advanceEnv là bot thật trên ván của newStoreGame (không phải ván thử), với
// đồng hồ giả và Cloud Tasks giả: task chỉ được ghi lại, test tự chạy.
type advanceEnv struct {
	*storeGame
	clock time.Time
	tasks []PublishTask
	bot   http.Handler
}

func newAdvanceEnv(t *testing.T, g *storeGame) *advanceEnv {
	t.Helper()
	e := &advanceEnv{storeGame: g, clock: msgStart}
	e.bot = NewBotServer(Config{GameInboundQueue: "game-inbound"}, &Dependencies{
		Firestore: g.db, Games: g.store, EnqueueTask: e.publish, Now: func() time.Time { return e.clock },
	})
	return e
}

func (e *advanceEnv) publish(_ context.Context, p PublishTask) (string, error) {
	e.tasks = append(e.tasks, p)
	return "created", nil
}

func (e *advanceEnv) post(path string, payload any) map[string]any {
	e.t.Helper()
	body, _ := json.Marshal(payload)
	rec := httptest.NewRecorder()
	e.bot.ServeHTTP(rec, httptest.NewRequest("POST", path, bytes.NewReader(body)))
	if rec.Code != 200 {
		e.t.Fatalf("%s: %d %s", path, rec.Code, rec.Body)
	}
	var out map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &out)
	return out
}

func (e *advanceEnv) tasksTo(path string) []PublishTask {
	var out []PublishTask
	for _, t := range e.tasks {
		if t.HandlerPath == path {
			out = append(out, t)
		}
	}
	return out
}

// scheduled là các game-advance có hẹn giờ.
func (e *advanceEnv) scheduled() []PublishTask {
	var out []PublishTask
	for _, t := range e.tasksTo("/tasks/game-advance") {
		if t.ScheduleTime != nil {
			out = append(out, t)
		}
	}
	return out
}

// lastScheduled là game-advance hẹn giờ mới nhất; phải hẹn đúng at, TaskID theo
// TaskKey của state hiện tại.
func (e *advanceEnv) lastScheduled(at time.Time) PublishTask {
	e.t.Helper()
	s := e.scheduled()
	if len(s) == 0 {
		e.t.Fatal("chưa hẹn game-advance nào")
	}
	task := s[len(s)-1]
	if !task.ScheduleTime.Equal(at) || task.Queue != QueueGameInbound ||
		task.TaskID != StableTaskID("gameadv", e.id+e.state().TaskKey()) {
		e.t.Fatalf("game-advance hẹn %v, TaskID %q; mong đợi %v, TaskKey %s", task.ScheduleTime, task.TaskID, at, e.state().TaskKey())
	}
	return task
}

// I5 "Xong khi": ván thật (không testMode) tự chuyển qua các mốc chỉ nhờ
// game-advance: mỗi lần task tới hạn thì chạy bước, kick flush, hẹn mốc kế.
func TestEmulatorGameAdvanceSchedulesItself(t *testing.T) {
	e := newAdvanceEnv(t, newStoreGame(t))
	// Start kick game-advance chạy ngay lúc 9h: chưa có gì tới hạn, chỉ hẹn 22h.
	if out := e.post("/tasks/game-advance", gameAdvanceTask{GameID: e.id}); out["steps"] != float64(0) {
		t.Fatalf("kick = %v", out)
	}
	task := e.lastScheduled(time.Date(2026, 10, 15, 22, 0, 30, 0, vietnam))

	for _, step := range []struct {
		phase    ww.Phase
		reminded bool
		next     time.Time
	}{
		{ww.PhaseNight, false, time.Date(2026, 10, 16, 0, 0, 30, 0, vietnam)}, // 22h mở đêm, hẹn 0h
		{ww.PhaseDawn, false, time.Date(2026, 10, 16, 10, 0, 30, 0, vietnam)}, // 0h khoá sói, hẹn 10h
		{ww.PhaseDay, false, time.Date(2026, 10, 16, 18, 0, 30, 0, vietnam)},  // 10h sang ngày, hẹn nhắc 18h
		{ww.PhaseDay, true, time.Date(2026, 10, 16, 20, 0, 30, 0, vietnam)},   // 18h nhắc đề cử, hẹn 20h
	} {
		flushes := len(e.tasksTo("/tasks/game-flush"))
		e.clock = *task.ScheduleTime
		out := e.post(task.HandlerPath, task.Payload)
		st := e.state()
		if out["steps"] != float64(1) || st.Phase != step.phase || (st.Reminded == st.PhaseKey()) != step.reminded {
			t.Fatalf("lúc %s: out %v, phase %s, reminded %q", vnTime(e.clock), out, st.Phase, st.Reminded)
		}
		if len(e.tasksTo("/tasks/game-flush")) != flushes+1 {
			t.Fatalf("lúc %s: chạy bước mà không kick flush", vnTime(e.clock))
		}
		task = e.lastScheduled(step.next)
	}

	// Cloud Tasks giao lại task cũ: không chốt lại, hẹn đúng task đã có (cùng
	// TaskID nên Cloud Tasks bỏ).
	n := len(e.scheduled())
	if out := e.post(task.HandlerPath, gameAdvanceTask{GameID: e.id}); out["steps"] != float64(0) {
		t.Fatalf("giao lại = %v", out)
	}
	if s := e.scheduled(); len(s) != n+1 || s[n].TaskID != task.TaskID {
		t.Fatalf("giao lại hẹn %+v", s[n:])
	}
}

// Ván tạm dừng thì game-advance không hẹn gì. Resume và extend (cả lệnh HTTP
// lẫn lệnh DM) kick game-advance, và nó hẹn theo hạn mới.
func TestEmulatorGameAdvanceFollowsPauseAndExtend(t *testing.T) {
	g, h := runningAPIGame(t)
	e := newAdvanceEnv(t, g)
	e.clock = time.Now()
	h.cfg.GameInboundQueue = "game-inbound"
	h.deps.EnqueueTask = e.publish
	h.srv = NewAPIServer(h.cfg, h.deps)
	path := "/v1/games/" + g.id
	kicks := func() int {
		n := 0
		for _, t := range e.tasksTo("/tasks/game-advance") {
			if t.ScheduleTime == nil && t.TaskID == "" {
				n++
			}
		}
		return n
	}
	// wallAt là giờ thật ứng với giờ ván at, cộng 30s của task.
	wallAt := func(at time.Time) time.Time {
		snap, err := g.db.Doc("games/" + g.id).Get(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		return at.Add(-clockOffset(snap.Data())).Add(advanceDelay)
	}

	h.want(h.call("boss", "POST", path+"/admin/pause", nil, ""), 200, "")
	if kicks() != 0 {
		t.Fatal("pause mà kick game-advance")
	}
	e.post("/tasks/game-advance", gameAdvanceTask{GameID: g.id})
	if s := e.scheduled(); len(s) != 0 {
		t.Fatalf("ván tạm dừng mà vẫn hẹn: %+v", s)
	}

	h.want(h.call("boss", "POST", path+"/admin/resume", nil, ""), 200, "")
	if kicks() != 1 {
		t.Fatal("resume không kick game-advance")
	}
	e.post("/tasks/game-advance", gameAdvanceTask{GameID: g.id})
	e.lastScheduled(wallAt(time.Date(2026, 10, 16, 0, 0, 0, 0, vietnam)))

	h.want(h.call("boss", "POST", path+"/admin/extend", map[string]any{"minutes": 30}, ""), 200, "")
	if kicks() != 2 {
		t.Fatal("extend không kick game-advance")
	}
	e.post("/tasks/game-advance", gameAdvanceTask{GameID: g.id})
	e.lastScheduled(wallAt(time.Date(2026, 10, 16, 0, 30, 0, 0, vietnam)))

	// Lệnh DM: /extend kick, /pause thì không.
	srv := &Server{config: h.cfg, deps: h.deps}
	for _, c := range []struct {
		cmd, arg string
		kicks    int
	}{{"/extend", "10", 3}, {"/pause", "", 3}, {"/resume", "", 4}} {
		if _, _, err := srv.runAdminCommand(context.Background(), g.id, "boss", c.cmd, c.arg); err != nil {
			t.Fatalf("%s: %v", c.cmd, err)
		}
		if kicks() != c.kicks {
			t.Fatalf("sau %s có %d lần kick, mong đợi %d", c.cmd, kicks(), c.kicks)
		}
	}
}

// Tick là lưới an toàn: task hẹn bị mất thì tick chạy bước quá hạn, kick flush và
// hẹn lại; không có bước thì vẫn kick flush khi outbox còn tin chờ. Chạy cả khi
// bot không có Gemini (Bot nil), trước đây tick trả 204 và không làm gì.
func TestEmulatorTickAdvancesGame(t *testing.T) {
	e := newAdvanceEnv(t, newStoreGame(t))
	e.clock = time.Date(2026, 10, 15, 22, 7, 0, 0, vietnam)
	e.post("/tasks/schedule-tick", map[string]any{})
	if st := e.state(); st.Phase != ww.PhaseNight {
		t.Fatalf("tick không chốt 22h: phase %s", st.Phase)
	}
	e.lastScheduled(time.Date(2026, 10, 16, 0, 0, 30, 0, vietnam))
	if len(e.tasksTo("/tasks/game-flush")) != 1 {
		t.Fatal("tick chạy bước mà không kick flush")
	}

	// Tick sau: không còn bước, outbox chưa ai gửi nên vẫn kick flush.
	e.clock = e.clock.Add(10 * time.Minute)
	e.post("/tasks/schedule-tick", map[string]any{})
	if len(e.tasksTo("/tasks/game-flush")) != 2 {
		t.Fatal("outbox còn tin chờ mà tick không kick flush")
	}
	// Gửi hết rồi thì thôi.
	if _, err := e.store.FlushGame(context.Background(), e.id, newFakeTelegram(t).service(testPscChat), time.Now); err != nil {
		t.Fatal(err)
	}
	e.post("/tasks/schedule-tick", map[string]any{})
	if len(e.tasksTo("/tasks/game-flush")) != 2 {
		t.Fatal("outbox trống mà tick vẫn kick flush")
	}

	// Ván lỗi thì tick báo 5xx.
	seed(t, e.db, "games/"+e.id+"/secret/state", map[string]any{"state": "{"})
	rec := httptest.NewRecorder()
	e.bot.ServeHTTP(rec, httptest.NewRequest("POST", "/tasks/schedule-tick", bytes.NewReader([]byte("{}"))))
	if rec.Code != 500 {
		t.Fatalf("ván lỗi mà tick trả %d", rec.Code)
	}
}
