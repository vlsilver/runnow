package backend

import (
	"context"
	"errors"
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

// DeliverLivePush báo mọi người trong club, trừ người đang chạy. Mỗi buổi chỉ
// báo một lần: tên task Cloud Tasks dùng lại được sau khi task đã chạy, nên
// trước khi gửi phải giữ chỗ ở livePushes/{activityId} (client không ghi được).
// Gửi lỗi thì nhả chỗ để lần gửi lại vẫn báo.
func DeliverLivePush(ctx context.Context, db *firestore.Client, push *PushService, t livePushTask) error {
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
	claim := db.Collection("livePushes").Doc(t.ActivityID)
	if _, err := claim.Create(ctx, map[string]any{"uid": t.UID, "at": time.Now()}); err != nil {
		if status.Code(err) == codes.AlreadyExists {
			return nil
		}
		return err
	}
	err = push.SendAll(ctx, t.UID, pushNote{
		Title: preferredName(profile) + " đang chạy live",
		Body:  "Vào xem đường chạy và cổ vũ.",
		Data:  map[string]string{"kind": livePushKind, "sessionId": t.ActivityID},
	})
	if err != nil {
		// ctx đã huỷ (task quá hạn) thì vẫn phải nhả chỗ cho lần gửi lại.
		if _, derr := claim.Delete(context.WithoutCancel(ctx)); derr != nil {
			return errors.Join(err, derr)
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
	if err := DeliverLivePush(r.Context(), s.deps.Firestore, s.deps.Push, task); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
