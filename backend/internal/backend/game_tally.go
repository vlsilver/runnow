package backend

import (
	"fmt"
	"html"
	"sort"
	"strings"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// tallyView là prompt đề cử hay biểu quyết trong topic (W2b): ai đang chọn gì
// theo lựa chọn đang lưu, cùng nút chung cho cả group. Nút không lọc theo người
// xem; ai bấm được thì lúc bấm Validate mới kiểm và trả toast lý do.
type tallyView struct {
	gameID, turnKey string
	st              *werewolf.State
	kind            werewolf.Kind
	acts            []werewolf.Action
	players         []gamePlayerInfo // thứ tự đăng ký, như danh sách trong app
	open            bool             // còn trong phase của kind
	notYet          bool             // chưa tới giờ mở (biểu quyết mở lúc 20h)
	opens, closes   time.Time        // giờ thật
}

func (v tallyView) render() (string, map[string]any, error) {
	index := playerIndex(v.players)
	order := map[string]int{}
	for i, p := range v.players {
		order[p.uid] = i
	}
	byOrder := func(uids []string) {
		sort.SliceStable(uids, func(i, j int) bool { return order[uids[i]] < order[uids[j]] })
	}
	name := func(uid string) string { return html.EscapeString(playerName(index, uid)) }
	names := func(uids []string) string {
		out := make([]string, len(uids))
		for i, uid := range uids {
			out[i] = name(uid)
		}
		return strings.Join(out, ", ")
	}
	alive := func(uid string) bool { p := v.st.Players[uid]; return p != nil && p.Alive }

	// Chỉ đếm lựa chọn mà bước chốt còn tính: người chọn còn sống, người được
	// đề cử còn sống, người lên giàn không bỏ phiếu.
	picks := map[string][]string{} // người được đề cử hay Treo/Tha → người chọn
	for _, a := range v.acts {
		if !alive(a.Actor) {
			continue
		}
		key := a.Choice
		if v.kind == werewolf.KindNominate {
			if len(a.Targets) != 1 || !alive(a.Targets[0]) {
				continue
			}
			key = a.Targets[0]
		} else if a.Actor == v.st.Nominee {
			continue
		}
		picks[key] = append(picks[key], a.Actor)
	}
	for _, uids := range picks {
		byOrder(uids)
	}

	var lines []string
	if v.kind == werewolf.KindNominate {
		lines = append(lines, fmt.Sprintf("<b>Đề cử lên giàn, ngày %d</b>", v.st.Round))
	} else {
		lines = append(lines, fmt.Sprintf("<b>Biểu quyết ngày %d: treo hay tha %s</b>", v.st.Round, name(v.st.Nominee)))
	}
	switch {
	case !v.open:
		lines = append(lines, "Đã hết giờ.")
	case v.notYet:
		lines = append(lines, "Mở lúc "+vnTime(v.opens)+", hạn "+vnTime(v.closes)+".")
	default:
		lines = append(lines, "Hạn: "+vnTime(v.closes)+".")
	}
	if v.kind == werewolf.KindNominate {
		targets := make([]string, 0, len(picks))
		for uid := range picks {
			targets = append(targets, uid)
		}
		byOrder(targets)
		sort.SliceStable(targets, func(i, j int) bool { return len(picks[targets[i]]) > len(picks[targets[j]]) })
		for _, uid := range targets {
			lines = append(lines, fmt.Sprintf("<b>%s</b>: %d (%s)", name(uid), len(picks[uid]), names(picks[uid])))
		}
		if len(targets) == 0 {
			lines = append(lines, "Chưa ai được đề cử.")
		}
	} else {
		for _, c := range voteChoices {
			line := fmt.Sprintf("<b>%s</b>: %d", choiceLabels[c], len(picks[c]))
			if len(picks[c]) > 0 {
				line += " (" + names(picks[c]) + ")"
			}
			lines = append(lines, line)
		}
	}
	if !v.open {
		return strings.Join(lines, "\n"), inlineKeyboard(nil), nil
	}
	if v.kind == werewolf.KindNominate {
		lines = append(lines, "Bấm tên để đề cử, bấm người khác để đổi. Chọn trong app RunNow cũng được.")
	} else {
		lines = append(lines, "Bấm Treo hoặc Tha, đổi được tới hạn. Chọn trong app RunNow cũng được.",
			"Số phiếu được tính chốt lúc 22h theo km của mỗi bên.")
	}

	button := func(label string, idx int) (map[string]any, error) {
		data, err := gameButton{GameID: v.gameID, TurnKey: v.turnKey, Kind: v.kind, Op: opPick, Idx: []int{idx}}.data()
		if err != nil {
			return nil, err
		}
		return map[string]any{"text": label, "callback_data": data}, nil
	}
	var rows [][]map[string]any
	if v.kind == werewolf.KindVote {
		var row []map[string]any
		for i, c := range voteChoices {
			b, err := button(choiceLabels[c], i)
			if err != nil {
				return "", nil, err
			}
			row = append(row, b)
		}
		return strings.Join(lines, "\n"), inlineKeyboard([][]map[string]any{row}), nil
	}
	pos := positions(v.st)
	var row []map[string]any
	for _, p := range v.players {
		if !alive(p.uid) {
			continue
		}
		n, ok := pos[p.uid]
		if !ok {
			return "", nil, fmt.Errorf("người chơi %q không có trong state", p.uid)
		}
		b, err := button(p.name, n)
		if err != nil {
			return "", nil, err
		}
		row = append(row, b)
		if len(row) == 2 {
			rows, row = append(rows, row), nil
		}
	}
	if row != nil {
		rows = append(rows, row)
	}
	return strings.Join(lines, "\n"), inlineKeyboard(rows), nil
}
