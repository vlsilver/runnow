package werewolf

import (
	"fmt"
	"slices"
)

// DarkPower là đặc quyền của phe Sói. Giá trị chuỗi nằm trong config ván và
// action, đừng đổi.
type DarkPower string

const (
	// DarkCloak: chọn một sói, đêm đó Tiên tri soi sói này ra Dân. Mỗi sói một
	// lần cả ván.
	DarkCloak DarkPower = "cloak"
	// DarkFrame: chọn một người không phải sói, đêm đó Tiên tri soi người này ra Sói.
	DarkFrame DarkPower = "frame"
	// DarkSilent: người bị cắn không chết lúc 10h mà chết ngay sau khi chốt
	// biểu quyết hôm sau. Phù thuỷ vẫn thấy và vẫn cứu được.
	DarkSilent DarkPower = "silent"
	// DarkVote: chọn một sói, phiếu của sói này tính 2 ở các phiên biểu quyết hôm sau.
	DarkVote DarkPower = "vote"
	// DarkPierce: cú cắn đêm đó xuyên qua Bảo vệ. Một lần cả ván.
	DarkPierce DarkPower = "pierce"
)

var darkPowers = []DarkPower{DarkCloak, DarkFrame, DarkSilent, DarkVote, DarkPierce}

// DarkPowers trả mọi đặc quyền theo thứ tự cố định.
func DarkPowers() []DarkPower { return append([]DarkPower(nil), darkPowers...) }

// MaxDarkKm là "km để mở" lớn nhất admin chọn được.
const MaxDarkKm = 10

// DarkUse là đặc quyền phe Sói đã chốt lúc hết pha Đêm. Có tác dụng tới hết
// lần chốt biểu quyết của vòng đó.
type DarkUse struct {
	Power  DarkPower `json:"power"`
	Target string    `json:"target,omitempty"`
}

// VoidNoBite: Cắn Im Lặng hay Đột Biến mà đêm đó sói không cắn ai, nên đặc
// quyền không dùng và không mất lượt.
const VoidNoBite = "no_bite"

func (c Config) validateDark() error {
	for i, p := range c.Dark {
		if !slices.Contains(darkPowers, p) {
			return fmt.Errorf("đặc quyền lạ %q", p)
		}
		if slices.Contains(c.Dark[:i], p) {
			return fmt.Errorf("đặc quyền %q bị bật hai lần", p)
		}
	}
	if c.DarkKm < 0 || c.DarkKm > MaxDarkKm {
		return fmt.Errorf("km để mở đặc quyền phải từ 0 tới %d: %v", MaxDarkKm, c.DarkKm)
	}
	return nil
}

// DarkMeters là km (mét) mỗi sói còn sống cần để phe mở đặc quyền; 0 là ván
// không dùng km. DarkKm = 0 nghĩa là mặc định 1 km.
func (c Config) DarkMeters() float64 {
	switch {
	case c.KmOff:
		return 0
	case c.DarkKm == 0:
		return 1000
	}
	return c.DarkKm * 1000
}

// DarkUnlocked: đêm nay phe Sói dùng được đặc quyền. Ván dùng km thì tổng km
// sói còn sống ở lần chốt 22h phải đủ DarkMeters × số sói còn sống.
func (st *State) DarkUnlocked() bool {
	n := st.aliveWolves()
	if len(st.Config.Dark) == 0 || n == 0 {
		return false
	}
	have, _ := WolfKm(st)
	return have >= st.Config.DarkMeters()*float64(n)
}

// DarkLeft: đặc quyền p còn lượt (chưa xét target). Ván không dùng km thì mỗi
// đặc quyền một lần cả ván; ván dùng km thì Đột Biến một lần, Tàng Hình mỗi
// sói một lần (xét ở darkTargetOK), còn lại mỗi đêm.
func (st *State) DarkLeft(p DarkPower) bool {
	if !slices.Contains(st.Config.Dark, p) {
		return false
	}
	if st.Config.KmOff || p == DarkPierce {
		return st.DarkUsed[p] == 0
	}
	return true
}

// DarkNeedsTarget: đặc quyền p phải chọn đúng một người.
func DarkNeedsTarget(p DarkPower) bool { return p != DarkSilent && p != DarkPierce }

// DarkTargetOK: chọn uid cho đặc quyền p thì hợp lệ, chưa xét km và lượt. App
// dùng để chỉ hiện người chọn được.
func (st *State) DarkTargetOK(p DarkPower, uid string) bool {
	return st.darkTargetOK(p, []string{uid})
}

// darkTargetOK kiểm mục tiêu của đặc quyền. Không trả lý do: Validate và lúc
// chốt cùng gọi, mỗi bên tự đổi sang mã của mình.
func (st *State) darkTargetOK(p DarkPower, targets []string) bool {
	switch p {
	case DarkSilent, DarkPierce:
		return len(targets) == 0
	}
	if len(targets) != 1 || !st.alive(targets[0]) {
		return false
	}
	t := targets[0]
	switch p {
	case DarkCloak:
		return st.role(t) == Wolf && !slices.Contains(st.Cloaked, t)
	case DarkVote:
		return st.role(t) == Wolf
	case DarkFrame:
		return st.role(t) != Wolf
	}
	return false
}

func validateDark(st *State, a Action) error {
	p := DarkPower(a.Choice)
	if !slices.Contains(st.Config.Dark, p) {
		return ErrInvalidTarget
	}
	if !st.DarkUnlocked() {
		return ErrKmInsufficient
	}
	if !st.DarkLeft(p) {
		return ErrAlreadyUsed
	}
	if !st.darkTargetOK(p, a.Targets) {
		if p == DarkCloak && len(a.Targets) == 1 && slices.Contains(st.Cloaked, a.Targets[0]) {
			return ErrAlreadyUsed
		}
		return ErrInvalidTarget
	}
	return nil
}

// PendingDark là đặc quyền sẽ chốt nếu hết pha Đêm ngay lúc này: lựa chọn
// hợp lệ bấm sau cùng của sói còn sống, như cú cắn. nil là không có. Tiên tri
// soi trong pha Đêm thì kết quả theo lựa chọn này, vì lúc đó đặc quyền chưa chốt.
func PendingDark(st *State, actions []Action) *DarkUse {
	if !st.DarkUnlocked() {
		return nil
	}
	var best *Action
	for i := range actions {
		a := actions[i]
		if a.Kind != KindWolfDark || a.Clear || !st.alive(a.Actor) || st.role(a.Actor) != Wolf {
			continue
		}
		p := DarkPower(a.Choice)
		if !st.DarkLeft(p) || !st.darkTargetOK(p, a.Targets) {
			continue
		}
		if best == nil || a.ReceivedAt.After(best.ReceivedAt) ||
			(a.ReceivedAt.Equal(best.ReceivedAt) && a.Actor > best.Actor) {
			best = &a
		}
	}
	if best == nil {
		return nil
	}
	return &DarkUse{Power: DarkPower(best.Choice), Target: best.target()}
}

// PeekWith là kết quả soi khi đặc quyền dark đang có tác dụng: Tàng Hình ra
// Dân, Vu Khống ra Sói, còn lại như Peek.
func (st *State) PeekWith(target string, dark *DarkUse) Team {
	if dark != nil && dark.Target == target {
		switch dark.Power {
		case DarkCloak:
			return TeamVillage
		case DarkFrame:
			return TeamWolves
		}
	}
	return Side(st.role(target))
}

// lockDark (gọi trong lockWolves, sau khi đã có Bitten): chốt đặc quyền của
// đêm và trừ lượt. Cắn Im Lặng, Đột Biến mà không ai bị cắn thì huỷ, không mất lượt.
func (r *resolver) lockDark() {
	r.st.Dark = nil
	var picks []Action
	for _, a := range r.actionsOf(KindWolfDark) {
		picks = append(picks, a)
	}
	use := PendingDark(r.st, picks)
	if use == nil {
		for _, a := range picks {
			reason := VoidInvalid
			if !r.st.DarkUnlocked() {
				reason = VoidNoKm
			}
			r.void(a, reason)
		}
		return
	}
	if (use.Power == DarkSilent || use.Power == DarkPierce) && r.st.Bitten == "" {
		for _, a := range picks {
			r.void(a, VoidNoBite)
		}
		return
	}
	r.st.Dark = use
	if r.st.DarkUsed == nil {
		r.st.DarkUsed = map[DarkPower]int{}
	}
	r.st.DarkUsed[use.Power]++
	if use.Power == DarkCloak {
		r.st.Cloaked = append(r.st.Cloaked, use.Target)
	}
	r.emit(Event{Kind: EventDark, Action: KindWolfDark, Reason: string(use.Power), UID: use.Target})
}

func (st *State) darkIs(p DarkPower) bool { return st.Dark != nil && st.Dark.Power == p }
