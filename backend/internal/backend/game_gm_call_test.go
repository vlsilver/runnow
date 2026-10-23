package backend

import (
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Quản trò gọi từng vai dậy theo giờ: 22h sói, tiên tri, bảo vệ; 0h phù thuỷ;
// 10h cả làng. Vai không còn ai sống thì không gọi.
func TestStepMessagesGameMasterCalls(t *testing.T) {
	call := func(m gameMsg) (any, any) { return m.Data["call"], m.Data["wake"] }
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	if wake := startMessages(st)[0].Data["wake"]; !reflect.DeepEqual(wake, []string{"cupid"}) {
		t.Fatalf("mở ván gọi %v", wake)
	}

	night, evs := mustStep(t, st)
	if c, w := call(stepMessages(st, night, evs)[0]); c != callNight || !reflect.DeepEqual(w, []string{"wolf", "seer", "guard"}) {
		t.Fatalf("22h đêm 1: %v %v", c, w)
	}
	dawn, evs := mustStep(t, night, act1(ww.KindWolfBite, "w1", "seer"))
	if c, w := call(stepMessages(night, dawn, evs)[0]); c != callWitch || !reflect.DeepEqual(w, []string{"witch"}) {
		t.Fatalf("0h: %v %v", c, w)
	}
	day, evs := mustStep(t, dawn)
	if !day.Players["witch"].Alive || day.Players["seer"].Alive {
		t.Fatalf("10h: tiên tri phải chết, phù thuỷ còn sống: %+v", evs)
	}
	if c, w := call(stepMessages(dawn, day, evs)[0]); c != callMorning || w != nil {
		t.Fatalf("10h: %v %v", c, w)
	}
	trial, evs := mustStep(t, day, act1(ww.KindNominate, "v1", "witch"))
	if c, _ := call(stepMessages(day, trial, evs)[0]); c != nil {
		t.Fatalf("17h mà quản trò gọi %v", c)
	}

	// Phù thuỷ bị treo ngày 1: đêm 2 không gọi tiên tri (chết đêm 1), 0h không
	// còn ai để gọi nên bản tin 0h không có lời quản trò.
	hang := func(actor string) ww.Action {
		return ww.Action{Kind: ww.KindVote, Actor: actor, Choice: ww.ChoiceHang, ReceivedAt: trial.NightAt.Add(23 * time.Hour)}
	}
	night2, evs := mustStep(t, trial, hang("v1"), hang("v2"), hang("v3"))
	if night2.Players["witch"].Alive {
		t.Fatalf("phù thuỷ chưa bị treo: %+v", evs)
	}
	if c, w := call(stepMessages(trial, night2, evs)[0]); c != callNight || !reflect.DeepEqual(w, []string{"wolf", "guard"}) {
		t.Fatalf("22h đêm 2: %v %v", c, w)
	}
	dawn2, evs := mustStep(t, night2)
	if c, _ := call(stepMessages(night2, dawn2, evs)[0]); c != nil {
		t.Fatalf("0h đêm 2 không còn phù thuỷ mà gọi %v", c)
	}
}

func TestRenderGameMasterCalls(t *testing.T) {
	r := testRenderer()
	howTo := "Ai có vai thì bấm trong tin 3i nhắn riêng hoặc trong app RunNow."

	// 22h đêm 1 không có gì công khai: trước đây không gửi, giờ có lời quản trò.
	out := renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/setup", "round": 1, "phase": "night", "deadline": "2026-10-15T17:00:00Z",
		"call": "night", "wake": []string{"wolf", "seer", "guard"},
	})
	want := "<b>Đêm 1 buông xuống, cả làng đi ngủ.</b>\n" +
		"Sói thức dậy, cả phe chọn một người để cắn, tới 0h.\n" +
		"Tiên tri thức dậy, chọn một người để soi, tới 10h sáng.\n" +
		"Bảo vệ thức dậy, chọn một người để che, tới 10h sáng.\n" + howTo
	if len(out.parts) != 1 || out.parts[0] != want {
		t.Fatalf("22h đêm 1 = %q", out.parts)
	}

	// 22h sau biểu quyết: kết quả trước, lời quản trò thay dòng "Tiếp theo".
	out = renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/trial", "round": 2, "phase": "night", "deadline": "2026-10-16T17:00:00Z",
		"events": []ww.Event{{Kind: ww.EventDeath, UID: "s1", Role: ww.Seer}},
		"call":   "night", "wake": []string{"wolf"},
	})
	want = "<b>Biểu quyết ngày 1</b>\nChi đã chết. Lá bài: Tiên tri.\n\n" +
		"<b>Đêm 2 buông xuống, cả làng đi ngủ.</b>\nSói thức dậy, cả phe chọn một người để cắn, tới 0h.\n" + howTo
	if out.parts[0] != want {
		t.Fatalf("22h đêm 2 = %q", out.parts[0])
	}

	out = renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/night", "round": 1, "phase": "dawn", "deadline": "2026-10-16T03:00:00Z",
		"call": "witch", "wake": []string{"witch"},
	})
	want = "<b>Sói đã chốt, sói đi ngủ.</b>\nPhù thuỷ thức dậy, chọn cứu người hay dùng bình độc, tới 10h sáng.\n" + howTo
	if out.parts[0] != want {
		t.Fatalf("0h = %q", out.parts[0])
	}

	out = renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/dawn", "round": 1, "phase": "day", "deadline": "2026-10-16T10:00:00Z",
		"events": []ww.Event{{Kind: ww.EventDeath, UID: "w2", Role: ww.Wolf}}, "call": "morning",
	})
	want = "<b>Trời sáng, cả làng thức dậy.</b>\n<b>Bản tin đêm 1</b>\nBình &amp; Co đã chết. Lá bài: Sói.\n\nTiếp theo: Ngày 1, đề cử, tới 17:00 16/10."
	if out.parts[0] != want {
		t.Fatalf("10h = %q", out.parts[0])
	}

	out = renderOne(t, r, chatGroup, tplStart, map[string]any{"nightAt": "2026-10-15T15:00:00Z", "wake": []string{"cupid"}})
	if !strings.HasSuffix(out.parts[0], "\nCupid thức dậy, chọn hai người để ghép đôi, tới 0h đêm 1.\n"+howTo) {
		t.Fatalf("mở ván có Cupid = %q", out.parts[0])
	}
}
