//go:build emulator

package backend

import (
	"context"
	"strconv"
	"testing"
	"time"

	"cloud.google.com/go/firestore"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Luật một ván tính theo chat và theo chủ ván: hai chủ ván ở hai chat mở được
// hai ván cùng lúc; trùng chat hay trùng chủ ván thì 409. Con trỏ
// gameState/current ở lại ván PSC, ván group khác không lấy mất.
func TestEmulatorCreateGameScopesOneGamePerChatAndHost(t *testing.T) {
	db := emulatorDB(t)
	store := NewGameStore(db, testPscChat)
	ctx := context.Background()
	psc, err := store.CreateGame(ctx, NewGameInput{CreatedBy: "boss", ChatID: testPscChat}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	other, err := store.CreateGame(ctx, NewGameInput{CreatedBy: "an", ChatID: "-1002222"}, msgStart)
	if err != nil {
		t.Fatalf("chat khác, chủ ván khác phải mở được: %v", err)
	}
	wantHTTP(t, second(store.CreateGame(ctx, NewGameInput{CreatedBy: "binh", ChatID: "-1002222"}, msgStart)), 409, "game_running")
	wantHTTP(t, second(store.CreateGame(ctx, NewGameInput{CreatedBy: "an", ChatID: "-1003333"}, msgStart)), 409, "game_running")
	wantHTTP(t, second(store.CreateGame(ctx, NewGameInput{CreatedBy: "binh", ChatID: testPscChat}, msgStart)), 409, "game_running")
	if cur := gameIDAt(t, db, "gameState/current"); cur != psc {
		t.Fatalf("gameState/current = %q, mong đợi ván PSC %q", cur, psc)
	}
	if _, err := db.Doc("games/"+other).Update(ctx, []firestore.Update{{Path: "status", Value: gameEnded}}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.CreateGame(ctx, NewGameInput{CreatedBy: "an", ChatID: "-1002222"}, msgStart); err != nil {
		t.Fatalf("ván cũ của chat đã kết thúc mà không mở lại được: %v", err)
	}
}

func second[T any](_ T, err error) error { return err }

func gameIDAt(t *testing.T, db *firestore.Client, path string) string {
	t.Helper()
	d, err := db.Doc(path).Get(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	return stringValue(d.Data()["gameId"])
}

// startGameIn mở và Start một ván 10 người của host ở chat, cùng db với ván
// khác; tg của người chơi bắt đầu từ tgBase để hai ván không trùng.
func startGameIn(t *testing.T, g *storeGame, host, chat string, tgBase int) string {
	t.Helper()
	ctx := context.Background()
	id, err := g.store.CreateGame(ctx, NewGameInput{CreatedBy: host, ChatID: chat}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	for i, uid := range sortedPlayers(ww.NewState(ww.Seed{}, ww.Config{}, storeRoles(), msgStart)) {
		tg := strconv.Itoa(tgBase + i)
		seed(t, g.db, "games/"+id+"/players/"+uid, map[string]any{"uid": uid, "tgUserId": tg})
		seed(t, g.db, "tgLinks/"+tg, map[string]any{"uid": uid, "inPsc": true})
	}
	if err := g.store.StartGame(ctx, id, ww.NewState(ww.Seed{3}, ww.Config{}, storeRoles(), msgStart), msgStart); err != nil {
		t.Fatal(err)
	}
	return id
}

// Tick chạy mọi ván đang mở chứ không chỉ ván gameState/current: hai ván ở hai
// chat cùng chốt mốc 22h. Ván đã kết thúc ngoài con trỏ mà outbox còn tin chờ
// thì tick vẫn kick flush.
func TestEmulatorTickAdvancesEveryOpenGame(t *testing.T) {
	g := newStoreGame(t)
	other := startGameIn(t, g, "an", "-1002222", 910000)
	e := newAdvanceEnv(t, g)
	e.clock = time.Date(2026, 10, 15, 22, 7, 0, 0, vietnam)
	e.post("/tasks/schedule-tick", map[string]any{})
	for _, id := range []string{g.id, other} {
		d, err := g.db.Doc("games/" + id).Get(context.Background())
		if err != nil {
			t.Fatal(err)
		}
		if d.Data()["phase"] != string(ww.PhaseNight) {
			t.Fatalf("ván %s: phase %v sau tick, mong đợi night", id, d.Data()["phase"])
		}
	}
	flushes := func(id string) int {
		n := 0
		for _, task := range e.tasksTo("/tasks/game-flush") {
			if p, ok := task.Payload.(gameFlushTask); ok && p.GameID == id {
				n++
			}
		}
		return n
	}
	if _, err := g.db.Doc("games/"+other).Update(context.Background(), []firestore.Update{{Path: "status", Value: gameEnded}, {Path: "updatedAt", Value: e.clock}}); err != nil {
		t.Fatal(err)
	}
	before := flushes(other)
	e.clock = e.clock.Add(10 * time.Minute)
	e.post("/tasks/schedule-tick", map[string]any{})
	if flushes(other) != before+1 {
		t.Fatal("ván đã kết thúc ngoài con trỏ còn outbox chờ mà tick không kick flush")
	}
}

// /vai tìm ván đang chạy có người gọi, không chỉ ván ở gameState/current.
func TestEmulatorCardTextFindsPlayersGameOutsidePointer(t *testing.T) {
	g := newStoreGame(t)
	other := startGameIn(t, g, "an", "-1002222", 910000)
	if cur := gameIDAt(t, g.db, "gameState/current"); cur != g.id {
		t.Fatalf("con trỏ = %q, mong đợi ván đầu %q", cur, g.id)
	}
	if _, err := g.db.Doc("games/"+g.id).Update(context.Background(), []firestore.Update{{Path: "status", Value: gameEnded}}); err != nil {
		t.Fatal(err)
	}
	text, err := g.store.CardText(context.Background(), "seer", "")
	if err != nil || text == "" {
		t.Fatalf("/vai của người chơi ván %s = %q, %v", other, text, err)
	}
	if text, err := g.store.CardText(context.Background(), "nobody", ""); err != nil || text != "" {
		t.Fatalf("/vai của người không chơi = %q, %v", text, err)
	}
}

// Đổi liên kết Telegram bị chặn khi người đó đang chơi ván nào, kể cả ván
// không ở gameState/current.
func TestEmulatorLinkChangeBlockedInGameOutsidePointer(t *testing.T) {
	e := newLinkEnv(t)
	e.start(100, 7, e.code("uA", time.Now()))
	seed(t, e.db, "gameState/current", map[string]any{"gameId": "g1"})
	seed(t, e.db, "games/g1", map[string]any{"status": gameEnded})
	seed(t, e.db, "games/g2", map[string]any{"status": gameRunning})
	seed(t, e.db, "games/g2/players/uA", map[string]any{"alive": true})
	wantHTTP(t, e.links.Unlink(context.Background(), "uA"), 409, "in_game")
}

// Mỗi quản trò giữ một ván chưa kết thúc của một người: đã đăng ký ván PSC thì
// không đăng ký được ván 3i khác, ván PSC kết thúc thì được; ván của bot ván thì
// đăng ký được song song với ván 3i, nhưng không hai ván cùng bot ván.
func TestEmulatorRegisterBlockedWhileInOtherOpenGame(t *testing.T) {
	db := emulatorDB(t)
	store := NewGameStore(db, testPscChat)
	h := newAPIHarness(t, store)
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}, "minAppVersion": "1.5.0"})
	r := h.call("boss", "POST", "/v1/games", map[string]any{}, "")
	h.want(r, 201, "")
	psc := r.body["id"].(string)
	other, err := store.CreateGame(context.Background(), NewGameInput{CreatedBy: "an", ChatID: "-1002222"}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	linkUser(t, h, "u1", "7001", true)
	h.want(h.call("u1", "POST", "/v1/games/"+psc+"/registration", nil, "1.5.0"), 200, "")
	h.want(h.call("u1", "POST", "/v1/games/"+other+"/registration", nil, "1.5.0"), 409, "in_other_game")
	// Gọi lại ván đã đăng ký vẫn trả kết quả cũ.
	h.want(h.call("u1", "POST", "/v1/games/"+psc+"/registration", nil, "1.5.0"), 200, "")
	if _, err := db.Doc("games/"+psc).Update(context.Background(), []firestore.Update{{Path: "status", Value: gameEnded}}); err != nil {
		t.Fatal(err)
	}
	h.want(h.call("u1", "POST", "/v1/games/"+other+"/registration", nil, "1.5.0"), 200, "")

	seed(t, db, "managedBots/9001", map[string]any{"kind": managedKindGame, "uid": "an", "username": "van_an_bot"})
	seed(t, db, "managedBots/9001/dms/7001", map[string]any{"open": true})
	bot1, err := store.CreateGame(context.Background(), NewGameInput{CreatedBy: "chu", ChatID: "-1003333", BotID: "9001", UserGame: true, MaxUserGames: 5}, msgStart)
	if err != nil {
		t.Fatal(err)
	}
	// Mỗi chủ chỉ mở một ván chưa kết thúc nên API không tạo được ván thứ hai
	// cùng bot; seed thẳng để giữ luật ở Register.
	seed(t, db, "games/oldbot", map[string]any{"status": gameRunning, "botId": "9001"})
	seed(t, db, "games/oldbot/players/u1", map[string]any{"alive": true})
	h.want(h.call("u1", "POST", "/v1/games/"+bot1+"/registration", nil, "1.5.0"), 409, "in_other_game")
	if _, err := db.Doc("games/oldbot").Update(context.Background(), []firestore.Update{{Path: "status", Value: gameEnded}}); err != nil {
		t.Fatal(err)
	}
	h.want(h.call("u1", "POST", "/v1/games/"+bot1+"/registration", nil, "1.5.0"), 200, "")
}
