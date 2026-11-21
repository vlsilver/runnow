//go:build emulator

package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"firebase.google.com/go/v4/messaging"
)

var errFakeDeadToken = errors.New("token đã chết")

// fakePushSender đứng thay FCM: ghi lại tin đã gửi, token nằm trong fail thì
// trả lỗi tương ứng.
type fakePushSender struct {
	mu   sync.Mutex
	sent []*messaging.Message
	fail map[string]error
}

func (f *fakePushSender) SendEach(_ context.Context, msgs []*messaging.Message) (*messaging.BatchResponse, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	res := &messaging.BatchResponse{}
	for _, m := range msgs {
		if err := f.fail[m.Token]; err != nil {
			res.FailureCount++
			res.Responses = append(res.Responses, &messaging.SendResponse{Error: err})
			continue
		}
		f.sent = append(f.sent, m)
		res.SuccessCount++
		res.Responses = append(res.Responses, &messaging.SendResponse{Success: true})
	}
	return res, nil
}

func newFakePush(db *firestore.Client) (*PushService, *fakePushSender) {
	f := &fakePushSender{fail: map[string]error{}}
	s := NewPushService(db, f)
	s.deadToken = func(err error) bool { return errors.Is(err, errFakeDeadToken) }
	return s, f
}

func pushTokenOwners(t *testing.T, db *firestore.Client) map[string]string {
	t.Helper()
	docs, err := db.Collection("pushTokens").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]string{}
	for _, d := range docs {
		out[stringValue(d.Data()["token"])] = stringValue(d.Data()["uid"])
	}
	return out
}

// Một máy chỉ nhận push của người đang đăng nhập: đăng ký lại token trên tài
// khoản khác thì token chuyển chủ; người không còn giữ token không gỡ được nó.
func TestEmulatorPushTokenFollowsSignedInUser(t *testing.T) {
	h := newRoomHarness(t)
	db := h.store.db

	h.want(h.call("u1", "PUT", "/v1/push-token", map[string]any{"token": "tok-a", "platform": "ios"}, ""), 200, "")
	h.want(h.call("u1", "PUT", "/v1/push-token", map[string]any{"token": "tok-a", "platform": "ios"}, ""), 200, "")
	if got := pushTokenOwners(t, db); len(got) != 1 || got["tok-a"] != "u1" {
		t.Fatalf("sau khi u1 đăng ký: %v", got)
	}

	h.want(h.call("u2", "PUT", "/v1/push-token", map[string]any{"token": "tok-a", "platform": "ios"}, ""), 200, "")
	if got := pushTokenOwners(t, db); len(got) != 1 || got["tok-a"] != "u2" {
		t.Fatalf("u2 đăng nhập trên cùng máy: %v", got)
	}

	h.want(h.call("u1", "DELETE", "/v1/push-token", map[string]any{"token": "tok-a"}, ""), 200, "")
	if got := pushTokenOwners(t, db); got["tok-a"] != "u2" {
		t.Fatalf("u1 gỡ token đã sang u2: %v", got)
	}
	h.want(h.call("u2", "DELETE", "/v1/push-token", map[string]any{"token": "tok-a"}, ""), 200, "")
	if got := pushTokenOwners(t, db); len(got) != 0 {
		t.Fatalf("u2 đăng xuất: %v", got)
	}

	h.want(h.call("u1", "PUT", "/v1/push-token", map[string]any{"token": "", "platform": "ios"}, ""), 400, "invalid_request")
	h.want(h.call("u1", "PUT", "/v1/push-token", map[string]any{"token": "tok-b", "platform": "symbian"}, ""), 400, "invalid_request")

	// Xoá tài khoản thì xoá máy của người đó, máy người khác giữ nguyên.
	h.want(h.call("u1", "PUT", "/v1/push-token", map[string]any{"token": "tok-c", "platform": "ios"}, ""), 200, "")
	h.want(h.call("u2", "PUT", "/v1/push-token", map[string]any{"token": "tok-d", "platform": "android"}, ""), 200, "")
	if err := NewAccountService(db, nil, nil, nil).deleteOwnedDocuments(context.Background(), "u1", ""); err != nil {
		t.Fatal(err)
	}
	if got := pushTokenOwners(t, db); len(got) != 1 || got["tok-d"] != "u2" {
		t.Fatalf("sau khi xoá tài khoản u1: %v", got)
	}
}

// Phòng chạy riêng không có tên: báo theo tên chủ phòng.
func TestEmulatorRoomPushSoloWording(t *testing.T) {
	h := newRoomPushHarness(t, "host", "u1")
	seed(t, h.store.db, "publicProfiles/host", map[string]any{"displayName": "Linh"})
	r := h.call("host", "POST", "/v1/run-rooms", map[string]any{"kind": "solo", "privacy": "private"}, "")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	h.want(h.call("u1", "POST", "/v1/run-rooms/"+id+"/join", map[string]any{}, ""), 200, "")
	h.deliver()
	if m := h.sent()["tok-host"]; m == nil || m.Notification.Title != "Đang nhận người chạy cùng" || m.Notification.Body != "Có người xin chạy cùng bạn. Mở app để duyệt." {
		t.Fatalf("báo chủ phòng solo: %+v", m)
	}
	h.want(h.call("host", "POST", "/v1/run-rooms/"+id+"/members/u1/approve", map[string]any{}, ""), 200, "")
	h.deliver()
	if m := h.sent()["tok-u1"]; m == nil || m.Notification.Title != "Chạy cùng Linh" {
		t.Fatalf("báo người được nhận chạy cùng: %+v", m)
	}
}

// roomPushHarness gài push giả và bắt task push thay Cloud Tasks.
type roomPushHarness struct {
	*apiHarness
	sender *fakePushSender
	tasks  []PublishTask
	bot    http.Handler
}

func newRoomPushHarness(t *testing.T, uids ...string) *roomPushHarness {
	t.Helper()
	h := &roomPushHarness{apiHarness: newRoomHarness(t)}
	h.deps.Push, h.sender = newFakePush(h.store.db)
	h.deps.RunRooms.enqueue = func(_ context.Context, p PublishTask) (string, error) {
		h.tasks = append(h.tasks, p)
		return "created", nil
	}
	h.bot = NewBotServer(Config{}, h.deps)
	for _, uid := range uids {
		h.want(h.call(uid, "PUT", "/v1/push-token", map[string]any{"token": "tok-" + uid, "platform": "ios"}, ""), 200, "")
	}
	return h
}

// deliver chạy các task push đã hẹn như Cloud Tasks gọi bot, rồi xoá hàng chờ.
func (h *roomPushHarness) deliver() {
	h.t.Helper()
	for _, p := range h.tasks {
		if p.Queue != QueueNotify || p.HandlerPath != roomPushPath {
			h.t.Fatalf("task push sai queue hay đường: %+v", p)
		}
		b, _ := json.Marshal(p.Payload)
		w := httptest.NewRecorder()
		h.bot.ServeHTTP(w, httptest.NewRequest("POST", p.HandlerPath, bytes.NewReader(b)))
		if w.Code != 200 {
			h.t.Fatalf("room-push: %d %s", w.Code, w.Body.String())
		}
	}
	h.tasks = nil
}

// sent trả token → tin đã gửi, rồi xoá. Một token nhận hai lần là lỗi.
func (h *roomPushHarness) sent() map[string]*messaging.Message {
	h.t.Helper()
	out := map[string]*messaging.Message{}
	for _, m := range h.sender.sent {
		if out[m.Token] != nil {
			h.t.Fatalf("token %s nhận hai lần", m.Token)
		}
		out[m.Token] = m
	}
	h.sender.sent = nil
	return out
}

// Phòng kín: chủ phòng được báo mỗi lời xin một lần (bấm xin hai lần vẫn một
// task), không báo lời đã rút, rút rồi xin lại chỉ báo lần sau. Người xin được
// báo nhận hay từ chối; được nhận rồi bị mời ra trước lúc gửi thì thôi.
func TestEmulatorRoomPushRequestApproveDeny(t *testing.T) {
	h := newRoomPushHarness(t, "host", "u1", "u2", "u3", "u4")
	r := h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Chạy đôi", "privacy": "private", "maxRunners": 5}, "")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	base := "/v1/run-rooms/" + id
	if len(h.tasks) != 0 {
		t.Fatalf("phòng chạy ngay mà vẫn hẹn nhắc: %+v", h.tasks)
	}

	h.want(h.call("u1", "POST", base+"/join", map[string]any{}, ""), 200, "")
	h.want(h.call("u1", "POST", base+"/join", map[string]any{}, ""), 200, "")
	if len(h.tasks) != 1 {
		t.Fatalf("bấm xin hai lần: %d task", len(h.tasks))
	}
	h.deliver()
	got := h.sent()
	m := got["tok-host"]
	if len(got) != 1 || m == nil || m.Notification.Title != "Chạy đôi" || m.Notification.Body != "Có người xin vào phòng. Mở app để duyệt." ||
		m.Data["roomId"] != id || m.Data["kind"] != roomPushRequest {
		t.Fatalf("báo chủ phòng: %+v", got)
	}

	h.want(h.call("u2", "POST", base+"/join", map[string]any{}, ""), 200, "")
	h.want(h.call("u2", "POST", base+"/leave", map[string]any{}, ""), 200, "")
	h.deliver()
	if got := h.sent(); len(got) != 0 {
		t.Fatalf("lời xin đã rút: %+v", got)
	}

	h.want(h.call("u4", "POST", base+"/join", map[string]any{}, ""), 200, "")
	h.want(h.call("u4", "POST", base+"/leave", map[string]any{}, ""), 200, "")
	h.want(h.call("u4", "POST", base+"/join", map[string]any{}, ""), 200, "")
	h.deliver()
	if got := h.sent(); len(got) != 1 {
		t.Fatalf("rút rồi xin lại: %+v", got)
	}

	h.want(h.call("u3", "POST", base+"/join", map[string]any{}, ""), 200, "")
	h.tasks = nil
	h.want(h.call("host", "POST", base+"/members/u1/approve", map[string]any{}, ""), 200, "")
	h.want(h.call("host", "POST", base+"/members/u3/deny", map[string]any{}, ""), 200, "")
	h.want(h.call("host", "POST", base+"/members/u4/approve", map[string]any{}, ""), 200, "")
	h.want(h.call("host", "POST", base+"/members/u4/kick", map[string]any{}, ""), 200, "")
	h.deliver()
	got = h.sent()
	if len(got) != 2 || got["tok-u1"] == nil || got["tok-u1"].Notification.Body != "Chủ phòng đã nhận bạn vào phòng." ||
		got["tok-u3"] == nil || got["tok-u3"].Notification.Body != "Chủ phòng chưa nhận bạn lần này." {
		t.Fatalf("báo người xin: %+v", got)
	}
}

// Phòng hẹn giờ: 10 phút trước giờ hẹn nhắc người đã vào phòng, kể cả chủ,
// không nhắc người còn chờ duyệt. Hẹn gần hơn 10 phút thì không nhắc. Tắt loại
// push trong appConfig/push thì không gửi.
func TestEmulatorRoomPushStartingReminder(t *testing.T) {
	h := newRoomPushHarness(t, "host", "u1", "u2")
	now := time.Date(2026, 11, 1, 5, 0, 0, 0, time.UTC)
	h.deps.Now = func() time.Time { return now }

	r := h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Hồ Tây", "privacy": "private", "startsAt": "2026-11-01T13:00:00+07:00"}, "")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	if len(h.tasks) != 1 || h.tasks[0].ScheduleTime == nil || !h.tasks[0].ScheduleTime.Equal(time.Date(2026, 11, 1, 5, 50, 0, 0, time.UTC)) {
		t.Fatalf("hẹn nhắc lúc 05:50 UTC: %+v", h.tasks)
	}
	remind := h.tasks
	h.tasks = nil
	h.want(h.call("u1", "POST", "/v1/run-rooms/"+id+"/join", map[string]any{}, ""), 200, "")
	h.want(h.call("host", "POST", "/v1/run-rooms/"+id+"/members/u1/approve", map[string]any{}, ""), 200, "")
	h.want(h.call("u2", "POST", "/v1/run-rooms/"+id+"/join", map[string]any{}, ""), 200, "")
	h.tasks = nil

	seed(t, h.store.db, "appConfig/push", map[string]any{"off": []any{roomPushStarting}})
	h.tasks = remind
	h.deliver()
	if got := h.sent(); len(got) != 0 {
		t.Fatalf("đã tắt room_starting mà vẫn gửi: %+v", got)
	}

	seed(t, h.store.db, "appConfig/push", map[string]any{"off": []any{}})
	now = time.Date(2026, 11, 1, 5, 50, 0, 0, time.UTC)
	h.tasks = remind
	h.deliver()
	got := h.sent()
	if len(got) != 2 || got["tok-host"] == nil || got["tok-u1"] == nil ||
		got["tok-u1"].Notification.Title != "Hồ Tây" || got["tok-u1"].Notification.Body != "Còn 10 phút nữa là tới giờ chạy." {
		t.Fatalf("nhắc trước giờ: %+v", got)
	}

	h.want(h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Sát giờ", "privacy": "public", "startsAt": "2026-11-01T12:59:00+07:00"}, ""), 201, "")
	if len(h.tasks) != 0 {
		t.Fatalf("hẹn còn 9 phút mà vẫn nhắc: %+v", h.tasks)
	}

	r = h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Huỷ", "privacy": "public", "startsAt": "2026-11-01T15:00:00+07:00"}, "")
	h.want(r, 201, "")
	h.want(h.call("host", "POST", "/v1/run-rooms/"+r.body["id"].(string)+"/end", map[string]any{}, ""), 200, "")
	h.deliver()
	if got := h.sent(); len(got) != 0 {
		t.Fatalf("phòng đã kết thúc vẫn nhắc: %+v", got)
	}
}

// Gửi tới mọi máy của người nhận: token FCM báo đã chết thì xoá; hỏng hết thì
// trả lỗi để Cloud Tasks gửi lại; hỏng một phần thì không trả lỗi, để máy đã
// nhận không nhận hai lần.
func TestEmulatorPushSendFailures(t *testing.T) {
	h := newRoomHarness(t)
	push, sender := newFakePush(h.store.db)
	h.deps.Push = push
	for _, tok := range []string{"tok-dead", "tok-a", "tok-b"} {
		h.want(h.call("u1", "PUT", "/v1/push-token", map[string]any{"token": tok, "platform": "android"}, ""), 200, "")
	}
	ctx := context.Background()
	note := pushNote{Title: "t", Body: "b"}

	sender.fail["tok-dead"] = errFakeDeadToken
	if err := push.Send(ctx, []string{"u1"}, note); err != nil {
		t.Fatalf("token chết không phải lỗi: %v", err)
	}
	if owners := pushTokenOwners(t, h.store.db); len(owners) != 2 || owners["tok-dead"] != "" {
		t.Fatalf("token chết chưa bị xoá: %v", owners)
	}

	unavailable := errors.New("fcm unavailable")
	sender.fail["tok-a"] = unavailable
	if err := push.Send(ctx, []string{"u1"}, note); err != nil {
		t.Fatalf("hỏng một phần mà trả lỗi: %v", err)
	}
	sender.fail["tok-b"] = unavailable
	if err := push.Send(ctx, []string{"u1"}, note); !errors.Is(err, unavailable) {
		t.Fatalf("hỏng hết phải trả lỗi, được %v", err)
	}
	if err := push.Send(ctx, []string{"không-có-máy"}, note); err != nil {
		t.Fatalf("người chưa có máy: %v", err)
	}
}
