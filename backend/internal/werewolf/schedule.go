package werewolf

import (
	"errors"
	"fmt"
	"time"
)

// vietnam là giờ nghiệp vụ (+7, không có giờ mùa hè).
var vietnam = time.FixedZone("ICT", 7*3600)

// FirstNight là mốc 22h đầu tiên cách lúc Start ít nhất 2 giờ (R12, C1).
func FirstNight(start time.Time) time.Time { return Config{}.FirstNight(start) }

// FirstNight là mốc mở vòng đầu tiên cách lúc Start ít nhất 2 giờ.
func (c Config) FirstNight(start time.Time) time.Time {
	return c.nextSlot(start.Add(2 * time.Hour))
}

// DefaultSchedule là lịch gốc: một vòng một ngày, mở đêm lúc 22h.
func DefaultSchedule() Schedule { return Schedule{StartHour: 22, RoundHours: 24, Rounds: 1} }

func (c Config) schedule() Schedule {
	if c.Schedule == nil {
		return DefaultSchedule()
	}
	return *c.Schedule
}

// RoundClock là giờ các mốc của một vòng, để in cho người chơi. Biểu quyết mở
// đúng lúc đề cử đóng.
type RoundClock struct {
	Night, WolfLock, Dawn, NominateClose, Close time.Time
}

// Clock là các mốc của vòng mở đêm lúc nightAt, chưa tính phần admin dời.
func (c Config) Clock(nightAt time.Time) RoundClock {
	at := func(p Phase) time.Time { return nightAt.Add(c.AtNight(nightAt, phaseEnd[p])) }
	return RoundClock{Night: nightAt, WolfLock: at(PhaseNight), Dawn: at(PhaseDawn), NominateClose: at(PhaseDay), Close: at(PhaseTrial)}
}

// PhaseOffset là hạn của phase ở vòng đầu ngày, tính từ lúc mở đêm, chưa tính
// phần admin dời.
func (c Config) PhaseOffset(p Phase) time.Duration { return c.At(phaseEnd[p]) }

// NightOf là giờ mở đêm của vòng có phase p chốt lúc deadline (chưa ai dời
// hạn). Mỗi vòng trong ngày có thể có lịch pha riêng, nên thử từng vòng và lấy
// vòng mà giờ mở rơi đúng vào nó.
func (c Config) NightOf(deadline time.Time, p Phase) time.Time {
	s := c.schedule()
	for i := 0; i < s.Rounds; i++ {
		night := deadline.Add(-c.at(s.phasesOf(i), phaseEnd[p]))
		if s.slot(night) == i {
			return night
		}
	}
	return deadline.Add(-c.PhaseOffset(p))
}

// RoundLen là độ dài một vòng.
func (c Config) RoundLen() time.Duration {
	return time.Duration(c.schedule().RoundHours) * time.Hour
}

// At đổi mốc d của lịch gốc 24 tiếng sang vòng đầu ngày của ván này.
func (c Config) At(d time.Duration) time.Duration {
	return c.at(c.schedule().phasesOf(0), d)
}

// AtNight là At cho vòng mở đêm lúc nightAt, theo lịch pha của vòng đó.
func (c Config) AtNight(nightAt time.Time, d time.Duration) time.Duration {
	s := c.schedule()
	return c.at(s.phasesOf(s.slot(nightAt)), d)
}

// at đổi mốc d theo bốn pha phases. Không có pha thì cả vòng co giãn đều
// (RoundHours chẵn nên ra số phút chẵn). Có pha thì mốc nằm trong pha nào của
// lịch gốc co giãn theo pha đó của ván: nhắc đề cử ở 4/5 pha Ngày, thợ săn bị
// treo bắn trong nửa đầu pha Đêm.
func (c Config) at(phases []int, d time.Duration) time.Duration {
	s := c.schedule()
	if phases == nil {
		return d / 24 * time.Duration(s.RoundHours)
	}
	var from, to time.Duration // đầu pha đang xét, của lịch gốc và của ván
	for i, p := range phaseOrder {
		baseEnd, end := phaseEnd[p], to+time.Duration(phases[i])*time.Minute
		if d <= baseEnd || i == len(phaseOrder)-1 {
			frac := float64(d-from) / float64(baseEnd-from)
			return to + time.Duration(frac*float64(end-to)).Round(time.Second)
		}
		from, to = baseEnd, end
	}
	panic("unreachable")
}

// phaseOrder là bốn pha của một vòng theo thứ tự, khớp thứ tự Schedule.Phases.
var phaseOrder = []Phase{PhaseNight, PhaseDawn, PhaseDay, PhaseTrial}

func (s Schedule) validatePhases() error {
	if s.RoundPhases != nil && len(s.RoundPhases) != s.Rounds {
		return fmt.Errorf("lịch riêng có %d vòng, phải bằng số vòng mỗi ngày %d", len(s.RoundPhases), s.Rounds)
	}
	for _, phases := range append([][]int{s.Phases}, s.RoundPhases...) {
		if err := s.validRound(phases); err != nil {
			return err
		}
	}
	return nil
}

// validRound kiểm bốn pha của một vòng; nil là vòng co đều, hợp lệ.
func (s Schedule) validRound(phases []int) error {
	if phases == nil {
		return nil
	}
	if len(phases) != len(phaseOrder) {
		return fmt.Errorf("lịch phải có đủ %d pha: %v", len(phaseOrder), phases)
	}
	total := 0
	for _, m := range phases {
		if m < MinPhaseMinutes || m%PhaseStepMinutes != 0 {
			return fmt.Errorf("pha nào cũng ít nhất %d phút, theo bước %d phút: %v", MinPhaseMinutes, PhaseStepMinutes, phases)
		}
		total += m
	}
	if total != s.RoundHours*60 {
		return fmt.Errorf("bốn pha cộng lại %d phút, phải bằng vòng %d tiếng", total, s.RoundHours)
	}
	return nil
}

// phasesOf là bốn pha của vòng thứ i trong ngày (từ 0); nil là co đều.
func (s Schedule) phasesOf(i int) []int {
	if i < len(s.RoundPhases) {
		return s.RoundPhases[i]
	}
	return s.Phases
}

// slot là vòng thứ mấy trong ngày (từ 0) của vòng mở đêm lúc nightAt. Giờ mở
// lệch khung (ván cũ, resume dời theo ngày nguyên thì không lệch) rơi về vòng
// gần nhất phía trước.
func (s Schedule) slot(nightAt time.Time) int {
	local := nightAt.In(vietnam)
	m := ((local.Hour()*60+local.Minute()-s.StartHour*60)%1440 + 1440) % 1440
	return min(m/(s.RoundHours*60), s.Rounds-1)
}

// RoundStarts là giờ (VN, 0–23) mở các vòng trong một ngày.
func (c Config) RoundStarts() []int {
	s := c.schedule()
	out := make([]int, s.Rounds)
	for i := range out {
		out[i] = (s.StartHour + i*s.RoundHours) % 24
	}
	return out
}

// nextSlot là mốc mở vòng sớm nhất không trước t.
func (c Config) nextSlot(t time.Time) time.Time {
	s := c.schedule()
	local := t.In(vietnam)
	// Bắt đầu từ hôm trước: khung của hôm trước có thể kéo qua nửa đêm.
	day := time.Date(local.Year(), local.Month(), local.Day()-1, s.StartHour, 0, 0, 0, vietnam)
	for {
		for i := 0; i < s.Rounds; i++ {
			if at := day.Add(time.Duration(i*s.RoundHours) * time.Hour); !at.Before(t) {
				return at
			}
		}
		day = day.AddDate(0, 0, 1)
	}
}

// nextNight là mốc mở đêm của vòng sau vòng mở lúc nightAt.
func (c Config) nextNight(nightAt time.Time) time.Time {
	return c.nextSlot(nightAt.Add(c.RoundLen()))
}

// Lịch một vòng (bảng 1.3), tính từ NightAt = 22h mở đêm. Hạn của phase là lúc
// chốt nó; phase sau mở ngay khi phase trước chốt xong.
var phaseEnd = map[Phase]time.Duration{
	PhaseSetup: 0,              // 22h đêm 1
	PhaseNight: 2 * time.Hour,  // 0h: khoá sói
	PhaseDawn:  12 * time.Hour, // 10h: chốt đêm
	PhaseDay:   22 * time.Hour, // 20h: lên giàn
	PhaseTrial: 24 * time.Hour, // 22h: chốt ngày
}

const (
	voteOpens     = 22 * time.Hour // 20h: biểu quyết mở ngay khi có người lên giàn
	remindNominee = 20 * time.Hour // 18h
	remindVote    = 23 * time.Hour // 21h, kèm nhắc mở app để sync km
	hunterDay     = 14 * time.Hour // chết trong đêm: bắn trong 10h–12h
	hunterNight   = 1 * time.Hour  // bị treo: bắn trong 22h–23h
)

// ReminderOffsets là lúc bot nhắc đề cử và nhắc biểu quyết, tính từ lúc mở đêm.
func (c Config) ReminderOffsets() (nominate, vote time.Duration) {
	return c.At(remindNominee), c.At(remindVote)
}

// Deadline là lúc chốt phase hiện tại, kể cả phần admin đã dời (Extend).
func (st *State) Deadline() time.Time {
	return st.NightAt.Add(st.at(phaseEnd[st.Phase]) + st.extra())
}

// at là mốc d của vòng đang chơi, theo lịch pha của vòng đó.
func (st *State) at(d time.Duration) time.Duration { return st.Config.AtNight(st.NightAt, d) }

func (st *State) hunterClose() time.Time {
	if st.Hunter == nil {
		return time.Time{}
	}
	end := hunterNight
	if st.Hunter.Phase == PhaseDay {
		end = hunterDay
	}
	return st.NightAt.Add(st.at(end) + st.extra())
}

// TurnClose là hạn của lượt đang mở: lượt bắn của thợ săn nếu đang có, không
// thì hạn phase.
func (st *State) TurnClose() time.Time {
	if st.Hunter != nil {
		return st.hunterClose()
	}
	return st.Deadline()
}

// extra là phần dời hạn của lượt đang mở. Sang lượt khác thì PhaseKey đổi nên
// tự hết, lịch các phase sau giữ đúng giờ.
func (st *State) extra() time.Duration {
	if st.ExtraKey != st.PhaseKey() {
		return 0
	}
	return st.Extra
}

// nextPhase là phase mở ngay sau khi phase này chốt (trial thì sang đêm vòng sau).
var nextPhase = map[Phase]Phase{
	PhaseSetup: PhaseNight, PhaseNight: PhaseDawn, PhaseDawn: PhaseDay, PhaseDay: PhaseTrial, PhaseTrial: PhaseNight,
}

// extendGap là thời gian tối thiểu còn lại cho lượt kế tiếp sau khi dời hạn.
const extendGap = time.Hour

// extendGap của ván: co đều thì là 1 giờ lịch gốc; lượt ngắn nhất (thợ săn bị
// treo, 22h–23h) dài đúng chừng đó nên Max >= 0. Lịch có pha riêng thì At(1h)
// thành nửa pha Đêm, không còn là một khoảng cố định, nên chừa nửa pha ngắn
// nhất (30 phút): pha nào cũng >= 60 phút, lượt thợ săn bị treo >= 30 phút.
func (c Config) extendGap() time.Duration {
	if s := c.schedule(); s.Phases != nil || s.RoundPhases != nil {
		return MinPhaseMinutes / 2 * time.Minute
	}
	return c.At(extendGap)
}

var ErrExtendState = errors.New("ván không dời hạn được")

// ExtendTooLong: dời quá mức để lượt sau còn extendGap. Max là phần còn dời được.
type ExtendTooLong struct{ Max time.Duration }

func (e *ExtendTooLong) Error() string {
	return fmt.Sprintf("chỉ dời được tối đa %s", e.Max)
}

// Extend dời hạn của lượt đang mở thêm d (admin, khi người chơi cần thêm giờ).
// Chỉ lượt này dời; lượt sau vẫn khoá đúng giờ cũ, nên phải còn ít nhất
// extendGap. Lượt thợ săn thì lượt sau là phase mà lượt bắn chen vào.
func Extend(st *State, d time.Duration) (*State, error) {
	if st.Phase == PhaseEnded || d <= 0 {
		return nil, ErrExtendState
	}
	follow := st.NightAt.Add(st.at(phaseEnd[nextPhase[st.Phase]]))
	if st.Phase == PhaseTrial {
		next := st.Config.nextNight(st.NightAt)
		follow = next.Add(st.Config.AtNight(next, phaseEnd[PhaseNight]))
	}
	if st.Hunter != nil {
		follow = st.NightAt.Add(st.at(phaseEnd[st.Phase]))
	}
	if closes, limit := st.TurnClose(), follow.Add(-st.Config.extendGap()); closes.Add(d).After(limit) {
		return nil, &ExtendTooLong{Max: limit.Sub(closes)}
	}
	next := st.clone()
	next.Extra, next.ExtraKey = st.extra()+d, st.PhaseKey()
	return next, nil
}

// windowOpen: hành động chỉ nhận trước hạn của phase, kể cả khi bước chốt tới
// trễ. Biểu quyết còn phải đợi tới 20h. Ngoài khung giờ hoạt động (đêm đã sang
// mà chưa tới giờ mở) thì chưa nhận gì.
func (st *State) windowOpen(kind Kind, now time.Time) bool {
	if !now.Before(st.Deadline()) || (st.Phase == PhaseNight && now.Before(st.NightAt)) {
		return false
	}
	return !IsVote(kind) || !now.Before(st.NightAt.Add(st.at(voteOpens)))
}

const (
	ReminderNominate = "nominate"
	ReminderVote     = "vote"
)

// EventReminder: tới giờ nhắc; Reason là ReminderNominate hoặc ReminderVote.
const EventReminder EventKind = "reminder"

// reminder trả loại và giờ của tin nhắc trong phase hiện tại, nếu có.
func (st *State) reminder() (string, time.Time, bool) {
	switch st.Phase {
	case PhaseDay:
		return ReminderNominate, st.NightAt.Add(st.at(remindNominee)), true
	case PhaseTrial:
		return ReminderVote, st.NightAt.Add(st.at(remindVote)), true
	}
	return "", time.Time{}, false
}

// NextAt là lúc cần gọi Advance tiếp: hạn thợ săn, giờ nhắc chưa gửi, hoặc hạn
// phase. W1 hẹn game-advance vào NextAt + 30s.
func (st *State) NextAt() time.Time {
	if st.Hunter != nil {
		return st.hunterClose()
	}
	if _, at, ok := st.reminder(); ok && st.Reminded != st.PhaseKey() {
		return at
	}
	return st.Deadline()
}

// TaskKey là khoá chống trùng cho Cloud Task game-advance. Có cả giờ hẹn, vì sau
// resume cùng một PhaseKey nhận hạn mới; chỉ dùng PhaseKey thì task hẹn lại bị
// coi là trùng với task cũ và không được tạo.
func (st *State) TaskKey() string {
	return fmt.Sprintf("%s@%d", st.PhaseKey(), st.NextAt().Unix())
}

// KmFrameEnd: lần chốt kế tiếp có cần snapshot km không, và khung kết thúc lúc
// nào. Chỉ mở đêm 1 và chốt vòng cần. Ván km chốt km lúc 22h, nên vòng chốt
// giữa ngày lấy khung kết thúc 22h gần nhất trước đó: các vòng trong ngày dùng
// chung km của ngày chạy trước. Ván không dùng km thì khung là hạn chốt.
func (st *State) KmFrameEnd() (time.Time, bool) {
	// Lượt thợ săn chỉ mở trong day và night, nên không chen vào hai mốc này.
	if st.Phase != PhaseSetup && st.Phase != PhaseTrial {
		return time.Time{}, false
	}
	end := st.Deadline()
	if st.Config.KmOff {
		return end, true
	}
	local := end.In(vietnam)
	day22 := time.Date(local.Year(), local.Month(), local.Day(), 22, 0, 0, 0, vietnam)
	if day22.After(local) {
		day22 = day22.AddDate(0, 0, -1)
	}
	return day22, true
}

var ErrNotDue = errors.New("chưa tới hạn")

// Advance chạy việc kế tiếp đã tới hạn lúc now. Gọi lặp tới khi nhận ErrNotDue
// thì chạy bù được nhiều mốc đã lỡ, đúng thứ tự (22h → 0h → 10h…). Mỗi lần gọi
// là một transaction ở W1. Thứ tự xét:
//   - lượt thợ săn: chốt ngay khi đã bắn, hoặc khi hết khung;
//   - hạn phase đã qua: chốt luôn; tin nhắc chưa gửi thì bỏ vì đã quá giờ;
//   - tin nhắc tới giờ mà chưa gửi.
func Advance(st *State, in Inputs, now time.Time) (*State, []Event, error) {
	if st.Phase == PhaseEnded || st.Paused {
		return nil, nil, ErrNotRunning
	}
	if h := st.Hunter; h != nil {
		if hasShot(in, h.UID) || !now.Before(st.hunterClose()) {
			return Step(st, in)
		}
		return nil, nil, ErrNotDue
	}
	if !now.Before(st.Deadline()) {
		return Step(st, in)
	}
	if reason, at, ok := st.reminder(); ok && st.Reminded != st.PhaseKey() && !now.Before(at) {
		next := st.clone()
		next.Reminded = st.PhaseKey()
		return next, []Event{{Kind: EventReminder, Reason: reason}}, nil
	}
	return nil, nil, ErrNotDue
}

func hasShot(in Inputs, hunter string) bool {
	for _, a := range in.Actions {
		if a.Kind == KindHunterShoot && a.Actor == hunter && !a.Clear {
			return true
		}
	}
	return false
}

var ErrPauseState = errors.New("ván không ở trạng thái pause/resume được")

// Pause đóng băng ván: hành động bị từ chối, Advance không chạy (R14).
func Pause(st *State) (*State, error) {
	if st.Phase == PhaseEnded || st.Paused {
		return nil, ErrPauseState
	}
	next := st.clone()
	next.Paused = true
	return next, nil
}

// Resume cho phase hiện tại hạn mới: lần kế tiếp (sau now) của giờ kết thúc phase
// đó. Cả lịch vòng dời theo số ngày nguyên, nên các cửa sổ còn lại giữ đúng giờ.
// Bước nào lỡ trong lúc pause thì không bù (R14).
func Resume(st *State, now time.Time) (*State, error) {
	if !st.Paused {
		return nil, ErrPauseState
	}
	next := st.clone()
	next.Paused = false
	if d := next.Deadline(); !now.Before(d) {
		days := int(now.Sub(d)/(24*time.Hour)) + 1
		next.NightAt = next.NightAt.Add(time.Duration(days) * 24 * time.Hour)
	}
	return next, nil
}
