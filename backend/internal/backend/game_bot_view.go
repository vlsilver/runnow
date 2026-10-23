package backend

import (
	"context"
	"errors"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Ma Sói cho 3i, hai tool:
//   - get_werewolf_game: luật cộng phần ván mà mọi người đều xem được trong app
//     và topic. Chỉ đọc doc ván, players, feed, km và lựa chọn đề cử/biểu quyết
//     (vốn hiện công khai trong topic). Không đọc secret/state, nên vai người còn
//     sống, lựa chọn ban đêm và kết quả soi không có đường nào tới model.
//   - get_my_werewolf: chỉ khai báo trong chat riêng; đúng phần /me của người
//     đang nhắn, xác định bằng Telegram user id phía server, không theo lời model.

var botWerewolfDecl = &genai.FunctionDeclaration{
	Name:        "get_werewolf_game",
	Description: "Luật Ma Sói của club (luật RIÊNG chạy theo km, khác Ma Sói thông thường) cộng diễn biến công khai của ván hiện tại: giai đoạn, hạn giờ, ai còn sống, ai đã chết kèm lá bài, ai lên giàn, ai đang đề cử ai, phiếu Treo/Tha đang bấm, ai chưa bấm, km chốt lúc 22h gần nhất (lastKm, quyết định ai dùng được kỹ năng đêm nay), km từ 22h gần nhất tới giờ của từng người (kmSinceLast22h, sẽ chốt lúc kmFrameEnd), dự báo nếu chốt biểu quyết với km hiện tại thì bao nhiêu phiếu được tính và ai mất phiếu (voteForecast), các bản tin của ván. Dùng cho MỌI câu hỏi về Ma Sói. Không có vai của người còn sống.",
	Parameters:  &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{}},
}

var botMyWerewolfDecl = &genai.FunctionDeclaration{
	Name:        "get_my_werewolf",
	Description: "Phần Ma Sói RIÊNG của CHÍNH người đang nhắn riêng với bạn: vai và luật vai, còn sống không, bình của Phù thuỷ, ghi chú chỉ họ biết (đồng đội sói, người yêu, kết quả soi, người bị cắn), các việc đang mở kèm đã chọn gì, giờ mở, hạn, làm được không và vì sao, việc còn phải làm, km của họ từ 22h gần nhất. Dùng khi người này hỏi về vai, việc, lựa chọn, km của chính họ trong Ma Sói.",
	Parameters:  &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{}},
}

const botNoGame = "Chưa có ván Ma Sói nào."

type BotWerewolf struct {
	Rules     string            `json:"rules"`
	VoteRules string            `json:"voteRules"`
	HowToPlay string            `json:"howToPlay"`
	Roles     map[string]string `json:"roles"`
	Game      *BotWerewolfGame  `json:"game,omitempty"`
	NoGame    string            `json:"noGame,omitempty"`
}

type BotWerewolfGame struct {
	Status               string              `json:"status"`
	Now                  string              `json:"now"`
	Phase                string              `json:"phase,omitempty"`
	Deadline             string              `json:"deadline,omitempty"`
	RegistrationDeadline string              `json:"registrationDeadline,omitempty"`
	Players              []string            `json:"players"`
	Alive                []string            `json:"alive,omitempty"`
	Dead                 []string            `json:"dead,omitempty"`
	OnTrial              string              `json:"onTrial,omitempty"`
	Nominations          map[string][]string `json:"nominations,omitempty"`
	Votes                map[string][]string `json:"votes,omitempty"`
	NotChosenYet         []string            `json:"notChosenYet,omitempty"`
	LastKm               map[string]string   `json:"lastKm,omitempty"`
	KmSinceLast22h       map[string]string   `json:"kmSinceLast22h,omitempty"`
	KmFrameEnd           string              `json:"kmFrameEnd,omitempty"`
	VoteForecast         *BotVoteForecast    `json:"voteForecast,omitempty"`
	News                 []BotWerewolfNews   `json:"news,omitempty"`
	Winner               string              `json:"winner,omitempty"`
}

// BotVoteForecast là R30 áp lên km tới giờ: nếu chốt ngay thì ra sao. Km còn
// tăng tới 22h nên đây chỉ là dự báo.
type BotVoteForecast struct {
	Voters       int      `json:"voters"`
	CountedIfNow int      `json:"countedIfNow"`
	LoseVote     []string `json:"loseVote,omitempty"`
	DrawAmong    []string `json:"drawAmong,omitempty"`
	DrawLose     int      `json:"drawLose,omitempty"`
}

type BotWerewolfNews struct {
	At    string   `json:"at"`
	Title string   `json:"title"`
	Lines []string `json:"lines"`
}

// BotWerewolf trả luật và ván gameState/current. Ván thử có người giả và giờ
// đẩy nhanh, không phải ván của group, nên coi như chưa có ván.
func (s *GameStore) BotWerewolf(ctx context.Context, wall time.Time) (BotWerewolf, error) {
	game, x, err := s.botGame(ctx, wall)
	if err != nil {
		return BotWerewolf{}, err
	}
	withX := func(text string) string { return strings.ReplaceAll(text, "X km", x+" km") }
	out := BotWerewolf{Rules: gameRulesText, VoteRules: withX(botVoteRulesText), HowToPlay: botHowToPlayText, Roles: map[string]string{}, Game: game}
	for role, rule := range roleRules {
		out.Roles[roleLabels[role]] = withX(rule)
	}
	if game == nil {
		out.NoGame = botNoGame
	}
	return out, nil
}

// botCurrentGame là ván gameState/current nếu có và không phải ván thử.
func (s *GameStore) botCurrentGame(ctx context.Context) (*firestore.DocumentSnapshot, error) {
	id, _, err := s.CurrentGame(ctx)
	if err != nil || id == "" {
		return nil, err
	}
	g, err := s.gameRef(id).Get(ctx)
	if err != nil {
		return nil, err
	}
	if g.Data()["testMode"] == true {
		return nil, nil
	}
	return g, nil
}

// botGame dựng phần ván; nil là chưa có ván. x là ngưỡng km của ván, "X" khi
// chưa có ván.
func (s *GameStore) botGame(ctx context.Context, wall time.Time) (*BotWerewolfGame, string, error) {
	g, err := s.botCurrentGame(ctx)
	if err != nil || g == nil {
		return nil, "X", err
	}
	data := g.Data()
	cfg, err := gameConfigOf(data)
	if err != nil {
		return nil, "X", err
	}
	x := formatKm(kmPerUnit(cfg))

	players, err := s.loadPlayers(ctx, g.Ref)
	if err != nil {
		return nil, x, err
	}
	index := playerIndex(players)
	name := func(uid string) string { return playerName(index, uid) }
	names := func(uids []string) []string {
		out := make([]string, len(uids))
		for i, uid := range uids {
			out[i] = name(uid)
		}
		return out
	}
	game := &BotWerewolfGame{Status: statusLabel(data), Now: vnTime(wall), Players: make([]string, 0, len(players))}
	for _, p := range players {
		game.Players = append(game.Players, p.name)
	}
	if t := timeValue(data["registrationDeadline"]); !t.IsZero() && stringValue(data["status"]) == gameRegistering {
		game.RegistrationDeadline = vnTime(t)
	}
	running := stringValue(data["status"]) == gameRunning
	if !running && stringValue(data["status"]) != gameEnded {
		return game, x, nil
	}

	if running {
		game.Phase = phaseLabelOf(data)
		if d := nextDeadline(data); d != nil {
			game.Deadline = vnTime(*d)
		}
	}
	game.Winner = teamLabels[werewolf.Team(stringValue(data["winner"]))]
	revealed, _ := data["revealed"].(map[string]any)
	alive := map[string]bool{}
	var aliveUIDs []string
	for _, p := range players {
		if p.data["alive"] != false {
			alive[p.uid] = true
			aliveUIDs = append(aliveUIDs, p.uid)
			continue
		}
		dead := p.name
		if role := roleLabels[werewolf.Role(stringValue(revealed[p.uid]))]; role != "" {
			dead += ": " + role
		}
		if n := int(number(p.data["deathRound"])); n > 0 {
			dead += ", chết vòng " + itoa(n)
		}
		game.Dead = append(game.Dead, dead)
	}
	game.Alive = names(aliveUIDs)
	nominee := stringValue(data["nominee"])
	if nominee != "" {
		game.OnTrial = name(nominee)
	}
	phase := werewolf.Phase(stringValue(data["phase"]))

	if running && !strings.HasSuffix(stringValue(data["phaseKey"]), "/hunter") && (phase == werewolf.PhaseDay || phase == werewolf.PhaseTrial) {
		kind := werewolf.KindNominate
		if phase == werewolf.PhaseTrial {
			kind = werewolf.KindVote
		}
		tally, chosen, err := s.botTally(ctx, g.Ref, int(number(data["round"])), kind, alive, nominee, name)
		if err != nil {
			return nil, x, err
		}
		if kind == werewolf.KindNominate {
			game.Nominations = tally
		} else {
			game.Votes = tally
		}
		for _, uid := range aliveUIDs {
			if !chosen[uid] && !(kind == werewolf.KindVote && uid == nominee) {
				game.NotChosenYet = append(game.NotChosenYet, name(uid))
			}
		}
	}

	km, err := s.lastKm(ctx, g.Ref, data, players)
	if err != nil {
		return nil, x, err
	}
	if len(km) > 0 {
		game.LastKm = map[string]string{}
		for uid, meters := range km {
			game.LastKm[name(uid)] = formatKm(meters/1000) + " km"
		}
	}

	if running {
		frameEnd := nextKmFrameEnd(wall)
		game.KmFrameEnd = vnTime(frameEnd)
		live := map[string]float64{}
		game.KmSinceLast22h = map[string]string{}
		for _, uid := range aliveUIDs {
			fk, err := s.frameKm(ctx, uid, frameEnd)
			if err != nil {
				return nil, x, err
			}
			live[uid] = fk.Meters
			game.KmSinceLast22h[name(uid)] = formatKm(fk.Meters/1000) + " km"
		}
		if phase == werewolf.PhaseTrial && alive[nominee] {
			var voters []string
			for _, uid := range aliveUIDs {
				if uid != nominee {
					voters = append(voters, uid)
				}
			}
			plan := werewolf.PlanVoteCut(voters, live, cfg)
			game.VoteForecast = &BotVoteForecast{Voters: len(voters), CountedIfNow: plan.Allowed, LoseVote: names(plan.Sure)}
			if plan.Need == len(plan.Tied) {
				game.VoteForecast.LoseVote = append(game.VoteForecast.LoseVote, names(plan.Tied)...)
			} else if plan.Need > 0 {
				game.VoteForecast.DrawAmong, game.VoteForecast.DrawLose = names(plan.Tied), plan.Need
			}
		}
	}

	feed, err := s.loadFeed(ctx, g.Ref, "", index)
	if err != nil {
		return nil, x, err
	}
	for _, item := range feed.Items {
		game.News = append(game.News, BotWerewolfNews{At: vnTime(item.At), Title: item.Title, Lines: item.Lines})
	}
	return game, x, nil
}

// nextKmFrameEnd là mốc chốt km 22:00 VN kế tiếp sau wall.
func nextKmFrameEnd(wall time.Time) time.Time {
	local := wall.In(vietnam)
	end := time.Date(local.Year(), local.Month(), local.Day(), 22, 0, 0, 0, vietnam)
	if !local.Before(end) {
		end = end.AddDate(0, 0, 1)
	}
	return end
}

// botTally đếm lựa chọn đề cử hay biểu quyết đang lưu của vòng, theo đúng cách
// tallyView đếm để hiện trong topic: người chọn còn sống, người được đề cử còn
// sống, người lên giàn không bỏ phiếu. Khoá là tên người được đề cử hoặc
// Treo/Tha, giá trị là tên người chọn; chosen là uid những người đã được đếm.
func (s *GameStore) botTally(ctx context.Context, game *firestore.DocumentRef, round int, kind werewolf.Kind, alive map[string]bool, nominee string, name func(string) string) (map[string][]string, map[string]bool, error) {
	docs, err := roundRef(game, round).Collection("actions").Where("kind", "==", string(kind)).Documents(ctx).GetAll()
	if err != nil {
		return nil, nil, err
	}
	out, chosen := map[string][]string{}, map[string]bool{}
	for _, d := range docs {
		a, ok := decodeAction(d.Data())
		if !ok || !alive[a.Actor] {
			continue
		}
		key := choiceLabels[a.Choice]
		if kind == werewolf.KindNominate {
			if len(a.Targets) != 1 || !alive[a.Targets[0]] {
				continue
			}
			key = name(a.Targets[0])
		} else if a.Actor == nominee || key == "" {
			continue
		}
		out[key] = append(out[key], name(a.Actor))
		chosen[a.Actor] = true
	}
	for _, names := range out {
		sort.Strings(names)
	}
	return out, chosen, nil
}

// ---- Phần riêng của người đang nhắn ----

type BotMyWerewolf struct {
	NotPlaying     string        `json:"notPlaying,omitempty"`
	Role           string        `json:"role,omitempty"`
	RoleRules      string        `json:"roleRules,omitempty"`
	Alive          bool          `json:"alive"`
	Potions        *GamePotions  `json:"potions,omitempty"`
	Notes          []string      `json:"notes,omitempty"`
	TeamChats      []string      `json:"teamChats,omitempty"`
	Actions        []BotMyAction `json:"actions,omitempty"`
	Todo           []string      `json:"todo,omitempty"`
	KmSinceLast22h string        `json:"kmSinceLast22h,omitempty"`
	KmPerUnit      string        `json:"kmPerUnit,omitempty"`
	KmFrameEnd     string        `json:"kmFrameEnd,omitempty"`
	AllRoles       []string      `json:"allRoles,omitempty"`
}

type BotMyAction struct {
	Label          string `json:"label"`
	Help           string `json:"help"`
	Opens          string `json:"opens,omitempty"`
	Closes         string `json:"closes,omitempty"`
	Enabled        bool   `json:"enabled"`
	DisabledReason string `json:"disabledReason,omitempty"`
	Selected       string `json:"selected,omitempty"`
}

// BotMyWerewolf trả /me của người có Telegram id tg. Người đó phải liên kết hai
// chiều (tgLinks/{tg} trỏ tới uid, telegramLinks/{uid} trỏ lại tg), như lúc bấm nút.
func (s *GameStore) BotMyWerewolf(ctx context.Context, tg string, wall time.Time) (BotMyWerewolf, error) {
	if tg == "" {
		return BotMyWerewolf{NotPlaying: "Không biết ai đang hỏi."}, nil
	}
	link, err := ctxGetter(ctx)(s.db.Collection("tgLinks").Doc(tg))
	if err != nil {
		return BotMyWerewolf{}, err
	}
	uid := ""
	if link.Exists() {
		uid = stringValue(link.Data()["uid"])
	}
	if uid != "" {
		back, err := s.readLink(ctxGetter(ctx), uid)
		if err != nil {
			return BotMyWerewolf{}, err
		}
		if !back.linked || tgIDString(back.tgUserID) != tg {
			uid = ""
		}
	}
	if uid == "" {
		return BotMyWerewolf{NotPlaying: "Telegram này chưa liên kết với app 3i Run."}, nil
	}
	g, err := s.botCurrentGame(ctx)
	if err != nil {
		return BotMyWerewolf{}, err
	}
	if g == nil {
		return BotMyWerewolf{NotPlaying: botNoGame}, nil
	}
	me, err := s.Me(ctx, g.Ref.ID, GameViewer{UID: uid}, wall)
	if errors.Is(err, errNotGamePlayer) || errors.Is(err, errGameNotFound) {
		return BotMyWerewolf{NotPlaying: "Người này không chơi ván hiện tại."}, nil
	}
	if err != nil {
		return BotMyWerewolf{}, err
	}
	players, err := s.loadPlayers(ctx, g.Ref)
	if err != nil {
		return BotMyWerewolf{}, err
	}
	index := playerIndex(players)

	out := BotMyWerewolf{Role: me.RoleLabel, RoleRules: me.RoleRules, Alive: me.Alive, Potions: me.Potions}
	if me.Role == "" {
		out.NotPlaying = "Ván chưa chia bài."
		return out, nil
	}
	for _, n := range me.Notes {
		out.Notes = append(out.Notes, "Vòng "+itoa(n.Round)+": "+n.Text)
	}
	for _, c := range me.Chats {
		out.TeamChats = append(out.TeamChats, c.Label)
	}
	for _, r := range me.AllRoles {
		out.AllRoles = append(out.AllRoles, r.Name+": "+r.RoleLabel)
	}
	for _, a := range me.Actions {
		ba := BotMyAction{Label: a.Label, Help: a.Help, Enabled: a.Enabled, DisabledReason: a.DisabledReason}
		if a.OpensAt != nil {
			ba.Opens = vnTime(*a.OpensAt)
		}
		if a.ClosesAt != nil {
			ba.Closes = vnTime(*a.ClosesAt)
		}
		if a.Selected != nil {
			var picked []string
			for _, uid := range a.Selected.Targets {
				picked = append(picked, playerName(index, uid))
			}
			if c := choiceLabels[a.Selected.Choice]; c != "" {
				picked = append(picked, c)
			}
			ba.Selected = strings.Join(picked, ", ")
		}
		if a.Enabled && a.Selected == nil {
			out.Todo = append(out.Todo, a.Label)
		}
		out.Actions = append(out.Actions, ba)
	}
	if stringValue(g.Data()["status"]) == gameRunning && me.Alive {
		cfg, err := gameConfigOf(g.Data())
		if err != nil {
			return BotMyWerewolf{}, err
		}
		frameEnd := nextKmFrameEnd(wall)
		fk, err := s.frameKm(ctx, uid, frameEnd)
		if err != nil {
			return BotMyWerewolf{}, err
		}
		out.KmSinceLast22h, out.KmPerUnit, out.KmFrameEnd = formatKm(fk.Meters/1000)+" km", formatKm(kmPerUnit(cfg))+" km", vnTime(frameEnd)
	}
	return out, nil
}
