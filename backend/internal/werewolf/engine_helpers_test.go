package werewolf

import (
	"errors"
	"sort"
	"testing"
	"time"
)

// baseRoles là bàn 13 người có vai cố định để tính tay. Không có Cupid, vì Cupid
// không ghép thì bot ghép ngẫu nhiên lúc 0h đêm 1 và kéo theo chết dây chuyền;
// test nào cần Cupid thì tự thêm.
func baseRoles() map[string]Role {
	return map[string]Role{
		"w1": Wolf, "w2": Wolf, "w3": Wolf,
		"seer": Seer, "guard": Guard, "witch": Witch, "hunter": Hunter,
		"v1": Villager, "v2": Villager, "v3": Villager, "v4": Villager, "v5": Villager, "v6": Villager,
	}
}

// testStart: Start lúc 9h ngày 15/10, nên đêm 1 là 22h cùng ngày.
var testStart = time.Date(2026, 10, 15, 9, 0, 0, 0, vietnam)

// tg giả lập một ván: giữ state, các action đang lưu của vòng hiện tại, và
// snapshot km sẽ chốt ở lần 22h kế tiếp.
type tg struct {
	t       *testing.T
	st      *State
	actions map[string]Action // key actor/kind; ghi đè như doc action
	km      map[string]float64
	seq     int
}

func newGame(t *testing.T, roles map[string]Role) *tg {
	t.Helper()
	g := &tg{t: t, st: NewState(Seed{7}, Config{}, roles, testStart), actions: map[string]Action{}, km: map[string]float64{}}
	for uid := range roles {
		g.km[uid] = 5000
	}
	return g
}

// game13 trả ván 13 người đã qua mốc 22h đêm 1, mọi người có 5 km.
func game13(t *testing.T) *tg {
	g := newGame(t, baseRoles())
	g.next()
	return g
}

func (g *tg) mine(actor string) []Action {
	var out []Action
	for _, a := range g.actions {
		if a.Actor == actor {
			out = append(out, a)
		}
	}
	return out
}

// now trả một giờ nằm trong cửa sổ đang mở: 30 phút trước hạn gần nhất, cộng dần
// từng giây để receivedAt giữ đúng thứ tự bấm.
func (g *tg) now() time.Time {
	g.seq++
	end := g.st.Deadline()
	if g.st.Hunter != nil {
		end = g.st.hunterClose()
	}
	return end.Add(-30*time.Minute + time.Duration(g.seq)*time.Second)
}

func (g *tg) try(a Action) error {
	a.ReceivedAt = g.now()
	if err := Validate(g.st, a, g.mine(a.Actor), a.ReceivedAt); err != nil {
		return err
	}
	key := a.Actor + "/" + string(a.Kind)
	if a.Clear {
		delete(g.actions, key)
	} else {
		g.actions[key] = a
	}
	return nil
}

// do ghi một hành động, fail nếu luật từ chối.
func (g *tg) do(kind Kind, actor string, targets ...string) {
	g.t.Helper()
	if err := g.try(Action{Kind: kind, Actor: actor, Targets: targets}); err != nil {
		g.t.Fatalf("%s %s %v bị từ chối: %v", actor, kind, targets, err)
	}
}

func (g *tg) vote(actor, choice string) {
	g.t.Helper()
	if err := g.try(Action{Kind: KindVote, Actor: actor, Choice: choice}); err != nil {
		g.t.Fatalf("%s vote %s bị từ chối: %v", actor, choice, err)
	}
}

// reject kiểm luật từ chối đúng mã.
func (g *tg) reject(want Reject, a Action) {
	g.t.Helper()
	if err := g.try(a); !errors.Is(err, want) {
		g.t.Fatalf("%+v: lỗi = %v, mong đợi %s", a, err, want)
	}
}

// next chạy một lần chốt. Sang vòng mới thì xoá action, như rounds/{n}/actions.
func (g *tg) next(left ...string) []Event {
	g.t.Helper()
	var acts []Action
	for _, a := range g.actions {
		acts = append(acts, a)
	}
	sort.Slice(acts, func(i, j int) bool { return acts[i].ReceivedAt.Before(acts[j].ReceivedAt) })
	round := g.st.Round
	st, evs, err := Step(g.st, Inputs{Actions: acts, Km: g.km, Left: left})
	if err != nil {
		g.t.Fatal(err)
	}
	g.st = st
	if st.Round != round {
		g.actions = map[string]Action{}
	}
	return evs
}

// toPhase chạy ít nhất một lần chốt, tiếp tục tới khi gặp phase p hoặc ván kết thúc.
func (g *tg) toPhase(p Phase) []Event {
	g.t.Helper()
	var evs []Event
	for i := 0; i == 0 || (g.st.Phase != p && g.st.Phase != PhaseEnded); i++ {
		if i > 10 {
			g.t.Fatalf("không tới được phase %s, đang ở %s", p, g.st.Phase)
		}
		evs = append(evs, g.next()...)
	}
	return evs
}

// hang đưa uid lên giàn và mọi người khác bấm Treo, rồi chốt 22h.
func (g *tg) hang(uid string) []Event {
	g.t.Helper()
	if g.st.Phase != PhaseDay {
		g.toPhase(PhaseDay)
	}
	for _, v := range g.st.aliveUIDs() {
		if v != uid {
			g.do(KindNominate, v, uid)
		}
	}
	g.next()
	for _, v := range g.st.aliveUIDs() {
		if v != uid && g.st.loverOf(v) != uid {
			g.vote(v, ChoiceHang)
		}
	}
	return g.next()
}

// setDead dựng thế cờ: đánh dấu chết thẳng vào state, không qua luật.
func (g *tg) setDead(uids ...string) {
	for _, uid := range uids {
		g.st.Players[uid].Alive = false
	}
}

func deaths(evs []Event) map[string]Cause {
	out := map[string]Cause{}
	for _, e := range evs {
		if e.Kind == EventDeath {
			out[e.UID] = e.Cause
		}
	}
	return out
}

func find(evs []Event, kind EventKind) *Event {
	for i := range evs {
		if evs[i].Kind == kind {
			return &evs[i]
		}
	}
	return nil
}

func voids(evs []Event) map[string]string {
	out := map[string]string{}
	for _, e := range evs {
		if e.Kind == EventVoid {
			out[e.UID+"/"+string(e.Action)] = e.Reason
		}
	}
	return out
}

func act(kind Kind, actor string, targets ...string) Action {
	return Action{Kind: kind, Actor: actor, Targets: targets}
}

func sameDeaths(t *testing.T, evs []Event, want map[string]Cause) {
	t.Helper()
	got := deaths(evs)
	if len(got) != len(want) {
		t.Fatalf("chết = %v, mong đợi %v", got, want)
	}
	for uid, c := range want {
		if got[uid] != c {
			t.Fatalf("chết = %v, mong đợi %v", got, want)
		}
	}
}
