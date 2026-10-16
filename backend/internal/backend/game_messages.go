package backend

import (
	"sort"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Tin outbox của Ma Sói ở dạng có cấu trúc. Chữ render lúc gửi (T6), nên sửa
// chữ không đụng tới bước chốt; tin prompt chỉ chở (uid, kind), lúc gửi mới đọc
// lựa chọn đang lưu rồi render (3.4).
type gameMsg struct {
	ChatKey  string
	Template string
	Data     map[string]any
}

const (
	chatGroup  = "group"  // topic Ma Sói của group ván
	chatWolves = "wolves" // group Phe Sói (wolfChatId), cả topic General
)

func dmChat(uid string) string { return "dm:" + uid }

const (
	tplStart    = "start"     // group: ván bắt đầu, đêm 1 lúc nào
	tplCard     = "card"      // dm: lá bài; sói thấy đồng đội
	tplDigest   = "digest"    // group: bản tin gộp của một lần chốt
	tplReminder = "reminder"  // group: nhắc 15h, 21h
	tplPrivate  = "private"   // dm: việc riêng sau một lần chốt (bị huỷ, người yêu, bạn chết…)
	tplPrompt   = "prompt"    // dm: tới lượt một loại hành động
	tplChoice   = "choice"    // dm: sửa prompt cho khớp lựa chọn vừa đổi
	tplTally    = "tally"     // group: sửa tin đếm đề cử/phiếu
	tplWolfPick = "wolf_pick" // wolves: một sói vừa chọn hay bỏ chọn cắn (C2)
)

// publicEvent trả bản công khai của e, hoặc false nếu e chỉ dành cho người
// trong cuộc. Lý do chết không công khai (C3), vai thì lật khi chết.
func publicEvent(e werewolf.Event) (werewolf.Event, bool) {
	switch e.Kind {
	case werewolf.EventDeath:
		e.Cause = ""
		return e, true
	case werewolf.EventNominee, werewolf.EventVoteCut, werewolf.EventVoteResult, werewolf.EventHunterTurn, werewolf.EventWinner:
		return e, true
	}
	return werewolf.Event{}, false
}

func publicEvents(evs []werewolf.Event) []werewolf.Event {
	out := []werewolf.Event{}
	for _, e := range evs {
		if pub, ok := publicEvent(e); ok {
			out = append(out, pub)
		}
	}
	return out
}

// startMessages: lúc Start, group nhận tin mở ván, mỗi người nhận lá bài, ai có
// việc ngay (Cupid) nhận prompt.
func startMessages(st *werewolf.State) []gameMsg {
	uids := sortedPlayers(st)
	msgs := []gameMsg{{ChatKey: chatGroup, Template: tplStart, Data: map[string]any{
		"phaseKey": st.PhaseKey(), "nightAt": st.NightAt.UTC().Format(time.RFC3339), "players": len(uids),
	}}}
	var wolves []string
	for _, uid := range uids {
		if st.Players[uid].Role == werewolf.Wolf {
			wolves = append(wolves, uid)
		}
	}
	for _, uid := range uids {
		data := map[string]any{"role": string(st.Players[uid].Role)}
		if st.Players[uid].Role == werewolf.Wolf {
			data["wolves"] = wolves
		}
		msgs = append(msgs, gameMsg{ChatKey: dmChat(uid), Template: tplCard, Data: data})
	}
	return append(msgs, promptMessages(nil, st)...)
}

// stepMessages chia kết quả một lần Advance thành tin outbox. Mỗi lần chốt ra
// đúng một bản tin group; lần gửi tin nhắc chỉ ra tin nhắc.
func stepMessages(before, after *werewolf.State, evs []werewolf.Event) []gameMsg {
	if len(evs) == 1 && evs[0].Kind == werewolf.EventReminder {
		return []gameMsg{{ChatKey: chatGroup, Template: tplReminder, Data: map[string]any{
			"reason": evs[0].Reason, "phaseKey": before.PhaseKey(),
		}}}
	}
	digest := map[string]any{
		"phaseKey": before.PhaseKey(),
		"round":    after.Round,
		"phase":    string(after.Phase),
		"events":   publicEvents(evs),
	}
	if after.Phase == werewolf.PhaseEnded {
		roles := map[string]string{}
		for uid, p := range after.Players {
			roles[uid] = string(p.Role)
		}
		digest["roles"] = roles
	} else {
		digest["deadline"] = after.Deadline().UTC().Format(time.RFC3339)
	}
	msgs := []gameMsg{{ChatKey: chatGroup, Template: tplDigest, Data: digest}}

	private := map[string][]werewolf.Event{}
	for _, e := range evs {
		switch e.Kind {
		case werewolf.EventVoid, werewolf.EventDeath:
			private[e.UID] = append(private[e.UID], e)
		case werewolf.EventLovers:
			// Mỗi người yêu được biết người kia và vai của người kia (R6).
			for _, uid := range e.Targets {
				partner := loverOf(after, uid)
				e := e
				e.UID, e.Role = partner, after.Players[partner].Role
				private[uid] = append(private[uid], e)
			}
		case werewolf.EventWolvesTarget:
			for _, uid := range sortedPlayers(after) {
				if p := after.Players[uid]; p.Role == werewolf.Wolf && p.Alive {
					private[uid] = append(private[uid], e)
				}
			}
		}
	}
	uids := make([]string, 0, len(private))
	for uid := range private {
		uids = append(uids, uid)
	}
	sort.Strings(uids)
	for _, uid := range uids {
		msgs = append(msgs, gameMsg{ChatKey: dmChat(uid), Template: tplPrivate, Data: map[string]any{
			"phaseKey": before.PhaseKey(), "events": private[uid],
		}})
	}
	return append(msgs, promptMessages(before, after)...)
}

// promptMessages: một prompt cho mỗi (uid, kind) vừa mở. Đề cử và biểu quyết
// là việc của cả group nên đi trong bản tin, không DM từng người.
func promptMessages(before, after *werewolf.State) []gameMsg {
	var msgs []gameMsg
	for _, uid := range sortedPlayers(after) {
		had := map[werewolf.Kind]bool{}
		if before != nil {
			for _, k := range before.Available(uid) {
				had[k] = true
			}
		}
		for _, k := range after.Available(uid) {
			if had[k] || k == werewolf.KindNominate || k == werewolf.KindVote {
				continue
			}
			msgs = append(msgs, gameMsg{ChatKey: dmChat(uid), Template: tplPrompt, Data: map[string]any{
				"kind": string(k), "phaseKey": after.PhaseKey(),
			}})
		}
	}
	return msgs
}

func loverOf(st *werewolf.State, uid string) string {
	if len(st.Lovers) != 2 {
		return ""
	}
	switch uid {
	case st.Lovers[0]:
		return st.Lovers[1]
	case st.Lovers[1]:
		return st.Lovers[0]
	}
	return ""
}

func sortedPlayers(st *werewolf.State) []string {
	uids := make([]string, 0, len(st.Players))
	for uid := range st.Players {
		uids = append(uids, uid)
	}
	sort.Strings(uids)
	return uids
}
