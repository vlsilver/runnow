package backend

import (
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// tallyFixture: a..e xếp theo uid (vị trí 0..4 trong callback), e đã chết. Thứ tự
// đăng ký là d, a, b, c, e.
func tallyFixture(kind ww.Kind, phase ww.Phase, acts ...ww.Action) tallyView {
	st := &ww.State{Round: 2, Phase: phase, Nominee: "c", Players: map[string]*ww.Player{
		"a": {Alive: true}, "b": {Alive: true}, "c": {Alive: true}, "d": {Alive: true}, "e": {Alive: false},
	}}
	var players []gamePlayerInfo
	for _, uid := range []string{"d", "a", "b", "c", "e"} {
		players = append(players, gamePlayerInfo{uid: uid, name: map[string]string{"a": "An", "b": "Bình <b>", "c": "Chi", "d": "Dũng", "e": "Em"}[uid]})
	}
	return tallyView{gameID: "g1", turnKey: "r2", st: st, kind: kind, acts: acts, players: players, open: true,
		opens:  time.Date(2026, 10, 13, 13, 0, 0, 0, time.UTC), // 20:00 giờ Việt Nam
		closes: time.Date(2026, 10, 13, 15, 0, 0, 0, time.UTC)} // 22:00
}

func nominate(actor, target string) ww.Action {
	return ww.Action{Kind: ww.KindNominate, Actor: actor, Targets: []string{target}}
}

func vote(actor, choice string) ww.Action {
	return ww.Action{Kind: ww.KindVote, Actor: actor, Choice: choice}
}

// Đề cử: chỉ đếm người chọn còn sống và người được đề cử còn sống; nhiều đề cử
// đứng trước, cùng số thì theo thứ tự đăng ký; tên được escape.
func TestTallyViewNominate(t *testing.T) {
	v := tallyFixture(ww.KindNominate, ww.PhaseDay,
		nominate("b", "c"), nominate("a", "c"), nominate("d", "b"), nominate("e", "c"), nominate("c", "e"))
	text, markup, err := v.render()
	if err != nil {
		t.Fatal(err)
	}
	want := strings.Join([]string{
		"<b>Đề cử lên giàn, ngày 2</b>",
		"Hạn: 22:00 13/10.",
		"<b>Chi</b>: 2 (An, Bình &lt;b&gt;)",
		"<b>Bình &lt;b&gt;</b>: 1 (Dũng)",
		"Bấm tên để đề cử, bấm người khác để đổi. Chọn trong app RunNow cũng được.",
	}, "\n")
	if text != want {
		t.Fatalf("text =\n%s\nmong đợi\n%s", text, want)
	}
	wantKb := [][]string{{"Dũng=m1|g1|r2|n|t|3", "An=m1|g1|r2|n|t|0"}, {"Bình <b>=m1|g1|r2|n|t|1", "Chi=m1|g1|r2|n|t|2"}}
	if kb := keyboard(t, markup); !reflect.DeepEqual(kb, wantKb) {
		t.Fatalf("nút = %v", kb)
	}

	v = tallyFixture(ww.KindNominate, ww.PhaseDay)
	if text, _, _ := v.render(); !strings.Contains(text, "\nChưa ai được đề cử.\n") {
		t.Fatalf("chưa ai đề cử = %q", text)
	}
	v = tallyFixture(ww.KindNominate, ww.PhaseTrial, nominate("a", "c"))
	v.open = false
	text, markup, _ = v.render()
	if text != "<b>Đề cử lên giàn, ngày 2</b>\nĐã hết giờ.\n<b>Chi</b>: 1 (An)" || len(keyboard(t, markup)) != 0 {
		t.Fatalf("hết giờ = %q %v", text, markup)
	}
}

// Biểu quyết: người lên giàn và người chết không được đếm; chưa tới 20h thì
// báo giờ mở; luôn có cả hai dòng Treo và Tha.
func TestTallyViewVote(t *testing.T) {
	v := tallyFixture(ww.KindVote, ww.PhaseTrial,
		vote("a", ww.ChoiceHang), vote("b", ww.ChoiceSpare), vote("c", ww.ChoiceHang), vote("d", ww.ChoiceHang), vote("e", ww.ChoiceSpare))
	v.notYet = true
	text, markup, err := v.render()
	if err != nil {
		t.Fatal(err)
	}
	want := strings.Join([]string{
		"<b>Biểu quyết ngày 2: treo hay tha Chi</b>",
		"Mở lúc 20:00 13/10, hạn 22:00 13/10.",
		"<b>Treo</b>: 2 (Dũng, An)",
		"<b>Tha</b>: 1 (Bình &lt;b&gt;)",
		"Bấm Treo hoặc Tha, đổi được tới hạn. Chọn trong app RunNow cũng được.",
		"Số phiếu được tính chốt lúc 22h theo km của mỗi bên.",
	}, "\n")
	if text != want {
		t.Fatalf("text =\n%s\nmong đợi\n%s", text, want)
	}
	if kb := keyboard(t, markup); !reflect.DeepEqual(kb, [][]string{{"Treo=m1|g1|r2|x|t|0", "Tha=m1|g1|r2|x|t|1"}}) {
		t.Fatalf("nút = %v", kb)
	}
	v = tallyFixture(ww.KindVote, ww.PhaseTrial)
	if text, _, _ := v.render(); !strings.Contains(text, "\n<b>Treo</b>: 0\n<b>Tha</b>: 0\n") {
		t.Fatalf("chưa ai bỏ phiếu = %q", text)
	}
}

// Nút Treo/Tha đọc lại đúng thành vị trí trong voteChoices.
func TestGameButtonVoteRoundTrip(t *testing.T) {
	b, ok := parseGameButton("m1|g1|r2|x|t|1")
	if !ok || b.Kind != ww.KindVote || voteChoices[b.Idx[0]] != ww.ChoiceSpare {
		t.Fatalf("nút Tha = %+v %v", b, ok)
	}
	if b, ok := parseGameButton("m1|g1|r2|n|t|4"); !ok || b.Kind != ww.KindNominate {
		t.Fatalf("nút đề cử = %+v %v", b, ok)
	}
}
