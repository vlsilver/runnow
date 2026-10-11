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
	Source     string // app | telegram
	TgUpdateID int64  // update_id của Telegram, 0 nếu từ app
	ReceivedAt time.Time
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
		if stringValue(g.Data()["status"]) != gameRunning {
			res.Reject = errGameNotRunning
			return nil
		}
		sec, err := tx.Get(secretRef(game))
		if err != nil {
			return err
		}
		st, err := decodeState(sec.Data())
		if err != nil {
			return err
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
		if t, ok := cur["receivedAt"].(time.Time); ok && t.After(req.ReceivedAt) {
			res.Current, res.Peek = storedAction(cur)
			return nil
		}

		a := werewolf.Action{Kind: req.Kind, Actor: req.UID, Targets: req.Targets, Choice: req.Choice, Clear: req.Clear, ReceivedAt: req.ReceivedAt}
		if err := werewolf.Validate(st, a, mine, req.ReceivedAt); err != nil {
			var reject werewolf.Reject
			if !errors.As(err, &reject) {
				return err
			}
			res.Reject = err
			return nil
		}

		msgs := []gameMsg{actionMessage(req.UID, req.Kind)}
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		doc := map[string]any{
			"uid": req.UID, "kind": string(req.Kind), "targets": req.Targets, "choice": req.Choice,
			"cleared": req.Clear, "receivedAt": req.ReceivedAt, "source": req.Source,
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
		w := stepWrite{tx: tx, game: game, msgs: msgs, chats: chats, now: req.ReceivedAt}
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

// actionMessage: lựa chọn riêng thì sửa tin DM của người đó; đề cử và biểu quyết
// là công khai nên sửa tin đếm phiếu trong topic (W2b). Tin chỉ chở (uid, kind),
// lúc gửi mới đọc lựa chọn đang lưu.
func actionMessage(uid string, kind werewolf.Kind) gameMsg {
	if kind == werewolf.KindNominate || kind == werewolf.KindVote {
		return gameMsg{ChatKey: chatGroup, Template: tplTally, Data: map[string]any{"kind": string(kind)}}
	}
	return gameMsg{ChatKey: dmChat(uid), Template: tplChoice, Data: map[string]any{"kind": string(kind)}}
}

func storedAction(d map[string]any) (*werewolf.Action, werewolf.Team) {
	peek := werewolf.Team(stringValue(d["peek"]))
	a, ok := decodeAction(d)
	if !ok {
		return nil, peek
	}
	return &a, peek
}
