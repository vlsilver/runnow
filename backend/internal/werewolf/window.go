package werewolf

import "time"

// Giờ mở của từng phase, tính từ NightAt như phaseEnd. Setup mở lúc Start, mà
// state không giữ giờ Start, nên không có ở đây.
var phaseStart = map[Phase]time.Duration{
	PhaseNight: 0,
	PhaseDawn:  2 * time.Hour,
	PhaseDay:   12 * time.Hour,
	PhaseTrial: 19 * time.Hour,
}

// Window là cửa sổ [opens, closes) của kind trong vòng hiện tại (bảng 1.3), để
// app và DM hiện giờ mở và giờ khoá. opens là zero khi cửa sổ đã mở từ lúc Start
// (Cupid ở setup). Không xét vai hay sống chết: việc đó là của Available và
// Precheck.
func (st *State) Window(kind Kind) (opens, closes time.Time) {
	if kind == KindHunterShoot {
		if st.Hunter == nil {
			return time.Time{}, time.Time{}
		}
		if st.Hunter.Phase == PhaseDay {
			return st.NightAt.Add(phaseStart[PhaseDay]), st.hunterClose()
		}
		return st.NightAt, st.hunterClose()
	}
	rule, ok := kindRules[kind]
	if !ok || len(rule.phases) == 0 {
		return time.Time{}, time.Time{}
	}
	first, last := rule.phases[0], rule.phases[len(rule.phases)-1]
	if first == PhaseSetup && st.Phase != PhaseSetup {
		first = rule.phases[1]
	}
	if first != PhaseSetup {
		opens = st.NightAt.Add(phaseStart[first])
	}
	if IsVote(kind) {
		opens = st.NightAt.Add(voteOpens)
	}
	if last == st.Phase {
		return opens, st.Deadline() // có cả phần admin dời hạn
	}
	return opens, st.NightAt.Add(phaseEnd[last])
}

// Precheck là Validate khi chưa chọn mục tiêu: lý do người chơi chưa bấm được
// kind lúc now (ngoài giờ, hết lượt, thiếu km, không có ai bị cắn để cứu…). nil
// là bấm được; mục tiêu cụ thể thì Validate kiểm sau.
func Precheck(st *State, kind Kind, actor string, mine []Action, now time.Time) error {
	if err := precheck(st, kind, actor, mine, now); err != nil {
		return err
	}
	rule := kindRules[kind]
	if rule.needsKm && !st.hasKm(actor) {
		return ErrKmInsufficient
	}
	switch kind {
	case KindWolfBite:
		if !wolvesHaveKm(st) {
			return ErrKmInsufficient
		}
	case KindWitchSave:
		if !st.SavePotion {
			return ErrAlreadyUsed
		}
		if !witchCanSave(st, actor) {
			return ErrInvalidTarget
		}
	case KindWitchPoison:
		if !st.PoisonPotion {
			return ErrAlreadyUsed
		}
	case KindVote, KindVote2, KindVote3:
		nominee := st.NomineeOf(kind)
		if nominee == "" {
			return ErrPhaseClosed
		}
		if actor == nominee {
			return ErrNotYourRole
		}
	}
	return nil
}

// KindTargets là số mục tiêu kind cần (0: không chọn ai, như bình cứu hay biểu
// quyết). Changeable: đổi hoặc bỏ được trong cửa sổ.
func KindTargets(kind Kind) int { return kindRules[kind].targets }

func KindChangeable(kind Kind) bool { return kindRules[kind].changeable }
