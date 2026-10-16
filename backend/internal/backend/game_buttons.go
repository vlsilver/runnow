package backend

import (
	"context"
	"errors"
	"fmt"
	"html"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Nút Telegram trong DM của Ma Sói (W2). callback_data chỉ chở ván, lượt, loại
// hành động và vị trí người được chọn; người bấm luôn lấy từ from.id qua
// tgLinks (3.2). Telegram giới hạn callback_data 64 byte, nên người được chọn
// ghi bằng vị trí trong danh sách uid đã sort của state (cố định từ lúc chia bài).
//
// Dạng: m1|<gameId>|<phaseKey>|<kind>|<op>|<i.j>, riêng nút xem lá bài là
// m1|<gameId>|v. op: t chọn, c chốt, r chọn lại.

const (
	buttonPrefix   = "m1"
	callbackLimit  = 64
	opPick         = "t"
	opConfirm      = "c"
	opReset        = "r"
	opCard         = "v"
	opCancel       = "k" // nút xác nhận của /cancel trong DM admin
	answerTextSize = 200 // answerCallbackQuery.text tối đa 200 ký tự
)

var kindCodes = map[werewolf.Kind]string{
	werewolf.KindWolfBite: "b", werewolf.KindSeerPeek: "s", werewolf.KindGuard: "g", werewolf.KindWitchSave: "w",
	werewolf.KindWitchPoison: "p", werewolf.KindHunterShoot: "h", werewolf.KindCupidPair: "c",
}

func kindOfCode(code string) (werewolf.Kind, bool) {
	for k, c := range kindCodes {
		if c == code {
			return k, true
		}
	}
	return "", false
}

type gameButton struct {
	GameID   string
	PhaseKey string
	Kind     werewolf.Kind
	Op       string
	Idx      []int
}

func (b gameButton) data() (string, error) {
	var s string
	if b.Op == opCard || b.Op == opCancel {
		s = strings.Join([]string{buttonPrefix, b.GameID, b.Op}, "|")
	} else {
		code, ok := kindCodes[b.Kind]
		if !ok {
			return "", fmt.Errorf("nút cho hành động %q", b.Kind)
		}
		idx := make([]string, len(b.Idx))
		for i, n := range b.Idx {
			idx[i] = strconv.Itoa(n)
		}
		s = strings.Join([]string{buttonPrefix, b.GameID, b.PhaseKey, code, b.Op, strings.Join(idx, ".")}, "|")
	}
	if len(s) > callbackLimit {
		return "", fmt.Errorf("callback_data dài %d byte", len(s))
	}
	return s, nil
}

// parseGameButton: false là không phải nút Ma Sói, hoặc data bị sửa.
func parseGameButton(s string) (gameButton, bool) {
	parts := strings.Split(s, "|")
	if len(parts) < 3 || parts[0] != buttonPrefix || parts[1] == "" {
		return gameButton{}, false
	}
	b := gameButton{GameID: parts[1]}
	if len(parts) == 3 {
		b.Op = parts[2]
		return b, b.Op == opCard || b.Op == opCancel
	}
	if len(parts) != 6 || parts[2] == "" {
		return gameButton{}, false
	}
	kind, ok := kindOfCode(parts[3])
	if !ok {
		return gameButton{}, false
	}
	b.PhaseKey, b.Kind, b.Op = parts[2], kind, parts[4]
	if b.Op != opPick && b.Op != opConfirm && b.Op != opReset {
		return gameButton{}, false
	}
	if parts[5] != "" {
		for _, p := range strings.Split(parts[5], ".") {
			n, err := strconv.Atoi(p)
			if err != nil || n < 0 {
				return gameButton{}, false
			}
			b.Idx = append(b.Idx, n)
		}
	}
	return b, true
}

// targetsNeeded: số người phải chọn cho một lượt bấm.
func targetsNeeded(kind werewolf.Kind) int {
	switch kind {
	case werewolf.KindWitchSave:
		return 0
	case werewolf.KindCupidPair:
		return 2
	}
	return 1
}

func positions(st *werewolf.State) map[string]int {
	out := map[string]int{}
	for i, uid := range sortedPlayers(st) {
		out[uid] = i
	}
	return out
}

func inlineKeyboard(rows [][]map[string]any) map[string]any {
	if rows == nil {
		rows = [][]map[string]any{}
	}
	return map[string]any{"inline_keyboard": rows}
}

// promptView là tin DM của một lượt hành động: chữ cùng nút, vẽ từ GameAction
// mà app cũng dùng (meActions), nên hai kênh luôn khớp nhau. pick là người đã
// chọn dở (Cupid chọn người thứ nhất) hoặc đang chờ chốt; a nil là lượt đã đóng.
// pick chỉ có ở kind phải chốt, mà kind đó đã có lựa chọn thì bị khoá, nên hai
// thứ không đi cùng nhau.
type promptView struct {
	gameID   string
	phaseKey string
	st       *werewolf.State
	kind     werewolf.Kind
	a        *GameAction
	pick     []string
	name     func(uid string) string // tên chưa escape
}

func (v promptView) render() (string, map[string]any, error) {
	text := actionTexts[v.kind]
	if text.label == "" {
		return "", nil, fmt.Errorf("hành động lạ %q", v.kind)
	}
	lines := []string{"<b>Tới lượt bạn: " + text.label + "</b>", html.EscapeString(text.help)}
	names := func(uids []string) string {
		out := make([]string, len(uids))
		for i, uid := range uids {
			out[i] = html.EscapeString(v.name(uid))
		}
		return strings.Join(out, " và ")
	}
	if v.a == nil {
		lines = append(lines, "Lượt này đã đóng.")
		return strings.Join(lines, "\n"), inlineKeyboard(nil), nil
	}
	var selected []string
	hasSel := v.a.Selected != nil
	if hasSel {
		selected = v.a.Selected.Targets
	}
	if v.a.ClosesAt != nil {
		lines = append(lines, "Hạn: "+vnTime(*v.a.ClosesAt)+".")
	}
	used := hasSel && v.kind == werewolf.KindWitchSave
	locked := hasSel && text.confirm != "" // soi, bắn, ghép đôi: chọn rồi không đổi
	// Lượt đã xong thì lý do khoá ("đã dùng lượt này") chỉ nói lại dòng dưới.
	if !v.a.Enabled && v.a.DisabledReason != "" && !used && !locked {
		lines = append(lines, "Chưa bấm được: "+html.EscapeString(v.a.DisabledReason))
	}
	switch {
	case used:
		lines = append(lines, "Bạn đã dùng bình cứu.")
	case locked:
		lines = append(lines, "Đã chốt: "+names(selected)+".")
	case hasSel && len(selected) > 0:
		lines = append(lines, "Đang chọn: "+names(selected)+".")
	}
	need := targetsNeeded(v.kind)
	confirming := len(v.pick) > 0 && len(v.pick) >= need
	switch {
	case confirming:
		lines = append(lines, "Bạn chọn "+names(v.pick)+". "+text.confirm)
	case len(v.pick) > 0:
		lines = append(lines, "Đã chọn "+names(v.pick)+". Chọn thêm một người.")
	}
	if used || locked {
		return strings.Join(lines, "\n"), inlineKeyboard(nil), nil
	}
	lines = append(lines, "Bấm nút bên dưới, hoặc chọn trong app RunNow.")

	pos := positions(v.st)
	idx := func(uids []string) ([]int, error) {
		out := make([]int, len(uids))
		for i, uid := range uids {
			n, ok := pos[uid]
			if !ok {
				return nil, fmt.Errorf("người chơi %q không có trong state", uid)
			}
			out[i] = n
		}
		return out, nil
	}
	button := func(label, op string, uids []string) (map[string]any, error) {
		n, err := idx(uids)
		if err != nil {
			return nil, err
		}
		data, err := gameButton{GameID: v.gameID, PhaseKey: v.phaseKey, Kind: v.kind, Op: op, Idx: n}.data()
		if err != nil {
			return nil, err
		}
		return map[string]any{"text": label, "callback_data": data}, nil
	}
	var rows [][]map[string]any
	if confirming {
		ok, err := button("Chốt", opConfirm, v.pick)
		if err != nil {
			return "", nil, err
		}
		again, err := button("Chọn lại", opReset, nil)
		if err != nil {
			return "", nil, err
		}
		rows = append(rows, []map[string]any{ok, again})
		return strings.Join(lines, "\n"), inlineKeyboard(rows), nil
	}
	if v.kind == werewolf.KindWitchSave {
		b, err := button("Dùng bình cứu", opPick, nil)
		if err != nil {
			return "", nil, err
		}
		return strings.Join(lines, "\n"), inlineKeyboard([][]map[string]any{{b}}), nil
	}
	picked := map[string]bool{}
	for _, uid := range v.pick {
		picked[uid] = true
	}
	chosen := map[string]bool{}
	for _, uid := range selected {
		chosen[uid] = true
	}
	var row []map[string]any
	for _, o := range v.a.Options {
		if picked[o.ID] {
			continue
		}
		label := o.Label
		if chosen[o.ID] {
			label = "✅ " + label
		}
		b, err := button(label, opPick, append(append([]string(nil), v.pick...), o.ID))
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
	if len(v.pick) > 0 {
		again, err := button("Chọn lại", opReset, nil)
		if err != nil {
			return "", nil, err
		}
		rows = append(rows, []map[string]any{again})
	}
	return strings.Join(lines, "\n"), inlineKeyboard(rows), nil
}

func findAction(acts []GameAction, kind werewolf.Kind) *GameAction {
	for i := range acts {
		if acts[i].Kind == string(kind) {
			return &acts[i]
		}
	}
	return nil
}

// ButtonReply là toast trả cho người bấm (answerCallbackQuery).
type ButtonReply struct {
	Text  string
	Alert bool // hiện hộp thoại thay vì toast: kết quả soi, lá bài
	Wrote bool // đã ghi outbox, cần enqueue game-flush
}

var buttonTexts = struct {
	gone, ended, notStarted, notPlayer, stale, badTarget, more, confirm, reset, kept string
}{
	gone:       "Ván này không còn.",
	ended:      "Ván đã kết thúc.",
	notStarted: "Ván chưa chia bài.",
	notPlayer:  "Bạn không ở trong ván này.",
	stale:      "Nút này của lượt trước, không bấm được nữa.",
	badTarget:  "Người này không có trong ván.",
	more:       "Chọn thêm một người.",
	confirm:    "Bấm Chốt để xác nhận.",
	reset:      "Chọn lại nhé.",
	kept:       "Đã nhận lựa chọn mới hơn của bạn.",
}

// PressButton xử lý một cú bấm của uid. Lựa chọn đủ người (và đã chốt nếu là
// lượt chọn một lần) thì đi qua SubmitAction như app; còn lại chỉ ghi một tin
// sửa prompt để vẽ bước kế tiếp. Lỗi Firestore thì trả lỗi để webhook quyết
// 5xx hay 200.
func (s *GameStore) PressButton(ctx context.Context, b gameButton, uid string, updateID int64, received time.Time) (ButtonReply, error) {
	game := s.gameRef(b.GameID)
	g, err := game.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return ButtonReply{Text: buttonTexts.gone}, nil
	}
	if err != nil {
		return ButtonReply{}, err
	}
	st, err := s.loadState(ctx, game)
	if err != nil {
		return ButtonReply{}, err
	}
	if st == nil {
		return ButtonReply{Text: buttonTexts.notStarted}, nil
	}
	if st.Players[uid] == nil {
		return ButtonReply{Text: buttonTexts.notPlayer}, nil
	}
	if b.Op == opCard {
		text, err := s.cardAlert(ctx, game, st, uid)
		return ButtonReply{Text: text, Alert: true}, err
	}
	switch stringValue(g.Data()["status"]) {
	case gameRunning:
	case gameEnded, gameCancelled:
		return ButtonReply{Text: buttonTexts.ended}, nil
	default:
		return ButtonReply{Text: buttonTexts.notStarted}, nil
	}
	if b.PhaseKey != st.PhaseKey() {
		return ButtonReply{Text: buttonTexts.stale}, nil
	}
	order := sortedPlayers(st)
	var targets []string
	for _, n := range b.Idx {
		if n >= len(order) {
			return ButtonReply{Text: buttonTexts.badTarget}, nil
		}
		targets = append(targets, order[n])
	}
	need := targetsNeeded(b.Kind)
	if len(targets) > need {
		return ButtonReply{Text: buttonTexts.badTarget}, nil
	}
	if b.Op == opReset {
		return ButtonReply{Text: buttonTexts.reset, Wrote: true}, s.queuePrompt(ctx, b.GameID, uid, b.Kind, nil)
	}
	if len(targets) < need {
		if b.Op == opConfirm {
			return ButtonReply{Text: buttonTexts.badTarget}, nil
		}
		return ButtonReply{Text: buttonTexts.more, Wrote: true}, s.queuePrompt(ctx, b.GameID, uid, b.Kind, targets)
	}
	if b.Op == opPick && actionTexts[b.Kind].confirm != "" {
		// Kiểm trước khi hỏi chốt, để người bấm biết ngay lựa chọn không được.
		mine, _, err := s.loadMine(ctx, game, st.Round, uid)
		if err != nil {
			return ButtonReply{}, err
		}
		a := werewolf.Action{Kind: b.Kind, Actor: uid, Targets: targets, ReceivedAt: gameNow(g.Data(), received)}
		if err := werewolf.Validate(st, a, mine, a.ReceivedAt); err != nil {
			var reject werewolf.Reject
			if !errors.As(err, &reject) {
				return ButtonReply{}, err
			}
			return ButtonReply{Text: rejectText(b.Kind, err)}, nil
		}
		return ButtonReply{Text: buttonTexts.confirm, Wrote: true}, s.queuePrompt(ctx, b.GameID, uid, b.Kind, targets)
	}
	if s.beforeSubmit != nil {
		s.beforeSubmit()
	}
	res, err := s.SubmitAction(ctx, ActionRequest{
		GameID: b.GameID, UID: uid, Kind: b.Kind, Targets: targets, Source: "telegram",
		TgUpdateID: updateID, PhaseKey: b.PhaseKey, ReceivedAt: received,
	})
	if err != nil {
		return ButtonReply{}, err
	}
	switch {
	case errors.Is(res.Reject, errStaleButton):
		return ButtonReply{Text: buttonTexts.stale}, nil
	case res.Reject != nil:
		return ButtonReply{Text: rejectText(b.Kind, res.Reject)}, nil
	case !res.Applied:
		return ButtonReply{Text: buttonTexts.kept}, nil
	}
	reply := ButtonReply{Wrote: true}
	if b.Kind == werewolf.KindWitchSave {
		reply.Text = "Đã dùng bình cứu."
		return reply, nil
	}
	players, err := s.loadPlayers(ctx, game)
	if err != nil {
		return ButtonReply{}, err
	}
	names := make([]string, len(targets))
	for i, uid := range targets {
		names[i] = playerName(playerIndex(players), uid)
	}
	reply.Text = "Đã chọn " + strings.Join(names, " và ") + "."
	if b.Kind == werewolf.KindSeerPeek {
		side := "Dân"
		if res.Peek == werewolf.TeamWolves {
			side = "Sói"
		}
		reply.Text, reply.Alert = names[0]+" là "+side+".", true
	}
	return reply, nil
}

func playerName(index map[string]gamePlayerInfo, uid string) string {
	if p, ok := index[uid]; ok {
		return p.name
	}
	return "Người chơi"
}

// queuePrompt ghi một tin sửa prompt (uid, kind) kèm người đang chọn dở. Tin
// chỉ tới DM của chính uid, nên pick không lộ cho ai.
func (s *GameStore) queuePrompt(ctx context.Context, gameID, uid string, kind werewolf.Kind, pick []string) error {
	game := s.gameRef(gameID)
	data := map[string]any{"kind": string(kind)}
	if len(pick) > 0 {
		data["pick"] = pick
	}
	msgs := []gameMsg{{ChatKey: dmChat(uid), Template: tplChoice, Data: data}}
	wall := time.Now()
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		w := stepWrite{tx: tx, game: game, gameData: g.Data(), msgs: msgs, chats: chats, wall: wall}
		return w.writeOutbox(int64(number(g.Data()["eventSeq"])))
	})
}

// cardAlert là lá bài gọn trong 200 ký tự cho nút "Xem lại lá bài".
func (s *GameStore) cardAlert(ctx context.Context, game *firestore.DocumentRef, st *werewolf.State, uid string) (string, error) {
	players, err := s.loadPlayers(ctx, game)
	if err != nil {
		return "", err
	}
	index := playerIndex(players)
	me := st.Players[uid]
	text := "Lá bài của bạn: " + roleLabels[me.Role] + "."
	if me.Role == werewolf.Wolf {
		var mates []string
		for _, other := range sortedPlayers(st) {
			if other != uid && st.Players[other].Role == werewolf.Wolf {
				mates = append(mates, playerName(index, other))
			}
		}
		if len(mates) > 0 {
			text += " Đồng đội: " + strings.Join(mates, ", ") + "."
		}
	}
	if !me.Alive {
		text += " Bạn đã chết."
	}
	return truncateUTF16(text, answerTextSize), nil
}

func truncateUTF16(s string, limit int) string {
	if utf16Len(s) <= limit {
		return s
	}
	head, _ := cutUTF16(s, limit-1)
	return head + "…"
}

// currentGameID là ván ở gameState/current; rỗng là chưa có ván nào.
func (s *GameStore) currentGameID(ctx context.Context) (string, error) {
	cur, err := s.db.Collection("gameState").Doc("current").Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return stringValue(cur.Data()["gameId"]), nil
}

// CardText là lá bài của uid trong ván hiện tại, cho /vai trong DM. Rỗng là
// uid không ở trong ván nào đang chạy.
func (s *GameStore) CardText(ctx context.Context, uid string) (string, error) {
	id, err := s.currentGameID(ctx)
	if err != nil || id == "" {
		return "", err
	}
	game := s.gameRef(id)
	g, err := game.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if stringValue(g.Data()["status"]) != gameRunning {
		return "", nil
	}
	st, err := s.loadState(ctx, game)
	if err != nil || st == nil || st.Players[uid] == nil {
		return "", err
	}
	r, err := s.outboxRenderer(ctx, game, g.Data())
	if err != nil {
		return "", err
	}
	role := st.Players[uid].Role
	return r.cardText(uid, role, cardWolves(st, role))
}

// cardWolves: chỉ sói mới thấy danh sách sói, như startMessages.
func cardWolves(st *werewolf.State, role werewolf.Role) []string {
	if role != werewolf.Wolf {
		return nil
	}
	var wolves []string
	for _, uid := range sortedPlayers(st) {
		if st.Players[uid].Role == werewolf.Wolf {
			wolves = append(wolves, uid)
		}
	}
	return wolves
}
