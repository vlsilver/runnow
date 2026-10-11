package werewolf

import (
	"errors"
	"math"
	"sort"
	"time"
)

// Inputs là những gì một lần chốt đọc từ Firestore.
type Inputs struct {
	// Actions là các lựa chọn đang lưu của vòng hiện tại, mỗi (Actor, Kind) một bản.
	Actions []Action `json:"actions,omitempty"`
	// Km là snapshot km (mét) vừa chốt lúc 22h. Chỉ bước mở đêm 1 và bước chốt
	// ngày dùng; bước khác bỏ qua.
	Km map[string]float64 `json:"km,omitempty"`
	// Left là người đã rời PSC hoặc xoá tài khoản tính tới lúc chốt (R33).
	Left []string `json:"left,omitempty"`
}

type EventKind string

const (
	EventDeath        EventKind = "death"         // UID, Role, Cause
	EventLovers       EventKind = "lovers"        // Targets; Draw = bot ghép thay Cupid
	EventWolvesTarget EventKind = "wolves_target" // UID = người bị cắn (rỗng: không ai), Reason
	EventNominee      EventKind = "nominee"       // UID (rỗng: không ai), Counts, Draw
	EventVoteCut      EventKind = "vote_cut"      // Targets = người mất phiếu, Draw
	EventVoteResult   EventKind = "vote_result"   // UID, Hang, Spare, Hanged, Reason
	EventHunterTurn   EventKind = "hunter_turn"   // UID
	EventVoid         EventKind = "void"          // UID = actor, Action, Reason (R19)
	EventWinner       EventKind = "winner"        // Team, Reason
)

// Event là kết quả có cấu trúc của một bước, dùng để ghi events/{seq}, render
// bản tin và đánh voidReason. Field nào không dùng thì để trống.
type Event struct {
	Kind    EventKind      `json:"kind"`
	UID     string         `json:"uid,omitempty"`
	Role    Role           `json:"role,omitempty"`
	Cause   Cause          `json:"cause,omitempty"`
	Targets []string       `json:"targets,omitempty"`
	Action  Kind           `json:"action,omitempty"`
	Counts  map[string]int `json:"counts,omitempty"`
	Hang    int            `json:"hang,omitempty"`
	Spare   int            `json:"spare,omitempty"`
	Hanged  bool           `json:"hanged,omitempty"`
	Draw    bool           `json:"draw,omitempty"`
	Team    Team           `json:"team,omitempty"`
	Reason  string         `json:"reason,omitempty"`
}

// Lý do huỷ action (voidReason) và lý do trong event.
const (
	VoidActorDead   = "actor_dead"
	VoidTargetDead  = "target_dead"
	VoidLoverTarget = "lover_target"
	VoidNoKm        = "km_insufficient"
	VoidRepeat      = "guard_repeat"
	VoidInvalid     = "invalid_target"
	VoidNoPotion    = "no_potion"
	VoidVoteCut     = "vote_cut"
	VoidGameOver    = "game_over"
	ReasonNoChoice  = "no_choice"
	ReasonNoTrial   = "nominee_left"
	ReasonTimeout   = "timeout"
)

var ErrNotRunning = errors.New("ván đã kết thúc hoặc đang pause")

// Step chạy đúng một lần chốt kế tiếp: lượt bắn của thợ săn nếu đang mở, không
// thì bước cuối của phase hiện tại. Không sửa st; trả state mới. Máy phase (E5)
// quyết định lúc nào gọi và gọi bao nhiêu lần.
func Step(st *State, in Inputs) (*State, []Event, error) {
	if st.Phase == PhaseEnded || st.Paused {
		return nil, nil, ErrNotRunning
	}
	r := &resolver{st: st.clone(), in: in}
	if r.st.Hunter != nil {
		r.resolveHunter()
		return r.st, r.events, nil
	}
	switch r.st.Phase {
	case PhaseSetup:
		r.openFirstNight()
	case PhaseNight:
		r.lockWolves()
	case PhaseDawn:
		r.resolveNight()
	case PhaseDay:
		r.pickNominee()
	case PhaseTrial:
		r.resolveDay()
	}
	return r.st, r.events, nil
}

type resolver struct {
	st     *State
	in     Inputs
	events []Event
	died   []string // chết trong bước này, theo thứ tự
}

func (r *resolver) emit(e Event) { r.events = append(r.events, e) }

func (r *resolver) void(a Action, reason string) {
	r.emit(Event{Kind: EventVoid, UID: a.Actor, Action: a.Kind, Reason: reason})
}

func (r *resolver) stream(purpose string) *stream {
	return newStream(r.st.Seed, r.st.PhaseKey(), purpose)
}

func (r *resolver) kill(uid string, cause Cause) {
	p := r.st.Players[uid]
	if p == nil || !p.Alive {
		return
	}
	p.Alive, p.DeathRound, p.Cause = false, r.st.Round, cause
	r.died = append(r.died, uid)
	// Người chết bị lật bài (R32); Cause chỉ để trong secret (C3).
	r.emit(Event{Kind: EventDeath, UID: uid, Role: p.Role, Cause: cause})
}

// killLeavers: rời PSC hoặc xoá tài khoản thì chết ở lần chốt kế, đứng đầu thứ
// tự chốt (R16, R33). Áp ở mốc 22h đêm 1, chốt đêm 10h và chốt ngày 22h; 0h và
// 17h không xử (MĐ).
func (r *resolver) killLeavers() {
	left := append([]string(nil), r.in.Left...)
	sort.Strings(left)
	for _, uid := range left {
		r.kill(uid, CauseLeft)
	}
}

// killLovers: một người yêu chết thì người kia chết theo (R6, R17).
func (r *resolver) killLovers() {
	for _, uid := range r.died {
		if lover := r.st.loverOf(uid); lover != "" {
			r.kill(lover, CauseLover)
		}
	}
}

// openHunterTurn (gọi sau khi đã sang phase mới, vì E5 tính khung theo phase
// đó): thợ săn chết trong bước này được bắn, trừ khi chết vì độc hay
// rời PSC (R5, C4), hoặc km lần chốt gần nhất < X.
func (r *resolver) openHunterTurn() {
	for _, uid := range r.died {
		p := r.st.Players[uid]
		if p.Role != Hunter || p.Cause == CausePoison || p.Cause == CauseLeft || !r.st.hasKm(uid) {
			continue
		}
		r.st.Hunter = &HunterTurn{UID: uid, Phase: r.st.Phase}
		r.emit(Event{Kind: EventHunterTurn, UID: uid})
	}
}

// actionsOf trả các action loại kind, bỏ (và đánh void) bản của người đã chết.
func (r *resolver) actionsOf(kind Kind) []Action {
	var out []Action
	for _, a := range r.in.Actions {
		if a.Kind != kind || a.Clear {
			continue
		}
		if !r.st.alive(a.Actor) {
			r.void(a, VoidActorDead)
			continue
		}
		out = append(out, a)
	}
	return out
}

// targetAlive lọc tiếp: target phải còn sống, không thì đánh void.
func (r *resolver) targetAlive(a Action) bool {
	for _, t := range a.Targets {
		if !r.st.alive(t) {
			r.void(a, VoidTargetDead)
			return false
		}
	}
	return true
}

// openFirstNight: mốc 22h đêm 1 (R12). Chưa có ngày nào để chốt; chỉ nhận km
// khung đầu (rounds/0/km) và xử người đã rời PSC.
func (r *resolver) openFirstNight() {
	r.st.Km = cloneKm(r.in.Km)
	r.killLeavers()
	r.st.Phase = PhaseNight
	r.finish()
}

// lockWolves: 0h. Đêm 1 thì áp cặp đôi trước, rồi khoá lựa chọn của sói (R1, R6).
func (r *resolver) lockWolves() {
	if r.st.Round == 1 {
		r.pairLovers()
	}
	r.st.Bitten = ""
	reason := ReasonNoChoice
	var best *Action
	for _, a := range r.actionsOf(KindWolfBite) {
		if !r.targetAlive(a) {
			continue
		}
		if a.target() == r.st.loverOf(a.Actor) {
			r.void(a, VoidLoverTarget)
			continue
		}
		// Sói chọn khác nhau thì bản bấm sau cùng thắng (C2); cùng giờ thì so uid
		// để kết quả không phụ thuộc thứ tự đọc.
		if best == nil || a.ReceivedAt.After(best.ReceivedAt) ||
			(a.ReceivedAt.Equal(best.ReceivedAt) && a.Actor > best.Actor) {
			a := a
			best = &a
		}
	}
	switch {
	case best == nil:
	case !wolvesHaveKm(r.st):
		reason = VoidNoKm
		r.void(*best, VoidNoKm)
	default:
		r.st.Bitten, reason = best.target(), ""
	}
	r.emit(Event{Kind: EventWolvesTarget, UID: r.st.Bitten, Reason: reason})
	r.st.Phase = PhaseDawn
}

// pairLovers: lấy lựa chọn của Cupid; quá 0h chưa ghép thì bot ghép ngẫu nhiên
// 2 người còn sống, không gồm Cupid (R6). Cupid đã chết thì không có cặp (MĐ).
func (r *resolver) pairLovers() {
	var cupid string
	for uid, p := range r.st.Players {
		if p.Role == Cupid && p.Alive {
			cupid = uid
		}
	}
	picks := r.actionsOf(KindCupidPair) // Cupid đã chết thì lựa chọn bị huỷ (R19)
	if cupid == "" || len(r.st.Lovers) == 2 {
		return
	}
	for _, a := range picks {
		if a.Actor == cupid && r.targetAlive(a) {
			r.st.Lovers = append([]string(nil), a.Targets...)
			sort.Strings(r.st.Lovers)
			r.emit(Event{Kind: EventLovers, Targets: r.st.Lovers})
			return
		}
	}
	var pool []string
	for _, uid := range r.st.aliveUIDs() {
		if uid != cupid {
			pool = append(pool, uid)
		}
	}
	s := r.stream("cupid")
	i := s.intn(len(pool))
	j := s.intn(len(pool) - 1)
	if j >= i {
		j++
	}
	r.st.Lovers = []string{pool[i], pool[j]}
	sort.Strings(r.st.Lovers)
	r.emit(Event{Kind: EventLovers, Targets: r.st.Lovers, Draw: true})
}

// resolveNight: 10h, theo R15: người rời PSC → sói cắn → bảo vệ đỡ → phù thuỷ
// cứu/độc → người yêu chết theo → lượt thợ săn.
func (r *resolver) resolveNight() {
	r.killLeavers()
	victim := r.st.Bitten
	if !r.st.alive(victim) {
		victim = ""
	}
	guarded := r.guardTarget()
	saved, poisoned := r.witchChoices()
	// Độc tính trước cắn: thợ săn vừa bị cắn vừa bị độc thì chết vì độc và không
	// được bắn (C4).
	if poisoned != "" {
		r.kill(poisoned, CausePoison)
	}
	// Bảo vệ và phù thuỷ cùng cứu một người thì người đó sống, bình vẫn mất (R15).
	if victim != "" && victim != guarded && !saved {
		r.kill(victim, CauseBite)
	}
	r.killLovers()
	r.st.Bitten = ""
	r.st.Phase = PhaseDay
	r.openHunterTurn()
	r.finish()
}

// guardTarget trả người được bảo vệ đêm nay. Lần bảo vệ hợp lệ mới được ghi làm
// "đêm trước" cho R3; lần bị huỷ thì không.
func (r *resolver) guardTarget() string {
	for _, a := range r.actionsOf(KindGuard) {
		switch {
		case !r.targetAlive(a):
		case a.target() == r.st.LastGuarded:
			r.void(a, VoidRepeat)
		case !r.st.hasKm(a.Actor):
			r.void(a, VoidNoKm)
		default:
			r.st.LastGuarded = a.target()
			return a.target()
		}
	}
	return ""
}

// witchChoices áp hai bình (R4) và trừ bình đã dùng.
func (r *resolver) witchChoices() (saved bool, poisoned string) {
	save := r.actionsOf(KindWitchSave)
	poison := r.actionsOf(KindWitchPoison)
	if len(save) > 0 {
		a := save[0]
		switch {
		case !r.st.SavePotion:
			r.void(a, VoidNoPotion)
		case !witchCanSave(r.st, a.Actor):
			r.void(a, VoidInvalid)
		case !r.st.alive(r.st.Bitten):
			r.void(a, VoidTargetDead)
		case !r.st.hasKm(a.Actor):
			r.void(a, VoidNoKm)
		default:
			r.st.SavePotion, saved = false, true
		}
	}
	if len(poison) > 0 {
		a := poison[0]
		switch {
		case !r.st.PoisonPotion:
			r.void(a, VoidNoPotion)
		case !r.targetAlive(a):
		case a.target() == a.Actor || (saved && a.target() == r.st.Bitten):
			r.void(a, VoidInvalid)
		case !r.st.hasKm(a.Actor):
			r.void(a, VoidNoKm)
		default:
			r.st.PoisonPotion, poisoned = false, a.target()
		}
	}
	return saved, poisoned
}

// pickNominee: 17h. Người có nhiều đề cử nhất lên giàn, một đề cử là đủ, hoà thì
// bốc thăm; không ai đề cử thì hôm nay không treo. Đề cử của người đã chết hoặc
// nhắm vào người đã chết bị huỷ (R19).
func (r *resolver) pickNominee() {
	counts := map[string]int{}
	for _, a := range r.actionsOf(KindNominate) {
		if r.targetAlive(a) {
			counts[a.target()]++
		}
	}
	var top []string
	best := 0
	for uid, n := range counts {
		switch {
		case n > best:
			best, top = n, []string{uid}
		case n == best:
			top = append(top, uid)
		}
	}
	sort.Strings(top)
	ev := Event{Kind: EventNominee, Counts: counts}
	switch len(top) {
	case 0:
	case 1:
		ev.UID = top[0]
	default:
		ev.UID, ev.Draw = top[r.stream("nominee").intn(len(top))], true
	}
	r.st.Nominee = ev.UID
	r.emit(ev)
	r.st.Phase = PhaseTrial
	r.finish()
}

// resolveDay: 22h, theo R16: nhận snapshot km → người rời PSC → treo → người yêu
// chết theo → lượt thợ săn. Rồi sang đêm của vòng sau.
func (r *resolver) resolveDay() {
	r.st.Km = cloneKm(r.in.Km)
	r.killLeavers()
	if nominee := r.st.Nominee; nominee != "" {
		if r.st.alive(nominee) {
			r.countVotes(nominee)
		} else {
			// Người lên giàn đã rời PSC thì bỏ biểu quyết (R16).
			for _, a := range r.actionsOf(KindVote) {
				r.void(a, VoidTargetDead)
			}
			r.emit(Event{Kind: EventVoteResult, UID: nominee, Reason: ReasonNoTrial})
		}
	}
	r.killLovers()
	r.st.Round++
	r.st.NightAt = r.st.NightAt.Add(24 * time.Hour)
	r.st.Phase = PhaseNight
	r.st.Nominee = ""
	r.openHunterTurn() // khung 22h–23h nằm trong đêm của vòng sau
	r.finish()
}

// countVotes áp R30, R31. Treo khi số phiếu Treo được tính nhiều hơn số phiếu Tha;
// hoà thì tha (MĐ).
func (r *resolver) countVotes(nominee string) {
	var voters []string
	for _, uid := range r.st.aliveUIDs() {
		if uid != nominee {
			voters = append(voters, uid)
		}
	}
	cut, draw := r.voteCut(voters)
	if len(cut) > 0 {
		r.emit(Event{Kind: EventVoteCut, Targets: cut, Draw: draw})
	}
	isCut := map[string]bool{}
	for _, uid := range cut {
		isCut[uid] = true
	}
	ev := Event{Kind: EventVoteResult, UID: nominee}
	for _, a := range r.actionsOf(KindVote) {
		switch {
		case a.Actor == nominee:
			r.void(a, VoidTargetDead)
		case isCut[a.Actor]:
			r.void(a, VoidVoteCut)
		case a.Choice == ChoiceHang && r.st.loverOf(a.Actor) == nominee:
			r.void(a, VoidLoverTarget)
		case a.Choice == ChoiceHang:
			ev.Hang++
		case a.Choice == ChoiceSpare:
			ev.Spare++
		}
	}
	ev.Hanged = ev.Hang > ev.Spare
	r.emit(ev)
	if ev.Hanged {
		r.kill(nominee, CauseHang)
	}
}

// voteCut chọn người mất phiếu (R30): được tính min(số người, floor(tổng km / X))
// phiếu; người mất phiếu là người ít km nhất, kể cả người không bấm. Bằng km ở
// đúng ngưỡng thì bốc thăm bằng hash(seed, phaseKey, "vote-cut").
func (r *resolver) voteCut(voters []string) (cut []string, draw bool) {
	var total float64
	for _, uid := range voters {
		total += r.st.Km[uid]
	}
	// Cộng float có thể ra 2999.9999999 thay vì 3000; dung sai 1 µm không đổi được
	// kết quả thật nào.
	allowed := int(math.Floor(total/r.st.Config.unitMeters() + 1e-9))
	n := len(voters) - min(len(voters), allowed)
	if n == 0 {
		return nil, false
	}
	sorted := append([]string(nil), voters...)
	sort.SliceStable(sorted, func(i, j int) bool { return r.st.Km[sorted[i]] < r.st.Km[sorted[j]] })
	edge := r.st.Km[sorted[n-1]]
	var tied []string
	for _, uid := range sorted {
		switch km := r.st.Km[uid]; {
		case km < edge:
			cut = append(cut, uid)
		case km == edge:
			tied = append(tied, uid)
		}
	}
	need := n - len(cut)
	if need < len(tied) {
		draw = true
		r.stream("vote-cut").shuffle(len(tied), func(i, j int) { tied[i], tied[j] = tied[j], tied[i] })
	}
	cut = append(cut, tied[:need]...)
	sort.Strings(cut)
	return cut, draw
}

// resolveHunter: thợ săn bắn (hoặc hết khung mà không bắn). Người trúng đạn đang
// yêu thì người yêu chết theo (R17). Action nhắm vào người vừa chết bị huỷ, nên
// sói có mục tiêu bị bắn được chọn lại tới 0h (R20).
func (r *resolver) resolveHunter() {
	h := r.st.Hunter
	r.st.Hunter = nil
	var shot *Action
	for _, a := range r.in.Actions {
		if a.Kind == KindHunterShoot && a.Actor == h.UID && !a.Clear {
			a := a
			shot = &a
		}
	}
	if shot != nil && r.targetAlive(*shot) && shot.target() != h.UID {
		r.kill(shot.target(), CauseShot)
		r.killLovers()
	}
	dead := map[string]bool{}
	for _, uid := range r.died {
		dead[uid] = true
	}
	for _, a := range r.in.Actions {
		if a.Kind == KindHunterShoot || a.Clear {
			continue
		}
		if dead[a.Actor] {
			r.void(a, VoidActorDead)
		} else if len(a.Targets) > 0 && anyIn(a.Targets, dead) {
			r.void(a, VoidTargetDead)
		}
	}
	r.finish()
	if r.st.Phase == PhaseEnded {
		// Phát bắn kết thúc ván thì mọi hành động đêm bị huỷ (R20).
		for _, a := range r.in.Actions {
			if a.Kind != KindHunterShoot && !dead[a.Actor] && !anyIn(a.Targets, dead) {
				r.void(a, VoidGameOver)
			}
		}
	}
}

// finish xét thắng thua (R18, R22–R25). Đang chờ thợ săn bắn thì chỉ kết thúc
// khi kết quả không còn phụ thuộc phát bắn: Dân đã thắng (hết sói) thì phát bắn
// không đổi được gì nữa.
func (r *resolver) finish() {
	w := r.st.winner()
	if r.st.Hunter != nil {
		if w != TeamVillage {
			return
		}
		r.st.Hunter = nil
		r.dropEvents(EventHunterTurn)
	}
	reason := ""
	if w == "" && r.st.Phase == PhaseNight && r.st.Round > MaxRounds {
		w, reason = TeamVillage, ReasonTimeout // R13, R25
	}
	if w == "" {
		return
	}
	r.st.Winner, r.st.Phase = w, PhaseEnded
	r.emit(Event{Kind: EventWinner, Team: w, Reason: reason})
}

// winner trả phe thắng, rỗng nếu ván còn tiếp.
func (st *State) winner() Team {
	alive := st.aliveUIDs()
	mixed := st.mixedCouple()
	// R24: cặp phe ba thắng khi chỉ còn 2 người họ.
	if mixed && len(alive) == 2 && st.alive(st.Lovers[0]) && st.alive(st.Lovers[1]) {
		return TeamLovers
	}
	wolves, free := 0, 0
	for _, uid := range alive {
		if st.role(uid) != Wolf {
			continue
		}
		wolves++
		if !mixed || st.loverOf(uid) == "" {
			free++
		}
	}
	switch {
	case wolves == 0: // R22: hết sói, kể cả sói đang yêu
		return TeamVillage
	case free >= len(alive)-free: // R23: sói đang yêu tính vào phe ba
		return TeamWolves
	}
	return ""
}

func anyIn(uids []string, set map[string]bool) bool {
	for _, u := range uids {
		if set[u] {
			return true
		}
	}
	return false
}

func cloneKm(km map[string]float64) map[string]float64 {
	out := make(map[string]float64, len(km))
	for k, v := range km {
		out[k] = v
	}
	return out
}

func (r *resolver) dropEvents(kind EventKind) {
	kept := r.events[:0]
	for _, e := range r.events {
		if e.Kind != kind {
			kept = append(kept, e)
		}
	}
	r.events = kept
}
