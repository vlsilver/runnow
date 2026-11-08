//go:build emulator

package backend

import (
	"context"
	"strconv"
	"strings"
	"testing"
	"time"
)

// userBot cho uid một bot ván làm admin ở chat, có topic 42.
func userBot(t *testing.T, h *apiHarness, uid, botID, chat string) map[string]any {
	t.Helper()
	seed(t, h.store.db, "gameBots/"+uid, map[string]any{"botId": botID, "username": "van_" + uid + "_bot"})
	seed(t, h.store.db, "managedBots/"+botID, map[string]any{"kind": managedKindGame, "uid": uid, "username": "van_" + uid + "_bot"})
	seed(t, h.store.db, "managedBots/"+botID+"/chats/"+chat, map[string]any{"status": "administrator", "topics": map[string]any{"42": map[string]any{"name": "Ma Sói"}}})
	return map[string]any{"telegram": map[string]any{"chatId": chat, "threadId": 42}}
}

// User thường mở ván ở group của bot riêng khi config bật cho bản app của họ;
// không mở được ván PSC, ván thử hay tắt vai; số ván user mở cùng lúc có hạn.
func TestEmulatorUserCreatesGameWithOwnBot(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	body := userBot(t, h, "an", "9001", "-100777")
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}})
	h.want(h.call("an", "POST", "/v1/games", body, "1.13.0"), 403, "not_admin")

	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}, "userGameMinAppVersion": "1.13.0", "maxUserGames": 1})
	h.want(h.call("an", "POST", "/v1/games", body, "1.12.0"), 403, "not_admin")
	h.want(h.call("an", "POST", "/v1/games", map[string]any{}, "1.13.0"), 422, "telegram_required")
	h.want(h.call("an", "POST", "/v1/games", map[string]any{"testMode": true, "chatId": "-100777"}, "1.13.0"), 403, "not_admin")
	h.want(h.call("an", "POST", "/v1/games", map[string]any{"roles": map[string]bool{"cupid": false}, "telegram": body["telegram"]}, "1.13.0"), 403, "not_admin")
	viewer := h.call("an", "GET", "/v1/games", nil, "1.13.0").body["viewer"].(map[string]any)
	if viewer["canCreate"] != true || viewer["canUsePsc"] != false || viewer["canPickRoles"] != false {
		t.Fatalf("viewer của user được bật = %v, muốn canCreate mà không PSC, không chọn vai", viewer)
	}
	boss := h.call("boss", "GET", "/v1/games", nil, "1.13.0").body["viewer"].(map[string]any)
	if boss["canUsePsc"] != true || boss["canPickRoles"] != true {
		t.Fatalf("viewer của admin = %v, muốn đủ quyền", boss)
	}
	if h.call("an", "GET", "/v1/games", nil, "1.12.0").body["viewer"].(map[string]any)["canCreate"] != false {
		t.Fatal("app cũ thấy canCreate")
	}

	r := h.call("an", "POST", "/v1/games", body, "1.13.0")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	g, err := db.Doc("games/" + id).Get(context.Background())
	if err != nil || g.Data()["userGame"] != true || g.Data()["chatId"] != "-100777" || g.Data()["botId"] != "9001" {
		t.Fatalf("games/%s = %v, %v", id, g.Data(), err)
	}
	if cur, err := db.Doc("gameState/current").Get(context.Background()); err == nil && cur.Exists() {
		t.Fatalf("ván user lấy gameState/current: %v", cur.Data())
	}
	// Đủ ván user thì user khác chờ; admin mở ván PSC vẫn được.
	h.want(h.call("binh", "POST", "/v1/games", userBot(t, h, "binh", "9002", "-100888"), "1.13.0"), 409, "too_many_games")
	h.want(h.call("boss", "POST", "/v1/games", map[string]any{}, ""), 201, "")
	// Bot của user làm admin ở PSC cũng không đăng vào PSC được.
	userBot(t, h, "chi", "9003", testPscChat)
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}, "userGameMinAppVersion": "1.13.0"})
	h.want(h.call("chi", "POST", "/v1/games", map[string]any{"telegram": map[string]any{"chatId": testPscChat, "threadId": 42}}, "1.13.0"), 422, "telegram_chat")
}

// openUserGame bật ván user trong config và cho an mở một ván; trả id.
func openUserGame(t *testing.T, h *apiHarness) string {
	t.Helper()
	body := userBot(t, h, "an", "9001", "-100777")
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}, "userGameMinAppVersion": "1.13.0"})
	r := h.call("an", "POST", "/v1/games", body, "1.13.0")
	h.want(r, 201, "")
	return r.body["id"].(string)
}

// Chủ ván điều khiển ván của mình như admin (Start, tạm dừng, chạy tiếp, gia
// hạn, huỷ); người khác thì không; lệnh chỉnh ván vẫn chỉ admin.
func TestEmulatorHostManagesOwnGame(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	id := openUserGame(t, h)
	base := "/v1/games/" + id
	for _, path := range []string{"/start?dryRun=true", "/start", "/admin/pause", "/admin/resume", "/admin/cancel"} {
		h.want(h.call("binh", "POST", base+path, nil, "1.13.0"), 403, "not_admin")
	}
	h.want(h.call("binh", "POST", base+"/admin/extend", map[string]any{"minutes": 10}, "1.13.0"), 403, "not_admin")
	for _, path := range []string{"/admin/advance", "/admin/retry-outbox", "/admin/fake-players"} {
		h.want(h.call("an", "POST", base+path, map[string]any{}, "1.13.0"), 403, "not_admin")
	}
	h.want(h.call("an", "POST", base+"/start?dryRun=true", nil, "1.13.0"), 200, "")
	if r := h.call("an", "POST", base+"/admin/pause", nil, "1.13.0"); r.status == 403 {
		t.Fatalf("chủ ván bị chặn pause: %s", r.raw)
	}
	if r := h.call("an", "POST", base+"/admin/extend", map[string]any{"minutes": 10}, "1.13.0"); r.status == 403 {
		t.Fatalf("chủ ván bị chặn extend: %s", r.raw)
	}
	d := h.call("an", "GET", base, nil, "1.13.0")
	if d.body["canManage"] != true || h.call("binh", "GET", base, nil, "1.13.0").body["canManage"] != false {
		t.Fatalf("canManage của chủ ván = %v", d.body["canManage"])
	}
	h.want(h.call("an", "POST", base+"/admin/cancel", nil, "1.13.0"), 200, "")
}

// Ván của user không lên danh sách chung: chỉ chủ ván, người đã đăng ký và
// admin thấy; người có link vẫn mở được chi tiết để đăng ký.
func TestEmulatorUserGameHiddenFromPublicList(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	id := openUserGame(t, h)
	listed := func(uid string) bool {
		for _, it := range h.call(uid, "GET", "/v1/games", nil, "1.13.0").body["items"].([]any) {
			if it.(map[string]any)["id"] == id {
				return true
			}
		}
		return false
	}
	if listed("binh") || !listed("an") || !listed("boss") {
		t.Fatalf("binh %v, an %v, boss %v", listed("binh"), listed("an"), listed("boss"))
	}
	h.want(h.call("binh", "GET", "/v1/games/"+id, nil, "1.13.0"), 200, "")
	linkUser(t, h, "binh", "7002", false)
	r := h.call("binh", "POST", "/v1/games/"+id+"/registration", nil, "1.13.0")
	h.want(r, 422, "requirements_unmet")
	if !strings.Contains(string(r.raw), `"key":"bot_dm","ok":false,"label":"Đã nhắn /start cho @van_an_bot","action":{"type":"open_url","url":"https://t.me/van_an_bot?start=van"}`) {
		t.Fatalf("chưa /start bot ván: %s", r.raw)
	}
	seed(t, h.store.db, "managedBots/9001/dms/7002", map[string]any{"open": true})
	h.want(h.call("binh", "POST", "/v1/games/"+id+"/registration", nil, "1.13.0"), 200, "")
	if !listed("binh") {
		t.Fatal("đã đăng ký mà không thấy ván trong danh sách")
	}
}

// Thiết lập bot quản trò mở cho user được mở ván; user khác vẫn 403.
func TestEmulatorGameTelegramRoutesFollowCanCreate(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}, "userGameMinAppVersion": "1.13.0"})
	for _, c := range []struct{ method, path string }{{"GET", "/v1/games/telegram"}, {"POST", "/v1/games/telegram/bot"}} {
		h.want(h.call("an", c.method, c.path, nil, "1.12.0"), 403, "not_admin")
		// Harness không có Managed Bots nên qua được quyền là 404 not_found.
		h.want(h.call("an", c.method, c.path, nil, "1.13.0"), 404, "not_found")
	}
}

// Nhiều ván user mở sau ván PSC không đẩy ván PSC khỏi danh sách.
func TestEmulatorPscGameStaysListedPastManyUserGames(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}})
	r := h.call("boss", "POST", "/v1/games", map[string]any{}, "")
	h.want(r, 201, "")
	psc := r.body["id"].(string)
	for i := range 12 {
		seed(t, db, "games/u"+strconv.Itoa(i), map[string]any{"status": gameRegistering, "userGame": true, "createdBy": "u" + strconv.Itoa(i),
			"createdAt": time.Now().Add(time.Duration(i+1) * time.Minute), "config": "{}"})
	}
	items := h.call("binh", "GET", "/v1/games", nil, "1.13.0").body["items"].([]any)
	if len(items) != 1 || items[0].(map[string]any)["id"] != psc {
		t.Fatalf("items = %v", items)
	}
}

// Ván của user hỏng: tick vẫn báo 5xx cho Cloud Scheduler, nhưng không DM admin
// "tick lỗi", vì cảnh báo admin chỉ nói về ván chính (gameState/current).
func TestEmulatorUserGameTickErrorDoesNotAlertAdmin(t *testing.T) {
	e := newAlertEnv(t)
	e.prefix = "Ma Sói cần xem:"
	seed(t, e.db, "games/ug", map[string]any{"status": gameRunning, "userGame": true, "chatId": "-100777", "config": "{}", "createdBy": "an"})
	seed(t, e.db, "games/ug/secret/state", map[string]any{"state": "{"})
	if dm := e.tick(at(15, 22, 7), 0, 500); len(dm) != 0 {
		t.Fatalf("ván user lỗi mà DM admin: %q", dm)
	}
}
