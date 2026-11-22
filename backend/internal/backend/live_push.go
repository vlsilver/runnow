package backend

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Push "đang chạy live": app báo mốc start qua /v1/live/announce, api hẹn task
// này để báo cả club. Lúc gửi đọc lại buổi live: chỉ buổi club xem được
// (visibility club, tức hồ sơ công khai và không phải phòng kín) và còn đang
// chạy mới báo, nên task chạy trễ sau khi về đích thì thôi.
const (
	livePushPath = "/tasks/live-push"
	livePushKind = "live_start"
)

type livePushTask struct {
	UID        string `json:"uid"`
	ActivityID string `json:"activityId"`
}

func livePushTaskFor(uid, activityID string) PublishTask {
	t := livePushTask{UID: uid, ActivityID: activityID}
	return PublishTask{Queue: QueueNotify, HandlerPath: livePushPath, Payload: t, TaskID: StableTaskID("live-push", activityID)}
}

// liveCooldown: một người chỉ làm club nhận push live một lần trong khoảng
// này, dù mở bao nhiêu buổi. Chặn cả việc tạo liên tục buổi mới để spam.
const liveCooldown = 2 * time.Hour

// DeliverLivePush báo mọi người trong club, trừ người đang chạy. Mỗi người
// giữ một chỗ ở livePushRunners/{uid} (client không ghi được): đã báo buổi
// này, hay đã báo một buổi khác chưa quá liveCooldown thì thôi. Gửi lỗi thì
// trả chỗ về như cũ để lần gửi lại vẫn báo.
func DeliverLivePush(ctx context.Context, db *firestore.Client, push *PushService, now time.Time, t livePushTask) error {
	off, err := pushKindOff(ctx, db, livePushKind)
	if err != nil || off {
		return err
	}
	session, err := getData(ctx, db.Collection("liveSessions").Doc(t.ActivityID))
	if err != nil || session == nil {
		return err
	}
	if stringValue(session["ownerUid"]) != t.UID || stringValue(session["visibility"]) != "club" {
		return nil
	}
	switch stringValue(session["status"]) {
	case "running", "paused":
	default:
		return nil
	}
	profile, err := resolveProfile(ctx, db, t.UID)
	if err != nil {
		return err
	}
	claim := db.Collection("livePushRunners").Doc(t.UID)
	var prev map[string]any
	claimed, skipped := false, ""
	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		prev, claimed, skipped = nil, false, ""
		snap, err := tx.Get(claim)
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		// tx.Get trả (nil, err) cả khi lỗi mang mã NotFound mà không phải do thiếu doc.
		if snap != nil && snap.Exists() {
			prev = snap.Data()
			last, _ := prev["at"].(time.Time)
			switch {
			case stringValue(prev["activityId"]) == t.ActivityID:
				skipped = "same_activity"
				return nil
			case now.Sub(last) < liveCooldown:
				skipped = "cooldown"
				return nil
			}
		}
		claimed = true
		return tx.Set(claim, map[string]any{"activityId": t.ActivityID, "at": now})
	})
	if err != nil {
		return err
	}
	if !claimed {
		slog.InfoContext(ctx, "live_push.skipped", "reason", skipped, "uid", t.UID, "activityId", t.ActivityID)
		return nil
	}
	err = push.SendAll(ctx, t.UID, pushNote{
		Title: preferredName(profile) + " đang chạy live",
		Body:  "Vào xem đường chạy và cổ vũ.",
		Data:  map[string]string{"kind": livePushKind, "sessionId": t.ActivityID},
	})
	if err != nil {
		// ctx đã huỷ (task quá hạn) thì vẫn phải trả chỗ cho lần gửi lại.
		ctx := context.WithoutCancel(ctx)
		var rerr error
		if prev == nil {
			_, rerr = claim.Delete(ctx)
		} else {
			_, rerr = claim.Set(ctx, prev)
		}
		if rerr != nil {
			return errors.Join(err, rerr)
		}
	}
	return err
}

func (s *Server) livePush(w http.ResponseWriter, r *http.Request) error {
	var task livePushTask
	if decodeJSON(r, &task) != nil || task.UID == "" || task.ActivityID == "" || s.deps.Push == nil {
		w.WriteHeader(204)
		return nil
	}
	if err := DeliverLivePush(r.Context(), s.deps.Firestore, s.deps.Push, s.now(), task); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
