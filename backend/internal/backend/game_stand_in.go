package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"slices"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/vlsilver/runnow/backend/internal/werewolf"
	"google.golang.org/genai"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// MyBot chơi thay: người chơi tự bật cho từng ván (players/{uid}.standIn). Tới
// sát giờ đóng của một lượt mà chủ chưa bấm, MyBot của chủ chọn thay. Bot chỉ
// đọc những gì chủ thấy (Me, Detail của chủ), không đọc secret state hay chat
// phe, và ghi qua SubmitAction như mọi kênh khác nên luật ván vẫn kiểm đủ.
const (
	// standInLead: bot đỡ lượt đóng trong khoảng này. Lớn hơn nhịp 10 phút của
	// schedule-tick, nên lượt nào cũng gặp ít nhất một tick trước giờ đóng.
	standInLead     = 15 * time.Minute
	standInPath     = "/tasks/game-stand-in"
	standInReasonMx = 200
)

// standInSkip là các lượt bot không làm thay: bình của Phù thuỷ, đặc quyền
// Sói và phát bắn của Thợ săn chỉ dùng được một lần cả ván; chủ có thể đang để
// dành, hay cố ý không bắn.
var standInSkip = map[werewolf.Kind]bool{
	werewolf.KindWitchSave:   true,
	werewolf.KindWitchPoison: true,
	werewolf.KindWolfDark:    true,
	werewolf.KindHunterShoot: true,
}

var errGameClosed = &HTTPError{Status: http.StatusConflict, Code: "game_closed", Message: "Ván đã kết thúc."}

// SetStandIn bật hay tắt MyBot chơi thay của uid trong ván. Bật chỉ được khi
// ván chưa kết thúc; tắt thì lúc nào cũng được. Điều kiện về MyBot (đã tạo,
// đã đồng ý AI) do route kiểm trước, vì đó là việc của AgentStore.
func (s *GameStore) SetStandIn(ctx context.Context, gameID, uid string, on bool, wall time.Time) error {
	if gameID == "" || len(gameID) > 64 || strings.Contains(gameID, "/") {
		return errGameNotFound
	}
	game := s.gameRef(gameID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := tx.Get(game)
		if status.Code(err) == codes.NotFound {
			return errGameNotFound
		}
		if err != nil {
			return err
		}
		pref := game.Collection("players").Doc(uid)
		p, err := tx.Get(pref)
		if status.Code(err) == codes.NotFound {
			return errNotGamePlayer
		}
		if err != nil {
			return err
		}
		if p.Data()["fake"] == true {
			return errNotGamePlayer
		}
		if on && gameClosed(stringValue(g.Data()["status"])) {
			return errGameClosed
		}
		return tx.Update(pref, []firestore.Update{{Path: "standIn", Value: on}, {Path: "standInAt", Value: wall}})
	})
}

type standInTask struct {
	GameID  string `json:"gameId"`
	UID     string `json:"uid"`
	Kind    string `json:"kind"`
	TurnKey string `json:"turnKey"`
	// PhaseKey chỉ để TaskID khác nhau giữa các phase cùng vòng (đề cử rồi
	// biểu quyết); handler không dùng.
	PhaseKey string `json:"phaseKey"`
}

func standInTaskFor(t standInTask) PublishTask {
	return PublishTask{Queue: QueueBotInbound, HandlerPath: standInPath, Payload: t, TaskID: StableTaskID("game-stand-in", t)}
}

// StandInsDue là các lượt cần MyBot đỡ ngay: người bật standIn, lượt đang mở
// và đóng trong standInLead. Chưa xét người đó đã bấm chưa; handler xét, để
// tick không phải đọc doc hành động của từng người.
func (s *GameStore) StandInsDue(ctx context.Context, gameID string, wall time.Time) ([]standInTask, error) {
	game := s.gameRef(gameID)
	players, err := game.Collection("players").Where("standIn", "==", true).Documents(ctx).GetAll()
	if err != nil || len(players) == 0 {
		return nil, err
	}
	g, err := game.Get(ctx)
	if err != nil {
		return nil, err
	}
	data := g.Data()
	if stringValue(data["status"]) != gameRunning || data["paused"] == true {
		return nil, nil
	}
	st, err := s.loadState(ctx, game)
	if err != nil || st == nil {
		return nil, err
	}
	return standInsDue(st, players, gameNow(data, wall)), nil
}

func standInsDue(st *werewolf.State, players []*firestore.DocumentSnapshot, now time.Time) []standInTask {
	var out []standInTask
	for _, p := range players {
		uid := p.Ref.ID
		if p.Data()["fake"] == true {
			continue
		}
		for _, kind := range st.Available(uid) {
			// Ván luật cũ: lựa chọn bấm sau cùng của phe Sói được tính, bot bấm sát
			// giờ sẽ đè lựa chọn của sói khác.
			if standInSkip[kind] || (kind == werewolf.KindWolfBite && !st.Config.KmTie()) {
				continue
			}
			opens, closes := st.Window(kind)
			if closes.IsZero() || !now.Before(closes) || closes.Sub(now) > standInLead || (!opens.IsZero() && now.Before(opens)) {
				continue
			}
			out = append(out, standInTask{GameID: p.Ref.Parent.Parent.ID, UID: uid, Kind: string(kind), TurnKey: turnKey(st), PhaseKey: st.PhaseKey()})
		}
	}
	return out
}

// enqueueStandIns hẹn các lượt MyBot cần đỡ của ván. TaskID cố định theo lượt,
// nên hai tick cùng thấy một lượt chỉ ra một task.
func (s *Server) enqueueStandIns(ctx context.Context, gameID string, wall time.Time) error {
	publish := s.enqueueTask()
	if publish == nil {
		return nil
	}
	due, err := s.deps.Games.StandInsDue(ctx, gameID, wall)
	if err != nil {
		return err
	}
	for _, t := range due {
		if _, err := publish(ctx, standInTaskFor(t)); err != nil {
			return fmt.Errorf("hẹn MyBot chơi thay %s/%s: %w", t.UID, t.Kind, err)
		}
	}
	return nil
}

// GameStandIn chọn thay người chơi bằng model, theo những gì người đó thấy.
type GameStandIn struct {
	games  *GameStore
	agents *AgentStore
	llm    learnLLM
}

func NewGameStandIn(games *GameStore, agents *AgentStore, llm learnLLM) *GameStandIn {
	return &GameStandIn{games: games, agents: agents, llm: llm}
}

var standInSchema = &genai.Schema{
	Type: genai.TypeObject,
	Properties: map[string]*genai.Schema{
		"targets": {Type: genai.TypeArray, Items: &genai.Schema{Type: genai.TypeString}, Description: "id người được chọn, lấy đúng id trong LỰA CHỌN; rỗng nếu lượt là chọn Treo/Tha"},
		"choice":  {Type: genai.TypeString, Description: "id lựa chọn khi lượt là Treo/Tha; rỗng nếu lượt là chọn người"},
		"reason":  {Type: genai.TypeString, Description: "một câu ngắn nói với chủ vì sao chọn vậy"},
	},
	Required: []string{"targets", "choice", "reason"},
}

// Turn là một lượt chơi thay. Trả kết quả để log: skipped_* là không có gì để
// làm, applied là đã ghi. Lỗi Firestore hay model thì trả lỗi để task chạy lại.
func (b *GameStandIn) Turn(ctx context.Context, t standInTask, wall time.Time) (string, error) {
	game := b.games.gameRef(t.GameID)
	p, err := game.Collection("players").Doc(t.UID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "skipped_not_player", nil
	}
	if err != nil {
		return "", err
	}
	if p.Data()["standIn"] != true {
		return "skipped_off", nil
	}
	// Chủ rút lại đồng ý AI thì dữ liệu ván không được gửi tới model nữa.
	if err := b.agents.requireConsent(ctx, t.UID); errors.Is(err, errAgentDisabled) || errors.Is(err, errAgentConsentRequired) {
		return "skipped_no_consent", nil
	} else if err != nil {
		return "", err
	}
	viewer := GameViewer{UID: t.UID}
	me, err := b.games.Me(ctx, t.GameID, viewer, wall)
	if errors.Is(err, errNotGamePlayer) || errors.Is(err, errGameNotFound) {
		return "skipped_not_player", nil
	}
	if err != nil {
		return "", err
	}
	i := slices.IndexFunc(me.Actions, func(a GameAction) bool { return a.Kind == t.Kind })
	if i < 0 || !me.Actions[i].Enabled || me.Actions[i].Selected != nil {
		return "skipped_not_needed", nil
	}
	action := me.Actions[i]
	detail, err := b.games.Detail(ctx, t.GameID, viewer, wall)
	if err != nil {
		return "", err
	}
	g, err := game.Get(ctx)
	if err != nil {
		return "", err
	}
	// Task tới trễ sang vòng sau cùng kind: bỏ trước khi trả tiền model, chứ
	// không đợi transaction từ chối.
	if "r"+strconv.Itoa(int(number(g.Data()["round"]))) != t.TurnKey {
		return "skipped_stale", nil
	}
	gc, err := gameConfigOf(g.Data())
	if err != nil {
		return "", err
	}
	agent, err := docMap(b.agents.agentRef(t.UID).Get(ctx))
	if err != nil {
		return "", err
	}
	resp, err := b.llm.Learn(withLLMLabel(ctx, "game_stand_in", t.UID), standInSystem(gc, stringValue(agent["persona"])), standInInput(me, action, detail), standInSchema)
	if errors.Is(err, errAgentOverBudget) {
		return "skipped_over_budget", nil
	}
	if err != nil {
		return "", err
	}
	var out struct {
		Targets []string `json:"targets"`
		Choice  string   `json:"choice"`
		Reason  string   `json:"reason"`
	}
	if err := json.Unmarshal([]byte(resp.Text()), &out); err != nil {
		return "", fmt.Errorf("game-stand-in: model trả JSON hỏng: %w", err)
	}
	targets, choice, ok := standInPick(action, out.Targets, out.Choice)
	if !ok {
		// Model chọn ngoài danh sách thì bỏ lượt, không đoán thay model.
		slog.WarnContext(ctx, "game.stand_in_bad_pick", "gameId", t.GameID, "kind", t.Kind, "targets", len(out.Targets))
		return "skipped_bad_pick", nil
	}
	res, err := b.games.SubmitAction(ctx, ActionRequest{
		GameID: t.GameID, UID: t.UID, Kind: werewolf.Kind(t.Kind), Targets: targets, Choice: choice,
		Source: "agent", TurnKey: t.TurnKey, ReceivedAt: wall, OnlyIfEmpty: true,
		AgentReason: cutRunes(strings.TrimSpace(out.Reason), standInReasonMx),
	})
	if err != nil {
		return "", err
	}
	if res.Reject != nil {
		return "skipped_rejected:" + res.Reject.Error(), nil
	}
	if !res.Applied {
		return "skipped_owner_acted", nil
	}
	return "applied", nil
}

// standInPick giữ lựa chọn của model khi nó khớp đúng kiểu và danh sách của lượt.
func standInPick(a GameAction, targets []string, choice string) ([]string, string, bool) {
	has := func(id string) bool {
		return slices.ContainsFunc(a.Options, func(o GameOption) bool { return o.ID == id })
	}
	switch a.Input {
	case "choice":
		return nil, choice, has(choice)
	case "single_target":
		return targets, "", len(targets) == 1 && has(targets[0])
	case "two_targets":
		return targets, "", len(targets) == 2 && targets[0] != targets[1] && has(targets[0]) && has(targets[1])
	}
	return nil, "", false
}

func standInSystem(gc werewolf.Config, persona string) string {
	if persona == "" {
		persona = "bình tĩnh, chơi chắc"
	}
	return "Bạn là MyBot của một người chơi trong ván Ma Sói chạy bộ của app 3i. Chủ đã nhờ bạn chơi thay khi họ chưa kịp bấm trước giờ đóng.\n" +
		"Tính cách chủ đặt cho bạn: " + persona + "\n" +
		"Dặn dò:\n" +
		"- Bạn chỉ biết những gì chủ thấy: vai của chủ, ghi chú riêng, diễn biến công khai. Không bịa thêm.\n" +
		"- Chọn có lợi nhất cho phe của chủ theo LUẬT CỦA VÁN NÀY bên dưới, đừng lấy luật Ma Sói bên ngoài.\n" +
		"- Chỉ dùng id có trong LỰA CHỌN. Lượt chọn người thì điền targets (Ghép đôi cần đúng hai id khác nhau), choice để rỗng. Lượt Treo/Tha thì điền choice, targets để rỗng.\n" +
		"- reason là một câu tiếng Việt nói với chủ vì sao chọn vậy, đúng tính cách trên.\n\n" +
		roomBotRules(gc)
}

func standInInput(me GameMe, a GameAction, d GameDetail) string {
	var sb strings.Builder
	fmt.Fprintf(&sb, "VAI CỦA CHỦ: %s (%s)\n", me.RoleLabel, map[bool]string{true: "còn sống", false: "đã chết"}[me.Alive])
	if me.RoleRules != "" {
		sb.WriteString("Luật của vai: " + me.RoleRules + "\n")
	}
	if len(me.Notes) > 0 {
		sb.WriteString("\nGHI CHÚ RIÊNG CỦA CHỦ:\n")
		for _, n := range me.Notes {
			fmt.Fprintf(&sb, "- Vòng %d: %s\n", n.Round, n.Text)
		}
	}
	sb.WriteString("\nNGƯỜI CHƠI:\n")
	for _, p := range d.Players {
		line := "- " + p.Name
		if !p.Alive {
			line += ", đã chết"
			if p.RevealedRoleLabel != "" {
				line += " (" + p.RevealedRoleLabel + ")"
			}
		}
		if p.LastKm != nil {
			line += fmt.Sprintf(", %s km lần chốt trước", formatKm(*p.LastKm))
		}
		sb.WriteString(line + "\n")
	}
	sb.WriteString("\nDIỄN BIẾN CÔNG KHAI (mới trước):\n")
	if len(d.Feed.Items) == 0 {
		sb.WriteString("(chưa có)\n")
	}
	for _, it := range d.Feed.Items {
		fmt.Fprintf(&sb, "- %s: %s\n", it.Title, strings.Join(it.Lines, " "))
	}
	fmt.Fprintf(&sb, "\nLƯỢT CẦN CHỌN: %s. %s\nLỰA CHỌN:\n", a.Label, a.Help)
	for _, o := range a.Options {
		fmt.Fprintf(&sb, "- id=%s: %s\n", o.ID, o.Label)
	}
	if a.Tally != nil {
		if b, err := json.Marshal(a.Tally); err == nil {
			sb.WriteString("\nKIỂM PHIẾU HIỆN TẠI: " + string(b) + "\n")
		}
	}
	return sb.String()
}

// gameStandIn là chặng của bot service. Payload hỏng thì 204 cho task thôi retry.
func (s *Server) gameStandIn(w http.ResponseWriter, r *http.Request) error {
	var task standInTask
	if err := decodeJSON(r, &task); err != nil || task.GameID == "" || task.UID == "" || task.Kind == "" {
		slog.WarnContext(r.Context(), "game.stand_in_bad_payload")
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if s.deps.StandIn == nil {
		return errors.New("game-stand-in cần Gemini")
	}
	outcome, err := s.deps.StandIn.Turn(r.Context(), task, s.now())
	if err != nil {
		return err
	}
	slog.InfoContext(r.Context(), "game.stand_in", "gameId", task.GameID, "kind", task.Kind, "outcome", outcome)
	if outcome == "applied" {
		s.kickGameFlush(r.Context(), task.GameID)
	}
	return writeJSON(w, 200, map[string]any{"outcome": outcome})
}

// standInRoute: PUT /v1/games/{id}/me/stand-in {on}. Bật cần MyBot đã tạo và
// đã đồng ý gửi dữ liệu tới AI, vì bot sẽ đọc phần riêng của người chơi.
func (s *Server) standInRoute(w http.ResponseWriter, r *http.Request, v GameViewer) error {
	var body struct {
		On *bool `json:"on"`
	}
	if err := decodeJSON(r, &body); err != nil || body.On == nil {
		return invalidRequest()
	}
	if *body.On {
		if s.deps.Agents == nil {
			return errAgentDisabled
		}
		// Chưa tạo MyBot thì báo trước, đừng bắt đồng ý AI rồi mới báo.
		if _, err := s.deps.Agents.agentRef(v.UID).Get(r.Context()); status.Code(err) == codes.NotFound {
			return errAgentNotFound
		} else if err != nil {
			return err
		}
		if err := s.deps.Agents.requireConsent(r.Context(), v.UID); err != nil {
			return err
		}
	}
	if err := s.deps.Games.SetStandIn(r.Context(), r.PathValue("id"), v.UID, *body.On, s.now()); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"standIn": *body.On})
}
