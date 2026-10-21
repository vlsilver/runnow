package werewolf

// kindOrder là thứ tự cố định khi liệt kê hành động, để DM và /me ổn định.
var kindOrder = []Kind{KindWolfBite, KindSeerPeek, KindGuard, KindWitchSave, KindWitchPoison, KindHunterShoot, KindCupidPair, KindNominate, KindVote}

// Available là các loại hành động đang mở cho uid theo phase, vai, sống/chết,
// lượt thợ săn, vòng của Cupid, bình còn hay hết và người lên giàn. Không xét
// giờ trong phase, km và lựa chọn đã có: các lý do đó Validate trả ra, để app và
// DM hiện nút bị khoá kèm lý do thay vì giấu nút.
func (st *State) Available(uid string) []Kind {
	p := st.Players[uid]
	if p == nil || st.Phase == PhaseEnded || st.Paused {
		return nil
	}
	var out []Kind
	for _, kind := range kindOrder {
		rule := kindRules[kind]
		if rule.role != "" && p.Role != rule.role {
			continue
		}
		if kind == KindHunterShoot {
			if st.Hunter != nil && st.Hunter.UID == uid {
				out = append(out, kind)
			}
			continue
		}
		if !p.Alive || !phaseOpen(rule.phases, st.Phase) {
			continue
		}
		switch kind {
		case KindCupidPair:
			if st.Round > 1 {
				continue
			}
		case KindWitchSave:
			if !st.SavePotion || !witchCanSave(st, uid) {
				continue
			}
		case KindWitchPoison:
			if !st.PoisonPotion {
				continue
			}
		case KindVote:
			if st.Nominee == "" || st.Nominee == uid {
				continue
			}
		}
		out = append(out, kind)
	}
	return out
}

// Kinds trả mọi loại hành động theo thứ tự cố định.
func Kinds() []Kind { return append([]Kind(nil), kindOrder...) }
