package werewolf

import (
	"errors"
	"fmt"
	"time"
)

// vietnam là giờ nghiệp vụ (+7, không có giờ mùa hè).
var vietnam = time.FixedZone("ICT", 7*3600)

// FirstNight là mốc 22h đầu tiên cách lúc Start ít nhất 2 giờ (R12, C1).
func FirstNight(start time.Time) time.Time {
	earliest := start.Add(2 * time.Hour).In(vietnam)
	night := time.Date(earliest.Year(), earliest.Month(), earliest.Day(), 22, 0, 0, 0, vietnam)
	if night.Before(earliest) {
		night = night.AddDate(0, 0, 1)
	}
	return night
}

// Lịch một vòng (bảng 1.3), tính từ NightAt = 22h mở đêm. Hạn của phase là lúc
// chốt nó; phase sau mở ngay khi phase trước chốt xong.
var phaseEnd = map[Phase]time.Duration{
	PhaseSetup: 0,              // 22h đêm 1
	PhaseNight: 2 * time.Hour,  // 0h: khoá sói
	PhaseDawn:  12 * time.Hour, // 10h: chốt đêm
	PhaseDay:   19 * time.Hour, // 17h: lên giàn
	PhaseTrial: 24 * time.Hour, // 22h: chốt ngày
}

const (
	voteOpens     = 22 * time.Hour // 20h: biểu quyết mở; 17h–20h là bào chữa
	remindNominee = 17 * time.Hour // 15h
	remindVote    = 23 * time.Hour // 21h, kèm nhắc mở app để sync km
	hunterDay     = 14 * time.Hour // chết trong đêm: bắn trong 10h–12h
	hunterNight   = 1 * time.Hour  // bị treo: bắn trong 22h–23h
)

// Deadline là lúc chốt phase hiện tại, kể cả phần admin đã dời (Extend).
func (st *State) Deadline() time.Time {
	return st.NightAt.Add(phaseEnd[st.Phase] + st.extra())
}

func (st *State) hunterClose() time.Time {
	if st.Hunter == nil {
		return time.Time{}
	}
	end := hunterNight
	if st.Hunter.Phase == PhaseDay {
		end = hunterDay
	}
	return st.NightAt.Add(end + st.extra())
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
	follow := st.NightAt.Add(phaseEnd[nextPhase[st.Phase]])
	if st.Phase == PhaseTrial {
		follow = follow.Add(24 * time.Hour)
	}
	if st.Hunter != nil {
		follow = st.NightAt.Add(phaseEnd[st.Phase])
	}
	// Lượt ngắn nhất (thợ săn bị treo, 22h–23h) dài đúng extendGap, nên Max >= 0.
	if closes, limit := st.TurnClose(), follow.Add(-extendGap); closes.Add(d).After(limit) {
		return nil, &ExtendTooLong{Max: limit.Sub(closes)}
	}
	next := st.clone()
	next.Extra, next.ExtraKey = st.extra()+d, st.PhaseKey()
	return next, nil
}

// windowOpen: hành động chỉ nhận trước hạn của phase, kể cả khi bước chốt tới
// trễ. Biểu quyết còn phải đợi tới 20h.
func (st *State) windowOpen(kind Kind, now time.Time) bool {
	if !now.Before(st.Deadline()) {
		return false
	}
	return kind != KindVote || !now.Before(st.NightAt.Add(voteOpens))
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
		return ReminderNominate, st.NightAt.Add(remindNominee), true
	case PhaseTrial:
		return ReminderVote, st.NightAt.Add(remindVote), true
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
// nào. Chỉ mốc 22h (mở đêm 1, chốt ngày) cần.
func (st *State) KmFrameEnd() (time.Time, bool) {
	// Lượt thợ săn chỉ mở trong day và night, nên không chen vào hai mốc này.
	if st.Phase == PhaseSetup || st.Phase == PhaseTrial {
		return st.Deadline(), true
	}
	return time.Time{}, false
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
