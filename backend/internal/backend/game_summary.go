package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"unicode"
	"unicode/utf8"

	"cloud.google.com/go/firestore"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// loadSummary đọc mọi bước đã chốt của ván (events/{seq} kind "step") theo thứ
// tự rồi dựng tổng kết. Doc hỏng thì trả lỗi, không bỏ qua: tổng kết thiếu một
// bước là kể sai ván.
func (s *GameStore) loadSummary(ctx context.Context, game *firestore.DocumentRef, st *werewolf.State, name func(string) string, cards map[string]string) (*GameSummary, error) {
	docs, err := game.Collection("events").OrderBy("seq", firestore.Asc).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	var steps []summaryStep
	for _, d := range docs {
		data := d.Data()
		if stringValue(data["kind"]) != "step" {
			continue
		}
		step := summaryStep{PhaseKey: stringValue(data["phaseKey"])}
		if err := json.Unmarshal([]byte(stringValue(data["events"])), &step.Events); err != nil {
			return nil, fmt.Errorf("events/%s: %w", d.Ref.ID, err)
		}
		if raw := stringValue(data["inputs"]); raw != "" {
			if err := json.Unmarshal([]byte(raw), &step.Inputs); err != nil {
				return nil, fmt.Errorf("events/%s inputs: %w", d.Ref.ID, err)
			}
		}
		steps = append(steps, step)
	}
	sum := buildSummary(st, steps, name, cards)
	return &sum, nil
}

// GameSummary là tổng kết ván đã hết, dựng lúc đọc từ events/{seq} (kể cả event
// riêng và lựa chọn ban đêm trong inputs), không ghi gì thêm. Nó lộ vai mọi
// người nên chỉ trả cùng chỗ với allRoles: /me của người trong ván, khi ván đã
// kết thúc. Chữ do backend dựng; app chỉ render.
type GameSummary struct {
	Winner      string            `json:"winner"`
	WinnerLabel string            `json:"winnerLabel"`
	Stats       []GameSummaryStat `json:"stats"`
	// Titles chỉ có khi có người đạt (km > 0, soi ra sói, cứu được người).
	Titles []GameSummaryTitle `json:"titles"`
	Teams  []GameSummaryTeam  `json:"teams"`
	// Replay là diễn lại theo từng đêm, từng ngày, đúng thứ tự xảy ra.
	Replay []GameSummarySection `json:"replay"`
}

type GameSummaryStat struct {
	Label string `json:"label"`
	Value string `json:"value"`
}

// GameSummaryTitle: hoà thì UIDs có nhiều người, Name nối tên bằng dấu phẩy.
type GameSummaryTitle struct {
	Key   string   `json:"key"` // runner, seer, guard
	Label string   `json:"label"`
	UIDs  []string `json:"uids"`
	Name  string   `json:"name"`
	Value string   `json:"value"`
}

type GameSummarySection struct {
	Title string            `json:"title"` // "Đêm 1", "Ngày 1"
	Night bool              `json:"night"`
	Lines []GameSummaryLine `json:"lines"`
}

// GameSummaryLine: Icon là khoá (bite, guard, seer, witch, lovers, survive,
// death, void, nominee, vote, hunter, reveal, winner); app gặp khoá lạ thì vẽ
// chấm mặc định. Tag là nhãn ngắn kèm câu (CỨU, SÓI, DÂN, TREO, THA).
type GameSummaryLine struct {
	Icon string `json:"icon"`
	Text string `json:"text"`
	Tag  string `json:"tag,omitempty"`
}

// GameSummaryTeam là một phe khi lật bài, phe thắng đứng đầu.
type GameSummaryTeam struct {
	Team    string              `json:"team"`
	Label   string              `json:"label"`
	Won     bool                `json:"won"`
	Players []GameSummaryPlayer `json:"players"`
}

// GameSummaryPlayer: Fate là "Sống" hoặc lúc chết ("Đêm 2", "Ngày 3").
type GameSummaryPlayer struct {
	UID        string `json:"uid"`
	Name       string `json:"name"`
	Role       string `json:"role"`
	RoleLabel  string `json:"roleLabel"`
	CardURL    string `json:"cardUrl,omitempty"`
	Alive      bool   `json:"alive"`
	Fate       string `json:"fate"`
	CauseLabel string `json:"causeLabel,omitempty"`
	Km         string `json:"km,omitempty"`
}

// summaryStep là một doc events/{seq} kind "step": phaseKey trước bước, mọi
// event của bước, inputs engine đã đọc.
type summaryStep struct {
	PhaseKey string
	Events   []werewolf.Event
	Inputs   werewolf.Inputs
}

var causeLabels = map[werewolf.Cause]string{
	werewolf.CauseBite: "Bị sói cắn", werewolf.CausePoison: "Trúng bình độc", werewolf.CauseHang: "Bị treo",
	werewolf.CauseShot: "Trúng đạn thợ săn", werewolf.CauseLover: "Chết theo người yêu", werewolf.CauseLeft: "Rời PSC",
}

// summaryMoment là đêm hay ngày mà một bước thuộc về, theo nhãn người chơi thấy.
// Lượt thợ săn mở sau khi treo nằm ở đêm vòng sau trong phaseKey, nhưng xảy ra
// ngay tối hôm treo nên tính vào ngày trước đó.
func summaryMoment(phaseKey string) (title string, night bool, n int) {
	round, phase, hunter := parsePhaseKey(phaseKey)
	switch {
	case hunter && phase == werewolf.PhaseNight:
		return fmt.Sprintf("Ngày %d", round-1), false, round - 1
	case phase == werewolf.PhaseSetup || phase == werewolf.PhaseNight || phase == werewolf.PhaseDawn:
		return fmt.Sprintf("Đêm %d", round), true, round
	default:
		return fmt.Sprintf("Ngày %d", round), false, round
	}
}

// summaryVoidKinds là các lượt riêng mà diễn lại kể khi bị huỷ. Lượt cắn, đề cử
// và phiếu bị huỷ không kể: đã có câu cắn, câu lên giàn và câu mất phiếu.
var summaryVoidKinds = map[werewolf.Kind]string{
	werewolf.KindGuard: "bảo vệ", werewolf.KindSeerPeek: "soi", werewolf.KindWitchSave: "cứu",
	werewolf.KindWitchPoison: "đầu độc", werewolf.KindCupidPair: "ghép đôi", werewolf.KindWolfDark: "đặc quyền Sói",
}

var summaryVoidReasons = map[string]string{
	werewolf.VoidActorDead: "người chọn đã chết", werewolf.VoidTargetDead: "người được chọn đã chết",
	werewolf.VoidNoKm: "chưa đủ km", werewolf.VoidRepeat: "trùng người của đêm trước", werewolf.VoidNoPotion: "đã hết bình",
	werewolf.VoidGameOver: "ván đã hết", werewolf.VoidNoBite: "đêm đó sói không cắn ai",
}

// eventIcons: icon của các câu lấy thẳng từ eventLine (eventItem).
var eventIcons = map[werewolf.EventKind]string{
	werewolf.EventNominee: "nominee", werewolf.EventVoteCut: "vote", werewolf.EventVoteBonus: "vote",
	werewolf.EventVoteResult: "vote", werewolf.EventHunterTurn: "hunter", werewolf.EventRevealed: "reveal",
	werewolf.EventWinner: "winner", werewolf.EventDeath: "death",
}

// eventItem là câu eventLine kèm icon và tag. Event không có trong eventIcons
// trả ok false.
func eventItem(e werewolf.Event, name func(string) string) (GameSummaryLine, bool) {
	icon, ok := eventIcons[e.Kind]
	if !ok {
		return GameSummaryLine{}, false
	}
	text, ok := eventLine(e, name)
	if !ok {
		return GameSummaryLine{}, false
	}
	line := GameSummaryLine{Icon: icon, Text: text}
	switch {
	case e.Kind == werewolf.EventVoteResult && e.Reason != werewolf.ReasonNoTrial:
		line.Tag = "THA"
		if e.Hanged {
			line.Tag = "TREO"
		}
	case e.Kind == werewolf.EventDeath:
		line.Tag = "CHẾT"
	case e.Kind == werewolf.EventNominee && (len(e.Targets) > 0 || e.UID != ""):
		line.Tag = "GIÀN"
	}
	return line, true
}

type summaryBuilder struct {
	st     *werewolf.State
	name   func(string) string
	replay []GameSummarySection
	fate   map[string]string
	cause  map[string]werewolf.Cause
	bitten string // người bị cắn của đêm đang xét
	rounds int    // số vòng thật đã chơi, theo đêm/ngày cuối có bước
	km     map[string]float64
	// hangs: lần làng chốt Treo (kể cả Kẻ ngốc lật bài); wolvesHanged: số sói chết vì treo.
	hangs, wolvesHanged int
	seerFinds           map[string]float64
	guardSaves          map[string]float64
}

func (b *summaryBuilder) add(title string, night bool, line GameSummaryLine) {
	if n := len(b.replay); n == 0 || b.replay[n-1].Title != title {
		b.replay = append(b.replay, GameSummarySection{Title: title, Night: night, Lines: []GameSummaryLine{}})
	}
	last := &b.replay[len(b.replay)-1]
	last.Lines = append(last.Lines, line)
}

// nightChoices kể lựa chọn của bảo vệ, tiên tri, phù thuỷ trong inputs của bước
// rạng sáng: event của engine không ghi người được bảo vệ hay người bị soi.
// Lượt đã bị huỷ ở chính bước đó thì bỏ, phần huỷ do câu void kể.
func (b *summaryBuilder) nightChoices(step summaryStep, title string) {
	voided := map[string]bool{}
	var dark *werewolf.DarkUse // Tàng Hình, Vu Khống chốt cùng bước, đổi kết quả soi
	for _, e := range step.Events {
		switch e.Kind {
		case werewolf.EventVoid:
			voided[e.UID+"/"+string(e.Action)] = true
		case werewolf.EventDark:
			dark = &werewolf.DarkUse{Power: werewolf.DarkPower(e.Reason), Target: e.UID}
		}
	}
	var guard, seer, save []werewolf.Action
	for _, a := range step.Inputs.Actions {
		if a.Clear || voided[a.Actor+"/"+string(a.Kind)] {
			continue
		}
		switch {
		case a.Kind == werewolf.KindGuard && len(a.Targets) > 0 && len(guard) == 0:
			guard = append(guard, a) // engine chỉ lấy lượt bảo vệ hợp lệ đầu tiên
		case a.Kind == werewolf.KindSeerPeek && len(a.Targets) > 0:
			seer = append(seer, a)
		case a.Kind == werewolf.KindWitchSave:
			save = append(save, a)
		}
	}
	for _, a := range guard {
		line := GameSummaryLine{Icon: "guard", Text: fmt.Sprintf("%s %s canh %s.", roleLabels[werewolf.Guard], b.name(a.Actor), b.name(a.Targets[0]))}
		if a.Targets[0] == b.bitten {
			line.Tag = "CỨU"
			b.guardSaves[a.Actor]++
		}
		b.add(title, true, line)
	}
	for _, a := range seer {
		side := "Dân"
		if b.st.PeekWith(a.Targets[0], dark) == werewolf.TeamWolves {
			side = "Sói"
			b.seerFinds[a.Actor]++
		}
		b.add(title, true, GameSummaryLine{Icon: "seer", Text: fmt.Sprintf("%s %s soi %s: %s.", roleLabels[werewolf.Seer], b.name(a.Actor), b.name(a.Targets[0]), side), Tag: strings.ToUpper(side)})
	}
	for _, a := range save {
		if b.bitten == "" {
			continue
		}
		b.add(title, true, GameSummaryLine{Icon: "witch", Text: fmt.Sprintf("%s %s cứu %s.", roleLabels[werewolf.Witch], b.name(a.Actor), b.name(b.bitten)), Tag: "CỨU"})
	}
}

func (b *summaryBuilder) event(e werewolf.Event, title string, night bool) {
	switch e.Kind {
	case werewolf.EventLovers:
		if len(e.Targets) != 2 {
			return
		}
		text := fmt.Sprintf("%s và %s thành cặp đôi.", b.name(e.Targets[0]), b.name(e.Targets[1]))
		if e.Draw {
			text += " Bot ghép thay Cupid."
		}
		b.add(title, night, GameSummaryLine{Icon: "lovers", Text: text})
	case werewolf.EventWolvesTarget:
		b.bitten = e.UID
		text := "Sói không cắn ai."
		if e.UID != "" {
			text = fmt.Sprintf("Sói cắn %s.", b.name(e.UID))
		}
		b.add(title, night, GameSummaryLine{Icon: "bite", Text: text})
	case werewolf.EventDark:
		text := fmt.Sprintf("Sói dùng %s.", darkTexts[werewolf.DarkPower(e.Reason)][0])
		if e.UID != "" {
			text = fmt.Sprintf("Sói dùng %s lên %s.", darkTexts[werewolf.DarkPower(e.Reason)][0], b.name(e.UID))
		}
		b.add(title, night, GameSummaryLine{Icon: "bite", Text: text})
	case werewolf.EventSurvived:
		b.add(title, night, GameSummaryLine{Icon: "survive", Text: fmt.Sprintf("%s là %s, thoát cú cắn đầu tiên.", b.name(e.UID), roleLabels[werewolf.Elder])})
	case werewolf.EventDeath:
		b.fate[e.UID], b.cause[e.UID] = title, e.Cause
		role := b.st.Players[e.UID].Role
		if e.Cause == werewolf.CauseHang && role == werewolf.Wolf {
			b.wolvesHanged++
		}
		b.add(title, night, GameSummaryLine{Icon: "death", Text: fmt.Sprintf("%s chết: %s. Lá bài: %s.", b.name(e.UID), lowerFirst(causeLabels[e.Cause]), roleLabels[role])})
	case werewolf.EventVoid:
		kind, ok := summaryVoidKinds[e.Action]
		if !ok {
			return
		}
		reason := summaryVoidReasons[e.Reason]
		if reason == "" {
			reason = "lựa chọn không hợp lệ"
		}
		b.add(title, night, GameSummaryLine{Icon: "void", Text: fmt.Sprintf("Lượt %s của %s bị huỷ: %s.", kind, b.name(e.UID), reason)})
	default:
		line, ok := eventItem(e, b.name)
		if !ok {
			return
		}
		if line.Tag == "TREO" {
			b.hangs++
		}
		b.add(title, night, line)
	}
}

func lowerFirst(s string) string {
	for i, r := range s {
		return string(unicode.ToLower(r)) + s[i+utf8.RuneLen(r):]
	}
	return s
}

// summaryTitle là danh hiệu cho người có số cao nhất (> 0); hoà thì cả nhóm.
func summaryTitle(key, label string, counts map[string]float64, uids []string, name func(string) string, value func(float64) string) []GameSummaryTitle {
	top := 0.0
	for _, uid := range uids {
		top = max(top, counts[uid])
	}
	if top <= 0 {
		return nil
	}
	t := GameSummaryTitle{Key: key, Label: label, Value: value(top)}
	var names []string
	for _, uid := range uids {
		if counts[uid] == top {
			t.UIDs = append(t.UIDs, uid)
			names = append(names, name(uid))
		}
	}
	t.Name = strings.Join(names, ", ")
	return []GameSummaryTitle{t}
}

func summaryKm(meters float64) string { return formatKm(meters/1000) + " km" }

func buildSummary(st *werewolf.State, steps []summaryStep, name func(string) string, cards map[string]string) GameSummary {
	s := GameSummary{Winner: string(st.Winner), WinnerLabel: teamLabels[st.Winner] + " thắng", Teams: []GameSummaryTeam{}}
	b := &summaryBuilder{st: st, name: name, replay: []GameSummarySection{}, fate: map[string]string{}, cause: map[string]werewolf.Cause{},
		km: map[string]float64{}, seerFinds: map[string]float64{}, guardSaves: map[string]float64{}}
	for _, step := range steps {
		title, night, n := summaryMoment(step.PhaseKey)
		b.rounds = max(b.rounds, n)
		// Km chỉ có ở hai mốc chốt km (readInputs), mỗi khung một lần.
		for uid, m := range step.Inputs.Km {
			b.km[uid] += m
		}
		if _, phase, hunter := parsePhaseKey(step.PhaseKey); phase == werewolf.PhaseDawn && !hunter {
			b.nightChoices(step, title)
		}
		for _, e := range step.Events {
			b.event(e, title, night)
		}
	}
	s.Replay = b.replay
	fate, cause := b.fate, b.cause
	uids := sortedPlayers(st)
	kmOn := !st.Config.KmOff

	dead, village := 0, 0.0
	for _, uid := range uids {
		if !st.Players[uid].Alive {
			dead++
		}
		village += b.km[uid]
	}
	s.Stats = []GameSummaryStat{{Label: "Số vòng", Value: strconv.Itoa(b.rounds)}, {Label: "Người chết", Value: fmt.Sprintf("%d/%d", dead, len(uids))}}
	if kmOn {
		s.Stats = append(s.Stats, GameSummaryStat{Label: "Km cả làng", Value: summaryKm(village)})
	}
	if b.hangs > 0 {
		s.Stats = append(s.Stats, GameSummaryStat{Label: "Treo trúng sói", Value: fmt.Sprintf("%d/%d", b.wolvesHanged, b.hangs)})
	}

	s.Titles = []GameSummaryTitle{}
	if kmOn {
		s.Titles = append(s.Titles, summaryTitle("runner", "Chạy nhiều nhất", b.km, uids, name, summaryKm)...)
	}
	s.Titles = append(s.Titles, summaryTitle("seer", "Tiên tri tìm ra sói", b.seerFinds, uids, name, func(n float64) string { return fmt.Sprintf("%.0f sói", n) })...)
	s.Titles = append(s.Titles, summaryTitle("guard", "Bảo vệ cứu người", b.guardSaves, uids, name, func(n float64) string { return fmt.Sprintf("%.0f lần", n) })...)

	order := []werewolf.Team{st.Winner}
	for _, t := range []werewolf.Team{werewolf.TeamWolves, werewolf.TeamVillage, werewolf.TeamLovers} {
		if t != st.Winner {
			order = append(order, t)
		}
	}
	for _, team := range order {
		out := GameSummaryTeam{Team: string(team), Label: teamLabels[team], Won: team == st.Winner}
		for _, uid := range uids {
			if st.TeamOf(uid) != team {
				continue
			}
			p := st.Players[uid]
			row := GameSummaryPlayer{UID: uid, Name: name(uid), Role: string(p.Role), RoleLabel: roleLabels[p.Role], CardURL: cards[string(p.Role)], Alive: p.Alive, Fate: "Sống"}
			if kmOn {
				row.Km = summaryKm(b.km[uid])
			}
			if !p.Alive {
				row.Fate, row.CauseLabel = fate[uid], causeLabels[cause[uid]]
				if row.Fate == "" {
					row.Fate = "Đã chết" // không thấy event chết của người này
				}
			}
			out.Players = append(out.Players, row)
		}
		if len(out.Players) > 0 {
			s.Teams = append(s.Teams, out)
		}
	}
	return s
}
