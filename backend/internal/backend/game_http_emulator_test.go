//go:build emulator

package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/api/option"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// apiHarness gọi API Ma Sói qua NewAPIServer thật, token lấy từ Auth emulator.
type apiHarness struct {
	t      *testing.T
	store  *GameStore
	srv    http.Handler
	auth   *auth.Client
	tokens map[string]string
	cfg    Config
	deps   *Dependencies
}

func newAPIHarness(t *testing.T, store *GameStore) *apiHarness {
	t.Helper()
	if os.Getenv("FIREBASE_AUTH_EMULATOR_HOST") == "" {
		t.Fatal("thiếu FIREBASE_AUTH_EMULATOR_HOST: chạy bằng backend/scripts/test_emulator.sh")
	}
	ctx := context.Background()
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: emulatorProject}, option.WithoutAuthentication())
	if err != nil {
		t.Fatal(err)
	}
	ac, err := app.Auth(ctx)
	if err != nil {
		t.Fatal(err)
	}
	deps := &Dependencies{Firestore: store.db, Auth: ac, Games: store, TelegramLinks: NewTelegramLinkService(store.db, "threei_bot")}
	cfg := Config{AllowedWebOrigins: map[string]struct{}{"https://threei.run": {}}}
	return &apiHarness{t: t, store: store, srv: NewAPIServer(cfg, deps), auth: ac, tokens: map[string]string{}, cfg: cfg, deps: deps}
}

// token đổi custom token của uid lấy ID token như app làm sau khi đăng nhập.
func (h *apiHarness) token(uid string) string {
	h.t.Helper()
	if tok, ok := h.tokens[uid]; ok {
		return tok
	}
	custom, err := h.auth.CustomToken(context.Background(), uid)
	if err != nil {
		h.t.Fatal(err)
	}
	body, _ := json.Marshal(map[string]any{"token": custom, "returnSecureToken": true})
	url := "http://" + os.Getenv("FIREBASE_AUTH_EMULATOR_HOST") + "/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=demo"
	resp, err := http.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		h.t.Fatal(err)
	}
	defer resp.Body.Close()
	var out struct {
		IDToken string `json:"idToken"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&out); err != nil || out.IDToken == "" {
		h.t.Fatalf("signInWithCustomToken %s: status %d, %v", uid, resp.StatusCode, err)
	}
	h.tokens[uid] = out.IDToken
	return out.IDToken
}

type apiResp struct {
	status int
	raw    []byte
	body   map[string]any
}

func (h *apiHarness) call(uid, method, path string, body any, version string) apiResp {
	h.t.Helper()
	var r *http.Request
	if body != nil {
		b, _ := json.Marshal(body)
		r = httptest.NewRequest(method, path, bytes.NewReader(b))
	} else {
		r = httptest.NewRequest(method, path, nil)
	}
	r.Header.Set("Authorization", "Bearer "+h.token(uid))
	if version != "" {
		r.Header.Set("X-App-Version", version)
	}
	w := httptest.NewRecorder()
	h.srv.ServeHTTP(w, r)
	out := apiResp{status: w.Code, raw: w.Body.Bytes()}
	_ = json.Unmarshal(out.raw, &out.body)
	return out
}

func (h *apiHarness) want(r apiResp, status int, code string) {
	h.t.Helper()
	if r.status != status || (code != "" && r.body["error"] != code) {
		h.t.Fatalf("status %d %s, mong đợi %d %s", r.status, r.raw, status, code)
	}
}

func linkUser(t *testing.T, h *apiHarness, uid, tg string, inPsc bool) {
	t.Helper()
	seed(t, h.store.db, "telegramLinks/"+uid, map[string]any{"tgUserId": mustInt(tg)})
	seed(t, h.store.db, "tgLinks/"+tg, map[string]any{"uid": uid, "inPsc": inPsc, "displayName": "TG " + uid})
}

func mustInt(s string) int64 {
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil {
		panic(err)
	}
	return n
}

func setConfig(t *testing.T, h *apiHarness, data map[string]any) {
	t.Helper()
	seed(t, h.store.db, "gameState/config", data)
}

// L2: luồng tạo → đăng ký trên ván thật, kèm các ca âm của quyền và điều kiện.
func TestEmulatorGameAPICreateAndRegister(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}, "minAppVersion": "1.5.0"})

	h.want(h.call("u1", "POST", "/v1/games", map[string]any{}, ""), 403, "not_admin")
	r := h.call("boss", "POST", "/v1/games", map[string]any{"roles": map[string]bool{"cupid": false}}, "")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	g, err := db.Collection("games").Doc(id).Get(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if g.Data()["chatId"] != testPscChat || !strings.Contains(g.Data()["config"].(string), `"disabled":["cupid"]`) {
		t.Fatalf("ván thật phải ở PSC và tắt cupid: %v", g.Data())
	}
	h.want(h.call("boss", "POST", "/v1/games", map[string]any{}, ""), 409, "game_running")
	// Cấu hình sai bị chặn trước, kể cả khi đang có ván.
	h.want(h.call("boss", "POST", "/v1/games", map[string]any{"roles": map[string]bool{"wolf": false}}, ""), 422, "invalid_config")

	list := h.call("u1", "GET", "/v1/games", nil, "")
	h.want(list, 200, "")
	if list.body["viewer"].(map[string]any)["canCreate"] != false {
		t.Fatal("user thường thấy canCreate")
	}
	if h.call("boss", "GET", "/v1/games", nil, "").body["viewer"].(map[string]any)["canCreate"] != true {
		t.Fatal("admin không thấy canCreate")
	}
	items := list.body["items"].([]any)
	if len(items) != 1 || items[0].(map[string]any)["status"] != "registering" {
		t.Fatalf("items = %v", items)
	}

	// Chưa liên kết: 422 kèm danh sách điều kiện để app vẽ.
	r = h.call("u1", "POST", "/v1/games/"+id+"/registration", nil, "1.5.0")
	h.want(r, 422, "requirements_unmet")
	reqs := r.body["requirements"].([]any)
	if len(reqs) != 3 || reqs[0].(map[string]any)["ok"] != false || reqs[0].(map[string]any)["action"].(map[string]any)["type"] != "link_telegram" {
		t.Fatalf("requirements = %v", reqs)
	}
	// tgLinks đã chuyển sang uid khác thì liên kết của u1 không còn.
	linkUser(t, h, "u1", "7001", true)
	seed(t, db, "tgLinks/7001", map[string]any{"uid": "someone", "inPsc": true})
	h.want(h.call("u1", "POST", "/v1/games/"+id+"/registration", nil, "1.5.0"), 422, "requirements_unmet")
	linkUser(t, h, "u1", "7001", false)
	h.want(h.call("u1", "POST", "/v1/games/"+id+"/registration", nil, "1.5.0"), 422, "requirements_unmet")
	linkUser(t, h, "u1", "7001", true)
	// Bản cũ, thiếu header (bản 1.4.3 chưa gửi) đều bị chặn; +build không tính.
	h.want(h.call("u1", "POST", "/v1/games/"+id+"/registration", nil, "1.4.9"), 422, "requirements_unmet")
	h.want(h.call("u1", "POST", "/v1/games/"+id+"/registration", nil, ""), 422, "requirements_unmet")
	r = h.call("u1", "POST", "/v1/games/"+id+"/registration", nil, "1.5.0+42")
	h.want(r, 200, "")
	if r.body["playerCount"] != 1.0 {
		t.Fatalf("playerCount = %v", r.body["playerCount"])
	}
	// Gọi lại không thêm người.
	if r := h.call("u1", "POST", "/v1/games/"+id+"/registration", nil, "1.5.0"); r.status != 200 || r.body["playerCount"] != 1.0 {
		t.Fatalf("đăng ký lại: %d %s", r.status, r.raw)
	}
	p, err := db.Doc("games/" + id + "/players/u1").Get(context.Background())
	if err != nil || p.Data()["tgUserId"] != int64(7001) || p.Data()["name"] != "TG u1" {
		t.Fatalf("players/u1 = %v, %v", p.Data(), err)
	}

	d := h.call("u1", "GET", "/v1/games/"+id, nil, "1.5.0")
	h.want(d, 200, "")
	if d.body["isRegistered"] != true || d.body["playerCount"] != 1.0 || d.body["isAdmin"] != false {
		t.Fatalf("detail = %s", d.raw)
	}
	// Chưa chia bài: /me có status, chưa có vai. Người ngoài ván thì 404.
	me := h.call("u1", "GET", "/v1/games/"+id+"/me", nil, "")
	h.want(me, 200, "")
	if me.body["status"] != "registering" || me.body["role"] != nil {
		t.Fatalf("me = %s", me.raw)
	}
	h.want(h.call("u2", "GET", "/v1/games/"+id+"/me", nil, ""), 404, "not_player")
	h.want(h.call("u2", "GET", "/v1/games/nope", nil, ""), 404, "not_found")

	r = h.call("u1", "DELETE", "/v1/games/"+id+"/registration", nil, "")
	if r.status != 200 || r.body["playerCount"] != 0.0 {
		t.Fatalf("rút: %d %s", r.status, r.raw)
	}
	h.want(h.call("u1", "DELETE", "/v1/games/"+id+"/registration", nil, ""), 200, "")
}

func TestEmulatorGameRegistrationDeadlineAndFull(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}, "testerUids": []any{"t1"}})
	h.want(h.call("boss", "POST", "/v1/games", map[string]any{"registrationDeadline": time.Now().Add(-time.Minute)}, ""), 422, "invalid_deadline")
	h.want(h.call("boss", "POST", "/v1/games", map[string]any{"testMode": true}, ""), 422, "invalid_chat")
	r := h.call("boss", "POST", "/v1/games", map[string]any{"testMode": true, "chatId": "-1002222"}, "")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	linkUser(t, h, "t1", "7002", true)
	linkUser(t, h, "u1", "7003", true)

	// Ván thử: người ngoài không thấy, không đăng ký được.
	if items := h.call("u1", "GET", "/v1/games", nil, "").body["items"].([]any); len(items) != 0 {
		t.Fatalf("user thường thấy ván thử: %v", items)
	}
	h.want(h.call("u1", "GET", "/v1/games/"+id, nil, ""), 404, "not_found")
	h.want(h.call("u1", "POST", "/v1/games/"+id+"/registration", nil, ""), 404, "not_found")
	if items := h.call("t1", "GET", "/v1/games", nil, "").body["items"].([]any); len(items) != 1 {
		t.Fatalf("tester không thấy ván thử: %v", items)
	}

	// Đủ 16 người (giả) thì 409; bớt người giả thì đăng ký được.
	h.want(h.call("u1", "POST", "/v1/games/"+id+"/admin/fake-players", map[string]any{"count": 16}, ""), 403, "not_admin")
	h.want(h.call("boss", "POST", "/v1/games/"+id+"/admin/fake-players", map[string]any{"count": 16}, ""), 200, "")
	h.want(h.call("t1", "POST", "/v1/games/"+id+"/registration", nil, ""), 409, "game_full")
	h.want(h.call("boss", "POST", "/v1/games/"+id+"/admin/fake-players", map[string]any{"count": 15}, ""), 200, "")
	if r := h.call("t1", "POST", "/v1/games/"+id+"/registration", nil, ""); r.status != 200 || r.body["playerCount"] != 16.0 {
		t.Fatalf("đăng ký sau khi bớt người giả: %d %s", r.status, r.raw)
	}
	h.want(h.call("boss", "POST", "/v1/games/"+id+"/admin/fake-players", map[string]any{"count": 14}, ""), 200, "")
	if r := h.call("boss", "GET", "/v1/games", nil, ""); r.body["items"].([]any)[0].(map[string]any)["playerCount"] != 15.0 {
		t.Fatalf("playerCount của list sau khi bớt người giả: %s", r.raw)
	}

	// Quá hạn đăng ký thì không đăng ký, không rút được.
	if _, err := db.Collection("games").Doc(id).Update(context.Background(), []firestore.Update{{Path: "registrationDeadline", Value: time.Now().Add(-time.Second)}}); err != nil {
		t.Fatal(err)
	}
	h.want(h.call("t1", "DELETE", "/v1/games/"+id+"/registration", nil, ""), 200, "")
	h.want(h.call("t1", "POST", "/v1/games/"+id+"/registration", nil, ""), 409, "phase_closed")
}

// runningAPIGame: ván 10 người của newStoreGame đã sang đêm 1 (22h 15/10), giờ
// ván được đặt thành 23h để action đang mở theo time.Now() của handler.
func runningAPIGame(t *testing.T) (*storeGame, *apiHarness) {
	t.Helper()
	g := newStoreGame(t)
	g.advance(time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam))
	if st := g.state(); st.Phase != ww.PhaseNight {
		t.Fatalf("phase = %s", st.Phase)
	}
	gameTime := time.Date(2026, 10, 15, 23, 0, 0, 0, vietnam)
	seedMerge(t, g, map[string]any{"clockOffsetNs": int64(gameTime.Sub(time.Now()))})
	for uid := range storeRoles() {
		seed(t, g.db, "publicProfiles/"+uid, map[string]any{"displayName": strings.ToUpper(uid)})
	}
	h := newAPIHarness(t, g.store)
	setConfig(t, h, map[string]any{"adminUids": []any{"boss"}, "cards": map[string]any{"seer": "https://img/seer.png", "back": "https://img/back.png"}})
	return g, h
}

func seedMerge(t *testing.T, g *storeGame, data map[string]any) {
	t.Helper()
	if _, err := g.db.Collection("games").Doc(g.id).Set(context.Background(), data, firestore.MergeAll); err != nil {
		t.Fatal(err)
	}
}

var roleKey = regexp.MustCompile(`"\w*[Rr]ole\w*"\s*:`)

// L2 "Xong khi": JSON của GET /v1/games/{id} không có vai của người còn sống,
// kể cả trong feed; người chết thì lật bài.
func TestEmulatorGameDetailHidesLivingRoles(t *testing.T) {
	g, h := runningAPIGame(t)
	d := h.call("v1", "GET", "/v1/games/"+g.id, nil, "")
	h.want(d, 200, "")
	// uid của test trùng tên vai ("seer"), nên soi theo key và nhãn vai.
	if m := roleKey.Find(d.raw); m != nil {
		t.Fatalf("detail có key %s khi chưa ai chết: %s", m, d.raw)
	}
	for _, leak := range []string{`"seed"`, `"wolf"`, `"villager"`, `"Sói"`, `"Dân"`, "Tiên tri", "Phù thuỷ", "Bảo vệ", "Thợ săn"} {
		if bytes.Contains(d.raw, []byte(leak)) {
			t.Fatalf("detail lộ %s: %s", leak, d.raw)
		}
	}
	for _, p := range d.body["players"].([]any) {
		if p.(map[string]any)["revealedRoleLabel"] != nil {
			t.Fatalf("người còn sống bị lật bài: %v", p)
		}
	}
	if d.body["phase"].(map[string]any)["key"] != "r1/night" || d.body["phase"].(map[string]any)["state"] != "open" {
		t.Fatalf("phase = %v", d.body["phase"])
	}
	// Bước mở đêm 1 không có event công khai nên không ra dòng feed; ván thật
	// không trả taskKey.
	if items := d.body["feed"].(map[string]any)["items"].([]any); len(items) != 0 || d.body["taskKey"] != nil {
		t.Fatalf("feed = %v, taskKey = %v", items, d.body["taskKey"])
	}
	// serverNow là giờ thật, deadline 0h đã trừ độ lệch nên cách now đúng 1 giờ.
	now, _ := time.Parse(time.RFC3339Nano, d.body["serverNow"].(string))
	deadline, _ := time.Parse(time.RFC3339Nano, d.body["phase"].(map[string]any)["deadline"].(string))
	if gap := deadline.Sub(now); gap < 59*time.Minute || gap > 61*time.Minute {
		t.Fatalf("deadline - serverNow = %v", gap)
	}
	var withKm int
	for _, p := range d.body["players"].([]any) {
		if p.(map[string]any)["lastKm"] == 5.0 {
			withKm++
		}
	}
	if withKm != 10 {
		t.Fatalf("lastKm của snapshot rounds/0: %d người", withKm)
	}

	// Sói cắn thợ săn, chốt tới 10h: bản tin có người chết, lật bài Thợ săn.
	// AdvanceGame cũng cộng độ lệch, nên đưa về giờ thật trước khi chốt.
	seedMerge(t, g, map[string]any{"clockOffsetNs": int64(0)})
	g.act(1, ww.KindWolfBite, "w1", time.Date(2026, 10, 15, 22, 30, 0, 0, vietnam), "hunter")
	g.advance(time.Date(2026, 10, 16, 10, 0, 0, 0, vietnam))
	d = h.call("v1", "GET", "/v1/games/"+g.id, nil, "")
	var hunter map[string]any
	for _, p := range d.body["players"].([]any) {
		pm := p.(map[string]any)
		if pm["uid"] == "hunter" {
			hunter = pm
		} else if pm["revealedRoleLabel"] != nil {
			t.Fatalf("lật bài người còn sống: %v", pm)
		}
	}
	if hunter["alive"] != false || hunter["revealedRoleLabel"] != "Thợ săn" || hunter["deathRound"] != 1.0 {
		t.Fatalf("thợ săn = %v", hunter)
	}
	items := d.body["feed"].(map[string]any)["items"].([]any)
	if len(items) == 0 {
		t.Fatalf("feed rỗng: %s", d.raw)
	}
	top := items[0].(map[string]any)
	lines, _ := json.Marshal(top["lines"])
	if top["title"] != "Bản tin đêm 1" || !strings.Contains(string(lines), "Lá bài: Thợ săn") || !strings.Contains(string(lines), "được bắn một người") {
		t.Fatalf("feed[0] = %v", top)
	}
	for _, leak := range []string{"Tiên tri", "Phù thuỷ", "Bảo vệ", `"wolf"`, `"villager"`} {
		if bytes.Contains(d.raw, []byte(leak)) {
			t.Fatalf("detail lộ %s sau khi có người chết: %s", leak, d.raw)
		}
	}

	// 20h: V2 lên giàn với một đề cử.
	g.act(1, ww.KindNominate, "v1", time.Date(2026, 10, 16, 11, 0, 0, 0, vietnam), "v2")
	g.advance(time.Date(2026, 10, 16, 20, 0, 0, 0, vietnam))
	d = h.call("v1", "GET", "/v1/games/"+g.id, nil, "")
	for _, p := range d.body["players"].([]any) {
		pm := p.(map[string]any)
		if (pm["onTrial"] == true) != (pm["uid"] == "v2") {
			t.Fatalf("onTrial: %v", pm)
		}
	}
	top = d.body["feed"].(map[string]any)["items"].([]any)[0].(map[string]any)
	if top["title"] != "Đề cử ngày 1" || top["lines"].([]any)[0] != "V2 lên giàn với 1 đề cử." {
		t.Fatalf("feed[0] = %v", top)
	}
}

// /me: vai, ghi chú riêng và actions[] lấy từ engine; gửi action qua app trả /me
// mới, luật từ chối thì 422/409 kèm chữ tiếng Việt.
func TestEmulatorGameMeAndActions(t *testing.T) {
	g, h := runningAPIGame(t)
	me := h.call("seer", "GET", "/v1/games/"+g.id+"/me", nil, "")
	h.want(me, 200, "")
	if me.body["role"] != "seer" || me.body["cardUrl"] != "https://img/seer.png" || me.body["cardBackUrl"] != "https://img/back.png" {
		t.Fatalf("me = %s", me.raw)
	}
	acts := me.body["actions"].([]any)
	if len(acts) != 1 {
		t.Fatalf("actions của tiên tri lúc 23h: %s", me.raw)
	}
	peek := acts[0].(map[string]any)
	if peek["kind"] != "seer_peek" || peek["enabled"] != true || peek["confirmText"] == nil || peek["input"] != "single_target" {
		t.Fatalf("seer_peek = %v", peek)
	}
	for _, o := range peek["options"].([]any) {
		if o.(map[string]any)["id"] == "seer" {
			t.Fatal("tiên tri thấy chính mình trong options")
		}
	}
	if n := len(peek["options"].([]any)); n != 9 {
		t.Fatalf("options = %d người", n)
	}
	// Soi khoá lúc 10h, tức 11 giờ sau giờ ván 23h; app nhận giờ thật.
	closes, _ := time.Parse(time.RFC3339Nano, peek["closesAt"].(string))
	if gap := time.Until(closes); gap < 10*time.Hour+58*time.Minute || gap > 11*time.Hour+time.Minute {
		t.Fatalf("closesAt - now = %v", gap)
	}

	r := h.call("seer", "POST", "/v1/games/"+g.id+"/actions", map[string]any{"kind": "seer_peek", "targets": []string{"seer"}}, "")
	h.want(r, 422, "invalid_target")
	if r.body["message"] != "Không chọn được người này." {
		t.Fatalf("message = %v", r.body["message"])
	}
	r = h.call("seer", "POST", "/v1/games/"+g.id+"/actions", map[string]any{"kind": "seer_peek", "targets": []string{"w1"}}, "")
	h.want(r, 200, "")
	notes, _ := json.Marshal(r.body["notes"])
	if !strings.Contains(string(notes), "là Sói") {
		t.Fatalf("notes sau khi soi: %s", notes)
	}
	peek = r.body["actions"].([]any)[0].(map[string]any)
	if peek["enabled"] != false || peek["disabledReason"] != "Bạn đã dùng lượt này rồi." || peek["selected"].(map[string]any)["targets"].([]any)[0] != "w1" {
		t.Fatalf("seer_peek sau khi soi = %v", peek)
	}
	h.want(h.call("seer", "POST", "/v1/games/"+g.id+"/actions", map[string]any{"kind": "seer_peek", "targets": []string{"v1"}}, ""), 422, "already_used")

	// Sói thấy đồng đội; đề cử chưa mở thì 409.
	w := h.call("w1", "GET", "/v1/games/"+g.id+"/me", nil, "")
	wn, _ := json.Marshal(w.body["notes"])
	if !strings.Contains(string(wn), `"Đồng đội Sói: W2."`) {
		t.Fatalf("notes của sói: %s", wn)
	}
	h.want(h.call("v1", "POST", "/v1/games/"+g.id+"/actions", map[string]any{"kind": "nominate", "targets": []string{"w1"}}, ""), 409, "phase_closed")
	h.want(h.call("v1", "POST", "/v1/games/"+g.id+"/actions", map[string]any{"kind": "bogus"}, ""), 409, "phase_closed")
	h.want(h.call("v1", "POST", "/v1/games/"+g.id+"/actions", map[string]any{"kind": "nominate", "extra": 1}, ""), 400, "invalid_request")
	// Ván đã chạy thì không đăng ký, không rút được.
	h.want(h.call("outsider", "POST", "/v1/games/"+g.id+"/registration", nil, ""), 409, "phase_closed")
	h.want(h.call("v1", "DELETE", "/v1/games/"+g.id+"/registration", nil, ""), 409, "phase_closed")
	// Người ngoài ván không đọc được /me, không bấm được.
	h.want(h.call("outsider", "GET", "/v1/games/"+g.id+"/me", nil, ""), 404, "not_player")
	h.want(h.call("outsider", "POST", "/v1/games/"+g.id+"/actions", map[string]any{"kind": "wolf_bite", "targets": []string{"v1"}}, ""), 422, "not_your_role")

	// Danh sách nằm trên feed Kèo, ai cũng liếc thấy, nên việc ban đêm không bật
	// badge: sói chưa cắn vẫn hasTodo false như dân. Việc ban ngày: xem tally test.
	if item := h.call("w1", "GET", "/v1/games", nil, "").body["items"].([]any)[0].(map[string]any); item["hasTodo"] != false {
		t.Fatalf("w1 chưa cắn mà hasTodo = %v", item["hasTodo"])
	}
	h.want(h.call("w1", "POST", "/v1/games/"+g.id+"/actions", map[string]any{"kind": "wolf_bite", "targets": []string{"v1"}}, ""), 200, "")
	// Admin không bấm thay được người chơi thật, không đẩy giờ được ván thật.
	h.want(h.call("boss", "POST", "/v1/games/"+g.id+"/admin/act-as", map[string]any{"uid": "w1", "kind": "wolf_bite", "targets": []string{"v1"}}, ""), 422, "not_test_mode")
	h.want(h.call("w1", "POST", "/v1/games/"+g.id+"/admin/advance", map[string]any{"expectedKey": "x"}, ""), 403, "not_admin")
	h.want(h.call("boss", "POST", "/v1/games/"+g.id+"/admin/advance", map[string]any{"expectedKey": "x"}, ""), 422, "not_test_mode")
}

// Ván kết thúc thì /me trả vai của mọi người.
func TestEmulatorGameMeAfterEndShowsAllRoles(t *testing.T) {
	g, h := runningAPIGame(t)
	seedMerge(t, g, map[string]any{"status": gameEnded})
	st := g.state()
	st.Phase, st.Winner = ww.PhaseEnded, ww.TeamVillage
	raw, _ := json.Marshal(st)
	seed(t, g.db, "games/"+g.id+"/secret/state", map[string]any{"state": string(raw)})
	me := h.call("v1", "GET", "/v1/games/"+g.id+"/me", nil, "")
	h.want(me, 200, "")
	if roles := me.body["allRoles"].([]any); len(roles) != 10 || len(me.body["actions"].([]any)) != 0 {
		t.Fatalf("me = %s", me.raw)
	}
}

// Ván đã huỷ hay đã hết chỉ nằm trên feed thêm một ngày, để mọi người kịp thấy
// kết quả, rồi thôi chiếm chỗ trên các kèo đang chạy.
func TestEmulatorGameListHidesOldClosedGames(t *testing.T) {
	g, h := runningAPIGame(t)
	if err := g.store.AdminCancel(context.Background(), g.id, "admin", time.Now()); err != nil {
		t.Fatal(err)
	}
	items := h.call("outsider", "GET", "/v1/games", nil, "").body["items"].([]any)
	if len(items) != 1 || items[0].(map[string]any)["status"] != "cancelled" {
		t.Fatalf("vừa huỷ: items = %v", items)
	}
	seedMerge(t, g, map[string]any{"updatedAt": time.Now().Add(-25 * time.Hour)})
	if items := h.call("outsider", "GET", "/v1/games", nil, "").body["items"].([]any); len(items) != 0 {
		t.Fatalf("huỷ quá một ngày: items = %v", items)
	}
}
