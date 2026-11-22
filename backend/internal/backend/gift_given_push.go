package backend

import (
	"context"
	"log/slog"
	"net/http"
	"slices"
	"time"

	"cloud.google.com/go/firestore"
)

// Push "quà đã được trao": người trao (admin với quà BXH, chủ kèo với quà kèo)
// bấm đã trao thì người trúng được nhắc vào bấm "Đã nhận". Lúc gửi đọc lại quà:
// đã bỏ đánh dấu trao hay người trúng đã bấm nhận thì thôi.
const (
	giftGivenPushPath = "/tasks/gift-given-push"
	giftGivenPushKind = "gift_given"

	giftFromRank     = "rank"
	giftFromContract = "contract"
)

type giftGivenPushTask struct {
	From string `json:"from"`
	// ID là boardId với quà BXH, contractId với quà kèo.
	ID  string `json:"id"`
	UID string `json:"uid"`
	// At là lúc bấm đã trao (UnixMicro), để bỏ trao rồi trao lại thì báo lại.
	At int64 `json:"at"`
}

// notifyGiftGiven hẹn push sau khi đã ghi givenAt. Hẹn hỏng thì log: việc chính
// đã xong, trả lỗi chỉ làm người trao bấm lại.
func (s *Server) notifyGiftGiven(ctx context.Context, t giftGivenPushTask) {
	publish := s.enqueueTask()
	if publish == nil {
		return
	}
	task := PublishTask{Queue: QueueNotify, HandlerPath: giftGivenPushPath, Payload: t, TaskID: StableTaskID("gift-given-push", t)}
	if _, err := publish(context.WithoutCancel(ctx), task); err != nil {
		slog.ErrorContext(ctx, "gift_given.push_enqueue_failed", "from", t.From, "id", t.ID, "uid", t.UID, "error", err)
	}
}

// giftGivenState đọc quà của uid: tên món, và còn chờ người trúng bấm nhận không.
func giftGivenState(ctx context.Context, db *firestore.Client, t giftGivenPushTask) (name string, waiting bool, err error) {
	switch t.From {
	case giftFromRank:
		card, err := getData(ctx, db.Collection("users").Doc(t.UID).Collection("rankCards").Doc(t.ID))
		if err != nil || card == nil {
			return "", false, err
		}
		reward, _ := card["reward"].(map[string]any)
		if reward == nil {
			return "", false, nil
		}
		return stringValue(reward["name"]), reward["givenAt"] != nil && reward["receivedAt"] == nil, nil
	case giftFromContract:
		gift, err := getData(ctx, db.Collection("contractGifts").Doc(t.ID))
		if err != nil || gift == nil {
			return "", false, err
		}
		winners := anyList(gift["winners"])
		i := slices.IndexFunc(winners, func(v any) bool {
			m, _ := v.(map[string]any)
			return stringValue(m["uid"]) == t.UID
		})
		if i < 0 {
			return "", false, nil
		}
		w, _ := winners[i].(map[string]any)
		for _, it := range contractGiftItemsFrom(gift["items"]) {
			if it.ID == stringValue(w["itemId"]) {
				name = it.Name
			}
		}
		return name, w["givenAt"] != nil && w["receivedAt"] == nil, nil
	}
	return "", false, nil
}

func DeliverGiftGivenPush(ctx context.Context, db *firestore.Client, push *PushService, t giftGivenPushTask) error {
	off, err := pushKindOff(ctx, db, giftGivenPushKind)
	if err != nil || off {
		return err
	}
	name, waiting, err := giftGivenState(ctx, db, t)
	if err != nil || !waiting {
		return err
	}
	data := map[string]string{"kind": giftGivenPushKind}
	if t.From == giftFromRank {
		data["boardId"] = t.ID
	} else {
		data["contractId"] = t.ID
	}
	title := "Quà của bạn đã được trao"
	if name != "" {
		title = name + " đã được trao cho bạn"
	}
	return push.Send(ctx, []string{t.UID}, pushNote{Title: title, Body: "Nhận được rồi thì vào bấm Đã nhận nhé.", Data: data})
}

func (s *Server) giftGivenPush(w http.ResponseWriter, r *http.Request) error {
	var task giftGivenPushTask
	if decodeJSON(r, &task) != nil || task.ID == "" || task.UID == "" || s.deps.Push == nil {
		w.WriteHeader(204)
		return nil
	}
	if err := DeliverGiftGivenPush(r.Context(), s.deps.Firestore, s.deps.Push, task); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

func giftGivenTask(from, id, uid string, at time.Time) giftGivenPushTask {
	return giftGivenPushTask{From: from, ID: id, UID: uid, At: at.UnixMicro()}
}
