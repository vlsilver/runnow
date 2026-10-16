package werewolf

import "time"

// Kind là loại hành động. Giá trị chuỗi nằm trong id doc action và API, đừng đổi.
type Kind string

const (
	KindWolfBite    Kind = "wolf_bite"
	KindSeerPeek    Kind = "seer_peek"
	KindGuard       Kind = "guard"
	KindWitchSave   Kind = "witch_save" // cứu người bị cắn đêm nay, không có target
	KindWitchPoison Kind = "witch_poison"
	KindHunterShoot Kind = "hunter_shoot"
	KindCupidPair   Kind = "cupid_pair"
	KindNominate    Kind = "nominate"
	KindVote        Kind = "vote"
)

const (
	ChoiceHang  = "hang"
	ChoiceSpare = "spare"
)

// Action là một lựa chọn của người chơi trong vòng hiện tại. Mỗi (Actor, Kind)
// chỉ có một bản; bản sau ghi đè bản trước.
type Action struct {
	Kind       Kind      `json:"kind"`
	Actor      string    `json:"actor"`
	Targets    []string  `json:"targets,omitempty"`
	Choice     string    `json:"choice,omitempty"`
	Clear      bool      `json:"clear,omitempty"` // bỏ lựa chọn đang có
	ReceivedAt time.Time `json:"receivedAt"`
}

func (a Action) target() string {
	if len(a.Targets) == 0 {
		return ""
	}
	return a.Targets[0]
}

// Reject là lỗi luật, mã khớp mục 3.8 để API trả thẳng cho app.
type Reject string

func (r Reject) Error() string { return string(r) }

const (
	ErrPhaseClosed    Reject = "phase_closed"
	ErrNotAlive       Reject = "not_alive"
	ErrNotYourRole    Reject = "not_your_role"
	ErrKmInsufficient Reject = "km_insufficient"
	ErrInvalidTarget  Reject = "invalid_target"
	ErrLoverTarget    Reject = "lover_target"
	ErrGuardRepeat    Reject = "guard_repeat"
	ErrAlreadyUsed    Reject = "already_used"
	ErrPaused         Reject = "paused"
)

type kindRule struct {
	role       Role // rỗng: ai còn sống cũng được
	phases     []Phase
	targets    int
	changeable bool // đổi hoặc bỏ được trong cửa sổ (bảng 1.3)
	needsKm    bool // km của chính người đó ≥ X
}

var kindRules = map[Kind]kindRule{
	KindWolfBite:    {role: Wolf, phases: []Phase{PhaseNight}, targets: 1, changeable: true},
	KindSeerPeek:    {role: Seer, phases: []Phase{PhaseNight, PhaseDawn}, targets: 1, needsKm: true},
	KindGuard:       {role: Guard, phases: []Phase{PhaseNight, PhaseDawn}, targets: 1, changeable: true, needsKm: true},
	KindWitchSave:   {role: Witch, phases: []Phase{PhaseDawn}, changeable: true, needsKm: true},
	KindWitchPoison: {role: Witch, phases: []Phase{PhaseDawn}, targets: 1, changeable: true, needsKm: true},
	KindHunterShoot: {role: Hunter, targets: 1}, // mở theo State.Hunter, không theo phase
	KindCupidPair:   {role: Cupid, phases: []Phase{PhaseSetup, PhaseNight}, targets: 2},
	KindNominate:    {phases: []Phase{PhaseDay}, targets: 1, changeable: true},
	KindVote:        {phases: []Phase{PhaseTrial}, changeable: true},
}

// Validate kiểm một hành động theo luật, trước khi service hành động ghi nó.
// mine là các action actor đang có trong vòng này (mọi kind), để kiểm luật chọn
// một lần và luật giữa hai bình của phù thuỷ. now là receivedAt: hành động phải
// nằm trong cửa sổ của nó (schedule.go), nên action tới sau hạn mà bước chốt chưa
// chạy vẫn bị từ chối, không lọt vào hay mất lặng lẽ.
func Validate(st *State, a Action, mine []Action, now time.Time) error {
	if err := precheck(st, a.Kind, a.Actor, mine, now); err != nil {
		return err
	}
	rule := kindRules[a.Kind]
	if a.Clear {
		if !rule.changeable {
			return ErrAlreadyUsed
		}
		return nil
	}
	if len(a.Targets) != rule.targets {
		return ErrInvalidTarget
	}
	seen := map[string]bool{}
	for _, t := range a.Targets {
		if seen[t] || !st.alive(t) {
			return ErrInvalidTarget
		}
		seen[t] = true
	}
	if rule.needsKm && !st.hasKm(a.Actor) {
		return ErrKmInsufficient
	}
	return validateKind(st, a, mine)
}

func validateKind(st *State, a Action, mine []Action) error {
	t := a.target()
	switch a.Kind {
	case KindWolfBite:
		if t == st.loverOf(a.Actor) {
			return ErrLoverTarget
		}
		if !wolvesHaveKm(st) {
			return ErrKmInsufficient
		}
	case KindSeerPeek:
		if t == a.Actor {
			return ErrInvalidTarget
		}
	case KindGuard:
		if t == st.LastGuarded {
			return ErrGuardRepeat
		}
	case KindWitchSave:
		if !st.SavePotion {
			return ErrAlreadyUsed
		}
		if !witchCanSave(st, a.Actor) {
			return ErrInvalidTarget
		}
		if poison := findAction(mine, KindWitchPoison); poison != nil && poison.target() == st.Bitten {
			return ErrInvalidTarget
		}
	case KindWitchPoison:
		if !st.PoisonPotion {
			return ErrAlreadyUsed
		}
		if t == a.Actor {
			return ErrInvalidTarget
		}
		if findAction(mine, KindWitchSave) != nil && t == st.Bitten {
			return ErrInvalidTarget
		}
	case KindHunterShoot, KindNominate:
		if t == a.Actor {
			return ErrInvalidTarget
		}
	case KindVote:
		if st.Nominee == "" {
			return ErrPhaseClosed // hôm nay không ai lên giàn
		}
		if a.Actor == st.Nominee {
			return ErrNotYourRole
		}
		if a.Choice != ChoiceHang && a.Choice != ChoiceSpare {
			return ErrInvalidTarget
		}
		if a.Choice == ChoiceHang && st.loverOf(a.Actor) == st.Nominee {
			return ErrLoverTarget
		}
	}
	return nil
}

// precheck là phần của Validate không phụ thuộc mục tiêu: ván còn chạy, đúng vai,
// còn sống, trong cửa sổ, chưa dùng lượt chọn một lần.
func precheck(st *State, kind Kind, actor string, mine []Action, now time.Time) error {
	rule, ok := kindRules[kind]
	if !ok {
		return ErrPhaseClosed
	}
	if st.Phase == PhaseEnded {
		return ErrPhaseClosed
	}
	if st.Paused {
		return ErrPaused
	}
	p := st.Players[actor]
	if p == nil {
		return ErrNotYourRole
	}
	if rule.role != "" && p.Role != rule.role {
		return ErrNotYourRole
	}
	if kind == KindHunterShoot {
		// Thợ săn bắn sau khi chết, nên không kiểm còn sống.
		if st.Hunter == nil || st.Hunter.UID != actor || !now.Before(st.hunterClose()) {
			return ErrPhaseClosed
		}
	} else {
		if !p.Alive {
			return ErrNotAlive
		}
		if !phaseOpen(rule.phases, st.Phase) || !st.windowOpen(kind, now) {
			return ErrPhaseClosed
		}
	}
	if kind == KindCupidPair && st.Round > 1 {
		return ErrPhaseClosed // Cupid chỉ ghép tới 0h đêm 1 (R6, R12)
	}
	if !rule.changeable && findAction(mine, kind) != nil {
		return ErrAlreadyUsed
	}
	return nil
}

// wolvesHaveKm: tổng km của sói còn sống ≥ X × số sói còn sống (R1).
func wolvesHaveKm(st *State) bool {
	var n int
	var sum float64
	for _, uid := range st.aliveUIDs() {
		if st.role(uid) == Wolf {
			n++
			sum += st.Km[uid]
		}
	}
	return n > 0 && sum >= float64(n)*st.Config.unitMeters()
}

// witchCanSave: có người bị cắn, và chỉ tự cứu được ở đêm 1 (R4).
func witchCanSave(st *State, witch string) bool {
	if st.Bitten == "" {
		return false
	}
	return st.Bitten != witch || st.Round == 1
}

func phaseOpen(phases []Phase, p Phase) bool {
	for _, x := range phases {
		if x == p {
			return true
		}
	}
	return false
}

func findAction(actions []Action, kind Kind) *Action {
	for i := range actions {
		if actions[i].Kind == kind {
			return &actions[i]
		}
	}
	return nil
}
