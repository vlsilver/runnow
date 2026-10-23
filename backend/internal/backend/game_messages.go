package backend

import (
	"slices"
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
	chatWolves = "wolves" // chat Phe Sói trong app (game_chat.go), không gửi Telegram
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
	tplTally    = "tally"     // group: sửa prompt đề cử/biểu quyết cho khớp lựa chọn vừa đổi
	tplChatPing = "chat_ping" // dm: có tin mới trong chat phe ở app
	tplNight    = "night"     // dm: vào đêm mà không có lượt mới (nightMessages)
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
	start := map[string]any{
		"phaseKey": st.PhaseKey(), "nightAt": st.NightAt.UTC().Format(time.RFC3339), "players": len(uids),
	}
	if wake := aliveRoles(st, werewolf.Cupid); len(wake) > 0 {
		start["wake"] = wake
	}
	msgs := []gameMsg{{ChatKey: chatGroup, Template: tplStart, Data: start}}
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
	if call, wake := gmCall(before, after); call != "" {
		digest["call"] = call
		if len(wake) > 0 {
			digest["wake"] = wake
		}
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
	msgs = append(msgs, promptMessages(before, after)...)
	if after.Phase == werewolf.PhaseNight && before.Phase != werewolf.PhaseNight {
		msgs = append(msgs, nightMessages(after, msgs)...)
	}
	return msgs
}

// Lời quản trò trong bản tin group, như quản trò gọi từng vai ở bàn chơi.
const (
	callNight   = "night"   // 22h: cả làng ngủ, gọi lần lượt các vai đêm
	callWitch   = "witch"   // 0h: sói xong, gọi phù thuỷ
	callMorning = "morning" // 10h: trời sáng, rồi tới bản tin đêm
)

// gmCall trả lời quản trò cho lần chuyển phase này và các vai được gọi. Chỉ gọi
// vai còn người sống: người chết đã lật bài nên group biết vai đó hết người,
// còn bộ vai thì suy ra được từ số người và config. Không xét bình hay km, nên
// phù thuỷ hết bình vẫn được gọi như thường. Phù thuỷ đã chết thì 0h không có
// gì để gọi, bản tin 0h vẫn rỗng và không gửi.
func gmCall(before, after *werewolf.State) (string, []string) {
	switch {
	case after.Phase == werewolf.PhaseNight && before.Phase != werewolf.PhaseNight:
		// Thứ tự gọi là thứ tự chốt đêm (R15): Cupid và sói chốt 0h, rồi bảo vệ
		// đỡ, phù thuỷ cứu hay độc. Tiên tri xem ngay nên đứng cạnh bảo vệ.
		order := []werewolf.Role{werewolf.Wolf, werewolf.Guard, werewolf.Seer, werewolf.Witch}
		if after.Round == 1 {
			order = append([]werewolf.Role{werewolf.Cupid}, order...)
		}
		return callNight, aliveRoles(after, order...)
	case after.Phase == werewolf.PhaseDawn && before.Phase == werewolf.PhaseNight:
		if wake := aliveRoles(after, werewolf.Witch); len(wake) > 0 {
			return callWitch, wake
		}
	case before.Phase == werewolf.PhaseDawn && after.Phase != werewolf.PhaseDawn:
		return callMorning, nil
	}
	return "", nil
}

// aliveRoles trả các vai trong roles (giữ thứ tự) còn ít nhất một người sống.
func aliveRoles(st *werewolf.State, roles ...werewolf.Role) []string {
	var out []string
	for _, role := range roles {
		for _, p := range st.Players {
			if p.Role == role && p.Alive {
				out = append(out, string(role))
				break
			}
		}
	}
	return out
}

// nightMessages: lúc vào đêm, ai còn sống mà chưa có DM nào trong msgs thì
// nhận một tin đêm. Nếu không, chỉ sói, tiên tri, bảo vệ nhận DM lúc 22h, và
// người nhìn màn hình khoá biết được ai có vai. Rạng sáng (0h) thì không làm
// vậy, để không đánh thức cả nhóm: sói và phù thuỷ vẫn nhận DM riêng lúc đó.
func nightMessages(st *werewolf.State, msgs []gameMsg) []gameMsg {
	has := map[string]bool{}
	for _, m := range msgs {
		has[m.ChatKey] = true
	}
	var out []gameMsg
	for _, uid := range sortedPlayers(st) {
		if st.Players[uid].Alive && !has[dmChat(uid)] {
			out = append(out, gameMsg{ChatKey: dmChat(uid), Template: tplNight, Data: map[string]any{
				"phaseKey": st.PhaseKey(), "round": st.Round,
			}})
		}
	}
	return out
}

// promptMessages: một prompt cho mỗi (uid, kind) vừa mở. Kind mở tiếp qua
// phase sau thì giữ prompt cũ, vì nút gắn với vòng (turnKey) nên vẫn bấm được.
// Đề cử và biểu quyết là việc của cả group: một prompt có nút trong topic, đi
// sau bản tin, không DM từng người.
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
				"kind": string(k), "turnKey": turnKey(after),
			}})
		}
	}
	for _, k := range []werewolf.Kind{werewolf.KindNominate, werewolf.KindVote} {
		if openForAnyone(after, k) && (before == nil || !openForAnyone(before, k)) {
			msgs = append(msgs, gameMsg{ChatKey: chatGroup, Template: tplPrompt, Data: map[string]any{
				"kind": string(k), "turnKey": turnKey(after),
			}})
		}
	}
	return msgs
}

func openForAnyone(st *werewolf.State, kind werewolf.Kind) bool {
	for _, uid := range sortedPlayers(st) {
		if slices.Contains(st.Available(uid), kind) {
			return true
		}
	}
	return false
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
