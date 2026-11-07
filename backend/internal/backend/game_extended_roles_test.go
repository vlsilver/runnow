package backend

import (
	"context"
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Già làng thoát cú cắn: chỉ Già làng nhận tin riêng, group không thấy gì, và
// app ghi lại vòng đó trong ghi chú của Già làng.
func TestElderSurvivalIsPrivate(t *testing.T) {
	roles := msgRoles()
	roles["v1"] = ww.Elder
	st := ww.NewState(ww.Seed{1}, ww.Config{Extended: []ww.Role{ww.Elder}}, roles, msgStart)
	st.Phase, st.Round = ww.PhaseDay, 3
	st.Players["v1"].SurvivedRound = 1
	evs := []ww.Event{{Kind: ww.EventSurvived, UID: "v1"}}
	if pub := publicEvents(st, evs); len(pub) != 0 {
		t.Fatalf("group thấy %+v", pub)
	}
	var dm []gameMsg
	for _, m := range stepMessages(st, st, evs) {
		if m.Template == tplPrivate {
			dm = append(dm, m)
		}
	}
	if len(dm) != 1 || dm[0].ChatKey != dmChat("v1") {
		t.Fatalf("tin riêng = %+v", dm)
	}
	want := "Đêm qua sói cắn bạn nhưng Già làng chịu được một lần nên bạn vẫn sống. Cú cắn sau sẽ chết."
	if got := testRenderer().privateText(evs, ""); got != dmText(want) {
		t.Fatalf("tin riêng = %q", got)
	}
	notes, err := (&GameStore{}).notes(context.Background(), nil, st, "v1", func(uid string) string { return uid })
	if err != nil {
		t.Fatal(err)
	}
	if len(notes) != 1 || notes[0] != (GameNote{Round: 1, Text: "Bạn đã thoát một cú cắn của sói. Cú cắn sau sẽ chết."}) {
		t.Fatalf("ghi chú = %+v", notes)
	}
}

// Kẻ ngốc lật bài thì cả làng biết: feed và digest có dòng riêng, doc công khai
// hiện lá bài dù còn sống. Treo lần hai thì vẫn hiện lá bài, không lùi về phe.
func TestIdiotRevealIsPublic(t *testing.T) {
	roles := msgRoles()
	roles["v1"] = ww.Idiot
	st := ww.NewState(ww.Seed{1}, ww.Config{Extended: []ww.Role{ww.Idiot}}, roles, msgStart)
	st.Phase = ww.PhaseNight
	st.Players["v1"].Revealed = true
	ev := ww.Event{Kind: ww.EventRevealed, UID: "v1", Role: ww.Idiot}
	if pub := publicEvents(st, []ww.Event{ev}); len(pub) != 1 || !reflect.DeepEqual(pub[0], ev) {
		t.Fatalf("group thấy %+v", pub)
	}
	names := map[string]gamePlayerInfo{"v1": {name: "An"}}
	item, err := feedItem(feedDoc(t, "r2/trial", ww.Event{Kind: ww.EventVoteResult, UID: "v1", Hang: 4, Spare: 2, Hanged: true}, ev), names)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"Treo 4, Tha 2: An bị treo.", "An lật bài Kẻ ngốc nên không chết, từ giờ mất quyền bỏ phiếu."}
	if strings.Join(item.Lines, "|") != strings.Join(want, "|") {
		t.Fatalf("feed = %q", item.Lines)
	}
	if label, role := revealedLabel((&stepWrite{after: st}).publicGame(), "v1"); label != "Kẻ ngốc" || role != ww.Idiot {
		t.Fatalf("còn sống, đã lật: lộ %q %q", label, role)
	}

	st.Players["v1"].Alive, st.Players["v1"].Cause = false, ww.CauseHang
	death := ww.Event{Kind: ww.EventDeath, UID: "v1", Role: ww.Idiot, Cause: ww.CauseHang}
	if pub := publicEvents(st, []ww.Event{death}); len(pub) != 1 || pub[0].Role != ww.Idiot {
		t.Fatalf("treo lần hai, group thấy %+v", pub)
	}
	if label, role := revealedLabel((&stepWrite{after: st}).publicGame(), "v1"); label != "Kẻ ngốc" || role != ww.Idiot {
		t.Fatalf("treo lần hai: lộ %q %q", label, role)
	}
}

// Dự báo phiếu lúc 21h không tính Kẻ ngốc đã lật: còn tính thì 3 người chỉ có
// 5,1 km, được 2 phiếu và Kẻ ngốc 0 km mất phiếu.
func TestVoteForecastSkipsRevealedIdiot(t *testing.T) {
	r := testRenderer() // ngưỡng 2,5 km một phiếu
	st := ww.NewState(ww.Seed{1}, r.cfg, map[string]ww.Role{"w1": ww.Wolf, "w2": ww.Villager, "s1": ww.Seer, "f1": ww.Idiot}, msgStart)
	st.Phase, st.Nominee = ww.PhaseTrial, "w2"
	st.Players["f1"].Revealed = true
	live := map[string]float64{"w1": 2500, "s1": 2600, "w2": 9000}
	r.st, r.now = st, func() time.Time { return time.Date(2026, 10, 24, 21, 0, 0, 0, vietnam) }
	r.store = &GameStore{frameKm: func(_ context.Context, uid string, _ time.Time) (FrameKm, error) {
		return FrameKm{Meters: live[uid]}, nil
	}}
	out, err := r.renderReminder(context.Background(), chatGroup, `{"reason":"vote"}`)
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.Join(out.parts, "\n"), "\n")
	if got := lines[len(lines)-2]; got != "Biểu quyết nếu chốt bây giờ: 2 người bỏ phiếu có tổng 5.1 km, đủ cho cả 2 phiếu." {
		t.Fatalf("dự báo = %q", got)
	}
}

// Kẻ ngốc đã lật bấm phiếu (nút group, app cũ) thì được nói rõ lý do, phiếu
// lọt vào lúc chốt thì tin riêng nói vì sao bị huỷ.
func TestRevealedIdiotVoteTexts(t *testing.T) {
	if got := rejectText(ww.KindVote2, ww.ErrNoVote); got != "Kẻ ngốc đã lật bài nên không được bỏ phiếu nữa." {
		t.Fatalf("từ chối = %q", got)
	}
	evs := []ww.Event{{Kind: ww.EventVoid, UID: "f1", Action: ww.KindVote, Reason: ww.VoidNoVote}}
	if got := testRenderer().privateText(evs, ""); got != dmText("Lựa chọn Biểu quyết của bạn không được tính: Kẻ ngốc đã lật bài nên mất phiếu.") {
		t.Fatalf("tin riêng = %q", got)
	}
}

// Vai mở rộng nào cũng phải có tên, luật và điểm cân bằng, và bật được trên màn
// tạo ván. Không bật thì ván không có vai đó.
func TestExtendedRolesDescribedAndToggled(t *testing.T) {
	for _, r := range ww.ExtendedRoles() {
		// Admin ép được vai này cho người chơi ván thử.
		if !ww.ValidRole(r) {
			t.Fatalf("vai %q không ép được", r)
		}
		if roleLabels[r] == "" || roleRules[r] == "" || roleWeight[r] == 0 {
			t.Fatalf("vai %q thiếu tên %q, luật %q hoặc điểm %d", r, roleLabels[r], roleRules[r], roleWeight[r])
		}
		var gc ww.Config
		if err := applyGameSettings(&gc, map[string]any{string(r): true}); err != nil {
			t.Fatal(err)
		}
		if !reflect.DeepEqual(gc.Extended, []ww.Role{r}) {
			t.Fatalf("bật %q → %v", r, gc.Extended)
		}
	}
	var gc ww.Config
	if err := applyGameSettings(&gc, nil); err != nil || gc.Extended != nil {
		t.Fatalf("không bật gì → %v, %v", gc.Extended, err)
	}
}
