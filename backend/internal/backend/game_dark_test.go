package backend

import (
	"slices"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Thẻ Đặc quyền của sói: các đặc quyền ván bật theo thứ tự cố định, Tàng Hình
// chỉ chọn sói, Vu Khống chỉ chọn người không phải sói, Cắn Im Lặng không chọn
// người. Phe Dân không có thẻ này.
func TestMeActionsDarkCard(t *testing.T) {
	cfg := ww.Config{KmOff: true, Dark: []ww.DarkPower{ww.DarkSilent, ww.DarkFrame, ww.DarkCloak}}
	st := ww.NewState(ww.Seed{1}, cfg, msgRoles(), msgStart)
	st.Phase = ww.PhaseNight
	players := []gamePlayerInfo{{uid: "w1", name: "Sói 1"}, {uid: "w2", name: "Sói 2"}, {uid: "seer", name: "Chi"}, {uid: "v1", name: "An"}}
	now := st.NightAt.Add(10 * time.Minute)

	var card *GameAction
	for _, a := range meActions(st, "w1", nil, nil, players, now, 0) {
		if a.Kind == string(ww.KindWolfDark) {
			card = &a
		}
	}
	if card == nil || card.Input != "dark" || !card.Enabled {
		t.Fatalf("thẻ đặc quyền = %+v", card)
	}
	want := []struct {
		id      string
		targets []string
	}{{"cloak", []string{"w1", "w2"}}, {"frame", []string{"seer", "v1"}}, {"silent", nil}}
	if len(card.Options) != len(want) {
		t.Fatalf("options = %+v", card.Options)
	}
	for i, w := range want {
		o := card.Options[i]
		var ids []string
		for _, p := range o.Targets {
			ids = append(ids, p.ID)
		}
		if o.ID != w.id || o.NeedsTarget != (w.targets != nil) || o.Disabled || o.Label == "" || !slices.Equal(ids, w.targets) {
			t.Fatalf("option %d = %+v, mong đợi %s chọn được %v", i, o, w.id, w.targets)
		}
	}

	for _, a := range meActions(st, "seer", nil, nil, players, now, 0) {
		if a.Kind == string(ww.KindWolfDark) {
			t.Fatal("Tiên tri có thẻ đặc quyền Sói")
		}
	}
}

// Đặc quyền chỉ chọn trong app: vào đêm sói nhận tin DM Cắn, không nhận tin
// Đặc quyền (nút Telegram không gói được danh sách đặc quyền rồi tới người).
func TestPromptMessagesSkipDark(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{KmOff: true, Dark: ww.DarkPowers()}, msgRoles(), msgStart)
	st.Phase = ww.PhaseNight
	kinds := map[string]bool{}
	for _, m := range promptMessages(nil, st) {
		if m.ChatKey == dmChat("w1") {
			kinds[m.Data["kind"].(string)] = true
		}
	}
	if !kinds[string(ww.KindWolfBite)] || kinds[string(ww.KindWolfDark)] {
		t.Fatalf("tin DM của w1 = %v", kinds)
	}
}
