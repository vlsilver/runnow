package backend

import (
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Quản trò gọi từng vai dậy theo thứ tự chốt đêm: 22h Cupid (đêm 1), sói, bảo
// vệ, tiên tri, phù thuỷ (gọi lúc 0h); 10h cả làng. Vai không còn ai sống thì
// không gọi.
func TestStepMessagesGameMasterCalls(t *testing.T) {
	call := func(m gameMsg) (any, any) { return m.Data["call"], m.Data["wake"] }
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	if wake := startMessages(st)[0].Data["wake"]; !reflect.DeepEqual(wake, []string{"cupid"}) {
		t.Fatalf("mở ván gọi %v", wake)
	}

	night, evs := mustStep(t, st)
	if c, w := call(stepMessages(st, night, evs)[0]); c != callNight || !reflect.DeepEqual(w, []string{"cupid", "wolf", "guard", "seer", "witch"}) {
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
		t.Fatalf("20h mà quản trò gọi %v", c)
	}

	// Phù thuỷ bị treo ngày 1: group chỉ biết người đó phe Dân, nên đêm 2 quản
	// trò vẫn gọi phù thuỷ, cả lúc 22h lẫn 0h, kẻo lời gọi lộ vai. Tiên tri chết
	// đêm 1 đã lật bài nên không gọi nữa.
	hang := func(actor string) ww.Action {
		return ww.Action{Kind: ww.KindVote, Actor: actor, Choice: ww.ChoiceHang, ReceivedAt: trial.NightAt.Add(23 * time.Hour)}
	}
	night2, evs := mustStep(t, trial, hang("v1"), hang("v2"), hang("v3"))
	if night2.Players["witch"].Alive {
		t.Fatalf("phù thuỷ chưa bị treo: %+v", evs)
	}
	if c, w := call(stepMessages(trial, night2, evs)[0]); c != callNight || !reflect.DeepEqual(w, []string{"wolf", "guard", "witch"}) {
		t.Fatalf("22h đêm 2: %v %v", c, w)
	}
	dawn2, evs := mustStep(t, night2)
	if c, w := call(stepMessages(night2, dawn2, evs)[0]); c != callWitch || !reflect.DeepEqual(w, []string{"witch"}) {
		t.Fatalf("0h đêm 2 phải gọi phù thuỷ đã bị treo: %v %v", c, w)
	}
}

// Người bị treo chỉ lộ phe; chết cách khác vẫn lật lá bài, thợ săn bị treo
// được mở lượt bắn cũng lật vì còn việc phải làm. Event công khai là thứ vào
// feed, bản tin group và app, nên vai bị giấu không được nằm trong đó.
func TestPublicEventHangShowsTeamOnly(t *testing.T) {
	cases := []struct {
		in       ww.Event
		dead     ww.Player
		role     ww.Role
		team     ww.Team
		feedLine string
	}{
		{ww.Event{Kind: ww.EventDeath, UID: "s1", Role: ww.Seer, Cause: ww.CauseHang}, ww.Player{Role: ww.Seer, Cause: ww.CauseHang},
			"", ww.TeamVillage, "Chi đã chết, thuộc Phe Dân."},
		{ww.Event{Kind: ww.EventDeath, UID: "w2", Role: ww.Wolf, Cause: ww.CauseHang}, ww.Player{Role: ww.Wolf, Cause: ww.CauseHang},
			"", ww.TeamWolves, "Bình & Co đã chết, thuộc Phe Sói."},
		{ww.Event{Kind: ww.EventDeath, UID: "s1", Role: ww.Seer, Cause: ww.CauseBite}, ww.Player{Role: ww.Seer, Cause: ww.CauseBite},
			ww.Seer, "", "Chi đã chết. Lá bài: Tiên tri."},
		{ww.Event{Kind: ww.EventDeath, UID: "s1", Role: ww.Seer, Cause: ww.CauseLover}, ww.Player{Role: ww.Seer, Cause: ww.CauseLover},
			ww.Seer, "", "Chi đã chết. Lá bài: Tiên tri."},
		{ww.Event{Kind: ww.EventDeath, UID: "s1", Role: ww.Hunter, Cause: ww.CauseHang}, ww.Player{Role: ww.Hunter, Cause: ww.CauseHang, ShotOpened: true},
			ww.Hunter, "", "Chi đã chết. Lá bài: Thợ săn."},
		{ww.Event{Kind: ww.EventDeath, UID: "s1", Role: ww.Hunter, Cause: ww.CauseHang}, ww.Player{Role: ww.Hunter, Cause: ww.CauseHang},
			"", ww.TeamVillage, "Chi đã chết, thuộc Phe Dân."},
	}
	r := testRenderer()
	for _, c := range cases {
		dead := c.dead
		st := &ww.State{Phase: ww.PhaseNight, Players: map[string]*ww.Player{c.in.UID: &dead}}
		pubs := publicEvents(st, []ww.Event{c.in})
		if len(pubs) != 1 || pubs[0].Role != c.role || pubs[0].Team != c.team || pubs[0].Cause != "" {
			t.Fatalf("publicEvents(%+v, %+v) = %+v", c.dead, c.in, pubs)
		}
		pub := pubs[0]
		raw, err := json.Marshal([]ww.Event{pub})
		if err != nil {
			t.Fatal(err)
		}
		item, err := feedItem(map[string]any{"events": string(raw), "phaseKey": "r1/trial"}, r.byUID)
		if err != nil || len(item.Lines) != 1 || item.Lines[0] != c.feedLine {
			t.Fatalf("feed của %+v = %q, %v", c.in, item.Lines, err)
		}
	}
}

// Doc game công khai giữ vai người chết cho app và 3i đọc: người bị treo chỉ
// có phe, tới hết ván mới lật lá bài.
func TestPublicGameHangShowsTeamOnly(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	st.Phase = ww.PhaseNight
	st.Players["witch"].Alive, st.Players["witch"].Cause = false, ww.CauseHang
	st.Players["w1"].Alive, st.Players["w1"].Cause = false, ww.CauseHang
	st.Players["seer"].Alive, st.Players["seer"].Cause = false, ww.CauseBite
	st.Players["hunter"].Alive, st.Players["hunter"].Cause, st.Players["hunter"].ShotOpened = false, ww.CauseHang, true

	data := (&stepWrite{after: st}).publicGame()
	want := map[string][2]string{"witch": {"Phe Dân", ""}, "w1": {"Phe Sói", ""}, "seer": {"Tiên tri", "seer"}, "hunter": {"Thợ săn", "hunter"}, "v1": {"", ""}}
	for uid, w := range want {
		if label, role := revealedLabel(data, uid); label != w[0] || string(role) != w[1] {
			t.Fatalf("đang chơi, %s lộ %q %q, muốn %q", uid, label, role, w)
		}
	}

	st.Phase = ww.PhaseEnded
	data = (&stepWrite{after: st}).publicGame()
	if label, role := revealedLabel(data, "witch"); label != roleLabels[ww.Witch] || role != ww.Witch {
		t.Fatalf("hết ván, phù thuỷ bị treo lộ %q %q", label, role)
	}
}

func TestRenderGameMasterCalls(t *testing.T) {
	r := testRenderer()
	howTo := "Ai có vai thì bấm trong tin 3i nhắn riêng hoặc trong app RunNow."

	// 22h đêm 1 không có gì công khai: trước đây không gửi, giờ có lời quản trò.
	out := renderOne(t, r, chatGroup, tplDigest, map[string]any{
		"phaseKey": "r1/setup", "round": 1, "phase": "night", "deadline": "2026-10-15T17:00:00Z",
		"call": "night", "wake": []string{"cupid", "wolf", "guard", "seer", "witch"},
	})
	want := "<b>Đêm 1 buông xuống, cả làng đi ngủ.</b>\nQuản trò gọi lần lượt:\n" +
		"1. Cupid thức dậy, chọn hai người để ghép đôi, chốt lúc 0h đêm 1.\n" +
		"2. Sói thức dậy, cả phe chọn một người để cắn, chốt lúc 0h.\n" +
		"3. Bảo vệ thức dậy, chọn một người để che, tới 10h sáng.\n" +
		"4. Tiên tri thức dậy, chọn một người để soi, tới 10h sáng.\n" +
		"5. Phù thuỷ: 0h sói chốt xong thì quản trò gọi.\n" + howTo
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
		"<b>Đêm 2 buông xuống, cả làng đi ngủ.</b>\nQuản trò gọi lần lượt:\n1. Sói thức dậy, cả phe chọn một người để cắn, chốt lúc 0h.\n" + howTo
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
	if !strings.HasSuffix(out.parts[0], "\nCupid thức dậy, chọn hai người để ghép đôi, chốt lúc 0h đêm 1.\n"+howTo) {
		t.Fatalf("mở ván có Cupid = %q", out.parts[0])
	}
}
