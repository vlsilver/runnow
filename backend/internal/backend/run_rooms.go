package backend

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"golang.org/x/crypto/bcrypt"
	"golang.org/x/text/unicode/norm"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Phòng chạy: chủ phòng mở, người khác vào để thấy nhau trên map. Chỉ backend
// ghi runRooms và members, vì trần người, mật khẩu và quyền chủ phòng phải kiểm
// trong một transaction; app chỉ đọc theo rules.
const (
	roomOpen  = "open"
	roomEnded = "ended"

	roomPublic   = "public"
	roomPrivate  = "private"
	roomPassword = "password"

	// roomGroup là phòng mở để rủ nhau chạy; roomSolo là phòng ngầm của một
	// buổi chạy riêng, chủ mở lúc bắt đầu chạy để người khác xin chạy cùng.
	roomGroup = "group"
	roomSolo  = "solo"

	memberRequested = "requested"
	memberJoined    = "joined"
	memberLeft      = "left"
	memberKicked    = "kicked"
	memberDenied    = "denied"

	roomMinRunners     = 2
	roomMaxRunners     = 20
	roomDefaultRunners = 8
	roomTitleMax       = 60
	// roomOpenFor: phòng tự đóng sau giờ hẹn chừng này, để list public không
	// giữ phòng chủ quên kết thúc.
	roomOpenFor = 6 * time.Hour
	// roomStartsWithin: hẹn giờ chạy trước tối đa chừng này.
	roomStartsWithin = 7 * 24 * time.Hour

	roomPasswordMin = 4
	roomPasswordMax = 24
	// bcrypt chỉ nhận tối đa 72 byte; emoji 4 byte thì 24 ký tự đã vượt.
	roomPasswordMaxBytes = 72
	// Cứ roomMaxFails lần sai thì người đó bị khoá ở phòng này, lần sau lâu
	// hơn lần trước, để không dò hết được mật khẩu 4 số trong đời phòng.
	roomMaxFails = 5
)

var roomLockSteps = []time.Duration{10 * time.Minute, time.Hour, 24 * time.Hour}

var (
	errRoomNotFound    = &HTTPError{Status: http.StatusNotFound, Code: "room_not_found", Message: "Không tìm thấy phòng chạy."}
	errRoomClosed      = &HTTPError{Status: http.StatusConflict, Code: "room_closed", Message: "Phòng chạy đã đóng."}
	errRoomFull        = &HTTPError{Status: http.StatusConflict, Code: "room_full", Message: "Phòng đã đủ người."}
	errRoomKicked      = &HTTPError{Status: http.StatusForbidden, Code: "room_kicked", Message: "Chủ phòng đã mời bạn ra khỏi phòng này."}
	errRoomDenied      = &HTTPError{Status: http.StatusForbidden, Code: "room_denied", Message: "Chủ phòng đã từ chối cho bạn vào phòng này."}
	errRoomPassword    = &HTTPError{Status: http.StatusForbidden, Code: "password_required", Message: "Phòng này cần mật khẩu."}
	errWrongPassword   = &HTTPError{Status: http.StatusForbidden, Code: "wrong_password", Message: "Sai mật khẩu phòng."}
	errHostCannotLeave = &HTTPError{Status: http.StatusConflict, Code: "host_cannot_leave", Message: "Chủ phòng kết thúc phòng thay vì rời phòng."}
	errNotRoomHost     = &HTTPError{Status: http.StatusForbidden, Code: "not_room_host", Message: "Chỉ chủ phòng làm được việc này."}
	errNotRoomMember   = &HTTPError{Status: http.StatusForbidden, Code: "not_room_member", Message: "Vào phòng rồi mới nói chuyện được."}

	errMemberNotFound     = &HTTPError{Status: http.StatusNotFound, Code: "member_not_found", Message: "Người này chưa xin vào phòng."}
	errMemberNotRequested = &HTTPError{Status: http.StatusConflict, Code: "member_not_requested", Message: "Người này không còn chờ duyệt."}
	errMemberNotJoined    = &HTTPError{Status: http.StatusConflict, Code: "member_not_joined", Message: "Người này không đang ở trong phòng."}
)

type RunRoomStore struct {
	db *firestore.Client
	// enqueue hẹn task push (run_room_push.go); nil thì không push.
	enqueue taskPublishFunc
}

func NewRunRoomStore(db *firestore.Client) *RunRoomStore {
	return &RunRoomStore{db: db}
}

type CreateRunRoomRequest struct {
	Title      string `json:"title"`
	Privacy    string `json:"privacy"`
	Password   string `json:"password"`
	MaxRunners int    `json:"maxRunners"`
	// StartsAt là giờ hẹn chạy (RFC 3339); rỗng là chạy ngay.
	StartsAt string `json:"startsAt"`
	// Kind rỗng là group. Phòng solo chỉ public hoặc private, mở ngay, và
	// không đặt tên thì lấy tên chủ.
	Kind string `json:"kind"`
	// Route là tuyến chủ phòng vẽ hay nhập GPX, đã rút gọn ở app để vẽ lên
	// map. DistanceMeters là quãng của tuyến gốc, chỉ để hiển thị.
	Route *RunRoomRoute `json:"route"`
}

type RunRoomRoute struct {
	DistanceMeters float64        `json:"distanceMeters"`
	Points         []RunRoomPoint `json:"points"`
}

type RunRoomPoint struct {
	Lat float64 `json:"lat"`
	Lng float64 `json:"lng"`
}

// Tuyến nằm luôn trong doc phòng, mà list phòng public đọc cả doc, nên chặn
// số điểm cho doc nhỏ (200 điểm chừng 8 KB).
const (
	roomRouteMaxPoints = 200
	roomRouteMaxMeters = 300_000
)

func (r *RunRoomRoute) valid() bool {
	if len(r.Points) < 2 || len(r.Points) > roomRouteMaxPoints ||
		!(r.DistanceMeters > 0 && r.DistanceMeters <= roomRouteMaxMeters) {
		return false
	}
	for _, p := range r.Points {
		if p.Lat < -90 || p.Lat > 90 || p.Lng < -180 || p.Lng > 180 {
			return false
		}
	}
	return true
}

func (r *RunRoomRoute) doc() map[string]any {
	points := make([]map[string]any, len(r.Points))
	for i, p := range r.Points {
		points[i] = map[string]any{"lat": p.Lat, "lng": p.Lng}
	}
	return map[string]any{"distanceMeters": r.DistanceMeters, "points": points}
}

func (s *RunRoomStore) roomRef(id string) *firestore.DocumentRef {
	return s.db.Collection("runRooms").Doc(id)
}

func memberRef(room *firestore.DocumentRef, uid string) *firestore.DocumentRef {
	return room.Collection("members").Doc(uid)
}

// passwordRef và attemptRef nằm dưới secret, rules không cho client đọc.
func passwordRef(room *firestore.DocumentRef) *firestore.DocumentRef {
	return room.Collection("secret").Doc("password")
}

func attemptRef(room *firestore.DocumentRef, uid string) *firestore.DocumentRef {
	return room.Collection("secret").Doc("attempts").Collection("by").Doc(uid)
}

// Create mở phòng và ghi chủ phòng là thành viên đầu tiên.
func (s *RunRoomStore) Create(ctx context.Context, uid string, in CreateRunRoomRequest, now time.Time) (string, error) {
	kind := in.Kind
	if kind == "" {
		kind = roomGroup
	}
	title := strings.TrimSpace(in.Title)
	switch kind {
	case roomGroup:
		if title == "" {
			return "", invalidRequest()
		}
	case roomSolo:
		if in.Privacy == roomPassword || in.StartsAt != "" {
			return "", invalidRequest()
		}
	default:
		return "", invalidRequest()
	}
	if utf8.RuneCountInString(title) > roomTitleMax || in.Route != nil && !in.Route.valid() {
		return "", invalidRequest()
	}
	if in.Privacy != roomPublic && in.Privacy != roomPrivate && in.Privacy != roomPassword {
		return "", invalidRequest()
	}
	max := in.MaxRunners
	if max == 0 {
		max = roomDefaultRunners
	}
	if max < roomMinRunners || max > roomMaxRunners {
		return "", invalidRequest()
	}
	password := roomPasswordForm(in.Password)
	n := utf8.RuneCountInString(password)
	if in.Privacy == roomPassword && (n < roomPasswordMin || n > roomPasswordMax || len(password) > roomPasswordMaxBytes) ||
		in.Privacy != roomPassword && n > 0 {
		return "", invalidRequest()
	}
	startsAt := now
	if in.StartsAt != "" {
		t, err := time.Parse(time.RFC3339, in.StartsAt)
		if err != nil || t.After(now.Add(roomStartsWithin)) {
			return "", invalidRequest()
		}
		if t.After(now) {
			startsAt = t
		}
	}
	names, err := displayNames(ctx, s.db, []string{uid})
	if err != nil {
		return "", err
	}
	if title == "" {
		title = names[uid]
	}
	data := map[string]any{
		"hostUid": uid, "hostName": names[uid], "title": title, "privacy": in.Privacy, "kind": kind,
		"maxRunners": max, "runnerCount": 1, "status": roomOpen,
		"createdAt": now, "updatedAt": now, "startsAt": startsAt, "closesAt": startsAt.Add(roomOpenFor),
	}
	if in.Route != nil {
		data["route"] = in.Route.doc()
	}
	room := s.db.Collection("runRooms").NewDoc()
	batch := s.db.Batch()
	batch.Create(room, data)
	batch.Create(memberRef(room, uid), map[string]any{
		"uid": uid, "name": names[uid], "role": "host", "state": memberJoined, "joinedAt": now, "updatedAt": now,
	})
	if in.Privacy == roomPassword {
		hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
		if err != nil {
			return "", err
		}
		batch.Create(passwordRef(room), map[string]any{"hash": string(hash)})
	}
	if _, err := batch.Commit(ctx); err != nil {
		return "", err
	}
	if remind := startsAt.Add(-roomRemindBefore); remind.After(now) {
		s.notify(ctx, roomPushTask{Kind: roomPushStarting, RoomID: room.ID, At: startsAt.UnixMicro()}, &remind)
	}
	return room.ID, nil
}

// JoinResult là state của người gọi sau Join: joined, hoặc requested khi phòng
// cần chủ duyệt.
type JoinResult struct {
	State string `json:"state"`
}

// Join cho uid vào phòng. Gọi lại khi đã ở trong phòng thì trả state hiện tại,
// không tính thêm chỗ. Phòng mật khẩu kiểm mật khẩu trước transaction, vì
// bcrypt chậm mà transaction có thể chạy lại.
func (s *RunRoomStore) Join(ctx context.Context, roomID, uid, password string, now time.Time) (JoinResult, error) {
	var res JoinResult
	room := s.roomRef(roomID)
	needs, err := s.passwordGate(ctx, room, uid, now)
	if err != nil {
		return res, err
	}
	if needs {
		if err := s.checkPassword(ctx, room, uid, password, now); err != nil {
			return res, err
		}
	}
	names, err := displayNames(ctx, s.db, []string{uid})
	if err != nil {
		return res, err
	}
	fresh := false
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		fresh = false
		r, err := tx.Get(room)
		if status.Code(err) == codes.NotFound {
			return errRoomNotFound
		}
		if err != nil {
			return err
		}
		data := r.Data()
		if !roomIsOpen(data, now) {
			return errRoomClosed
		}
		m, err := tx.Get(memberRef(room, uid))
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		if m.Exists() {
			switch st := stringValue(m.Data()["state"]); st {
			case memberJoined, memberRequested:
				res.State = st
				return nil
			case memberKicked:
				return errRoomKicked
			case memberDenied:
				return errRoomDenied
			}
		}
		if stringValue(data["privacy"]) == roomPrivate {
			res.State = memberRequested
			fresh = true
			return tx.Set(memberRef(room, uid), map[string]any{
				"uid": uid, "name": names[uid], "role": "runner", "state": memberRequested, "requestedAt": now, "updatedAt": now,
			})
		}
		if number(data["runnerCount"]) >= number(data["maxRunners"]) {
			return errRoomFull
		}
		res.State = memberJoined
		if err := tx.Set(memberRef(room, uid), map[string]any{
			"uid": uid, "name": names[uid], "role": "runner", "state": memberJoined, "joinedAt": now, "updatedAt": now,
		}); err != nil {
			return err
		}
		return addRunner(tx, room, 1, now)
	})
	if err == nil && fresh {
		s.notify(ctx, roomPushTask{Kind: roomPushRequest, RoomID: roomID, UID: uid, At: now.UnixMicro()}, nil)
	}
	return res, err
}

// passwordGate cho biết có phải so mật khẩu không: phòng mật khẩu và uid
// chưa ở trong phòng. Phòng đã đóng, hay uid đã bị mời ra, từ chối thì báo
// luôn ở đây, không chạy bcrypt. Phòng không có thì để transaction của Join
// trả room_not_found.
func (s *RunRoomStore) passwordGate(ctx context.Context, room *firestore.DocumentRef, uid string, now time.Time) (bool, error) {
	r, err := room.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if stringValue(r.Data()["privacy"]) != roomPassword {
		return false, nil
	}
	if !roomIsOpen(r.Data(), now) {
		return false, errRoomClosed
	}
	m, err := memberRef(room, uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	switch stringValue(m.Data()["state"]) {
	case memberJoined:
		return false, nil
	case memberKicked:
		return false, errRoomKicked
	case memberDenied:
		return false, errRoomDenied
	}
	return true, nil
}

// roomPasswordForm đưa mật khẩu về NFC: bàn phím tiếng Việt có thể gửi chữ
// có dấu dạng tổ hợp (NFD), gõ đúng vẫn bị báo sai nếu so từng byte.
func roomPasswordForm(password string) string {
	return norm.NFC.String(password)
}

// checkPassword so mật khẩu với hash. Sai thì đếm vào attempts của uid, cứ
// roomMaxFails lần thì khoá tới lockedUntil theo roomLockSteps; đúng thì xoá
// bộ đếm.
func (s *RunRoomStore) checkPassword(ctx context.Context, room *firestore.DocumentRef, uid, password string, now time.Time) error {
	if password == "" {
		return errRoomPassword
	}
	attempts := attemptRef(room, uid)
	a, err := attempts.Get(ctx)
	if err != nil && status.Code(err) != codes.NotFound {
		return err
	}
	if a.Exists() {
		if until, ok := a.Data()["lockedUntil"].(time.Time); ok && now.Before(until) {
			return roomLocked(until, now)
		}
	}
	p, err := passwordRef(room).Get(ctx)
	if err != nil {
		return err
	}
	err = bcrypt.CompareHashAndPassword([]byte(stringValue(p.Data()["hash"])), []byte(roomPasswordForm(password)))
	if err == nil {
		if a.Exists() {
			_, err := attempts.Delete(ctx)
			return err
		}
		return nil
	}
	if !errors.Is(err, bcrypt.ErrMismatchedHashAndPassword) {
		return err
	}
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		a, err := tx.Get(attempts)
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		fails := 1
		if a.Exists() {
			fails = int(number(a.Data()["fails"])) + 1
		}
		var lockedUntil any
		if fails%roomMaxFails == 0 {
			step := min(fails/roomMaxFails, len(roomLockSteps)) - 1
			lockedUntil = now.Add(roomLockSteps[step])
		}
		return tx.Set(attempts, map[string]any{"fails": fails, "lockedUntil": lockedUntil})
	})
	if err != nil {
		return err
	}
	return errWrongPassword
}

func roomLocked(until, now time.Time) error {
	return &HTTPError{Status: http.StatusTooManyRequests, Code: "room_locked",
		Message: "Sai mật khẩu nhiều lần, thử lại sau ít phút.",
		Extra:   map[string]any{"retryAfterSeconds": int(until.Sub(now).Seconds()) + 1}}
}

func addRunner(tx *firestore.Transaction, room *firestore.DocumentRef, n int, now time.Time) error {
	return tx.Update(room, []firestore.Update{
		{Path: "runnerCount", Value: firestore.Increment(n)},
		{Path: "updatedAt", Value: now},
	})
}

// Việc chủ phòng làm với một thành viên.
const (
	roomApprove = "approve"
	roomDeny    = "deny"
	roomKick    = "kick"
)

// Moderate là chủ phòng duyệt, từ chối người xin vào, hoặc mời một người đang
// chạy ra khỏi phòng.
func (s *RunRoomStore) Moderate(ctx context.Context, roomID, host, target, action string, now time.Time) error {
	room := s.roomRef(roomID)
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		data, err := s.hostRoom(tx, room, host, now)
		if err != nil {
			return err
		}
		m, err := tx.Get(memberRef(room, target))
		if status.Code(err) == codes.NotFound {
			return errMemberNotFound
		}
		if err != nil {
			return err
		}
		st := stringValue(m.Data()["state"])
		switch action {
		case roomApprove, roomDeny:
			if st != memberRequested {
				return errMemberNotRequested
			}
			if action == roomDeny {
				return tx.Update(m.Ref, []firestore.Update{{Path: "state", Value: memberDenied}, {Path: "updatedAt", Value: now}})
			}
			if number(data["runnerCount"]) >= number(data["maxRunners"]) {
				return errRoomFull
			}
			if err := tx.Update(m.Ref, []firestore.Update{
				{Path: "state", Value: memberJoined}, {Path: "joinedAt", Value: now}, {Path: "updatedAt", Value: now},
			}); err != nil {
				return err
			}
			return addRunner(tx, room, 1, now)
		case roomKick:
			if target == host || st != memberJoined {
				return errMemberNotJoined
			}
			if err := tx.Update(m.Ref, []firestore.Update{{Path: "state", Value: memberKicked}, {Path: "updatedAt", Value: now}}); err != nil {
				return err
			}
			return addRunner(tx, room, -1, now)
		}
		return invalidRequest()
	})
	if err != nil {
		return err
	}
	switch action {
	case roomApprove:
		s.notify(ctx, roomPushTask{Kind: roomPushApproved, RoomID: roomID, UID: target, At: now.UnixMicro()}, nil)
	case roomDeny:
		s.notify(ctx, roomPushTask{Kind: roomPushDenied, RoomID: roomID, UID: target, At: now.UnixMicro()}, nil)
	}
	return nil
}

// Leave: người đang chạy hay đang chờ duyệt tự ra khỏi phòng. Gọi lại, hoặc đã
// bị mời ra, thì không đổi gì. Phòng đã đóng vẫn rời được.
func (s *RunRoomStore) Leave(ctx context.Context, roomID, uid string, now time.Time) error {
	room := s.roomRef(roomID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		m, err := tx.Get(memberRef(room, uid))
		if status.Code(err) == codes.NotFound {
			return errMemberNotFound
		}
		if err != nil {
			return err
		}
		if stringValue(m.Data()["role"]) == "host" {
			return errHostCannotLeave
		}
		st := stringValue(m.Data()["state"])
		if st != memberJoined && st != memberRequested {
			return nil
		}
		if err := tx.Update(m.Ref, []firestore.Update{{Path: "state", Value: memberLeft}, {Path: "updatedAt", Value: now}}); err != nil {
			return err
		}
		if st == memberJoined {
			return addRunner(tx, room, -1, now)
		}
		return nil
	})
}

// End: chủ phòng kết thúc phòng. Gọi lại thì không đổi gì.
func (s *RunRoomStore) End(ctx context.Context, roomID, uid string, now time.Time) error {
	room := s.roomRef(roomID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		r, err := tx.Get(room)
		if status.Code(err) == codes.NotFound {
			return errRoomNotFound
		}
		if err != nil {
			return err
		}
		if stringValue(r.Data()["hostUid"]) != uid {
			return errNotRoomHost
		}
		if stringValue(r.Data()["status"]) == roomEnded {
			return nil
		}
		return tx.Update(room, []firestore.Update{
			{Path: "status", Value: roomEnded}, {Path: "endedAt", Value: now}, {Path: "updatedAt", Value: now},
		})
	})
}

// VoiceMember trả tên uid trong phòng khi uid đã vào một phòng còn mở: chỉ
// người đang chạy cùng mới được nói chuyện.
func (s *RunRoomStore) VoiceMember(ctx context.Context, roomID, uid string, now time.Time) (string, error) {
	room := s.roomRef(roomID)
	r, err := room.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", errRoomNotFound
	}
	if err != nil {
		return "", err
	}
	if !roomIsOpen(r.Data(), now) {
		return "", errRoomClosed
	}
	m, err := memberRef(room, uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", errNotRoomMember
	}
	if err != nil {
		return "", err
	}
	if stringValue(m.Data()["state"]) != memberJoined {
		return "", errNotRoomMember
	}
	return stringValue(m.Data()["name"]), nil
}

// hostRoom đọc phòng trong tx và kiểm uid là chủ một phòng còn mở.
func (s *RunRoomStore) hostRoom(tx *firestore.Transaction, room *firestore.DocumentRef, uid string, now time.Time) (map[string]any, error) {
	r, err := tx.Get(room)
	if status.Code(err) == codes.NotFound {
		return nil, errRoomNotFound
	}
	if err != nil {
		return nil, err
	}
	data := r.Data()
	if stringValue(data["hostUid"]) != uid {
		return nil, errNotRoomHost
	}
	if !roomIsOpen(data, now) {
		return nil, errRoomClosed
	}
	return data, nil
}

func roomIsOpen(data map[string]any, now time.Time) bool {
	if stringValue(data["status"]) != roomOpen {
		return false
	}
	closes, ok := data["closesAt"].(time.Time)
	return ok && now.Before(closes)
}
