package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"slices"
	"strings"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// ActionRequest là một lựa chọn từ app hoặc nút Telegram (3.2). ReceivedAt là
// giờ server lúc handler bắt đầu, lấy ngoài transaction: transaction có chạy lại
// thì thứ tự bấm vẫn giữ nguyên.
type ActionRequest struct {
	GameID     string
	UID        string // người hành động; với Telegram là uid tra từ from.id, không lấy từ callback_data
	Kind       werewolf.Kind
	Targets    []string
	Choice     string
	Clear      bool
	Source     string // app | telegram | admin
	TgUpdateID int64  // update_id của Telegram, 0 nếu từ app
	// TurnKey khác rỗng: nút Telegram vẽ cho vòng này (turnKey). Ván đã sang vòng
	// khác thì từ chối (errStaleButton), kể cả khi kind cùng tên đang mở ở vòng mới.
	TurnKey    string
	ReceivedAt time.Time
	// ActAs: admin bấm thay người chơi giả của ván thử (X1). Ván thật hoặc người
	// chơi thật thì bị từ chối, nên admin không bấm thay được người nào đang chơi.
	ActAs bool
}

// ActionResult: Reject khác nil là luật từ chối (trả 409/422, không phải 5xx).
// Applied=false mà Reject nil là request cũ bị bỏ qua (Telegram gửi lại, hoặc
// thua bản đang lưu khi so receivedAt); Current là lựa chọn đang được lưu.
type ActionResult struct {
	Applied bool
	Reject  error
	Current *werewolf.Action
	Peek    werewolf.Team // kết quả soi khi Kind là seer_peek (R2)
}

// errGameNotRunning: ván chưa Start hoặc đã kết thúc thì không nhận hành động.
var errGameNotRunning = werewolf.ErrPhaseClosed

var errStaleButton = errors.New("stale_button")

func actionRef(game *firestore.DocumentRef, round int, uid string, kind werewolf.Kind) *firestore.DocumentRef {
	return roundRef(game, round).Collection("actions").Doc(uid + "_" + string(kind))
}

// SubmitAction kiểm và ghi một hành động trong một transaction. Transaction đọc
// games/{id} và secret/state, mà bước chốt luôn ghi hai doc này, nên một hành
// động sát giờ hoặc vào kịp bước chốt, hoặc chạy lại sau bước chốt và bị từ
// chối vì cửa sổ đã đóng; không bị mất lặng lẽ. Không tăng version của ván: app
// thấy version nhảy lúc 3h sáng là đoán được có vai đêm đang thức.
func (s *GameStore) SubmitAction(ctx context.Context, req ActionRequest) (ActionResult, error) {
	game := s.gameRef(req.GameID)
	var res ActionResult
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		res = ActionResult{}
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		if req.ActAs {
			if g.Data()["testMode"] != true {
				return errNotTestMode
			}
			if !fakeUIDs(g.Data())[req.UID] {
				return errNotFakePlayer
			}
		}
		if stringValue(g.Data()["status"]) != gameRunning {
			res.Reject = errGameNotRunning
			return nil
		}
		// Mọi so sánh giờ dùng giờ ván; ván thật thì đúng bằng ReceivedAt.
		now := gameNow(g.Data(), req.ReceivedAt)
		sec, err := tx.Get(secretRef(game))
		if err != nil {
			return err
		}
		st, err := decodeState(sec.Data())
		if err != nil {
			return err
		}
		if req.TurnKey != "" && req.TurnKey != turnKey(st) {
			res.Reject = errStaleButton
			return nil
		}

		var refs []*firestore.DocumentRef
		for _, kind := range werewolf.Kinds() {
			refs = append(refs, actionRef(game, st.Round, req.UID, kind))
		}
		docs, err := tx.GetAll(refs)
		if err != nil {
			return err
		}
		var mine []werewolf.Action
		var cur map[string]any
		for i, d := range docs {
			if !d.Exists() {
				continue
			}
			if refs[i].ID == req.UID+"_"+string(req.Kind) {
				cur = d.Data()
			}
			if a, ok := decodeAction(d.Data()); ok {
				mine = append(mine, a)
			}
		}

		// Telegram gửi lại update cũ, hoặc hai cú bấm tới lệch thứ tự (webhook
		// mở nhiều kết nối song song): update_id không lớn hơn bản đã lưu thì bỏ.
		lastTg := int64(number(cur["lastTgUpdateId"]))
		if cur != nil && req.TgUpdateID > 0 && req.TgUpdateID <= lastTg {
			res.Current, res.Peek = storedAction(cur)
			return nil
		}
		// Hai kênh cùng ghi một doc: bản có receivedAt muộn hơn thắng.
		if t, ok := cur["receivedAt"].(time.Time); ok && t.After(now) {
			res.Current, res.Peek = storedAction(cur)
			return nil
		}

		a := werewolf.Action{Kind: req.Kind, Actor: req.UID, Targets: req.Targets, Choice: req.Choice, Clear: req.Clear, ReceivedAt: now}
		if err := werewolf.Validate(st, a, mine, now); err != nil {
			var reject werewolf.Reject
			if !errors.As(err, &reject) {
				return err
			}
			res.Reject = err
			return nil
		}

		msgs := withoutFakeDMs(actionMessages(a), g.Data())
		prev, _ := storedAction(cur)
		p, posted := newPick(st, a, prev, req.ReceivedAt)
		if posted {
			msgs = append(msgs, gameMsg{ChatKey: chatGroup, Template: tplPick, Data: p.data()})
		}
		var wolfChat *chatPost
		var pings []gameMsg
		if a.Kind == werewolf.KindWolfBite && chatMembers(st, chatWolves) != nil {
			c, err := readChat(tx, game, chatWolves)
			if err != nil {
				return err
			}
			wolfChat, pings = &c, c.pings(st, chatWolves, a.Actor, g.Data(), req.ReceivedAt)
			msgs = append(msgs, pings...)
		}
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		doc := map[string]any{
			"uid": req.UID, "kind": string(req.Kind), "targets": req.Targets, "choice": req.Choice,
			"cleared": req.Clear, "receivedAt": now, "source": req.Source,
			"lastTgUpdateId": max(lastTg, req.TgUpdateID), "phaseKey": st.PhaseKey(), "updatedAt": req.ReceivedAt,
		}
		if req.Kind == werewolf.KindSeerPeek {
			res.Peek = st.Peek(req.Targets[0])
			doc["peek"] = string(res.Peek)
		}
		// Set ghi đè cả doc, nên voidReason của lựa chọn cũ (nếu có) cũng mất.
		if err := tx.Set(actionRef(game, st.Round, req.UID, req.Kind), doc); err != nil {
			return err
		}
		if wolfChat != nil {
			if err := wolfChat.write(tx, wolfPickMessage(a), "", pings, req.ReceivedAt); err != nil {
				return err
			}
		}
		if posted {
			if err := writePickFeed(tx, game, g.Data(), st, p, now); err != nil {
				return err
			}
		}
		w := stepWrite{tx: tx, game: game, gameData: g.Data(), msgs: msgs, chats: chats, now: now, wall: req.ReceivedAt}
		if err := w.writeOutbox(int64(number(g.Data()["eventSeq"]))); err != nil {
			return err
		}
		res.Applied = true
		if !req.Clear {
			res.Current = &a
		}
		return nil
	})
	return res, err
}

// actionMessages: lựa chọn riêng thì sửa tin DM của người đó; đề cử và biểu
// quyết là công khai nên sửa tin đếm phiếu trong topic (W2b). Các tin này chỉ
// chở (uid, kind), lúc gửi mới đọc lựa chọn đang lưu. Lựa chọn cắn còn vào chat
// Phe Sói trong app (C2), ghi ở SubmitAction.
func actionMessages(a werewolf.Action) []gameMsg {
	kind := map[string]any{"kind": string(a.Kind)}
	if groupKind(a.Kind) {
		return []gameMsg{{ChatKey: chatGroup, Template: tplTally, Data: kind}}
	}
	return []gameMsg{{ChatKey: dmChat(a.Actor), Template: tplChoice, Data: kind}}
}

// pick là một lần đề cử hoặc biểu quyết vừa đổi lựa chọn. Nó thành một tin
// mới trong topic và một dòng trong mục diễn biến của pha ở nhật ký app, nên
// bấm ở app hay ở Telegram thì cả hai nơi đều thấy. Chở snapshot lúc bấm, vì
// lúc outbox gửi thì lựa chọn đang lưu có thể đã đổi tiếp.
type pick struct {
	At      time.Time     `json:"at"`
	UID     string        `json:"uid"`
	Kind    werewolf.Kind `json:"kind"`
	Targets []string      `json:"targets,omitempty"`
	Choice  string        `json:"choice,omitempty"`
	Nominee string        `json:"nominee,omitempty"` // người lên giàn của phiên, khi là phiếu
	Clear   bool          `json:"clear,omitempty"`
}

// newPick trả pick của a. False khi a không phải đề cử hay biểu quyết, hoặc
// không đổi gì so với prev (lựa chọn đang lưu; nil nếu chưa có hay đã rút):
// bấm lại đúng nút cũ thì không đăng thêm tin.
func newPick(st *werewolf.State, a werewolf.Action, prev *werewolf.Action, at time.Time) (pick, bool) {
	if !groupKind(a.Kind) {
		return pick{}, false
	}
	if a.Clear && prev == nil {
		return pick{}, false
	}
	if !a.Clear && prev != nil && prev.Choice == a.Choice && slices.Equal(prev.Targets, a.Targets) {
		return pick{}, false
	}
	p := pick{At: at, UID: a.Actor, Kind: a.Kind, Targets: a.Targets, Choice: a.Choice, Clear: a.Clear}
	if werewolf.IsVote(a.Kind) {
		p.Nominee = st.NomineeOf(a.Kind)
	}
	return p, true
}

func (p pick) data() map[string]any {
	return map[string]any{"at": p.At, "uid": p.UID, "kind": string(p.Kind), "targets": p.Targets,
		"choice": p.Choice, "nominee": p.Nominee, "clear": p.Clear}
}

// text là câu của p, dùng chung cho topic và nhật ký. name trả tên đã escape
// theo nơi hiển thị.
func (p pick) text(name func(string) string) string {
	switch {
	case p.Kind == werewolf.KindNominate && p.Clear:
		return name(p.UID) + " rút đề cử."
	case p.Kind == werewolf.KindNominate:
		names := make([]string, len(p.Targets))
		for i, uid := range p.Targets {
			names[i] = name(uid)
		}
		return fmt.Sprintf("%s đề cử %s.", name(p.UID), strings.Join(names, ", "))
	case p.Clear:
		return fmt.Sprintf("%s rút phiếu ở phiên %s.", name(p.UID), name(p.Nominee))
	default:
		return fmt.Sprintf("%s bỏ phiếu %s %s.", name(p.UID), choiceLabels[p.Choice], name(p.Nominee))
	}
}

// pickFeedID là doc gom mọi lần bấm của một pha, như "picks-r3-day". Mỗi lần
// bấm một mục thì một ngày 15 người ra vài chục mục, đẩy bản tin ra khỏi
// trang đầu nhật ký.
func pickFeedID(st *werewolf.State) string {
	return "picks-" + strings.ReplaceAll(st.PhaseKey(), "/", "-")
}

// writePickFeed thêm p vào mục diễn biến của pha và đẩy mục lên đầu nhật ký
// bằng feedSeq mới. Đề cử và biểu quyết là việc ban ngày, ai cũng thấy, nên
// tăng feedSeq không lộ gì như tăng version lúc đêm.
func writePickFeed(tx *firestore.Transaction, game *firestore.DocumentRef, gameData map[string]any, st *werewolf.State, p pick, now time.Time) error {
	line, err := json.Marshal(p)
	if err != nil {
		return err
	}
	seq := int64(number(gameData["feedSeq"])) + 1
	if err := tx.Set(game.Collection("feed").Doc(pickFeedID(st)), map[string]any{
		"seq": seq, "at": now, "wallAt": p.At, "phaseKey": st.PhaseKey(), "round": st.Round,
		"phase": string(st.Phase), "events": "[]", "picks": firestore.ArrayUnion(string(line)),
	}, firestore.MergeAll); err != nil {
		return err
	}
	return tx.Set(game, map[string]any{"feedSeq": seq}, firestore.MergeAll)
}

// wolfPickMessage là tin hệ thống của chat Phe Sói cho một lần chọn cắn, chở
// lựa chọn lúc đó để cả phe thấy từng lần đổi.
func wolfPickMessage(a werewolf.Action) map[string]any {
	msg := map[string]any{"uid": a.Actor, "kind": chatKindWolfPick}
	if !a.Clear && len(a.Targets) > 0 {
		msg["target"] = a.Targets[0]
	}
	return msg
}

func storedAction(d map[string]any) (*werewolf.Action, werewolf.Team) {
	peek := werewolf.Team(stringValue(d["peek"]))
	a, ok := decodeAction(d)
	if !ok {
		return nil, peek
	}
	return &a, peek
}
