package backend

import (
	"context"
	"fmt"
	"math"
	"slices"
	"sort"
	"strings"

	"cloud.google.com/go/firestore"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// GameTally là bảng kiểm phiếu của một action đang mở (đề cử, biểu quyết, sói
// bầu cắn): ai chọn gì, phiếu nào được tính, bên nào đang dẫn và vì sao. Chỉ có
// ở ván luật km; phân định giống engine: phiếu, rồi tổng km, rồi bốc thăm.
type GameTally struct {
	Rows []GameTallyRow `json:"rows"`
	// Seats là số lựa chọn thắng: số suất lên giàn với đề cử, 1 với còn lại.
	Seats int `json:"seats"`
	// Reason nói vì sao các hàng Lead dẫn; rỗng khi chưa có phiếu nào.
	Reason string `json:"reason,omitempty"`
	// Note giải thích phiếu bị cắt; rỗng khi không ai mất phiếu.
	Note string `json:"note,omitempty"`
}

type GameTallyRow struct {
	ID     string           `json:"id"`
	Label  string           `json:"label"`
	Votes  int              `json:"votes"`
	Km     float64          `json:"km"`
	Lead   bool             `json:"lead,omitempty"`
	Voters []GameTallyVoter `json:"voters"`
}

// GameTallyVoter: Cut là phiếu không được tính; Weight > 1 là phiếu Top.
type GameTallyVoter struct {
	Name   string  `json:"name"`
	Km     float64 `json:"km"`
	Cut    bool    `json:"cut,omitempty"`
	Weight int     `json:"weight,omitempty"`
}

const (
	tallyMoreVotes = "Nhiều phiếu hơn"
	tallyMoreKm    = "Bằng phiếu · hơn km"
	tallyDraw      = "Bằng phiếu, bằng km · bốc thăm"
)

// attachTallies gắn bảng kiểm phiếu vào các action có bảng. Biểu quyết chốt lúc
// 22h nên dùng km tới giờ (live; ván thử không có thì km chốt gần nhất), còn đề
// cử và cắn chốt bằng km 22h trước (st.Km).
func (s *GameStore) attachTallies(ctx context.Context, game *firestore.DocumentRef, st *werewolf.State, acts []GameAction, players []gamePlayerInfo, live *liveKm) error {
	if !st.Config.KmTie() {
		return nil
	}
	for i := range acts {
		kind := werewolf.Kind(acts[i].Kind)
		if kind != werewolf.KindNominate && kind != werewolf.KindWolfBite && !werewolf.IsVote(kind) {
			continue
		}
		docs, err := roundRef(game, st.Round).Collection("actions").Where("kind", "==", string(kind)).Documents(ctx).GetAll()
		if err != nil {
			return err
		}
		var round []werewolf.Action
		for _, d := range docs {
			if a, ok := decodeAction(d.Data()); ok {
				round = append(round, a)
			}
		}
		km := st.Km
		if werewolf.IsVote(kind) && live != nil {
			km = live.Meters
		}
		acts[i].Tally = actionTally(st, kind, round, km, players)
	}
	return nil
}

// actionTally dựng bảng kiểm phiếu của kind từ các lựa chọn đang lưu của vòng.
// km (mét) là km bước chốt sẽ dùng: km chốt 22h trước với đề cử và cắn, km tới
// giờ với biểu quyết (chốt lúc 22h). nil khi kind không có bảng hoặc ván luật cũ.
func actionTally(st *werewolf.State, kind werewolf.Kind, acts []werewolf.Action, km map[string]float64, players []gamePlayerInfo) *GameTally {
	if !st.Config.KmTie() {
		return nil
	}
	alive := func(uid string) bool { p := st.Players[uid]; return p != nil && p.Alive }
	index := playerIndex(players)
	order := map[string]int{}
	for i, p := range players {
		order[p.uid] = i
	}
	names := func(uids []string) string { return tallyNames(index, uids) }
	t := &GameTally{Seats: 1}
	var cut map[string]bool
	weight := map[string]int{}
	var rows []GameTallyRow
	var pick func(a werewolf.Action) string
	switch {
	case kind == werewolf.KindNominate:
		t.Seats = st.Config.NomineeSeats()
		pick = func(a werewolf.Action) string {
			if len(a.Targets) != 1 || !alive(a.Targets[0]) {
				return ""
			}
			return a.Targets[0]
		}
	case kind == werewolf.KindWolfBite:
		plan := werewolf.WolfVotePlan(st)
		cut, t.Note = tallyCut(plan, names, "", cutLead(st.Config, st.Config.SkillMeters(werewolf.Wolf)))
		pick = func(a werewolf.Action) string {
			if st.Players[a.Actor].Role != werewolf.Wolf || len(a.Targets) != 1 {
				return ""
			}
			return a.Targets[0]
		}
	case werewolf.IsVote(kind):
		nominee := st.NomineeOf(kind)
		if nominee == "" {
			return nil
		}
		var voters []string
		var total float64
		for _, uid := range sortedPlayers(st) {
			if alive(uid) && uid != nominee && st.CanVote(uid) {
				voters = append(voters, uid)
				total += km[uid]
			}
		}
		if mode := st.Config.VoteMode(); mode == werewolf.VoteCut || mode == werewolf.VoteSolo {
			plan := werewolf.PlanVoteCut(voters, km, st.Config)
			unit := formatKm(kmPerUnit(st.Config))
			head := ""
			if mode == werewolf.VoteCut && plan.Allowed < len(voters) {
				head = fmt.Sprintf("Nhóm chạy %s km, %s km một phiếu: đủ %d phiếu cho %d người.", formatKm(math.Floor(total/100)/10), unit, plan.Allowed, len(voters))
			}
			cut, t.Note = tallyCut(plan, names, head, cutLead(st.Config, kmPerUnit(st.Config)*1000))
			if w := st.Config.TopWeight; w > 0 {
				var top string
				weight, top = tallyTop(st, voters, cut, km, w, names)
				t.Note = strings.TrimSpace(t.Note + " " + top)
			}
		}
		for _, c := range voteChoices {
			rows = append(rows, GameTallyRow{ID: c, Label: choiceLabels[c], Voters: []GameTallyVoter{}})
		}
		pick = func(a werewolf.Action) string {
			if a.Actor == nominee {
				return ""
			}
			return a.Choice
		}
	default:
		return nil
	}

	byID := map[string]*GameTallyRow{}
	for i := range rows {
		byID[rows[i].ID] = &rows[i]
	}
	acts = slices.Clone(acts)
	sort.SliceStable(acts, func(i, j int) bool { return order[acts[i].Actor] < order[acts[j].Actor] })
	for _, a := range acts {
		if a.Kind != kind || a.Clear || !alive(a.Actor) {
			continue
		}
		id := pick(a)
		if id == "" {
			continue
		}
		row := byID[id]
		if row == nil {
			rows = append(rows, GameTallyRow{ID: id, Label: playerName(index, id), Voters: []GameTallyVoter{}})
			row = &rows[len(rows)-1]
			byID = map[string]*GameTallyRow{}
			for i := range rows {
				byID[rows[i].ID] = &rows[i]
			}
		}
		v := GameTallyVoter{Name: playerName(index, a.Actor), Km: km[a.Actor] / 1000, Cut: cut[a.Actor], Weight: weight[a.Actor]}
		row.Voters = append(row.Voters, v)
		if !v.Cut {
			row.Votes += max(1, v.Weight)
			row.Km += km[a.Actor]
		}
	}
	for i := range rows {
		rows[i].Km /= 1000
	}
	t.Rows = rows
	t.Reason = tallyLead(t, kind)
	return t
}

// tallyCut là tập người mất phiếu theo plan và câu giải thích. Bằng km ở ngưỡng
// mà chưa biết ai bị bốc thăm thì không đánh dấu ai, câu nói rõ là bốc thăm.
func tallyCut(plan werewolf.VoteCutPlan, names func([]string) string, head, lead string) (map[string]bool, string) {
	cut := map[string]bool{}
	sure := plan.Sure
	if plan.Need == len(plan.Tied) {
		sure = append(slices.Clone(sure), plan.Tied...)
	}
	for _, uid := range sure {
		cut[uid] = true
	}
	var parts []string
	if head != "" {
		parts = append(parts, head)
	}
	if len(sure) > 0 {
		parts = append(parts, lead+names(sure)+".")
	}
	if plan.Need > 0 && plan.Need < len(plan.Tied) {
		parts = append(parts, fmt.Sprintf("Bốc thăm %d người mất phiếu trong: %s.", plan.Need, names(plan.Tied)))
	}
	return cut, strings.Join(parts, " ")
}

// cutLead mở câu liệt kê người mất phiếu, theo chế độ; unit theo mét.
func cutLead(cfg werewolf.Config, unit float64) string {
	if cfg.VoteMode() == werewolf.VoteSolo {
		return "Chưa đủ " + formatKm(unit/1000) + " km nên mất phiếu: "
	}
	return "Mất phiếu vì ít km nhất: "
}

// tallyTop: người được TopWeight phiếu, xét trên người còn phiếu như engine
// (countVotes, PlanVoteBonus), và câu giải thích. Bằng km ở suất cuối thì chưa
// ai được đánh dấu, câu nói là bốc thăm.
func tallyTop(st *werewolf.State, voters []string, cut map[string]bool, km map[string]float64, w int, names func([]string) string) (map[string]int, string) {
	var kept []string
	for _, uid := range voters {
		if !cut[uid] {
			kept = append(kept, uid)
		}
	}
	wolves := 0
	for _, p := range st.Players {
		if p.Alive && p.Role == werewolf.Wolf {
			wolves++
		}
	}
	plan := werewolf.PlanVoteBonus(kept, km, st.Config, wolves)
	top := plan.Sure
	if plan.Need == len(plan.Tied) {
		top = append(slices.Clone(top), plan.Tied...)
	}
	weight := map[string]int{}
	for _, uid := range top {
		weight[uid] = w
	}
	var parts []string
	if len(top) > 0 {
		parts = append(parts, fmt.Sprintf("Top %d được %d phiếu: %s.", plan.Top, w, names(top)))
	}
	if plan.Need > 0 && plan.Need < len(plan.Tied) {
		parts = append(parts, fmt.Sprintf("Bốc thăm %d suất Top trong: %s.", plan.Need, names(plan.Tied)))
	}
	return weight, strings.Join(parts, " ")
}

func tallyNames(index map[string]gamePlayerInfo, uids []string) string {
	out := make([]string, len(uids))
	for i, uid := range uids {
		out[i] = playerName(index, uid)
	}
	return strings.Join(out, ", ")
}

// tallyLead đánh dấu các hàng đang dẫn và trả lý do, theo cách engine phân
// định (rankVotes, countVotes): phiếu, rồi tổng km, rồi bốc thăm.
func tallyLead(t *GameTally, kind werewolf.Kind) string {
	rows := t.Rows
	if werewolf.IsVote(kind) {
		hang, spare := &rows[0], &rows[1]
		switch {
		case hang.Votes == 0 && spare.Votes == 0:
			return ""
		case hang.Votes != spare.Votes:
			lead := hang
			if spare.Votes > hang.Votes {
				lead = spare
			}
			lead.Lead = true
			return tallyMoreVotes
		case hang.Km != spare.Km:
			lead := hang
			if spare.Km > hang.Km {
				lead = spare
			}
			lead.Lead = true
			return tallyMoreKm
		}
		return tallyDraw
	}
	sort.SliceStable(rows, func(i, j int) bool {
		if rows[i].Votes != rows[j].Votes {
			return rows[i].Votes > rows[j].Votes
		}
		return rows[i].Km > rows[j].Km
	})
	var live []*GameTallyRow
	for i := range rows {
		if rows[i].Votes > 0 {
			live = append(live, &rows[i])
		}
	}
	if len(live) == 0 {
		return ""
	}
	n := min(t.Seats, len(live))
	edge, next := live[n-1], (*GameTallyRow)(nil)
	if n < len(live) {
		next = live[n]
	}
	reason := tallyMoreVotes
	switch {
	case next == nil || next.Votes < edge.Votes:
	case next.Km < edge.Km:
		reason = tallyMoreKm
	default:
		// Bằng cả phiếu lẫn km ở suất cuối: chưa biết ai, không đánh dấu suất đó.
		for _, r := range live[:n] {
			if r.Votes > edge.Votes || r.Km > edge.Km {
				r.Lead = true
			}
		}
		return tallyDraw
	}
	for _, r := range live[:n] {
		r.Lead = true
	}
	return reason
}
