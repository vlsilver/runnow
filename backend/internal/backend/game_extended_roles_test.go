package backend

import (
	"context"
	"reflect"
	"testing"

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
