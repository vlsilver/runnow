package werewolf

import (
	"fmt"
	"math/rand/v2"
	"reflect"
	"sort"
	"testing"
	"time"
)

// TestFuzzRandomGames chơi 5.000 ván ngẫu nhiên: số người, vai bị tắt, km, ai
// bấm gì lúc nào, ai rời PSC, pause/resume. Sau mỗi bước kiểm bất biến. Ván lỗi
// in seed; chạy lại một ván: go test -run 'TestFuzzRandomGames/seed=123$'.
func TestFuzzRandomGames(t *testing.T) {
	n := 5000
	if testing.Short() {
		n = 300
	}
	for seed := uint64(1); seed <= uint64(n); seed++ {
		seed := seed
		t.Run(fmt.Sprintf("seed=%d", seed), func(t *testing.T) {
			first := playRandomGame(t, seed)
			// Replay: cùng seed, cùng đầu vào thì ra cùng chuỗi event (mục 3.9).
			if again := playRandomGame(t, seed); !reflect.DeepEqual(first, again) {
				t.Fatalf("seed %d: chạy lại ra event khác", seed)
			}
		})
	}
}

// fuzzMaxSteps khoảng 100 vòng, gấp nhiều lần một ván thật.
const fuzzMaxSteps = 400

var fuzzKm = []float64{0, 0, 500, 999, 1000, 1000, 2500, 5000, 12000}

func playRandomGame(t *testing.T, seed uint64) []Event {
	t.Helper()
	rng := rand.New(rand.NewPCG(seed, seed^0x9e3779b97f4a7c15))
	players := make([]string, MinPlayers+rng.IntN(MaxPlayers-MinPlayers+1))
	for i := range players {
		players[i] = fmt.Sprintf("p%02d", i)
	}
	var cfg Config
	for _, r := range specialRoles {
		if rng.IntN(5) == 0 {
			cfg.Disabled = append(cfg.Disabled, r)
		}
	}
	var gameSeed Seed
	for i := range gameSeed {
		gameSeed[i] = byte(rng.UintN(256))
	}
	roles, err := Deal(gameSeed, players, cfg)
	if err != nil {
		t.Fatal(err)
	}
	start := time.Date(2026, 10, 15, 6+rng.IntN(16), rng.IntN(60), 0, 0, vietnam)
	st := NewState(gameSeed, cfg, roles, start)
	actions := map[string]Action{}
	var all []Event
	dead := map[string]bool{}
	saveUsed, poisonUsed, winners, poisoned := 0, 0, 0, 0

	// Ván không giới hạn số vòng (R13), nên ván ngẫu nhiên có thể chạy mãi khi
	// không ai đủ km. Dừng ở fuzzMaxSteps bước và vẫn kiểm bất biến tới đó.
	for steps := 0; st.Phase != PhaseEnded && steps < fuzzMaxSteps; steps++ {
		now := st.NextAt()
		// Người chơi bấm ngẫu nhiên trong cửa sổ, trước giờ chốt kế tiếp.
		for i := 0; i < 2*len(players); i++ {
			a := randomAction(rng, st, players)
			a.ReceivedAt = now.Add(-time.Duration(1+rng.IntN(3600)) * time.Second)
			var mine []Action
			for _, m := range actions {
				if m.Actor == a.Actor {
					mine = append(mine, m)
				}
			}
			if Validate(st, a, mine, a.ReceivedAt) != nil {
				continue
			}
			if p := st.Players[a.Actor]; !p.Alive && a.Kind != KindHunterShoot {
				t.Fatalf("seed %d: người chết %s được nhận %s", seed, a.Actor, a.Kind)
			}
			key := a.Actor + "/" + string(a.Kind)
			if a.Clear {
				delete(actions, key)
			} else {
				actions[key] = a
			}
		}
		if rng.IntN(60) == 0 {
			paused, err := Pause(st)
			if err != nil {
				t.Fatal(err)
			}
			if _, _, err := Advance(paused, Inputs{}, now.Add(time.Hour)); err != ErrNotRunning {
				t.Fatalf("seed %d: Advance lúc pause: %v", seed, err)
			}
			resumeAt := now.Add(time.Duration(rng.IntN(48)) * time.Hour)
			if st, err = Resume(paused, resumeAt); err != nil {
				t.Fatal(err)
			}
			// R14: không bù bước đã lỡ, nên hạn mới phải ở sau lúc resume.
			if !st.Deadline().After(resumeAt) {
				t.Fatalf("seed %d: resume lúc %s mà hạn %s đã qua", seed, resumeAt, st.Deadline())
			}
			continue
		}

		in := Inputs{Km: map[string]float64{}}
		keys := make([]string, 0, len(actions))
		for k := range actions {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			in.Actions = append(in.Actions, actions[k])
		}
		for _, uid := range players {
			in.Km[uid] = fuzzKm[rng.IntN(len(fuzzKm))]
		}
		if rng.IntN(40) == 0 {
			in.Left = []string{players[rng.IntN(len(players))]}
		}

		before := st.clone()
		hunterBefore, nomineeBefore := st.Hunter, st.Nominee
		next, evs, err := Advance(st, in, now.Add(30*time.Second))
		if err != nil {
			t.Fatalf("seed %d %s: %v", seed, st.PhaseKey(), err)
		}
		if !reflect.DeepEqual(before, st) {
			t.Fatalf("seed %d: Advance sửa state đầu vào", seed)
		}
		checkStep(t, seed, before, next, evs, hunterBefore, nomineeBefore, dead, in)
		if before.SavePotion && !next.SavePotion {
			saveUsed++
		}
		if before.PoisonPotion && !next.PoisonPotion {
			poisonUsed++
		}
		if !before.SavePotion && next.SavePotion || !before.PoisonPotion && next.PoisonPotion {
			t.Fatalf("seed %d: bình phù thuỷ được trả lại", seed)
		}
		for _, e := range evs {
			switch {
			case e.Kind == EventWinner:
				winners++
			case e.Kind == EventDeath && e.Cause == CausePoison:
				poisoned++
			}
		}
		if next.Round != st.Round {
			actions = map[string]Action{}
		}
		all = append(all, evs...)
		st = next
	}
	if saveUsed > 1 || poisonUsed > 1 || poisoned > 1 {
		t.Fatalf("seed %d: dùng bình cứu %d lần, bình độc %d lần", seed, saveUsed, poisonUsed)
	}
	if ended := st.Phase == PhaseEnded; ended != (winners == 1) || ended != (st.Winner != "") || winners > 1 {
		t.Fatalf("seed %d: phase %s, %d event thắng, winner %q", seed, st.Phase, winners, st.Winner)
	}
	return all
}

// checkStep kiểm bất biến của một bước.
func checkStep(t *testing.T, seed uint64, before, after *State, evs []Event, hunterBefore *HunterTurn, nomineeBefore string, dead map[string]bool, in Inputs) {
	t.Helper()
	aliveBefore := func(role Role) bool {
		for _, p := range before.Players {
			if p.Alive && p.Role == role {
				return true
			}
		}
		return false
	}
	for _, e := range evs {
		if e.Kind != EventDeath {
			continue
		}
		if dead[e.UID] {
			t.Fatalf("seed %d: %s chết hai lần", seed, e.UID)
		}
		dead[e.UID] = true
		if p := after.Players[e.UID]; p.Alive || p.Role != e.Role {
			t.Fatalf("seed %d: event chết của %s không khớp state", seed, e.UID)
		}
		// Người đã chết không gây ra cái chết nào: mỗi nguyên nhân cần người gây
		// ra còn sống (hoặc thợ săn đang có lượt) lúc bước bắt đầu.
		var ok bool
		switch e.Cause {
		case CauseBite:
			ok = before.Bitten == e.UID && before.Phase == PhaseDawn
		case CausePoison:
			ok = aliveBefore(Witch) && before.Phase == PhaseDawn
		case CauseShot:
			ok = hunterBefore != nil
		case CauseHang:
			ok = nomineeBefore == e.UID && before.Phase == PhaseTrial
		case CauseLover:
			ok = before.loverOf(e.UID) != ""
		case CauseLeft:
			ok = contains(in.Left, e.UID)
		}
		if !ok {
			t.Fatalf("seed %d %s: %s chết vì %s không có người gây ra hợp lệ", seed, before.PhaseKey(), e.UID, e.Cause)
		}
	}
	for uid, p := range after.Players {
		if !p.Alive && !dead[uid] {
			t.Fatalf("seed %d: %s chết mà không có event", seed, uid)
		}
		if p.Alive && dead[uid] {
			t.Fatalf("seed %d: %s sống lại", seed, uid)
		}
	}
	// Phiếu được tính không vượt số người được bỏ phiếu còn sống, trừ người bị cắt.
	if e := find(evs, EventVoteResult); e != nil {
		voters := len(before.aliveUIDs()) - 1
		if cut := find(evs, EventVoteCut); cut != nil {
			voters -= len(cut.Targets)
		}
		if e.Hang+e.Spare > voters {
			t.Fatalf("seed %d: %d phiếu với %d người", seed, e.Hang+e.Spare, voters)
		}
	}
	// Người chết không có hành động được tính: bước nào dùng tới action của người
	// đã chết từ trước (hoặc vừa bị xử vì rời PSC ở đầu bước) thì phải huỷ nó.
	voided := voids(evs)
	for _, a := range in.Actions {
		if a.Clear || !consumes(before, a.Kind) || isReminder(evs) {
			continue
		}
		gone := !before.alive(a.Actor) || (contains(in.Left, a.Actor) && (before.Phase == PhaseDawn || before.Phase == PhaseTrial))
		if gone && voided[a.Actor+"/"+string(a.Kind)] != VoidActorDead && !(a.Kind == KindVote && voided[a.Actor+"/"+string(a.Kind)] != "") {
			t.Fatalf("seed %d %s: %s của %s đã chết mà không bị huỷ", seed, before.PhaseKey(), a.Kind, a.Actor)
		}
	}
	if after.Phase == PhaseEnded && after.Winner == "" {
		t.Fatalf("seed %d: kết thúc không có phe thắng", seed)
	}
}

func contains(xs []string, x string) bool {
	for _, v := range xs {
		if v == x {
			return true
		}
	}
	return false
}

func fittingKind(rng *rand.Rand, st *State, r Role) (Kind, bool) {
	switch st.Phase {
	case PhaseSetup:
		if r == Cupid {
			return KindCupidPair, true
		}
	case PhaseNight:
		switch r {
		case Wolf:
			return KindWolfBite, true
		case Seer:
			return KindSeerPeek, true
		case Guard:
			return KindGuard, true
		case Cupid:
			return KindCupidPair, true
		}
	case PhaseDawn:
		switch r {
		case Witch:
			return []Kind{KindWitchSave, KindWitchPoison}[rng.IntN(2)], true
		case Seer:
			return KindSeerPeek, true
		case Guard:
			return KindGuard, true
		}
	case PhaseDay:
		return KindNominate, true
	case PhaseTrial:
		return KindVote, true
	}
	return "", false
}

var fuzzKinds = []Kind{KindWolfBite, KindSeerPeek, KindGuard, KindWitchSave, KindWitchPoison, KindHunterShoot, KindCupidPair, KindNominate, KindVote}

// randomAction sinh một hành động bất kỳ, kể cả không hợp lệ (người chết, sai
// vai, sai target), để Validate là chỗ duy nhất lọc.
func randomAction(rng *rand.Rand, st *State, players []string) Action {
	a := Action{Kind: fuzzKinds[rng.IntN(len(fuzzKinds))], Actor: players[rng.IntN(len(players))]}
	// Phần lớn lần bấm là hành động đúng vai đúng phase, để ván đi được xa và phủ
	// các nhánh hiếm (thợ săn bắn, cặp đôi thắng); phần còn lại để ngẫu nhiên.
	if rng.IntN(4) != 0 {
		if h := st.Hunter; h != nil && rng.IntN(2) == 0 {
			a.Actor, a.Kind = h.UID, KindHunterShoot
		} else if k, ok := fittingKind(rng, st, st.role(a.Actor)); ok {
			a.Kind = k
		}
	}
	if rng.IntN(10) == 0 {
		a.Clear = true
		return a
	}
	n := 1
	switch a.Kind {
	case KindWitchSave, KindVote:
		n = 0
	case KindCupidPair:
		n = 2
	}
	for i := 0; i < n; i++ {
		a.Targets = append(a.Targets, players[rng.IntN(len(players))])
	}
	if a.Kind == KindVote {
		a.Choice = []string{ChoiceHang, ChoiceSpare, "x"}[rng.IntN(3)]
	}
	return a
}

// consumes: lần chốt kế tiếp của st có đọc action loại kind không.
func consumes(st *State, kind Kind) bool {
	if st.Hunter != nil {
		return false
	}
	switch st.Phase {
	case PhaseNight:
		return kind == KindWolfBite || (kind == KindCupidPair && st.Round == 1)
	case PhaseDawn:
		return kind == KindGuard || kind == KindWitchSave || kind == KindWitchPoison
	case PhaseDay:
		return kind == KindNominate
	case PhaseTrial:
		return kind == KindVote && st.Nominee != ""
	}
	return false
}

// isReminder: lần Advance này chỉ gửi tin nhắc, không chốt gì.
func isReminder(evs []Event) bool {
	return len(evs) == 1 && evs[0].Kind == EventReminder
}
