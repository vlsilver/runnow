package backend

import (
	"context"
	"errors"
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
	switch a.Kind {
	case werewolf.KindNominate, werewolf.KindVote:
		return []gameMsg{{ChatKey: chatGroup, Template: tplTally, Data: kind}}
	}
	return []gameMsg{{ChatKey: dmChat(a.Actor), Template: tplChoice, Data: kind}}
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
