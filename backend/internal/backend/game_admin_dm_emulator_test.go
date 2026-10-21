//go:build emulator

package backend

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

const bossTg = "6999"

// command gửi text như một tin nhắn của tg trong chat kiểu chatType và trả body
// trả lời ngay trong response webhook.
func (e *buttonEnv) command(tg, chatType, text string) map[string]any {
	e.t.Helper()
	e.updateID++
	code, body := e.webhook(fmt.Sprintf(`{"update_id":%d,"message":{"message_id":1,"text":%q,"chat":{"id":%s,"type":%q},"from":{"id":%s}}}`,
		e.updateID, text, tg, chatType, tg))
	if code != 200 || body["method"] != "sendMessage" {
		e.t.Fatalf("%s = %d %v", text, code, body)
	}
	return body
}

func (e *buttonEnv) adminSays(text string) string {
	e.t.Helper()
	return e.command(bossTg, "private", text)["text"].(string)
}

// Admin gõ lệnh trong DM: ván ở gameState/current đổi theo, tin trả lời nói
// kết quả, có ghi thì kick flush. Lỗi của store hiện đúng câu của nó.
func TestEmulatorAdminDMCommands(t *testing.T) {
	e := newButtonEnv(t)
	e.srv.config.TelegramBotUsername = "Run3IBot"
	linkUser(t, e.h, "boss", bossTg, true)
	kicks := e.flushTasks()

	if got := e.adminSays("/pause"); got != "Đã tạm dừng ván." || !e.state().Paused || e.flushTasks() != kicks+1 {
		t.Fatalf("/pause = %q, paused=%v, kick=%d", got, e.state().Paused, e.flushTasks()-kicks)
	}
	if got := e.adminSays("/pause"); got != "Ván đang tạm dừng rồi." || e.flushTasks() != kicks+1 {
		t.Fatalf("/pause lần hai = %q", got)
	}
	if got := e.adminSays("/resume"); got != "Ván đã chạy tiếp." || e.state().Paused || e.flushTasks() != kicks+2 {
		t.Fatalf("/resume = %q", got)
	}

	syntax := "Gõ /extend <số phút>, từ 1 tới 240."
	for _, bad := range []string{"/extend", "/extend abc", "/extend 0", "/extend 241", "/extend 1.5"} {
		if got := e.adminSays(bad); got != syntax {
			t.Fatalf("%s = %q", bad, got)
		}
	}
	before := e.state().Deadline()
	if got := e.adminSays("/extend 30"); got != "Đã dời hạn thêm 30 phút." || !e.state().Deadline().Equal(before.Add(30*time.Minute)) || e.flushTasks() != kicks+3 {
		t.Fatalf("/extend 30 = %q, hạn %s → %s", got, before, e.state().Deadline())
	}
	// Đêm 1 khoá lúc 0h, lượt sau (rạng sáng) khoá lúc 10h: tổng dời tối đa 9h,
	// nên sau 30 + 240 + 240 phút chỉ còn 30 phút.
	for _, cmd := range []string{"/extend@run3ibot 240", "/extend 240"} {
		if got := e.adminSays(cmd); got != "Đã dời hạn thêm 240 phút." {
			t.Fatalf("%s = %q", cmd, got)
		}
	}
	if got := e.adminSays("/extend 31"); got != "Chỉ dời thêm được tối đa 30 phút, để lượt sau còn ít nhất 1 giờ." || e.flushTasks() != kicks+5 {
		t.Fatalf("/extend quá mức = %q", got)
	}

	if got := e.adminSays("/retry"); got != "Đã xếp lại 0 tin lỗi để gửi lại." || e.flushTasks() != kicks+6 {
		t.Fatalf("/retry = %q", got)
	}
	seed(t, e.db, "games/"+e.id+"/outbox/group_99", map[string]any{"chatKey": chatGroup, "seq": int64(99), "template": tplAdmin,
		"data": `{"action":"pause"}`, "status": outboxFailed, "eventSeq": int64(1), "createdAt": time.Now()})
	if got := e.adminSays("/retry"); got != "Đã xếp lại 1 tin lỗi để gửi lại." {
		t.Fatalf("/retry có tin lỗi = %q", got)
	}
}

// Người không phải admin, Telegram chưa liên kết, gõ trong group, chưa có ván:
// mỗi ca một câu cố định, không đụng vào ván.
func TestEmulatorAdminDMRejects(t *testing.T) {
	e := newButtonEnv(t)
	linkUser(t, e.h, "boss", bossTg, true)
	kicks := e.flushTasks()
	for _, c := range []struct{ tg, chat, want string }{
		{e.storeGame.tg["w1"], "private", "Lệnh này chỉ dành cho admin Ma Sói."},
		{"555", "private", "Lệnh này chỉ dành cho admin Ma Sói."},
		{bossTg, "supergroup", "Lệnh admin Ma Sói chỉ dùng trong tin nhắn riêng với 3i."},
	} {
		for _, cmd := range []string{"/pause", "/resume", "/extend 30", "/retry", "/xem", "/cancel"} {
			body := e.command(c.tg, c.chat, cmd)
			if body["text"] != c.want || body["reply_markup"] != nil {
				t.Fatalf("%s %s %s = %v", c.tg, c.chat, cmd, body)
			}
		}
	}
	if e.state().Paused || e.flushTasks() != kicks {
		t.Fatal("lệnh bị từ chối mà vẫn đổi ván")
	}

	// Firestore lỗi tạm thời thì trả 5xx để Telegram gửi lại.
	expired, cancel := context.WithDeadline(context.Background(), time.Now().Add(-time.Second))
	defer cancel()
	raw := fmt.Sprintf(`{"update_id":990,"message":{"message_id":1,"text":"/pause","chat":{"id":%s,"type":"private"},"from":{"id":%s}}}`, bossTg, bossTg)
	if code, body := e.webhookCtx(expired, raw); code != 503 || body != nil {
		t.Fatalf("/pause khi Firestore lỗi tạm thời = %d %v", code, body)
	}

	if _, err := e.db.Doc("gameState/current").Delete(context.Background()); err != nil {
		t.Fatal(err)
	}
	if got := e.adminSays("/xem"); got != "Chưa có ván Ma Sói nào." {
		t.Fatalf("/xem khi chưa có ván = %q", got)
	}
}

func (e *buttonEnv) gameStatus() any {
	e.t.Helper()
	return e.data("games/" + e.id)["status"]
}

// /cancel chỉ trả nút xác nhận; bấm nút mới huỷ. Người không phải admin bấm
// thì không huỷ, Telegram gửi lại cú bấm thì báo ván đã huỷ.
func TestEmulatorAdminDMCancelConfirm(t *testing.T) {
	e := newButtonEnv(t)
	linkUser(t, e.h, "boss", bossTg, true)
	body := e.command(bossTg, "private", "/cancel")
	data, _ := gameButton{GameID: e.id, Op: opCancel}.data()
	markup, _ := body["reply_markup"].(map[string]any)
	rows, _ := markup["inline_keyboard"].([]any)
	if body["text"] != "Huỷ ván Ma Sói đang chạy? Huỷ rồi thì không chơi tiếp được." || len(rows) != 1 || data != "m1|"+e.id+"|k" {
		t.Fatalf("/cancel = %v", body)
	}
	if row, _ := rows[0].([]any); len(row) != 1 || row[0].(map[string]any)["text"] != "Huỷ ván" || row[0].(map[string]any)["callback_data"] != data {
		t.Fatalf("nút = %v", rows)
	}
	if st := e.gameStatus(); st != gameRunning {
		t.Fatalf("mới gõ /cancel mà ván đã %v", st)
	}
	kicks := e.flushTasks()
	if text, _ := e.press(e.storeGame.tg["w1"], data); text != "Lệnh này chỉ dành cho admin Ma Sói." || e.gameStatus() != gameRunning {
		t.Fatalf("người chơi bấm huỷ = %q", text)
	}
	if text, alert := e.press(bossTg, data); text != "Đã huỷ ván." || !alert || e.gameStatus() != gameCancelled || e.flushTasks() != kicks+1 {
		t.Fatalf("admin bấm huỷ = %q, status %v", text, e.gameStatus())
	}
	if text, _ := e.press(bossTg, data); text != "Ván đã kết thúc hoặc đã huỷ." || e.flushTasks() != kicks+1 {
		t.Fatalf("bấm lại = %q", text)
	}
}

// /xem chỉ có số đếm: lượt, hạn, số người sống, số đề cử/phiếu ban ngày, số
// tin chờ và tin lỗi. Không có tên ai, không đếm hành động đêm.
func TestEmulatorAdminDMSummary(t *testing.T) {
	e := newButtonEnv(t)
	linkUser(t, e.h, "boss", bossTg, true)
	if text, _ := e.press(e.storeGame.tg["w1"], e.btn(ww.KindWolfBite, opPick, "v1")); text != "Đã chọn V1." {
		t.Fatalf("cắn = %q", text)
	}
	// Hạn hiện theo giờ thật như app: ván test chạy lệch đồng hồ clockOffsetNs.
	real := func(gameAt time.Time) string {
		return vnTime(gameAt.Add(-time.Duration(number(e.data("games/" + e.id)["clockOffsetNs"]))))
	}
	want := "Trạng thái: Đang chơi\nLượt: Đêm 1, sói đang chọn\nHạn: " + real(time.Date(2026, 10, 16, 0, 0, 0, 0, vietnam)) +
		"\nCòn sống: 10/10\nTin chờ gửi: 2, tin lỗi: 0" // tin sửa DM và tin Phe Sói của lần cắn
	if got := e.adminSays("/xem"); got != want {
		t.Fatalf("/xem đêm =\n%s\nmong đợi\n%s", got, want)
	}

	// Sang ngày 1 thì v1 chết. Đề cử đã huỷ chọn (cleared) không đếm; tin lỗi
	// đã gửi lại không tính là lỗi.
	e.advanceTo(time.Date(2026, 10, 16, 10, 0, 0, 0, vietnam))
	e.flush()
	day := "games/" + e.id + "/rounds/1/actions/"
	seed(t, e.db, day+"w1_nominate", map[string]any{"kind": "nominate", "uid": "w1", "targets": []any{"seer"}})
	seed(t, e.db, day+"w2_nominate", map[string]any{"kind": "nominate", "uid": "w2", "targets": []any{"seer"}, "cleared": true})
	seed(t, e.db, "games/"+e.id+"/outbox/group_98", map[string]any{"status": outboxFailed, "retriedAs": "group_99"})
	seed(t, e.db, "games/"+e.id+"/outbox/group_97", map[string]any{"status": outboxFailed})
	seed(t, e.db, "games/"+e.id+"/outbox/group_96", map[string]any{"status": outboxSending})
	want = "Trạng thái: Đang chơi\nLượt: Ngày 1, đề cử\nHạn: " + real(time.Date(2026, 10, 16, 17, 0, 0, 0, vietnam)) +
		"\nCòn sống: 9/10\nĐề cử: 1, phiếu: 0\nTin chờ gửi: 1, tin lỗi: 1 (gõ /retry để gửi lại)"
	if got := e.adminSays("/xem"); got != want {
		t.Fatalf("/xem ngày =\n%s\nmong đợi\n%s", got, want)
	}
	// Lúc lên giàn thì đếm cả phiếu. Chỉ đổi doc công khai, /xem không đọc state.
	seedMerge(t, e.storeGame, map[string]any{"phase": "trial"})
	seed(t, e.db, day+"v2_vote", map[string]any{"kind": "vote", "uid": "v2", "choice": "hang"})
	if got := e.adminSays("/xem"); !strings.Contains(got, "\nLượt: Ngày 1, lên giàn\n") || !strings.Contains(got, "\nĐề cử: 1, phiếu: 1\n") {
		t.Fatalf("/xem lên giàn = %q", got)
	}
	seedMerge(t, e.storeGame, map[string]any{"phase": "day"})

	e.adminSays("/pause")
	if got := e.adminSays("/xem"); !strings.HasPrefix(got, "Trạng thái: Tạm dừng\nLượt: Ngày 1, đề cử\nCòn sống:") {
		t.Fatalf("/xem lúc tạm dừng = %q", got)
	}
}
