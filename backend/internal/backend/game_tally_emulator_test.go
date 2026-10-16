//go:build emulator

package backend

import (
	"context"
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// groupCalls là các lần gửi hay sửa tin trong group của ván.
func (e *buttonEnv) groupCalls() []tgCall {
	var out []tgCall
	for _, c := range e.tg.Calls("") {
		if c.Params["chat_id"] == "-100" {
			out = append(out, c)
		}
	}
	return out
}

func (e *buttonEnv) lastGroup() tgCall {
	e.t.Helper()
	calls := e.groupCalls()
	if len(calls) == 0 {
		e.t.Fatal("group chưa nhận tin nào")
	}
	return calls[len(calls)-1]
}

func (e *buttonEnv) groupPromptID(kind ww.Kind) float64 {
	e.t.Helper()
	snap, err := e.db.Doc("games/" + e.id + "/outboxChats/group").Get(context.Background())
	if err != nil {
		e.t.Fatal(err)
	}
	p := anyMap(anyMap(snap.Data()["prompts"])[string(kind)])
	if p["turnKey"] != turnKey(e.state()) || number(p["messageId"]) == 0 {
		e.t.Fatalf("prompt group/%s = %v", kind, p)
	}
	return float64(number(p["messageId"]))
}

// wall là giờ thật ứng với giờ ván at, như app và DM hiện (ván thử chạy lệch
// đồng hồ; ván thật có offset 0).
func (e *buttonEnv) wall(at time.Time) string {
	return vnTime(at.Add(-clockOffset(e.data("games/" + e.id))))
}

// buttonData lấy callback_data của nút có nhãn label trong tin c.
func buttonData(t *testing.T, c tgCall, label string) string {
	t.Helper()
	kb, _ := c.Params["reply_markup"].(map[string]any)
	rows, _ := kb["inline_keyboard"].([]any)
	for _, row := range rows {
		for _, b := range row.([]any) {
			if b := b.(map[string]any); b["text"] == label {
				return b["callback_data"].(string)
			}
		}
	}
	t.Fatalf("tin không có nút %q: %v", label, c.Params)
	return ""
}

// W2b "Xong khi": đề cử và Treo/Tha bấm ngay trong topic. Người không được bấm
// nhận toast riêng và số đếm không đổi; chọn trong app thì tin trong topic cập
// nhật.
func TestEmulatorTopicNominateAndVote(t *testing.T) {
	e := newButtonEnv(t)
	tg := e.storeGame.tg
	if text, _ := e.press(tg["w1"], e.btn(ww.KindWolfBite, opPick, "v1")); text != "Đã chọn V1." {
		t.Fatalf("cắn = %q", text)
	}
	// Hành động đêm cùng vòng nhắm người còn sống không được đếm thành đề cử.
	if text, _ := e.press(tg["guard"], e.btn(ww.KindGuard, opPick, "v2")); text != "Đã chọn V2." {
		t.Fatalf("bảo vệ = %q", text)
	}
	e.advanceTo(time.Date(2026, 10, 16, 10, 0, 0, 0, vietnam))
	e.flush()
	if e.state().Players["v1"].Alive {
		t.Fatal("v1 chưa chết")
	}
	prompt := e.lastGroup()
	id := e.groupPromptID(ww.KindNominate)
	if prompt.Method != "sendMessage" || !strings.HasPrefix(prompt.Params["text"].(string), "<b>Đề cử lên giàn, ngày 1</b>\nHạn: "+e.wall(time.Date(2026, 10, 16, 17, 0, 0, 0, vietnam))+".\nChưa ai được đề cử.\n") ||
		strings.Join(buttonsOf(prompt), ",") != "GUARD,HUNTER,SEER,V2,V3,V4,W1,W2,WITCH" {
		t.Fatalf("prompt đề cử = %v", prompt)
	}
	pick := buttonData(t, prompt, "W1")

	edits := func() int { return len(e.tg.Calls("editMessageText")) }
	wantEdit := func(lines ...string) {
		t.Helper()
		e.flush()
		c := e.lastGroup()
		text, _ := c.Params["text"].(string)
		if c.Method != "editMessageText" || c.Params["message_id"] != id || !strings.Contains(text, "\n"+strings.Join(lines, "\n")+"\n") {
			t.Fatalf("tin sửa = %v, mong đợi có %q", c, lines)
		}
	}
	if text, _ := e.press(tg["v2"], pick); text != "Đã chọn W1." {
		t.Fatalf("v2 đề cử = %q", text)
	}
	wantEdit("<b>W1</b>: 1 (V2)")

	n := edits()
	for _, c := range []struct{ uid, data, want string }{
		{"v1", pick, "Bạn đã chết."},
		{"w1", pick, "Không chọn được người này."},
		{"v1", "m1|" + e.id + "|r0|n|t|0", buttonTexts.stale},
	} {
		if text, _ := e.press(tg[c.uid], c.data); text != c.want {
			t.Fatalf("%s bấm = %q, mong đợi %q", c.uid, text, c.want)
		}
	}
	e.flush()
	if edits() != n {
		t.Fatal("cú bấm bị từ chối mà tin trong topic vẫn bị sửa")
	}

	e.h.want(e.h.call("v3", "POST", "/v1/games/"+e.id+"/actions", map[string]any{"kind": "nominate", "targets": []string{"w1"}}, ""), 200, "")
	wantEdit("<b>W1</b>: 2 (V2, V3)")

	// Tin sửa ghi trước 17h mà gửi sau lần chốt thì vẽ số cuối, hết nút.
	if text, _ := e.press(tg["v4"], pick); text != "Đã chọn W1." {
		t.Fatalf("v4 đề cử = %q", text)
	}
	nominateID := id

	// 17h: W1 lên giàn, topic có prompt biểu quyết. Bấm trước 20h thì bị từ chối.
	e.advanceTo(time.Date(2026, 10, 16, 17, 0, 0, 0, vietnam))
	e.flush()
	var last tgCall
	for _, c := range e.tg.Calls("editMessageText") {
		if c.Params["message_id"] == nominateID {
			last = c
		}
	}
	if text, _ := last.Params["text"].(string); text != "<b>Đề cử lên giàn, ngày 1</b>\nĐã hết giờ.\n<b>W1</b>: 3 (V2, V3, V4)" || len(buttonsOf(last)) != 0 {
		t.Fatalf("tin đề cử sau 17h = %v", last)
	}
	prompt = e.lastGroup()
	id = e.groupPromptID(ww.KindVote)
	if prompt.Method != "sendMessage" || !strings.HasPrefix(prompt.Params["text"].(string), "<b>Biểu quyết ngày 1: treo hay tha W1</b>\nMở lúc "+e.wall(time.Date(2026, 10, 16, 20, 0, 0, 0, vietnam))+
		", hạn "+e.wall(time.Date(2026, 10, 16, 22, 0, 0, 0, vietnam))+".\n<b>Treo</b>: 0\n<b>Tha</b>: 0\n") ||
		strings.Join(buttonsOf(prompt), ",") != "Treo,Tha" {
		t.Fatalf("prompt biểu quyết = %v", prompt)
	}
	hang := buttonData(t, prompt, "Treo")
	if text, _ := e.press(tg["v2"], hang); text != "Chưa tới giờ hoặc đã hết giờ." {
		t.Fatalf("Treo lúc 17h30 = %q", text)
	}

	e.advanceTo(time.Date(2026, 10, 16, 20, 0, 0, 0, vietnam))
	if text, _ := e.press(tg["v2"], hang); text != "Đã chọn Treo." {
		t.Fatalf("v2 Treo = %q", text)
	}
	wantEdit("Hạn: "+e.wall(time.Date(2026, 10, 16, 22, 0, 0, 0, vietnam))+".", "<b>Treo</b>: 1 (V2)", "<b>Tha</b>: 0")
	n = edits()
	if text, _ := e.press(tg["w1"], hang); text != "Người lên giàn không bỏ phiếu." {
		t.Fatalf("người lên giàn bấm = %q", text)
	}
	e.flush()
	if edits() != n {
		t.Fatal("người lên giàn bấm mà tin vẫn bị sửa")
	}
	e.h.want(e.h.call("v3", "POST", "/v1/games/"+e.id+"/actions", map[string]any{"kind": "vote", "choice": "spare"}, ""), 200, "")
	wantEdit("<b>Treo</b>: 1 (V2)", "<b>Tha</b>: 1 (V3)")
	if a := e.data("games/" + e.id + "/rounds/1/actions/v2_vote"); a["choice"] != ww.ChoiceHang || a["source"] != "telegram" {
		t.Fatalf("action của v2 = %v", a)
	}
}

// Prompt đề cử ghi lúc 10h mà tới sau 17h mới gửi thì bỏ, không đăng nút của
// phase đã qua; tin sửa của nó cũng bỏ vì prompt chưa từng gửi.
func TestEmulatorTopicLatePromptIsSkipped(t *testing.T) {
	e := newButtonEnv(t)
	e.advanceTo(time.Date(2026, 10, 16, 10, 0, 0, 0, vietnam))
	e.h.want(e.h.call("v3", "POST", "/v1/games/"+e.id+"/actions", map[string]any{"kind": "nominate", "targets": []string{"w1"}}, ""), 200, "")
	e.advanceTo(time.Date(2026, 10, 16, 17, 0, 0, 0, vietnam))
	e.flush()
	docs, err := e.db.Collection("games/"+e.id+"/outbox").Where("chatKey", "==", chatGroup).Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, d := range docs {
		m := d.Data()
		if tpl := stringValue(m["template"]); tpl == tplPrompt || tpl == tplTally {
			got[tpl+"/"+stringValue(m["data"])] = stringValue(m["status"]) + "/" + stringValue(m["skipReason"])
		}
	}
	want := map[string]string{
		`prompt/{"kind":"nominate","turnKey":"r1"}`: "skipped/closed",
		`tally/{"kind":"nominate"}`:                 "skipped/no_prompt",
		`prompt/{"kind":"vote","turnKey":"r1"}`:     "sent/",
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tin group = %v", got)
	}
}
