package backend

import (
	"context"
	"log/slog"
	"slices"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Push của phòng chạy: chủ phòng biết có người xin vào, người xin biết được
// nhận hay không, thành viên được nhắc trước giờ hẹn. Mỗi push là một task;
// lúc gửi đọc lại phòng và thành viên, state đã khác thì thôi, nên task chạy
// lại hay chạy trễ không báo sai.
const (
	roomPushRequest  = "room_request"
	roomPushApproved = "room_approved"
	roomPushDenied   = "room_denied"
	roomPushStarting = "room_starting"

	roomPushPath = "/tasks/room-push"
	// roomRemindBefore: nhắc thành viên trước giờ hẹn chừng này. Phòng hẹn
	// gần hơn thì không nhắc.
	roomRemindBefore = 10 * time.Minute
)

type roomPushTask struct {
	Kind   string `json:"kind"`
	RoomID string `json:"roomId"`
	// UID là người xin vào; rỗng với lời nhắc trước giờ hẹn.
	UID string `json:"uid,omitempty"`
	// At là thời điểm của việc (UnixMicro): lúc xin, lúc duyệt hay giờ hẹn,
	// để TaskID khác nhau giữa các lần. Lời xin còn phải khớp requestedAt lúc
	// gửi: rút rồi xin lại thì chỉ lần xin sau được báo.
	At int64 `json:"at"`
}

// notify hẹn một push sau khi việc chính đã ghi xong. Hẹn hỏng (Publish đã tự
// thử lại) thì log chứ không trả lỗi: trả lỗi thì app báo hỏng cho một thao
// tác đã thành công, bấm lại còn bị 409.
func (s *RunRoomStore) notify(ctx context.Context, t roomPushTask, at *time.Time) {
	if s.enqueue == nil {
		return
	}
	task := PublishTask{Queue: QueueNotify, HandlerPath: roomPushPath, Payload: t, TaskID: StableTaskID("room-push", t), ScheduleTime: at}
	if _, err := s.enqueue(ctx, task); err != nil {
		slog.ErrorContext(ctx, "run_room.push_enqueue_failed", "kind", t.Kind, "roomId", t.RoomID, "error", err)
	}
}

// Deliver chạy một task push của phòng.
func (s *RunRoomStore) Deliver(ctx context.Context, push *PushService, t roomPushTask, now time.Time) error {
	off, err := pushKindOff(ctx, s.db, t.Kind)
	if err != nil || off {
		return err
	}
	uids, note, err := s.pushPlan(ctx, t, now)
	if err != nil || len(uids) == 0 {
		return err
	}
	return push.Send(ctx, uids, note)
}

// pushPlan đọc phòng lúc gửi và trả ai nhận, nội dung gì. Không còn gì để báo
// thì uids rỗng.
func (s *RunRoomStore) pushPlan(ctx context.Context, t roomPushTask, now time.Time) ([]string, pushNote, error) {
	var note pushNote
	room := s.roomRef(t.RoomID)
	r, err := room.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, note, nil
	}
	if err != nil {
		return nil, note, err
	}
	data := r.Data()
	if !roomIsOpen(data, now) {
		return nil, note, nil
	}
	solo := stringValue(data["kind"]) == roomSolo
	note.Title = stringValue(data["title"])
	if solo {
		note.Title = "Chạy cùng " + stringValue(data["hostName"])
	}
	note.Data = map[string]string{"kind": t.Kind, "roomId": t.RoomID}

	if t.Kind == roomPushStarting {
		docs, err := room.Collection("members").Where("state", "==", memberJoined).Documents(ctx).GetAll()
		if err != nil {
			return nil, note, err
		}
		uids := make([]string, 0, len(docs))
		for _, d := range docs {
			uids = append(uids, d.Ref.ID)
		}
		note.Body = "Còn 10 phút nữa là tới giờ chạy."
		return uids, note, nil
	}

	m, err := memberRef(room, t.UID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, note, nil
	}
	if err != nil {
		return nil, note, err
	}
	st := stringValue(m.Data()["state"])
	switch t.Kind {
	case roomPushRequest:
		requestedAt, _ := m.Data()["requestedAt"].(time.Time)
		if st != memberRequested || requestedAt.UnixMicro() != t.At {
			return nil, note, nil
		}
		if solo {
			note.Title = "Đang nhận người chạy cùng"
			note.Body = "Có người xin chạy cùng bạn. Mở app để duyệt."
		} else {
			note.Body = "Có người xin vào phòng. Mở app để duyệt."
		}
		return []string{stringValue(data["hostUid"])}, note, nil
	case roomPushApproved:
		if st != memberJoined {
			return nil, note, nil
		}
		note.Body = "Chủ phòng đã nhận bạn vào phòng."
		return []string{t.UID}, note, nil
	case roomPushDenied:
		// Từ chối là state cuối: không xin lại hay được duyệt được nữa.
		note.Body = "Chủ phòng chưa nhận bạn lần này."
		return []string{t.UID}, note, nil
	}
	return nil, note, nil
}

// pushKindOff đọc appConfig/push.off: tắt từng loại push không cần ra bản
// app mới. Chưa có doc thì mọi loại đều bật.
func pushKindOff(ctx context.Context, db *firestore.Client, kind string) (bool, error) {
	d, err := db.Collection("appConfig").Doc("push").Get(ctx)
	if status.Code(err) == codes.NotFound {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	off, _ := d.Data()["off"].([]any)
	return slices.Contains(off, any(kind)), nil
}
