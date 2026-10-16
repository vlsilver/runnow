//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http/httptest"
	"regexp"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type linkEnv struct {
	t     *testing.T
	db    *firestore.Client
	links *TelegramLinkService
	srv   *Server
	tasks []PublishTask
}

func newLinkEnv(t *testing.T) *linkEnv {
	db := emulatorDB(t)
	links := NewTelegramLinkService(db, "Run3IBot")
	e := &linkEnv{t: t, db: db, links: links}
	e.srv = &Server{config: testBotCfg, deps: &Dependencies{Firestore: db, TelegramLinks: links}}
	seed(t, db, "users/uA", map[string]any{"displayName": "An"})
	seed(t, db, "users/uB", map[string]any{"displayName": "Bình"})
	return e
}

func (e *linkEnv) code(uid string, now time.Time) string {
	e.t.Helper()
	c, err := e.links.CreateLinkCode(context.Background(), uid, now)
	if err != nil {
		e.t.Fatal(err)
	}
	return c.Code
}

// start gửi "/start <mã>" từ tg qua webhook, trả status và text trả lời.
func (e *linkEnv) start(updateID, tg int64, code string) (int, string) {
	e.t.Helper()
	raw := fmt.Sprintf(`{"update_id":%d,"message":{"message_id":1,"text":"/start %s","chat":{"id":%d,"type":"private"},"from":{"id":%d,"username":"tg%d","first_name":"Người %d"}}}`, updateID, code, tg, tg, tg, tg)
	rec := httptest.NewRecorder()
	e.srv.serveTelegramUpdate(context.Background(), rec, []byte(raw), func(_ context.Context, p PublishTask) (string, error) {
		e.tasks = append(e.tasks, p)
		return "created", nil
	})
	if rec.Body.Len() == 0 {
		return rec.Code, ""
	}
	var body map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		e.t.Fatalf("body không phải JSON: %q", rec.Body.String())
	}
	if body["method"] != "sendMessage" || body["chat_id"] != float64(tg) {
		e.t.Fatalf("trả lời sai chỗ: %v", body)
	}
	text, _ := body["text"].(string)
	return rec.Code, text
}

func (e *linkEnv) data(path string) map[string]any {
	e.t.Helper()
	snap, err := e.db.Doc(path).Get(context.Background())
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		e.t.Fatal(err)
	}
	return snap.Data()
}

// wantLink kiểm hai đầu của liên kết uid ↔ tg cùng khớp.
func (e *linkEnv) wantLink(uid string, tg int64) {
	e.t.Helper()
	byUID := e.data("telegramLinks/" + uid)
	byTG := e.data(fmt.Sprintf("tgLinks/%d", tg))
	if byUID == nil || byUID["tgUserId"] != tg || byTG == nil || byTG["uid"] != uid {
		e.t.Fatalf("liên kết %s ↔ %d: telegramLinks=%v tgLinks=%v", uid, tg, byUID, byTG)
	}
}

func (e *linkEnv) runningGame(status string, players ...string) {
	seed(e.t, e.db, "gameState/current", map[string]any{"gameId": "g1"})
	seed(e.t, e.db, "games/g1", map[string]any{"status": status})
	for _, uid := range players {
		seed(e.t, e.db, "games/g1/players/"+uid, map[string]any{"alive": true})
	}
}

func TestEmulatorLinkCodeShape(t *testing.T) {
	e := newLinkEnv(t)
	now := time.Date(2026, 10, 16, 9, 0, 0, 0, time.UTC)
	c, err := e.links.CreateLinkCode(context.Background(), "uA", now)
	if err != nil {
		t.Fatal(err)
	}
	// 256 bit base64url không padding là 43 ký tự.
	if !regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`).MatchString(c.Code) {
		t.Fatalf("mã sai dạng: %q", c.Code)
	}
	if c.DeepLink != "https://t.me/Run3IBot?start="+c.Code || !c.ExpiresAt.Equal(now.Add(10*time.Minute)) {
		t.Fatalf("%+v", c)
	}
	if again := e.code("uA", now); again == c.Code {
		t.Fatal("hai lần lấy mã ra cùng một mã")
	}
	// Doc lưu theo hash: đọc được Firestore cũng không ra mã.
	docs, err := e.db.Collection("linkCodes").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range docs {
		if d.Ref.ID == c.Code || strings.Contains(fmt.Sprint(d.Data()), c.Code) {
			t.Fatalf("mã thô nằm trong Firestore: %s %v", d.Ref.ID, d.Data())
		}
	}
}

func TestEmulatorLinkViaWebhookThenTelegramResends(t *testing.T) {
	e := newLinkEnv(t)
	code := e.code("uA", time.Now())
	st, text := e.start(100, 7, code)
	if st != 200 || text != "Đã liên kết Telegram với An." {
		t.Fatalf("status=%d text=%q", st, text)
	}
	e.wantLink("uA", 7)
	if l := e.data("tgLinks/7"); l["username"] != "tg7" || l["displayName"] != "Người 7" {
		t.Fatalf("tgLinks thiếu tên: %v", l)
	}
	if len(e.tasks) != 1 || e.tasks[0].HandlerPath != "/tasks/game-update" || e.tasks[0].Queue != QueueGameInbound {
		t.Fatalf("phải enqueue game-update để bot ghi inPsc: %v", e.tasks)
	}
	linkedAt := e.data("telegramLinks/uA")["linkedAt"]

	// Telegram gửi lại đúng update đó: vẫn báo đã liên kết, không ghi lại gì,
	// task trùng TaskID nên Cloud Tasks bỏ.
	st, text = e.start(100, 7, code)
	if st != 200 || text != "Đã liên kết Telegram với An." {
		t.Fatalf("gửi lại: status=%d text=%q", st, text)
	}
	if got := e.data("telegramLinks/uA")["linkedAt"]; got != linkedAt {
		t.Fatalf("gửi lại mà ghi lại liên kết: %v → %v", linkedAt, got)
	}
	if len(e.tasks) != 2 || e.tasks[1].TaskID != e.tasks[0].TaskID {
		t.Fatalf("TaskID phải theo update_id: %v", e.tasks)
	}
}

func TestEmulatorLinkCodeReplayedByAnotherTelegram(t *testing.T) {
	e := newLinkEnv(t)
	code := e.code("uA", time.Now())
	e.start(100, 7, code)
	_, text := e.start(101, 8, code)
	if text != "Mã này đã được dùng rồi. Mở app 3i Run để lấy mã mới." {
		t.Fatalf("text=%q", text)
	}
	e.wantLink("uA", 7)
	if e.data("tgLinks/8") != nil {
		t.Fatal("tg thứ hai không được có liên kết")
	}
}

func TestEmulatorLinkCodeExpiresAtTenMinutes(t *testing.T) {
	e := newLinkEnv(t)
	ctx := context.Background()
	created := time.Date(2026, 10, 16, 9, 0, 0, 0, time.UTC)
	code := e.code("uA", created)
	if _, err := e.links.ConsumeLinkCode(ctx, code, TelegramUser{ID: 7}, created.Add(10*time.Minute)); !errors.Is(err, errLinkCodeExpired) {
		t.Fatalf("đúng 10 phút: err=%v", err)
	}
	if e.data("tgLinks/7") != nil {
		t.Fatal("mã hết hạn mà vẫn liên kết")
	}
	if _, err := e.links.ConsumeLinkCode(ctx, code, TelegramUser{ID: 7}, created.Add(10*time.Minute-time.Second)); err != nil {
		t.Fatalf("còn 1 giây: %v", err)
	}
	e.wantLink("uA", 7)
}

func TestEmulatorLinkWebhookExpiredAndUnknownCode(t *testing.T) {
	e := newLinkEnv(t)
	expired := e.code("uA", time.Now().Add(-11*time.Minute))
	for _, code := range []string{expired, "khongcoma", strings.Repeat("a", 65)} {
		st, text := e.start(100, 7, code)
		if st != 200 || text != "Mã liên kết không đúng hoặc đã hết hạn. Mở app 3i Run để lấy mã mới." {
			t.Fatalf("%q: status=%d text=%q", code, st, text)
		}
	}
	if e.data("tgLinks/7") != nil || len(e.tasks) != 0 {
		t.Fatalf("mã hỏng mà vẫn liên kết hoặc enqueue: %v", e.tasks)
	}
}

// Một tg chỉ trỏ một uid. Chủ tg bấm mã của uid khác thì liên kết chuyển sang
// uid đó, uid cũ mất liên kết; inPsc là của tg nên giữ nguyên.
func TestEmulatorLinkSameTelegramToSecondUID(t *testing.T) {
	e := newLinkEnv(t)
	e.start(100, 7, e.code("uA", time.Now()))
	if _, err := e.db.Doc("tgLinks/7").Update(context.Background(), []firestore.Update{{Path: "inPsc", Value: true}}); err != nil {
		t.Fatal(err)
	}
	_, text := e.start(101, 7, e.code("uB", time.Now()))
	if text != "Đã liên kết Telegram với Bình." {
		t.Fatalf("text=%q", text)
	}
	e.wantLink("uB", 7)
	if e.data("telegramLinks/uA") != nil {
		t.Fatal("uA vẫn còn trỏ tg 7")
	}
	if e.data("tgLinks/7")["inPsc"] != true {
		t.Fatal("chuyển uid mà mất inPsc của tg")
	}
}

// Một uid chỉ có một tg: liên kết tg mới thì tgLinks của tg cũ bị gỡ.
func TestEmulatorLinkUIDToSecondTelegram(t *testing.T) {
	e := newLinkEnv(t)
	e.start(100, 7, e.code("uA", time.Now()))
	e.start(101, 8, e.code("uA", time.Now()))
	e.wantLink("uA", 8)
	if e.data("tgLinks/7") != nil {
		t.Fatal("tg cũ vẫn trỏ uA")
	}
}

func TestEmulatorLinkBothSidesMoveAtOnce(t *testing.T) {
	e := newLinkEnv(t)
	e.start(100, 7, e.code("uA", time.Now()))
	e.start(101, 8, e.code("uB", time.Now()))
	// tg 8 (đang của uB) bấm mã của uA (đang có tg 7).
	e.start(102, 8, e.code("uA", time.Now()))
	e.wantLink("uA", 8)
	if e.data("tgLinks/7") != nil || e.data("telegramLinks/uB") != nil {
		t.Fatalf("còn sót đầu cũ: tgLinks/7=%v telegramLinks/uB=%v", e.data("tgLinks/7"), e.data("telegramLinks/uB"))
	}
}

// Đổi liên kết giữa ván làm người chơi bị tính đã rời PSC, nên từ chối và giữ
// mã; ván kết thúc rồi thì dùng lại đúng mã đó được (nếu còn hạn).
func TestEmulatorLinkChangeBlockedWhileInGame(t *testing.T) {
	e := newLinkEnv(t)
	e.start(100, 7, e.code("uA", time.Now()))
	e.runningGame(gameRunning, "uA")
	code := e.code("uB", time.Now())
	_, text := e.start(101, 7, code)
	if text != errLinkInGame.Message {
		t.Fatalf("text=%q", text)
	}
	e.wantLink("uA", 7)
	if e.data("telegramLinks/uB") != nil {
		t.Fatal("uB không được có liên kết")
	}
	// uA đổi sang tg khác giữa ván cũng bị chặn.
	if _, err := e.links.ConsumeLinkCode(context.Background(), e.code("uA", time.Now()), TelegramUser{ID: 9}, time.Now()); !errors.Is(err, errLinkInGame) {
		t.Fatalf("uA đổi tg giữa ván: err=%v", err)
	}
	seed(t, e.db, "games/g1", map[string]any{"status": gameEnded})
	if _, text = e.start(102, 7, code); text != "Đã liên kết Telegram với Bình." {
		t.Fatalf("sau ván: text=%q", text)
	}
	e.wantLink("uB", 7)
}

// Ván đang đăng ký, hoặc người không chơi, thì đổi liên kết bình thường.
func TestEmulatorLinkChangeAllowedOutsideRunningGame(t *testing.T) {
	for _, c := range []struct {
		status  string
		players []string
	}{{gameRegistering, []string{"uA"}}, {gameStarting, []string{"uX"}}, {gameRunning, nil}} {
		e := newLinkEnv(t)
		e.start(100, 7, e.code("uA", time.Now()))
		e.runningGame(c.status, c.players...)
		if err := e.links.Unlink(context.Background(), "uA"); err != nil {
			t.Fatalf("%s %v: %v", c.status, c.players, err)
		}
	}
	e := newLinkEnv(t)
	e.start(100, 7, e.code("uA", time.Now()))
	e.runningGame(gameStarting, "uA")
	wantHTTP(t, e.links.Unlink(context.Background(), "uA"), 409, "in_game")
}

// Hai tg bấm cùng một mã cùng lúc: đúng một bên được liên kết.
func TestEmulatorLinkConcurrentConsumeOneWins(t *testing.T) {
	e := newLinkEnv(t)
	code := e.code("uA", time.Now())
	var wg sync.WaitGroup
	errs := make([]error, 2)
	for i := range errs {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, errs[i] = e.links.ConsumeLinkCode(context.Background(), code, TelegramUser{ID: int64(7 + i)}, time.Now())
		}(i)
	}
	wg.Wait()
	won := -1
	for i, err := range errs {
		switch {
		case err == nil:
			if won >= 0 {
				t.Fatal("cả hai cùng liên kết được")
			}
			won = i
		case !errors.Is(err, errLinkCodeUsed):
			t.Fatalf("bên thua phải là errLinkCodeUsed: %v", err)
		}
	}
	if won < 0 {
		t.Fatal("không bên nào liên kết được")
	}
	e.wantLink("uA", int64(7+won))
	if e.data(fmt.Sprintf("tgLinks/%d", 8-won)) != nil {
		t.Fatal("bên thua vẫn có tgLinks")
	}
}

func TestEmulatorLinkStatusAndUnlink(t *testing.T) {
	e := newLinkEnv(t)
	ctx := context.Background()
	// Client tự ghi tg vào users/{uid} thì không tính là liên kết.
	seed(t, e.db, "users/uA", map[string]any{"displayName": "An", "telegramUserId": int64(7)})
	if got, err := e.links.Link(ctx, "uA"); err != nil || got != (LinkStatus{}) {
		t.Fatalf("users.telegramUserId không được có tác dụng: %+v %v", got, err)
	}
	e.start(100, 7, e.code("uA", time.Now()))
	if got, _ := e.links.Link(ctx, "uA"); got != (LinkStatus{Linked: true, TgUsername: "tg7", DisplayName: "Người 7"}) {
		t.Fatalf("%+v", got)
	}
	if err := e.links.RecordMembership(ctx, 7, TelegramChatMember{Status: "member"}, time.Now()); err != nil {
		t.Fatal(err)
	}
	if got, _ := e.links.Link(ctx, "uA"); !got.InPsc {
		t.Fatalf("thiếu inPsc: %+v", got)
	}
	if err := e.links.Unlink(ctx, "uA"); err != nil {
		t.Fatal(err)
	}
	if e.data("telegramLinks/uA") != nil || e.data("tgLinks/7") != nil {
		t.Fatal("huỷ mà còn liên kết")
	}
	if err := e.links.Unlink(ctx, "uA"); err != nil {
		t.Fatalf("huỷ lần hai: %v", err)
	}
	if got, _ := e.links.Link(ctx, "uA"); got.Linked {
		t.Fatalf("%+v", got)
	}
}

// Hai đầu liên kết lệch nhau là dữ liệu hỏng: báo lỗi chứ không trả linked
// theo một đầu.
func TestEmulatorLinkStatusMismatchedSidesIsError(t *testing.T) {
	e := newLinkEnv(t)
	seed(t, e.db, "telegramLinks/uA", map[string]any{"tgUserId": int64(7)})
	seed(t, e.db, "tgLinks/7", map[string]any{"uid": "uB", "inPsc": true})
	if got, err := e.links.Link(context.Background(), "uA"); err == nil {
		t.Fatalf("phải lỗi, được %+v", got)
	}
}

// Mã chỉ tiêu trong DM. Gõ trong group thì không liên kết, đi đường cũ sang LLM.
func TestEmulatorLinkCodeInGroupIsNotConsumed(t *testing.T) {
	e := newLinkEnv(t)
	code := e.code("uA", time.Now())
	raw := fmt.Sprintf(`{"update_id":100,"message":{"message_id":1,"text":"/start %s","chat":{"id":-100,"type":"supergroup"},"from":{"id":7}}}`, code)
	rec := httptest.NewRecorder()
	e.srv.serveTelegramUpdate(context.Background(), rec, []byte(raw), func(_ context.Context, p PublishTask) (string, error) {
		e.tasks = append(e.tasks, p)
		return "created", nil
	})
	if rec.Body.Len() != 0 || len(e.tasks) != 1 || e.tasks[0].HandlerPath != "/tasks/bot-message" {
		t.Fatalf("body=%s tasks=%v", rec.Body, e.tasks)
	}
	if e.data("tgLinks/7") != nil {
		t.Fatal("mã gõ trong group mà vẫn liên kết")
	}
}

func TestEmulatorRecordMembershipKeepsNewestCheck(t *testing.T) {
	e := newLinkEnv(t)
	ctx := context.Background()
	t0 := time.Date(2026, 10, 16, 9, 0, 0, 0, time.UTC)
	// tg chưa liên kết: không tạo doc.
	if err := e.links.RecordMembership(ctx, 7, TelegramChatMember{Status: "member"}, t0); err != nil {
		t.Fatal(err)
	}
	if e.data("tgLinks/7") != nil {
		t.Fatal("tg chưa liên kết mà có tgLinks")
	}
	e.start(100, 7, e.code("uA", time.Now()))
	left := TelegramChatMember{Status: "left"}
	if err := e.links.RecordMembership(ctx, 7, left, t0.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	// Kết quả kiểm sớm hơn đến muộn: không ghi đè.
	if err := e.links.RecordMembership(ctx, 7, TelegramChatMember{Status: "member"}, t0); err != nil {
		t.Fatal(err)
	}
	if l := e.data("tgLinks/7"); l["inPsc"] != false {
		t.Fatalf("lần kiểm cũ ghi đè lần mới: %v", l)
	}
	if err := e.links.RecordMembership(ctx, 7, TelegramChatMember{Status: "restricted", IsMember: true}, t0.Add(2*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if l := e.data("tgLinks/7"); l["inPsc"] != true {
		t.Fatalf("restricted mà còn ở nhóm phải là inPsc: %v", l)
	}
}

// Bot nhận game-update: hỏi getChatMember ở PSC cho từng người trong update rồi
// ghi inPsc.
func TestEmulatorGameUpdateWritesInPsc(t *testing.T) {
	e := newLinkEnv(t)
	e.start(100, 7, e.code("uA", time.Now()))
	e.start(101, 8, e.code("uB", time.Now()))
	tg := newFakeTelegram(t)
	tg.Then("getChatMember",
		tgReply{200, `{"ok":true,"result":{"status":"member","user":{"id":7,"username":"moi7"}}}`},
		tgReply{200, `{"ok":true,"result":{"status":"kicked","user":{"id":8}}}`})
	srv := NewBotServer(testBotCfg, &Dependencies{Firestore: e.db, TelegramLinks: e.links, Telegram: tg.service("-100psc")})

	raw := `{"update_id":30,"message":{"message_id":3,"chat":{"id":-100,"type":"supergroup"},"from":{"id":7},"new_chat_members":[{"id":7},{"id":99,"is_bot":true}],"left_chat_member":{"id":8}}}`
	body, _ := json.Marshal(gameUpdateTask{UpdateID: 30, Raw: json.RawMessage(raw)})
	rec := httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest("POST", "/tasks/game-update", strings.NewReader(string(body))))
	if rec.Code != 200 {
		t.Fatalf("status=%d body=%s", rec.Code, rec.Body)
	}
	calls := tg.Calls("getChatMember")
	if len(calls) != 2 || calls[0].Params["chat_id"] != "-100psc" || calls[0].Params["user_id"] != float64(7) || calls[1].Params["user_id"] != float64(8) {
		t.Fatalf("phải hỏi PSC cho 7 và 8, bỏ bot: %v", calls)
	}
	if l := e.data("tgLinks/7"); l["inPsc"] != true || l["username"] != "moi7" {
		t.Fatalf("tgLinks/7=%v", l)
	}
	if l := e.data("tgLinks/8"); l["inPsc"] != false {
		t.Fatalf("tgLinks/8=%v", l)
	}

	// Telegram lỗi thì trả non-2xx để Cloud Tasks retry, không đoán là đã rời nhóm.
	tg.Then("getChatMember", tgTooManyRequests(3))
	rec = httptest.NewRecorder()
	srv.ServeHTTP(rec, httptest.NewRequest("POST", "/tasks/game-update", strings.NewReader(string(body))))
	if rec.Code < 500 {
		t.Fatalf("lỗi Telegram phải retry: status=%d", rec.Code)
	}
	if l := e.data("tgLinks/7"); l["inPsc"] != true {
		t.Fatalf("lỗi mà vẫn ghi đè inPsc: %v", l)
	}
}

func TestEmulatorAccountDeleteRemovesTelegramLinks(t *testing.T) {
	e := newLinkEnv(t)
	e.start(100, 7, e.code("uA", time.Now()))
	e.start(101, 8, e.code("uB", time.Now()))
	e.code("uA", time.Now())
	accounts := &AccountService{db: e.db}
	if err := accounts.deleteOwnedDocuments(context.Background(), "uA", ""); err != nil {
		t.Fatal(err)
	}
	if e.data("telegramLinks/uA") != nil || e.data("tgLinks/7") != nil {
		t.Fatal("xoá tài khoản mà còn liên kết Telegram")
	}
	docs, err := e.db.Collection("linkCodes").Where("uid", "==", "uA").Documents(context.Background()).GetAll()
	if err != nil || len(docs) != 0 {
		t.Fatalf("còn %d mã của uA (%v)", len(docs), err)
	}
	e.wantLink("uB", 8)
}
