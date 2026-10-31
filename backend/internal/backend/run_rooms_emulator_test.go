//go:build emulator

package backend

import (
	"context"
	"strings"
	"testing"
	"time"
)

func newRoomHarness(t *testing.T) *apiHarness {
	t.Helper()
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	h.deps.RunRooms = NewRunRoomStore(db)
	return h
}

func roomMember(t *testing.T, h *apiHarness, roomID, uid string) map[string]any {
	t.Helper()
	d, err := h.store.db.Collection("runRooms").Doc(roomID).Collection("members").Doc(uid).Get(context.Background())
	if err != nil {
		t.Fatalf("members/%s: %v", uid, err)
	}
	return d.Data()
}

func roomDoc(t *testing.T, h *apiHarness, roomID string) map[string]any {
	t.Helper()
	d, err := h.store.db.Collection("runRooms").Doc(roomID).Get(context.Background())
	if err != nil {
		t.Fatalf("runRooms/%s: %v", roomID, err)
	}
	return d.Data()
}

// Phòng public: vào thẳng tới trần maxRunners (tính cả chủ phòng), người thứ
// ba bị room_full; vào lại lần hai không tính thêm chỗ.
func TestEmulatorRunRoomPublicJoinUpToCap(t *testing.T) {
	h := newRoomHarness(t)
	seed(t, h.store.db, "publicProfiles/host", map[string]any{"displayName": "Linh"})

	r := h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Hồ Tây 6h", "privacy": "public", "maxRunners": 2}, "")
	h.want(r, 201, "")
	id, _ := r.body["id"].(string)
	if id == "" {
		t.Fatalf("thiếu id: %s", r.raw)
	}
	room := roomDoc(t, h, id)
	if room["hostUid"] != "host" || room["hostName"] != "Linh" || room["status"] != "open" || room["runnerCount"] != int64(1) || room["maxRunners"] != int64(2) {
		t.Fatalf("phòng: %v", room)
	}
	if m := roomMember(t, h, id, "host"); m["state"] != "joined" || m["role"] != "host" {
		t.Fatalf("chủ phòng: %v", m)
	}

	r = h.call("u1", "POST", "/v1/run-rooms/"+id+"/join", map[string]any{}, "")
	h.want(r, 200, "")
	if r.body["state"] != "joined" {
		t.Fatalf("u1: %s", r.raw)
	}
	h.want(h.call("u1", "POST", "/v1/run-rooms/"+id+"/join", map[string]any{}, ""), 200, "")
	h.want(h.call("u2", "POST", "/v1/run-rooms/"+id+"/join", map[string]any{}, ""), 409, "room_full")
	if c := roomDoc(t, h, id)["runnerCount"]; c != int64(2) {
		t.Fatalf("runnerCount %v, mong đợi 2", c)
	}
	h.want(h.call("u1", "POST", "/v1/run-rooms/nope/join", map[string]any{}, ""), 404, "room_not_found")
}

// Phòng private: xin vào thành requested, chỉ chủ phòng duyệt hay từ chối;
// người bị từ chối không xin lại được; duyệt khi đã đủ người thì room_full.
func TestEmulatorRunRoomPrivateApproveDeny(t *testing.T) {
	h := newRoomHarness(t)
	r := h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Chạy đôi", "privacy": "private", "maxRunners": 2}, "")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	base := "/v1/run-rooms/" + id

	for _, uid := range []string{"u1", "u2", "u3"} {
		r = h.call(uid, "POST", base+"/join", map[string]any{}, "")
		h.want(r, 200, "")
		if r.body["state"] != "requested" {
			t.Fatalf("%s: %s", uid, r.raw)
		}
	}
	if c := roomDoc(t, h, id)["runnerCount"]; c != int64(1) {
		t.Fatalf("xin vào đã tính chỗ: runnerCount %v", c)
	}
	h.want(h.call("u1", "POST", base+"/members/u2/approve", nil, ""), 403, "not_room_host")
	h.want(h.call("host", "POST", base+"/members/ghost/approve", nil, ""), 404, "member_not_found")

	h.want(h.call("host", "POST", base+"/members/u1/approve", nil, ""), 200, "")
	if m := roomMember(t, h, id, "u1"); m["state"] != "joined" {
		t.Fatalf("u1: %v", m)
	}
	h.want(h.call("host", "POST", base+"/members/u2/approve", nil, ""), 409, "room_full")
	if m := roomMember(t, h, id, "u2"); m["state"] != "requested" {
		t.Fatalf("u2 sau room_full: %v", m)
	}

	h.want(h.call("host", "POST", base+"/members/u3/deny", nil, ""), 200, "")
	if m := roomMember(t, h, id, "u3"); m["state"] != "denied" {
		t.Fatalf("u3: %v", m)
	}
	h.want(h.call("u3", "POST", base+"/join", map[string]any{}, ""), 403, "room_denied")
	// Đã joined thì không còn gì để từ chối.
	h.want(h.call("host", "POST", base+"/members/u1/deny", nil, ""), 409, "member_not_requested")
	if c := roomDoc(t, h, id)["runnerCount"]; c != int64(2) {
		t.Fatalf("runnerCount %v, mong đợi 2", c)
	}
}

// Phòng mật khẩu: đúng mật khẩu thì vào thẳng; sai 5 lần thì khoá 10 phút,
// kể cả khi lần sau gõ đúng; hết 10 phút thì vào được. Hash không lộ ra phòng.
func TestEmulatorRunRoomPasswordLockout(t *testing.T) {
	h := newRoomHarness(t)
	now := time.Date(2026, 11, 1, 6, 0, 0, 0, time.UTC)
	h.deps.Now = func() time.Time { return now }
	h.want(h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Có pass", "privacy": "password"}, ""), 400, "invalid_request")
	h.want(h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Lẫn pass", "privacy": "public", "password": "1234"}, ""), 400, "invalid_request")
	r := h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Có pass", "privacy": "password", "password": "hoTay6h"}, "")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	join := "/v1/run-rooms/" + id + "/join"
	for k, v := range roomDoc(t, h, id) {
		if s, ok := v.(string); ok && (s == "hoTay6h" || len(s) > 50) {
			t.Fatalf("phòng lộ mật khẩu ở %s", k)
		}
	}

	h.want(h.call("u1", "POST", join, map[string]any{"password": "hoTay6h"}, ""), 200, "")
	if m := roomMember(t, h, id, "u1"); m["state"] != "joined" {
		t.Fatalf("u1: %v", m)
	}
	h.want(h.call("u2", "POST", join, map[string]any{}, ""), 403, "password_required")
	for i := 0; i < 5; i++ {
		h.want(h.call("u2", "POST", join, map[string]any{"password": "sai"}, ""), 403, "wrong_password")
	}
	h.want(h.call("u2", "POST", join, map[string]any{"password": "hoTay6h"}, ""), 429, "room_locked")
	// Khoá theo người: người khác vẫn vào được.
	h.want(h.call("u3", "POST", join, map[string]any{"password": "hoTay6h"}, ""), 200, "")
	now = now.Add(10*time.Minute + time.Second)
	h.want(h.call("u2", "POST", join, map[string]any{"password": "hoTay6h"}, ""), 200, "")
	if c := roomDoc(t, h, id)["runnerCount"]; c != int64(4) {
		t.Fatalf("runnerCount %v, mong đợi 4", c)
	}
}

// Mời ra, rời phòng, kết thúc: số người đếm đúng; người bị mời ra không vào lại
// được; người tự rời thì vào lại được; chủ phòng không rời mà kết thúc phòng;
// phòng đã kết thúc hay quá giờ đóng thì không vào được nữa.
func TestEmulatorRunRoomKickLeaveEnd(t *testing.T) {
	h := newRoomHarness(t)
	now := time.Date(2026, 11, 1, 6, 0, 0, 0, time.UTC)
	h.deps.Now = func() time.Time { return now }
	r := h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Sáng CN", "privacy": "public"}, "")
	h.want(r, 201, "")
	id := r.body["id"].(string)
	base := "/v1/run-rooms/" + id
	for _, uid := range []string{"u1", "u2"} {
		h.want(h.call(uid, "POST", base+"/join", map[string]any{}, ""), 200, "")
	}

	h.want(h.call("host", "POST", base+"/members/u1/kick", nil, ""), 200, "")
	h.want(h.call("host", "POST", base+"/members/u1/kick", nil, ""), 409, "member_not_joined")
	h.want(h.call("host", "POST", base+"/members/host/kick", nil, ""), 409, "member_not_joined")
	h.want(h.call("u1", "POST", base+"/join", map[string]any{}, ""), 403, "room_kicked")

	h.want(h.call("u2", "POST", base+"/leave", nil, ""), 200, "")
	h.want(h.call("u2", "POST", base+"/leave", nil, ""), 200, "")
	if m := roomMember(t, h, id, "u2"); m["state"] != "left" {
		t.Fatalf("u2: %v", m)
	}
	h.want(h.call("ghost", "POST", base+"/leave", nil, ""), 404, "member_not_found")
	h.want(h.call("host", "POST", base+"/leave", nil, ""), 409, "host_cannot_leave")
	if c := roomDoc(t, h, id)["runnerCount"]; c != int64(1) {
		t.Fatalf("runnerCount %v, mong đợi 1", c)
	}
	h.want(h.call("u2", "POST", base+"/join", map[string]any{}, ""), 200, "")

	h.want(h.call("u2", "POST", base+"/end", nil, ""), 403, "not_room_host")
	h.want(h.call("host", "POST", base+"/end", nil, ""), 200, "")
	h.want(h.call("host", "POST", base+"/end", nil, ""), 200, "")
	if room := roomDoc(t, h, id); room["status"] != "ended" || room["endedAt"] == nil {
		t.Fatalf("phòng sau end: %v", room)
	}
	h.want(h.call("u3", "POST", base+"/join", map[string]any{}, ""), 409, "room_closed")

	r = h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Quên đóng", "privacy": "public"}, "")
	h.want(r, 201, "")
	now = now.Add(6*time.Hour + time.Second)
	h.want(h.call("u3", "POST", "/v1/run-rooms/"+r.body["id"].(string)+"/join", map[string]any{}, ""), 409, "room_closed")
}

// Tạo phòng: input sai trả invalid_request; hẹn giờ thì phòng đóng 6 tiếng sau
// giờ hẹn chứ không phải sau lúc tạo.
func TestEmulatorRunRoomCreateValidation(t *testing.T) {
	h := newRoomHarness(t)
	now := time.Date(2026, 11, 1, 6, 0, 0, 0, time.UTC)
	h.deps.Now = func() time.Time { return now }
	for _, body := range []map[string]any{
		{"title": "  ", "privacy": "public"},
		{"title": strings.Repeat("a", 61), "privacy": "public"},
		{"title": "x", "privacy": "club"},
		{"title": "x", "privacy": "public", "maxRunners": 1},
		{"title": "x", "privacy": "public", "maxRunners": 21},
		{"title": "x", "privacy": "public", "startsAt": "mai"},
		{"title": "x", "privacy": "public", "startsAt": "2026-11-08T06:00:01Z"},
		{"title": "x", "privacy": "password", "password": "abc"},
		{"title": "x", "privacy": "public", "extra": 1},
	} {
		h.want(h.call("host", "POST", "/v1/run-rooms", body, ""), 400, "invalid_request")
	}
	r := h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": strings.Repeat("ă", 60), "privacy": "public", "startsAt": "2026-11-01T07:30:00+07:00"}, "")
	h.want(r, 201, "")
	room := roomDoc(t, h, r.body["id"].(string))
	if room["maxRunners"] != int64(8) {
		t.Fatalf("maxRunners mặc định %v, mong đợi 8", room["maxRunners"])
	}
	// 07:30 giờ VN là 00:30 UTC, trước lúc tạo (06:00 UTC): tính là chạy ngay.
	if got := room["closesAt"].(time.Time); !got.Equal(now.Add(6 * time.Hour)) {
		t.Fatalf("closesAt %v", got)
	}
	r = h.call("host", "POST", "/v1/run-rooms", map[string]any{"title": "Hẹn", "privacy": "public", "startsAt": "2026-11-02T05:30:00+07:00"}, "")
	h.want(r, 201, "")
	room = roomDoc(t, h, r.body["id"].(string))
	if got := room["closesAt"].(time.Time); !got.Equal(time.Date(2026, 11, 2, 4, 30, 0, 0, time.UTC)) {
		t.Fatalf("closesAt %v, mong đợi 04:30 UTC 2/11", got)
	}
}
