package backend

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

func TestGameButtonRoundTrip(t *testing.T) {
	gameID := strings.Repeat("a", 20) // id tự sinh của Firestore dài 20 ký tự
	cases := []gameButton{
		{GameID: gameID, Op: opCard},
		{GameID: gameID, TurnKey: "r14", Kind: ww.KindCupidPair, Op: opConfirm, Idx: []int{15, 14}},
		{GameID: gameID, TurnKey: "r1", Kind: ww.KindWitchSave, Op: opPick},
		{GameID: gameID, TurnKey: "r3", Kind: ww.KindSeerPeek, Op: opReset},
	}
	for _, b := range cases {
		data, err := b.data()
		if err != nil {
			t.Fatal(err)
		}
		if len(data) > callbackLimit {
			t.Fatalf("%q dài %d byte", data, len(data))
		}
		got, ok := parseGameButton(data)
		if !ok {
			t.Fatalf("không đọc lại được %q", data)
		}
		g, _ := json.Marshal(got)
		w, _ := json.Marshal(b)
		if string(g) != string(w) {
			t.Fatalf("%q: đọc ra %s, muốn %s", data, g, w)
		}
	}
	if s, _ := cases[1].data(); s != "m1|"+gameID+"|r14|c|c|15.14" {
		t.Fatalf("data = %q", s)
	}
	// Ván có id dài bất thường thì báo lỗi lúc vẽ, không gửi nút Telegram từ chối.
	if _, err := (gameButton{GameID: strings.Repeat("a", 50), TurnKey: "r14", Kind: ww.KindCupidPair, Op: opPick, Idx: []int{1, 2}}).data(); err == nil {
		t.Fatal("callback_data quá 64 byte mà không lỗi")
	}
}

func TestParseGameButtonRejectsTampered(t *testing.T) {
	for _, s := range []string{
		"", "x", "m2|g|v", "m1||v", "m1|g|x", "m1|g|r1|z|t|1", "m1|g|r1|s|q|1",
		"m1|g|r1|s|t|-1", "m1|g|r1|s|t|a", "m1|g||s|t|1", "m1|g|r1|s|t", "m1|g|r1|s|t|1|2",
	} {
		if _, ok := parseGameButton(s); ok {
			t.Fatalf("%q được nhận", s)
		}
	}
}

// promptState: 4 người, xếp theo uid là a, b, c, d (vị trí 0..3 trong callback).
func promptState() *ww.State {
	return &ww.State{Round: 1, Phase: ww.PhaseNight, Players: map[string]*ww.Player{
		"a": {Role: ww.Seer, Alive: true}, "b": {Role: ww.Wolf, Alive: true},
		"c": {Role: ww.Cupid, Alive: true}, "d": {Role: ww.Villager, Alive: true},
	}}
}

func promptNames(uid string) string {
	return map[string]string{"a": "An", "b": "Bình <b>", "c": "Chi", "d": "Dũng"}[uid]
}

func keyboard(t *testing.T, m map[string]any) [][]string {
	t.Helper()
	var out [][]string
	for _, row := range m["inline_keyboard"].([][]map[string]any) {
		var r []string
		for _, b := range row {
			r = append(r, b["text"].(string)+"="+b["callback_data"].(string))
		}
		out = append(out, r)
	}
	return out
}

func options(uids ...string) []GameOption {
	var out []GameOption
	for _, uid := range uids {
		out = append(out, GameOption{ID: uid, Label: promptNames(uid)})
	}
	return out
}

func TestPromptViewSingleTarget(t *testing.T) {
	closes := time.Date(2026, 10, 12, 17, 0, 0, 0, time.UTC) // 0:00 ngày 13 giờ Việt Nam
	a := &GameAction{Kind: "wolf_bite", Enabled: true, ClosesAt: &closes, Options: options("a", "c", "d"),
		Selected: &GameSelected{Targets: []string{"c"}}}
	v := promptView{gameID: "g1", turnKey: "r1", st: promptState(), kind: ww.KindWolfBite, a: a, name: promptNames}
	text, markup, err := v.render()
	if err != nil {
		t.Fatal(err)
	}
	want := "<b>Tới lượt bạn: Cắn</b>\nChọn người phe Sói cắn đêm nay. Lựa chọn bấm sau cùng của phe được tính. Khoá lúc 0h.\n" +
		"Hạn: 00:00 13/10.\nĐang chọn: Chi.\nBấm nút bên dưới, hoặc chọn trong app RunNow."
	if text != want {
		t.Fatalf("text = %q", text)
	}
	kb := keyboard(t, markup)
	if len(kb) != 2 || kb[0][0] != "An=m1|g1|r1|b|t|0" || kb[0][1] != "✅ Chi=m1|g1|r1|b|t|2" || kb[1][0] != "Dũng=m1|g1|r1|b|t|3" {
		t.Fatalf("nút = %v", kb)
	}
}

func TestPromptViewConfirmAndLocked(t *testing.T) {
	st := promptState()
	a := &GameAction{Kind: "seer_peek", Enabled: true, Options: options("b", "c", "d")}
	v := promptView{gameID: "g1", turnKey: "r1", st: st, kind: ww.KindSeerPeek, a: a, pick: []string{"b"}, name: promptNames}
	text, markup, err := v.render()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(text, "\nBạn chọn Bình &lt;b&gt;. Chọn rồi không đổi được. Chắc chưa?\n") {
		t.Fatalf("text chờ chốt = %q", text)
	}
	if kb := keyboard(t, markup); len(kb) != 1 || kb[0][0] != "Chốt=m1|g1|r1|s|c|1" || kb[0][1] != "Chọn lại=m1|g1|r1|s|r|" {
		t.Fatalf("nút chờ chốt = %v", kb)
	}

	// Đã soi rồi thì không đổi được: hết nút, và không nhắc lại lý do khoá.
	a.Selected = &GameSelected{Targets: []string{"b"}}
	a.Enabled, a.DisabledReason = false, "Bạn đã dùng lượt này rồi."
	v.pick = nil
	text, markup, err = v.render()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasSuffix(text, "\nĐã chốt: Bình &lt;b&gt;.") || strings.Contains(text, "Chưa bấm được") || len(keyboard(t, markup)) != 0 {
		t.Fatalf("đã chốt = %q %v", text, markup)
	}
}

func TestPromptViewCupidTwoSteps(t *testing.T) {
	a := &GameAction{Kind: "cupid_pair", Enabled: true, Options: options("a", "b", "c", "d")}
	v := promptView{gameID: "g1", turnKey: "r1", st: promptState(), kind: ww.KindCupidPair, a: a, pick: []string{"d"}, name: promptNames}
	text, markup, err := v.render()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(text, "\nĐã chọn Dũng. Chọn thêm một người.\n") {
		t.Fatalf("text = %q", text)
	}
	kb := keyboard(t, markup)
	// Người đã chọn không hiện lại; nút mang cả người thứ nhất.
	if len(kb) != 3 || kb[0][0] != "An=m1|g1|r1|c|t|3.0" || kb[1][0] != "Chi=m1|g1|r1|c|t|3.2" || kb[2][0] != "Chọn lại=m1|g1|r1|c|r|" {
		t.Fatalf("nút = %v", kb)
	}
	v.pick = []string{"d", "a"}
	text, markup, err = v.render()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(text, "Bạn chọn Dũng và An.") || keyboard(t, markup)[0][0] != "Chốt=m1|g1|r1|c|c|3.0" {
		t.Fatalf("chờ chốt = %q %v", text, keyboard(t, markup))
	}
}

func TestPromptViewWitchSaveDisabledAndClosed(t *testing.T) {
	a := &GameAction{Kind: "witch_save", Enabled: false, DisabledReason: "Chưa đủ km."}
	v := promptView{gameID: "g1", turnKey: "r1", st: promptState(), kind: ww.KindWitchSave, a: a, name: promptNames}
	text, markup, err := v.render()
	if err != nil {
		t.Fatal(err)
	}
	// Vẫn có nút: bấm thì nhận toast lý do, và km có thể đủ sau khi admin sửa.
	if !strings.Contains(text, "\nChưa bấm được: Chưa đủ km.\n") || keyboard(t, markup)[0][0] != "Dùng bình cứu=m1|g1|r1|w|t|" {
		t.Fatalf("bình cứu = %q %v", text, markup)
	}
	a.Selected = &GameSelected{}
	text, markup, _ = v.render()
	if !strings.HasSuffix(text, "\nBạn đã dùng bình cứu.") || strings.Contains(text, "Chưa bấm được") || len(keyboard(t, markup)) != 0 {
		t.Fatalf("đã dùng = %q", text)
	}
	v.a = nil
	text, markup, _ = v.render()
	if !strings.HasSuffix(text, "\nLượt này đã đóng.") || len(keyboard(t, markup)) != 0 {
		t.Fatalf("đã đóng = %q", text)
	}
}

func TestTruncateUTF16(t *testing.T) {
	s := strings.Repeat("😀", 150) // 300 đơn vị UTF-16
	got := truncateUTF16(s, answerTextSize)
	if utf16Len(got) > answerTextSize || !strings.HasSuffix(got, "…") {
		t.Fatalf("dài %d", utf16Len(got))
	}
	if truncateUTF16("ngắn", answerTextSize) != "ngắn" {
		t.Fatal("cắt chữ ngắn")
	}
}
