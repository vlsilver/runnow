package backend

import (
	"reflect"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

func msgRoles() map[string]ww.Role {
	return map[string]ww.Role{
		"w1": ww.Wolf, "w2": ww.Wolf, "seer": ww.Seer, "guard": ww.Guard, "witch": ww.Witch, "hunter": ww.Hunter,
		"cupid": ww.Cupid, "v1": ww.Villager, "v2": ww.Villager, "v3": ww.Villager,
	}
}

var msgStart = time.Date(2026, 10, 15, 9, 0, 0, 0, vietnam)

func msgKm(st *ww.State) map[string]float64 {
	km := map[string]float64{}
	for uid := range st.Players {
		km[uid] = 5000
	}
	return km
}

func mustStep(t *testing.T, st *ww.State, acts ...ww.Action) (*ww.State, []ww.Event) {
	t.Helper()
	next, evs, err := ww.Step(st, ww.Inputs{Actions: acts, Km: msgKm(st)})
	if err != nil {
		t.Fatal(err)
	}
	return next, evs
}

func act1(kind ww.Kind, actor string, targets ...string) ww.Action {
	return ww.Action{Kind: kind, Actor: actor, Targets: targets, ReceivedAt: msgStart}
}

// summary rút tin về "chatKey/template[/kind]" để so cả bộ.
func summary(msgs []gameMsg) []string {
	var out []string
	for _, m := range msgs {
		s := m.ChatKey + "/" + m.Template
		if k, ok := m.Data["kind"]; ok {
			s += "/" + k.(string)
		}
		out = append(out, s)
	}
	return out
}

func sameMsgs(t *testing.T, msgs []gameMsg, want ...string) {
	t.Helper()
	if got := summary(msgs); !reflect.DeepEqual(got, want) {
		t.Fatalf("tin = %v\nmong đợi %v", got, want)
	}
}

func TestStartMessagesDealCardsAndPromptCupid(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	msgs := startMessages(st)
	sameMsgs(t, msgs, "group/start",
		"dm:cupid/card", "dm:guard/card", "dm:hunter/card", "dm:seer/card", "dm:v1/card", "dm:v2/card", "dm:v3/card",
		"dm:w1/card", "dm:w2/card", "dm:witch/card", "dm:cupid/prompt/cupid_pair")
	if got := msgs[0].Data["nightAt"]; got != "2026-10-15T15:00:00Z" {
		t.Fatalf("nightAt = %v", got)
	}
	if got := msgs[8].Data["wolves"]; !reflect.DeepEqual(got, []string{"w1", "w2"}) {
		t.Fatalf("sói thấy đồng đội = %v", got)
	}
	if _, ok := msgs[4].Data["wolves"]; ok {
		t.Fatal("dân thấy danh sách sói")
	}
}

// Một vòng đêm: mở đêm thì prompt các vai đêm; 0h thì sói biết người bị cắn,
// phù thuỷ được prompt; 10h thì người chết lật bài, lý do chết không lộ.
func TestStepMessagesThroughANight(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	pair := act1(ww.KindCupidPair, "cupid", "w1", "v1") // action của vòng 1 còn đó tới 0h
	night, evs := mustStep(t, st, pair)
	// Ai không có lượt mới cũng nhận DM, để lúc vào đêm máy ai cũng báo tin như nhau.
	sameMsgs(t, stepMessages(st, night, evs), "group/digest",
		"dm:guard/prompt/guard", "dm:seer/prompt/seer_peek", "dm:w1/prompt/wolf_bite", "dm:w2/prompt/wolf_bite",
		"dm:cupid/night", "dm:hunter/night", "dm:v1/night", "dm:v2/night", "dm:v3/night", "dm:witch/night")

	dawn, evs := mustStep(t, night, pair, act1(ww.KindWolfBite, "w2", "v2"))
	msgs := stepMessages(night, dawn, evs)
	sameMsgs(t, msgs, "group/digest", "dm:v1/private", "dm:w1/private", "dm:w2/private",
		"dm:witch/prompt/witch_save", "dm:witch/prompt/witch_poison")
	lovers := msgs[1].Data["events"].([]ww.Event)[0]
	if lovers.Kind != ww.EventLovers || lovers.UID != "w1" || lovers.Role != ww.Wolf {
		t.Fatalf("v1 nhận = %+v, mong đợi biết người yêu w1 là sói", lovers)
	}
	if evs := msgs[3].Data["events"].([]ww.Event); len(evs) != 1 || evs[0].Kind != ww.EventWolvesTarget || evs[0].UID != "v2" {
		t.Fatalf("w2 nhận = %+v", evs)
	}
	if len(msgs[0].Data["events"].([]ww.Event)) != 0 {
		t.Fatalf("bản tin 0h lộ việc của đêm: %+v", msgs[0].Data["events"])
	}

	day, evs := mustStep(t, dawn)
	msgs = stepMessages(dawn, day, evs)
	sameMsgs(t, msgs, "group/digest", "dm:v2/private", "group/prompt/nominate")
	pub := msgs[0].Data["events"].([]ww.Event)
	if len(pub) != 1 || !reflect.DeepEqual(pub[0], ww.Event{Kind: ww.EventDeath, UID: "v2", Role: ww.Villager}) {
		t.Fatalf("bản tin 10h = %+v", pub)
	}
	if got := msgs[0].Data["deadline"]; got != "2026-10-16T10:00:00Z" {
		t.Fatalf("hạn đề cử = %v", got)
	}
	if got := msgs[2].Data; !reflect.DeepEqual(got, map[string]any{"kind": "nominate", "turnKey": "r1"}) {
		t.Fatalf("prompt đề cử = %v", got)
	}

	// 17h có người lên giàn thì topic có prompt biểu quyết; không ai được đề cử
	// thì không.
	trial, evs := mustStep(t, day, act1(ww.KindNominate, "v1", "w1"))
	sameMsgs(t, stepMessages(day, trial, evs), "group/digest", "group/prompt/vote")

	// Sang đêm 2: v2 đã chết nên không nhận gì; cupid đã ghép, chỉ còn tin đêm.
	night2, evs := mustStep(t, trial)
	if night2.Phase != ww.PhaseNight || night2.Round != 2 {
		t.Fatalf("chưa sang đêm 2: %s", night2.PhaseKey())
	}
	sameMsgs(t, stepMessages(trial, night2, evs), "group/digest",
		"dm:guard/prompt/guard", "dm:seer/prompt/seer_peek", "dm:w1/prompt/wolf_bite", "dm:w2/prompt/wolf_bite",
		"dm:cupid/night", "dm:hunter/night", "dm:v1/night", "dm:v3/night", "dm:witch/night")

	empty, evs := mustStep(t, day)
	sameMsgs(t, stepMessages(day, empty, evs), "group/digest")
}

func TestStepMessagesHunterTurnPromptsTheHunter(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	night, _ := mustStep(t, st)
	dawn, _ := mustStep(t, night, act1(ww.KindWolfBite, "w1", "hunter"))
	day, evs := mustStep(t, dawn)
	msgs := stepMessages(dawn, day, evs)
	sameMsgs(t, msgs, "group/digest", "dm:hunter/private", "dm:hunter/prompt/hunter_shoot", "group/prompt/nominate")

	// Thợ săn bắn xong thì đề cử vẫn đang mở: giữ prompt cũ, không đăng lại.
	after, evs := mustStep(t, day, act1(ww.KindHunterShoot, "hunter", "v3"))
	if after.Hunter != nil || after.Phase != ww.PhaseDay {
		t.Fatalf("chưa chốt lượt thợ săn: %s", after.PhaseKey())
	}
	sameMsgs(t, stepMessages(day, after, evs), "group/digest", "dm:v3/private")
}

func TestStepMessagesReminderOnly(t *testing.T) {
	st := ww.NewState(ww.Seed{1}, ww.Config{}, msgRoles(), msgStart)
	msgs := stepMessages(st, st, []ww.Event{{Kind: ww.EventReminder, Reason: ww.ReminderVote}})
	sameMsgs(t, msgs, "group/reminder")
	if msgs[0].Data["reason"] != ww.ReminderVote {
		t.Fatalf("reason = %v", msgs[0].Data["reason"])
	}
}

// Hết ván thì bản tin lật hết vai, không còn hạn.
func TestStepMessagesEndRevealsAllRoles(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "v1": ww.Villager, "v2": ww.Villager, "v3": ww.Villager}
	st := ww.NewState(ww.Seed{1}, ww.Config{}, roles, msgStart)
	night, _ := mustStep(t, st)
	dawn, _ := mustStep(t, night, act1(ww.KindWolfBite, "w1", "v1"))
	day, evs := mustStep(t, dawn) // v1 chết: còn 1 sói, 2 dân
	trial, _ := mustStep(t, day, act1(ww.KindNominate, "v2", "v3"), act1(ww.KindNominate, "w1", "v3"))
	hang := func(actor string) ww.Action {
		return ww.Action{Kind: ww.KindVote, Actor: actor, Choice: ww.ChoiceHang, ReceivedAt: trial.NightAt.Add(23 * time.Hour)}
	}
	end, evs := mustStep(t, trial, hang("v2"), hang("w1"))
	if end.Phase != ww.PhaseEnded {
		t.Fatalf("chưa kết thúc: %s, %+v", end.PhaseKey(), evs)
	}
	msgs := stepMessages(trial, end, evs)
	if _, ok := msgs[0].Data["deadline"]; ok {
		t.Fatal("ván đã hết mà còn hạn")
	}
	want := map[string]string{"w1": "wolf", "v1": "villager", "v2": "villager", "v3": "villager"}
	if got := msgs[0].Data["roles"]; !reflect.DeepEqual(got, want) {
		t.Fatalf("roles = %v", got)
	}
	_ = day
}

// Đề cử và biểu quyết là công khai nên vào tin đếm trong topic; lựa chọn riêng
// sửa tin DM của người chọn; lựa chọn cắn có thêm tin cho group Phe Sói.
func TestActionMessagesChats(t *testing.T) {
	for _, c := range []struct {
		a    ww.Action
		want []gameMsg
	}{
		{ww.Action{Kind: ww.KindVote, Actor: "v1", Choice: ww.ChoiceHang}, []gameMsg{{ChatKey: chatGroup, Template: tplTally, Data: map[string]any{"kind": "vote"}}}},
		{ww.Action{Kind: ww.KindNominate, Actor: "v1", Targets: []string{"w1"}}, []gameMsg{{ChatKey: chatGroup, Template: tplTally, Data: map[string]any{"kind": "nominate"}}}},
		{ww.Action{Kind: ww.KindSeerPeek, Actor: "seer", Targets: []string{"w1"}}, []gameMsg{{ChatKey: "dm:seer", Template: tplChoice, Data: map[string]any{"kind": "seer_peek"}}}},
	} {
		if got := actionMessages(c.a); !reflect.DeepEqual(got, c.want) {
			t.Fatalf("%s = %+v", c.a.Kind, got)
		}
	}
}
