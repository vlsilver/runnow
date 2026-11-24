//go:build emulator

package backend

import (
	"context"
	"slices"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// startedNoTelegramGame mở một ván không Telegram 10 người rồi chạy task Start.
func startedNoTelegramGame(t *testing.T, e *startEnv) string {
	t.Helper()
	r := e.call("boss", "POST", "/v1/games", map[string]any{"roles": map[string]bool{"cupid": false}, "settings": map[string]any{"telegram": false}}, "")
	e.want(r, 201, "")
	id := r.body["id"].(string)
	for i := 1; i <= 10; i++ {
		e.want(e.call(userOf(i), "POST", "/v1/games/"+id+"/registration", nil, ""), 200, "")
	}
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
	if rec := e.runTask(e.tasksTo("/tasks/game-start")[0]); rec.Code != 200 {
		t.Fatalf("game-start: %d %s", rec.Code, rec.Body)
	}
	return id
}

func (e *startEnv) pushToken(uid string) {
	e.t.Helper()
	seed(e.t, e.store.db, "pushTokens/"+uid, map[string]any{"uid": uid, "token": "tok-" + uid, "platform": "ios", "updatedAt": time.Now()})
}

func (e *startEnv) pushedTokens() []string {
	e.fcm.mu.Lock()
	defer e.fcm.mu.Unlock()
	out := []string{}
	for _, m := range e.fcm.sent {
		out = append(out, m.Token)
	}
	slices.Sort(out)
	return out
}

func TestEmulatorGameStartPushesThePlayers(t *testing.T) {
	e := newStartEnv(t)
	e.pushToken(userOf(1))
	e.pushToken(userOf(2))
	e.pushToken("outsider")
	id := startedNoTelegramGame(t, e)

	tasks := e.tasksTo(gamePushPath)
	if len(tasks) != 1 || tasks[0].Queue != QueueNotify || tasks[0].TaskID == "" {
		t.Fatalf("task push = %+v", tasks)
	}
	if rec := e.runTask(tasks[0]); rec.Code != 200 {
		t.Fatalf("game-push: %d %s", rec.Code, rec.Body)
	}
	if got := e.pushedTokens(); !slices.Equal(got, []string{"tok-u01", "tok-u02"}) {
		t.Fatalf("tokens = %v", got)
	}
	m := e.fcm.sent[0]
	if m.Notification.Title != "Ma Sói" || m.Notification.Body != "Ván đã bắt đầu. Vào xem lá bài của bạn." ||
		m.Data["kind"] != "game_started" || m.Data["gameId"] != id {
		t.Fatalf("message = %+v / %+v", m.Notification, m.Data)
	}
}

func TestEmulatorGamePushStopsWhenItNoLongerApplies(t *testing.T) {
	e := newStartEnv(t)
	e.pushToken(userOf(1))
	id := startedNoTelegramGame(t, e)
	task := e.tasksTo(gamePushPath)[0]

	seed(t, e.store.db, "appConfig/push", map[string]any{"off": []any{"game_started"}})
	if rec := e.runTask(task); rec.Code != 200 {
		t.Fatalf("tắt loại push: %d %s", rec.Code, rec.Body)
	}
	if _, err := e.store.db.Doc("appConfig/push").Delete(context.Background()); err != nil {
		t.Fatal(err)
	}

	if _, err := e.store.db.Collection("games").Doc(id).Update(context.Background(), []firestore.Update{{Path: "status", Value: gameCancelled}}); err != nil {
		t.Fatal(err)
	}
	if rec := e.runTask(task); rec.Code != 200 {
		t.Fatalf("ván đã huỷ: %d %s", rec.Code, rec.Body)
	}
	if got := e.pushedTokens(); len(got) != 0 {
		t.Fatalf("không được báo, tokens = %v", got)
	}
}

func TestEmulatorGameStartRevertedDoesNotPush(t *testing.T) {
	e := newStartEnv(t)
	id := e.createGame()
	e.register(id, 1, 10)
	e.want(e.call("boss", "POST", "/v1/games/"+id+"/start", nil, ""), 202, "")
	e.tg.Then("getChatMember", memberReply("kicked"))
	for i := 0; i < 9; i++ {
		e.tg.Then("getChatMember", memberReply("member"))
	}
	if rec := e.runTask(e.tasksTo("/tasks/game-start")[0]); rec.Code != 200 {
		t.Fatalf("game-start: %d %s", rec.Code, rec.Body)
	}
	if e.game(id)["status"] != gameRegistering {
		t.Fatalf("status = %v", e.game(id)["status"])
	}
	if n := len(e.tasksTo(gamePushPath)); n != 0 {
		t.Fatalf("ván trả về đăng ký mà vẫn hẹn %d push", n)
	}
}
