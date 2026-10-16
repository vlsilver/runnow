//go:build emulator

package backend

import (
	"bytes"
	"context"
	"fmt"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

const adminChat = "5000"

// alertEnv là advanceEnv có Telegram giả và admin boss đã liên kết (tg 5000).
type alertEnv struct {
	*advanceEnv
	tg     *fakeTelegram
	prefix string // tick chỉ trả DM bắt đầu bằng chuỗi này
}

func newAlertEnv(t *testing.T) *alertEnv {
	t.Helper()
	e := &alertEnv{advanceEnv: newAdvanceEnv(t, newStoreGame(t)), tg: newFakeTelegram(t)}
	e.bot = NewBotServer(Config{GameInboundQueue: "game-inbound"}, &Dependencies{
		Firestore: e.db, Games: e.store, Telegram: e.tg.service(testPscChat), EnqueueTask: e.publish, Now: func() time.Time { return e.clock },
	})
	seed(t, e.db, "gameState/config", map[string]any{"adminUids": []any{"boss"}})
	seed(t, e.db, "telegramLinks/boss", map[string]any{"tgUserId": adminChat})
	seed(t, e.db, "tgLinks/"+adminChat, map[string]any{"uid": "boss"})
	// Gửi hết tin của bước Start (9h), để test chỉ thấy tin của các bước sau.
	if _, err := e.store.FlushGame(context.Background(), e.id, e.tg.service(testPscChat), time.Now); err != nil {
		t.Fatal(err)
	}
	return e
}

// tick chạy schedule-tick lúc at, Telegram báo webhook còn pending update; trả
// các DM admin mới nhận trong tick này, lọc theo prefix.
func (e *alertEnv) tick(at time.Time, pending, wantCode int) []string {
	e.t.Helper()
	before := len(e.adminDMs())
	e.tg.Then("getWebhookInfo", tgReply{200, fmt.Sprintf(`{"ok":true,"result":{"url":"https://x","pending_update_count":%d}}`, pending)})
	e.clock = at
	rec := httptest.NewRecorder()
	e.bot.ServeHTTP(rec, httptest.NewRequest("POST", "/tasks/schedule-tick", bytes.NewReader([]byte("{}"))))
	if rec.Code != wantCode {
		e.t.Fatalf("tick lúc %s: %d %s", vnTime(at), rec.Code, rec.Body)
	}
	var out []string
	for _, d := range e.adminDMs()[before:] {
		if strings.HasPrefix(d, e.prefix) {
			out = append(out, d)
		}
	}
	return out
}

func (e *alertEnv) adminDMs() []string {
	var out []string
	for _, c := range e.tg.Calls("sendMessage") {
		if c.Params["chat_id"] == adminChat {
			out = append(out, c.Params["text"].(string))
		}
	}
	return out
}

func at(day, hour, min int) time.Time { return time.Date(2026, 10, day, hour, min, 0, 0, vietnam) }

// M1 "Xong khi": ép từng loại lỗi thì admin nhận DM ở tick kế tiếp (≤ 10 phút
// sau khi vượt ngưỡng). Chỉ báo khi có loại mới, hết chuyện rồi bị lại thì báo
// lại. Tin chỉ có số đếm.
func TestEmulatorAlertsAdminOnNewIssues(t *testing.T) {
	e := newAlertEnv(t)
	e.prefix = "Ma Sói cần xem:"
	// 22:07 tick chốt 22h; tin của bước nằm pending vì flush chưa chạy.
	if dm := e.tick(at(15, 22, 7), 0, 200); len(dm) != 0 {
		t.Fatalf("chưa có chuyện mà báo: %q", dm)
	}
	if dm := e.tick(at(15, 22, 17), 0, 200); len(dm) != 0 {
		t.Fatalf("tin mới chờ 10 phút mà đã báo: %q", dm)
	}
	// 22:27: tin chờ đã quá 15 phút; webhook mới thấy pending lần đầu. health
	// còn của ván trước (đã báo tin chờ) không chặn báo của ván này.
	seed(t, e.db, "gameState/health", map[string]any{"gameId": "old", "alertKey": "stale,webhook"})
	dm := e.tick(at(15, 22, 27), 2, 200)
	if len(dm) != 1 || !strings.HasPrefix(dm[0], "Ma Sói cần xem:\n- ") || !strings.HasSuffix(dm[0], " tin chờ gửi quá 15 phút.") {
		t.Fatalf("22:27 = %q", dm)
	}
	// 22:37: tick thứ hai liền nhau còn thấy webhook pending (10 phút) là loại mới.
	dm = e.tick(at(15, 22, 37), 3, 200)
	if len(dm) != 1 || !strings.HasSuffix(dm[0], " tin chờ gửi quá 15 phút.\n- Telegram còn 3 update chưa giao tới webhook, đã hơn 10 phút.") {
		t.Fatalf("22:37 = %q", dm)
	}
	if dm := e.tick(at(15, 22, 47), 3, 200); len(dm) != 0 {
		t.Fatalf("cùng loại mà báo lại: %q", dm)
	}

	// Tin lỗi và người chặn DM.
	seed(t, e.db, "games/"+e.id+"/outbox/group_99", map[string]any{"chatKey": chatGroup, "seq": int64(99), "template": tplAdmin,
		"data": `{"action":"pause"}`, "status": outboxFailed, "eventSeq": int64(1), "createdAt": at(15, 22, 50)})
	if _, err := e.db.Doc("games/"+e.id+"/players/v1").Update(context.Background(), []firestore.Update{{Path: "dmOk", Value: false}}); err != nil {
		t.Fatal(err)
	}
	dm = e.tick(at(15, 22, 57), 0, 200)
	if len(dm) != 1 || !strings.HasPrefix(dm[0], "Ma Sói cần xem:\n- 1 tin gửi lỗi, gõ /retry để gửi lại.\n- ") ||
		!strings.HasSuffix(dm[0], " tin chờ gửi quá 15 phút.\n- 1 người chơi chưa nhận được DM của bot.") {
		t.Fatalf("22:57 = %q", dm)
	}

	// Hết chuyện: không báo gì, và lần sau bị lại thì báo lại.
	if _, err := e.store.FlushGame(context.Background(), e.id, e.tg.service(testPscChat), time.Now); err != nil {
		t.Fatal(err)
	}
	seed(t, e.db, "games/"+e.id+"/outbox/group_99", map[string]any{"status": outboxFailed, "retriedAs": "group_100"})
	if _, err := e.db.Doc("games/"+e.id+"/players/v1").Update(context.Background(), []firestore.Update{{Path: "dmOk", Value: true}}); err != nil {
		t.Fatal(err)
	}
	if dm := e.tick(at(15, 23, 7), 0, 200); len(dm) != 0 {
		t.Fatalf("hết chuyện mà báo: %q", dm)
	}
	if dm := e.tick(at(15, 23, 17), 1, 200); len(dm) != 0 {
		t.Fatalf("webhook mới pending mà báo: %q", dm)
	}
	if dm := e.tick(at(15, 23, 27), 1, 200); len(dm) != 1 || dm[0] != "Ma Sói cần xem:\n- Telegram còn 1 update chưa giao tới webhook, đã hơn 10 phút." {
		t.Fatalf("webhook bị lại = %q", dm)
	}

	// Ván hỏng: tick lỗi (5xx) và admin được báo; quá mốc 0h hơn 25 phút thì
	// thêm dòng quá hạn.
	seed(t, e.db, "games/"+e.id+"/secret/state", map[string]any{"state": "{"})
	if dm := e.tick(at(15, 23, 37), 0, 500); len(dm) != 1 || dm[0] != "Ma Sói cần xem:\n- Tick chạy ván bị lỗi, xem log tick.job_failed." {
		t.Fatalf("tick lỗi = %q", dm)
	}
	if dm := e.tick(at(16, 0, 25), 0, 500); len(dm) != 0 {
		t.Fatalf("mới quá mốc 25 phút mà báo: %q", dm)
	}
	if dm := e.tick(at(16, 0, 26), 0, 500); len(dm) != 1 ||
		dm[0] != "Ma Sói cần xem:\n- Tick chạy ván bị lỗi, xem log tick.job_failed.\n- Quá mốc chốt hơn 25 phút mà ván chưa chuyển lượt." {
		t.Fatalf("quá hạn = %q", dm)
	}
	// Ván tạm dừng thì không tính quá hạn; bớt một loại thì không báo lại, loại đó
	// quay lại thì báo.
	seedMerge(t, e.storeGame, map[string]any{"paused": true})
	if dm := e.tick(at(16, 0, 36), 0, 500); len(dm) != 0 {
		t.Fatalf("tạm dừng = %q", dm)
	}
	seedMerge(t, e.storeGame, map[string]any{"paused": false})
	if dm := e.tick(at(16, 0, 46), 0, 500); len(dm) != 1 || !strings.HasSuffix(dm[0], "Quá mốc chốt hơn 25 phút mà ván chưa chuyển lượt.") {
		t.Fatalf("chạy tiếp = %q", dm)
	}
}

// Một admin chặn bot thì admin kia vẫn nhận, và tick sau không báo lặp. Không
// admin nào nhận được thì tick báo lỗi và tick sau gửi lại.
func TestEmulatorAlertsReachAnyAdmin(t *testing.T) {
	e := newAlertEnv(t)
	e.prefix = "Ma Sói cần xem:"
	seed(t, e.db, "gameState/config", map[string]any{"adminUids": []any{"boss", "boss2"}})
	seed(t, e.db, "telegramLinks/boss2", map[string]any{"tgUserId": "5001"})
	seed(t, e.db, "tgLinks/5001", map[string]any{"uid": "boss2"})
	toBoss2 := func() int {
		n := 0
		for _, c := range e.tg.Calls("sendMessage") {
			if c.Params["chat_id"] == "5001" {
				n++
			}
		}
		return n
	}
	// 21h: chưa tới bước chốt, giờ tóm tắt cũng chưa tới; chỉ có webhook pending.
	e.tick(at(15, 21, 7), 1, 200)
	// boss (uid đứng trước) chặn bot.
	e.tg.Then("sendMessage", tgForbidden("Forbidden: bot was blocked by the user"))
	if dm := e.tick(at(15, 21, 17), 1, 200); len(dm) != 1 || toBoss2() != 1 { // dm là lần thử gửi boss
		t.Fatalf("gửi boss %q, boss2 nhận %d tin", dm, toBoss2())
	}
	if e.tick(at(15, 21, 27), 1, 200); toBoss2() != 1 {
		t.Fatal("đã có admin nhận mà tick sau báo lặp")
	}
	// Cả hai chặn: 5xx, tick sau gửi lại.
	seed(t, e.db, "games/"+e.id+"/outbox/group_99", map[string]any{"chatKey": chatGroup, "status": outboxFailed, "createdAt": at(15, 21, 30)})
	e.tg.Then("sendMessage", tgForbidden("Forbidden: bot was blocked by the user"), tgForbidden("Forbidden: bot was blocked by the user"))
	e.tick(at(15, 21, 37), 1, 500)
	if dm := e.tick(at(15, 21, 47), 1, 200); len(dm) != 1 || !strings.HasPrefix(dm[0], "Ma Sói cần xem:\n- 1 tin gửi lỗi") || toBoss2() != 3 { // 21:17, lần bị chặn 21:37, 21:47
		t.Fatalf("gửi lại = %q", dm)
	}
}

// Tin tóm tắt: tick đầu tiên sau 10:30 và sau 22:30, mỗi mốc một lần, nội dung
// như /xem.
func TestEmulatorAlertsSummaryTwiceADay(t *testing.T) {
	e := newAlertEnv(t)
	e.prefix = "Tóm tắt"
	e.advance(at(16, 10, 0)) // tới ngày 1
	if s := e.tick(at(16, 10, 29), 0, 200); len(s) != 0 {
		t.Fatalf("10:29 = %q", s)
	}
	s := e.tick(at(16, 10, 31), 0, 200)
	want, err := e.store.AdminSummary(context.Background(), e.id)
	if err != nil {
		t.Fatal(err)
	}
	if len(s) != 1 || s[0] != "Tóm tắt Ma Sói lúc 10:30\n"+want || !strings.HasPrefix(want, "Trạng thái: ") {
		t.Fatalf("10:31 = %q", s)
	}
	for _, h := range []time.Time{at(16, 10, 41), at(16, 11, 31), at(16, 22, 21)} {
		if s := e.tick(h, 0, 200); len(s) != 0 {
			t.Fatalf("%s = %q", vnTime(h), s)
		}
	}
	// Tick 22:30 lỡ, 22:41 gửi bù.
	if s := e.tick(at(16, 22, 41), 0, 200); len(s) != 1 || !strings.HasPrefix(s[0], "Tóm tắt Ma Sói lúc 22:30\nTrạng thái: ") {
		t.Fatalf("22:41 = %q", s)
	}
}

// Không có admin nào đã liên kết thì không hỏi Telegram, không gửi gì.
func TestEmulatorAlertsNeedLinkedAdmin(t *testing.T) {
	e := newAlertEnv(t)
	seed(t, e.db, "gameState/config", map[string]any{"adminUids": []any{"nolink"}})
	e.clock = at(16, 10, 31)
	before := len(e.tg.Calls(""))
	e.post("/tasks/schedule-tick", map[string]any{})
	if n := len(e.tg.Calls("")) - before; n != 0 {
		t.Fatalf("gọi Telegram %d lần", n)
	}
}
