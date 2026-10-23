package backend

import (
	"context"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Ma Sói cho 3i: luật cộng phần ván hiện tại mà mọi người đều xem được trong app
// và topic. Chỉ đọc doc ván, players, feed, km và lựa chọn đề cử/biểu quyết (vốn
// hiện công khai trong topic). Không đọc secret/state, nên vai người còn sống,
// lựa chọn ban đêm và kết quả soi không có đường nào tới model, dù bị dụ.

var botWerewolfDecl = &genai.FunctionDeclaration{
	Name:        "get_werewolf_game",
	Description: "Luật Ma Sói của club (luật RIÊNG chạy theo km, khác Ma Sói thông thường) cộng diễn biến công khai của ván hiện tại: giai đoạn, hạn giờ, ai còn sống, ai đã chết kèm lá bài, ai lên giàn, ai đang đề cử ai, phiếu Treo/Tha đang bấm, km chốt gần nhất, các bản tin gần nhất. Dùng cho MỌI câu hỏi về Ma Sói: luật, vai, giờ giấc, cách bấm, ván đang tới đâu. Không có vai của người còn sống.",
	Parameters:  &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{}},
}

// botRecentNews: số bản tin gần nhất gửi cho model, đủ để kể lại vài ngày.
const botRecentNews = 10

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
	LastKm               map[string]string   `json:"lastKm,omitempty"`
	RecentNews           []BotWerewolfNews   `json:"recentNews,omitempty"`
	Winner               string              `json:"winner,omitempty"`
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
		out.NoGame = "Chưa có ván Ma Sói nào."
	}
	return out, nil
}

// botGame dựng phần ván; nil là chưa có ván. x là ngưỡng km của ván, "X" khi
// chưa có ván.
func (s *GameStore) botGame(ctx context.Context, wall time.Time) (*BotWerewolfGame, string, error) {
	id, _, err := s.CurrentGame(ctx)
	if err != nil || id == "" {
		return nil, "X", err
	}
	g, err := s.gameRef(id).Get(ctx)
	if err != nil {
		return nil, "X", err
	}
	data := g.Data()
	if data["testMode"] == true {
		return nil, "X", nil
	}
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
	game := &BotWerewolfGame{Status: statusLabel(data), Now: vnTime(wall), Players: make([]string, 0, len(players))}
	for _, p := range players {
		game.Players = append(game.Players, p.name)
	}
	if t := timeValue(data["registrationDeadline"]); !t.IsZero() && stringValue(data["status"]) == gameRegistering {
		game.RegistrationDeadline = vnTime(t)
	}
	switch stringValue(data["status"]) {
	case gameRunning, gameEnded:
	default:
		return game, x, nil
	}

	if stringValue(data["status"]) == gameRunning {
		game.Phase = phaseLabelOf(data)
		if d := nextDeadline(data); d != nil {
			game.Deadline = vnTime(*d)
		}
	}
	game.Winner = teamLabels[werewolf.Team(stringValue(data["winner"]))]
	revealed, _ := data["revealed"].(map[string]any)
	alive := map[string]bool{}
	for _, p := range players {
		if p.data["alive"] != false {
			alive[p.uid] = true
			game.Alive = append(game.Alive, p.name)
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
	if nominee := stringValue(data["nominee"]); nominee != "" {
		game.OnTrial = name(nominee)
	}

	if stringValue(data["status"]) == gameRunning && !strings.HasSuffix(stringValue(data["phaseKey"]), "/hunter") {
		round := int(number(data["round"]))
		switch werewolf.Phase(stringValue(data["phase"])) {
		case werewolf.PhaseDay:
			if game.Nominations, err = s.botTally(ctx, g.Ref, round, werewolf.KindNominate, alive, "", name); err != nil {
				return nil, x, err
			}
		case werewolf.PhaseTrial:
			if game.Votes, err = s.botTally(ctx, g.Ref, round, werewolf.KindVote, alive, stringValue(data["nominee"]), name); err != nil {
				return nil, x, err
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

	feed, err := s.loadFeed(ctx, g.Ref, "", index)
	if err != nil {
		return nil, x, err
	}
	for i, item := range feed.Items {
		if i == botRecentNews {
			break
		}
		game.RecentNews = append(game.RecentNews, BotWerewolfNews{At: vnTime(item.At), Title: item.Title, Lines: item.Lines})
	}
	return game, x, nil
}

// botTally đếm lựa chọn đề cử hay biểu quyết đang lưu của vòng, theo đúng cách
// tallyView đếm để hiện trong topic: người chọn còn sống, người được đề cử còn
// sống, người lên giàn không bỏ phiếu. Khoá là tên người được đề cử hoặc
// Treo/Tha, giá trị là tên người chọn.
func (s *GameStore) botTally(ctx context.Context, game *firestore.DocumentRef, round int, kind werewolf.Kind, alive map[string]bool, nominee string, name func(string) string) (map[string][]string, error) {
	docs, err := roundRef(game, round).Collection("actions").Where("kind", "==", string(kind)).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := map[string][]string{}
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
	}
	for _, names := range out {
		sort.Strings(names)
	}
	return out, nil
}
