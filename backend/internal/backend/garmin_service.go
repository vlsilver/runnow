package backend

import (
	"context"
	"crypto/subtle"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// GarminService nối tài khoản Garmin Connect và nhận buổi chạy Garmin đẩy về.
//
// Dữ liệu:
//   - garminConnections/{uid}: token, garminUserId, status (active|revoked).
//   - garminUserLinks/{garminUserId}: uid, để map push về đúng người.
//   - users/{uid}/activities/garmin-{activityId}: buổi chạy, source "garmin".
//
// Push mang sẵn dữ liệu buổi chạy nên được ghi ngay trong request (Garmin chờ
// tối đa 30 giây). Lỗi thì trả 500 để Garmin gửi lại; ghi theo doc id cố định
// nên gửi lại chỉ ghi đè.
type GarminService struct {
	db                                         *firestore.Client
	gateway                                    *GarminGateway
	activities                                 *ActivityService
	enabled                                    bool
	webhookToken                               string
	callbackURL, mobileReturnURI, webReturnURI string
	now                                        func() time.Time
}

func NewGarminService(db *firestore.Client, g *GarminGateway, activities *ActivityService, c Config) *GarminService {
	return &GarminService{
		db: db, gateway: g, activities: activities,
		enabled: c.GarminEnabled(), webhookToken: c.GarminWebhookToken,
		callbackURL:     c.PublicBaseURL + "/v1/garmin/callback",
		mobileReturnURI: c.MobileReturnURI, webReturnURI: c.WebReturnURI,
		now: time.Now,
	}
}

// garminBackfillWindow là khoảng Garmin cho xin lại mỗi lần (tối đa 30 ngày).
const garminBackfillWindow = 30 * 24 * time.Hour

// garminPushLimit: Garmin bắt nhận được push tới 10 MB khi duyệt production.
const garminPushLimit = 16 << 20

func errGarminNotConfigured() error {
	return &HTTPError{Status: 503, Code: "garmin_not_configured", Message: "Garmin is not configured"}
}

// Authorization xin request token rồi trả trang cho phép của Garmin. OAuth
// 1.0a không có state: callback mang lại oauth_token, nên oauthStates khoá
// theo request token và giữ secret của nó để đổi access token.
func (s *GarminService) Authorization(ctx context.Context, uid, target string) (string, error) {
	if !s.enabled {
		return "", errGarminNotConfigured()
	}
	if target != "mobile" && target != "web" {
		return "", &HTTPError{Status: 400, Code: "invalid_request", Message: "Invalid OAuth return target"}
	}
	request, err := s.gateway.RequestToken(ctx, s.callbackURL)
	if err != nil {
		return "", fmt.Errorf("garmin request token: %w", err)
	}
	_, err = s.db.Collection("oauthStates").Doc(hashState(request.Token)).Create(ctx, map[string]any{
		"provider": "garmin", "uid": uid, "returnTarget": target, "requestTokenSecret": request.Secret,
		"createdAt": firestore.ServerTimestamp, "expiresAt": s.now().Add(10 * time.Minute),
	})
	if err != nil {
		return "", err
	}
	return s.gateway.AuthorizationURL(request.Token, s.callbackURL), nil
}

func (s *GarminService) Callback(ctx context.Context, requestToken, verifier string) (string, error) {
	state, err := consumeOAuthState(ctx, s.db, "garmin", requestToken)
	if err != nil {
		return "", err
	}
	returnURI := s.mobileReturnURI
	if state.Target == "web" {
		returnURI = s.webReturnURI
	}
	// garminError chứ không phải error: deep link trả về dùng chung với Strava,
	// và app cũ đọc error là lỗi Strava. Không có verifier là Garmin không cấp
	// quyền; OAuth 1.0a không nói lý do nên ghi lại để điều tra.
	if verifier == "" || state.Secret == "" {
		return s.failure(ctx, state.UID, returnURI, "garmin_authorization_failed", errors.New("garmin callback without oauth_verifier"))
	}
	if !s.enabled {
		return withQuery(returnURI, map[string]string{"garminError": "garmin_not_configured"}), nil
	}
	access, err := s.gateway.AccessToken(ctx, garminCredentials{Token: requestToken, Secret: state.Secret}, verifier)
	if err != nil {
		return s.failure(ctx, state.UID, returnURI, "garmin_token_failed", err)
	}
	userID, err := s.gateway.UserID(ctx, access)
	if err != nil {
		return s.failure(ctx, state.UID, returnURI, "garmin_user_failed", err)
	}
	if err := s.link(ctx, state.UID, userID, access); err != nil {
		code := "garmin_link_failed"
		var httpErr *HTTPError
		if errors.As(err, &httpErr) {
			code = httpErr.Code
		}
		return s.failure(ctx, state.UID, returnURI, code, err)
	}
	if err := s.requestBackfill(ctx, state.UID, access); err != nil {
		return "", err
	}
	return withQuery(returnURI, map[string]string{"garmin": "connected"}), nil
}

func (s *GarminService) failure(ctx context.Context, uid, returnURI, code string, cause error) (string, error) {
	slog.WarnContext(ctx, "garmin.oauth_failed", "uid", uid, "code", code, "error", cause)
	_, err := s.db.Collection("garminConnections").Doc(uid).Set(ctx, map[string]any{
		"uid": uid, "lastErrorCode": code, "updatedAt": firestore.ServerTimestamp,
	}, firestore.MergeAll)
	if err != nil {
		return "", err
	}
	return withQuery(returnURI, map[string]string{"garminError": code}), nil
}

func (s *GarminService) link(ctx context.Context, uid, garminUserID string, access garminCredentials) error {
	connection := s.db.Collection("garminConnections").Doc(uid)
	link := s.db.Collection("garminUserLinks").Doc(garminUserID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		connSnap, connErr := tx.Get(connection)
		if connErr != nil && status.Code(connErr) != codes.NotFound {
			return connErr
		}
		linkSnap, linkErr := tx.Get(link)
		if linkErr != nil && status.Code(linkErr) != codes.NotFound {
			return linkErr
		}
		if linkErr == nil {
			if existing := stringValue(linkSnap.Data()["uid"]); existing != "" && existing != uid {
				return &HTTPError{Status: 409, Code: "garmin_user_already_linked", Message: "Garmin account is linked to another 3i account"}
			}
		}
		// Đổi sang tài khoản Garmin khác thì gỡ link cũ, kẻo push của tài khoản
		// cũ vẫn đổ về uid này.
		if connErr == nil {
			if previous := stringValue(connSnap.Data()["garminUserId"]); previous != "" && previous != garminUserID {
				if err := tx.Delete(s.db.Collection("garminUserLinks").Doc(previous)); err != nil {
					return err
				}
			}
		}
		if err := tx.Set(link, map[string]any{"uid": uid, "garminUserId": garminUserID, "linkedAt": firestore.ServerTimestamp}); err != nil {
			return err
		}
		if err := tx.Set(connection, map[string]any{
			"uid": uid, "garminUserId": garminUserID,
			"accessToken": access.Token, "accessTokenSecret": access.Secret, "status": "active",
			// User bấm nối sau khi đọc dòng đồng ý cho 3i bot dùng km từ
			// Garmin; rút lại bằng cách ngắt kết nối.
			"aiConsentAt":   firestore.ServerTimestamp,
			"lastErrorCode": firestore.Delete, "disconnectedAt": firestore.Delete,
			"linkedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp,
		}, firestore.MergeAll); err != nil {
			return err
		}
		return tx.Set(s.db.Collection("users").Doc(uid), map[string]any{
			"garminConnected": true, "garminLinkedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp,
		}, firestore.MergeAll)
	})
}

// requestBackfill xin Garmin đẩy lại 30 ngày gần nhất. Chỉ gói Enterprise và
// user có bật quyền dữ liệu cũ mới được, nên Garmin từ chối thì vẫn nối xong:
// ghi lý do vào connection và log, buổi mới vẫn về qua push.
func (s *GarminService) requestBackfill(ctx context.Context, uid string, access garminCredentials) error {
	now := s.now()
	result := map[string]any{"backfillRequestedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}
	if err := s.gateway.BackfillActivities(ctx, access, now.Add(-garminBackfillWindow), now); err != nil {
		slog.WarnContext(ctx, "garmin.backfill_rejected", "uid", uid, "error", err)
		result["backfillStatus"] = "rejected"
		result["backfillError"] = err.Error()
	} else {
		result["backfillStatus"] = "requested"
		result["backfillError"] = firestore.Delete
	}
	_, err := s.db.Collection("garminConnections").Doc(uid).Set(ctx, result, firestore.MergeAll)
	return err
}

type GarminConnectionStatus struct {
	// Available là backend đã cấu hình Garmin. App ẩn nút nối khi false.
	Available    bool       `json:"available"`
	Connected    bool       `json:"connected"`
	Status       string     `json:"status"`
	LastPushAt   *time.Time `json:"lastPushAt,omitempty"`
	Permissions  []string   `json:"permissions,omitempty"`
	LastErrorKey string     `json:"lastErrorCode,omitempty"`
}

func (s *GarminService) Status(ctx context.Context, uid string) (GarminConnectionStatus, error) {
	out := GarminConnectionStatus{Available: s.enabled, Status: "disconnected"}
	snap, err := s.db.Collection("garminConnections").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return out, nil
	}
	if err != nil {
		return GarminConnectionStatus{}, err
	}
	data := snap.Data()
	if st := stringValue(data["status"]); st != "" {
		out.Status = st
	}
	out.Connected = out.Status == "active" && stringValue(data["garminUserId"]) != ""
	if t, ok := data["lastPushAt"].(time.Time); ok {
		out.LastPushAt = &t
	}
	if raw, ok := data["permissions"].([]any); ok {
		for _, p := range raw {
			if v := stringValue(p); v != "" {
				out.Permissions = append(out.Permissions, v)
			}
		}
	}
	out.LastErrorKey = stringValue(data["lastErrorCode"])
	return out, nil
}

// Disconnect gỡ đăng ký trên Garmin (Garmin bắt app làm khi user ngắt) rồi gỡ
// link. Garmin trả 4xx (user đã gỡ bên Garmin, thiếu token) thì vẫn gỡ
// phía mình; 5xx hay lỗi mạng thì trả lỗi để user bấm lại.
func (s *GarminService) Disconnect(ctx context.Context, uid string) error {
	snap, err := s.db.Collection("garminConnections").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	data := snap.Data()
	if stringValue(data["status"]) == "active" && s.enabled {
		err := s.gateway.Deregister(ctx, garminCredentials{Token: stringValue(data["accessToken"]), Secret: stringValue(data["accessTokenSecret"])})
		var api *GarminAPIError
		if err != nil && (!errors.As(err, &api) || api.Status >= 500) {
			return err
		}
		if err != nil {
			slog.WarnContext(ctx, "garmin.deregister_rejected", "uid", uid, "error", err)
		}
	}
	return s.revokeLocal(ctx, uid, stringValue(data["garminUserId"]), "disconnected")
}

// revokeLocal gỡ connection và link của uid. Link chỉ bị xoá khi còn trỏ về
// đúng uid này.
func (s *GarminService) revokeLocal(ctx context.Context, uid, garminUserID, reason string) error {
	connection := s.db.Collection("garminConnections").Doc(uid)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		var link *firestore.DocumentRef
		if garminUserID != "" {
			link = s.db.Collection("garminUserLinks").Doc(garminUserID)
			linkSnap, err := tx.Get(link)
			if err != nil && status.Code(err) != codes.NotFound {
				return err
			}
			if err != nil || stringValue(linkSnap.Data()["uid"]) != uid {
				link = nil
			}
		}
		if link != nil {
			if err := tx.Delete(link); err != nil {
				return err
			}
		}
		if err := tx.Set(connection, map[string]any{
			"status": "revoked", "revokeReason": reason,
			"accessToken": firestore.Delete, "accessTokenSecret": firestore.Delete,
			"disconnectedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp,
		}, firestore.MergeAll); err != nil {
			return err
		}
		return tx.Set(s.db.Collection("users").Doc(uid), map[string]any{
			"garminConnected": false, "garminDisconnectedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp,
		}, firestore.MergeAll)
	})
}

// garminActivity là một summary trong push Activity API (mục 7.1).
// activityId lúc là số lúc là chuỗi tuỳ tài liệu, nên đọc vào any.
type garminActivity struct {
	UserID                            string  `json:"userId"`
	SummaryID                         string  `json:"summaryId"`
	ActivityID                        any     `json:"activityId"`
	ActivityName                      string  `json:"activityName"`
	ActivityType                      string  `json:"activityType"`
	StartTimeInSeconds                int64   `json:"startTimeInSeconds"`
	DurationInSeconds                 int64   `json:"durationInSeconds"`
	DistanceInMeters                  float64 `json:"distanceInMeters"`
	AverageHeartRateInBeatsPerMinute  float64 `json:"averageHeartRateInBeatsPerMinute"`
	AverageRunCadenceInStepsPerMinute float64 `json:"averageRunCadenceInStepsPerMinute"`
	ActiveKilocalories                float64 `json:"activeKilocalories"`
	TotalElevationGainInMeters        float64 `json:"totalElevationGainInMeters"`
	DeviceName                        string  `json:"deviceName"`
	Manual                            bool    `json:"manual"`
}

type garminUserRef struct {
	UserID string `json:"userId"`
}

type garminPermissionChange struct {
	UserID      string   `json:"userId"`
	Permissions []string `json:"permissions"`
}

// garminPush là một lần Garmin đẩy về. Một lần đẩy có thể chứa nhiều user.
// Loại khác (activityDetails, moveIQActivities…) bị bỏ qua.
type garminPush struct {
	Activities                []garminActivity         `json:"activities"`
	ManuallyUpdatedActivities []garminActivity         `json:"manuallyUpdatedActivities"`
	Deregistrations           []garminUserRef          `json:"deregistrations"`
	UserPermissionsChange     []garminPermissionChange `json:"userPermissionsChange"`
}

// garminSportTypes map activityType của Garmin (Activity API phụ lục A) về
// sportType của 3i. Mọi kiểu chạy về Run vì nguồn phụ chỉ được tính khi là
// Run (SelectOfficialActivities). Kiểu khác không lưu.
var garminSportTypes = map[string]string{
	"RUNNING": "Run", "INDOOR_RUNNING": "Run", "OBSTACLE_RUN": "Run", "STREET_RUNNING": "Run",
	"TRACK_RUNNING": "Run", "TRAIL_RUNNING": "Run", "TREADMILL_RUNNING": "Run",
	"ULTRA_RUN": "Run", "VIRTUAL_RUN": "Run",
	"WALKING": "Walk", "CASUAL_WALKING": "Walk", "SPEED_WALKING": "Walk",
	"HIKING": "Hike",
}

// garminDeviceLabel là nhãn nguồn theo brand guideline của Garmin: "Garmin
// [tên máy]", không có tên máy thì "Garmin".
func garminDeviceLabel(deviceName string) string {
	name := strings.TrimSpace(deviceName)
	if name == "" || strings.EqualFold(name, "unknown") {
		return "Garmin"
	}
	if strings.HasPrefix(strings.ToLower(name), "garmin") {
		return name
	}
	return "Garmin " + name
}

// garminActivityDoc dựng doc activity từ một summary. false là summary không
// lưu: không phải chạy/đi bộ, thiếu id hay số liệu vô lý.
func garminActivityDoc(a garminActivity, now time.Time) (map[string]any, bool) {
	sport := garminSportTypes[a.ActivityType]
	if sport == "" {
		return nil, false
	}
	// activityId giữ nguyên khi user sửa buổi trên Garmin Connect, còn summaryId
	// đổi theo loại push (bản chi tiết là "<id>-detail"), nên doc id theo activityId.
	sourceID := ""
	switch v := a.ActivityID.(type) {
	case json.Number:
		sourceID = v.String()
	case string:
		sourceID = strings.TrimSpace(v)
	}
	if sourceID == "" {
		sourceID = strings.TrimSpace(a.SummaryID)
	}
	if sourceID == "" || len(sourceID) > 100 || strings.ContainsAny(sourceID, "/ ") {
		return nil, false
	}
	if a.DurationInSeconds <= 0 || a.DurationInSeconds > 7*24*60*60 || a.DistanceInMeters <= 0 || a.DistanceInMeters > 1e7 {
		return nil, false
	}
	started := time.Unix(a.StartTimeInSeconds, 0).UTC()
	if a.StartTimeInSeconds <= 0 || started.After(now.Add(10*time.Minute)) {
		return nil, false
	}
	name := strings.TrimSpace(a.ActivityName)
	if name == "" {
		name = sportDisplayFor(sport).defaultName
	}
	doc := map[string]any{
		"id":                 "garmin-" + sourceID,
		"source":             "garmin",
		"sourceActivityId":   sourceID,
		"sportType":          sport,
		"name":               name,
		"manual":             a.Manual,
		"recordingDevice":    garminDeviceLabel(a.DeviceName),
		"startedAt":          started.Format(time.RFC3339Nano),
		"distanceMeters":     a.DistanceInMeters,
		"movingTimeSeconds":  a.DurationInSeconds,
		"elapsedTimeSeconds": a.DurationInSeconds,
		// Push chỉ có phần tóm tắt; thiếu cờ này thì app gọi hydrate (chỉ chạy
		// qua Strava) và màn chi tiết không mở được.
		"hydrated":  true,
		"updatedAt": firestore.ServerTimestamp,
	}
	optional := map[string]float64{
		"averageHeartRate":    a.AverageHeartRateInBeatsPerMinute,
		"averageCadence":      a.AverageRunCadenceInStepsPerMinute,
		"elevationGainMeters": a.TotalElevationGainInMeters,
		"caloriesKcal":        a.ActiveKilocalories,
	}
	for k, v := range optional {
		if v > 0 {
			doc[k] = v
		}
	}
	return doc, true
}

// ValidPushToken so đoạn bí mật trong đường dẫn webhook. Garmin không ký push,
// nên đây cùng với việc chỉ nhận userId đã liên kết là lớp chặn push giả.
func (s *GarminService) ValidPushToken(token string) bool {
	return s.enabled && token != "" && subtle.ConstantTimeCompare([]byte(token), []byte(s.webhookToken)) == 1
}

func decodeGarminPush(body io.Reader) (garminPush, error) {
	decoder := json.NewDecoder(io.LimitReader(body, garminPushLimit))
	decoder.UseNumber()
	var push garminPush
	err := decoder.Decode(&push)
	return push, err
}

// HandlePush xử lý một lần Garmin đẩy về. Trả lỗi là để Garmin gửi lại.
func (s *GarminService) HandlePush(ctx context.Context, push garminPush) error {
	links := map[string]string{}
	uidFor := func(garminUserID string) (string, error) {
		if uid, ok := links[garminUserID]; ok {
			return uid, nil
		}
		uid := ""
		if garminUserID != "" {
			snap, err := s.db.Collection("garminUserLinks").Doc(garminUserID).Get(ctx)
			if err != nil && status.Code(err) != codes.NotFound {
				return "", err
			}
			if err == nil {
				uid = stringValue(snap.Data()["uid"])
			}
		}
		links[garminUserID] = uid
		return uid, nil
	}

	for _, d := range push.Deregistrations {
		uid, err := uidFor(d.UserID)
		if err != nil {
			return err
		}
		if uid == "" {
			continue
		}
		if err := s.revokeLocal(ctx, uid, d.UserID, "deregistered"); err != nil {
			return err
		}
		links[d.UserID] = ""
	}
	for _, p := range push.UserPermissionsChange {
		uid, err := uidFor(p.UserID)
		if err != nil {
			return err
		}
		if uid == "" {
			continue
		}
		if _, err := s.db.Collection("garminConnections").Doc(uid).Set(ctx, map[string]any{
			"permissions": p.Permissions, "permissionsChangedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp,
		}, firestore.MergeAll); err != nil {
			return err
		}
	}

	now := s.now()
	touched := map[string][]time.Time{}
	stored, skipped := 0, 0
	for _, a := range append(push.Activities, push.ManuallyUpdatedActivities...) {
		uid, err := uidFor(a.UserID)
		if err != nil {
			return err
		}
		doc, ok := garminActivityDoc(a, now)
		if uid == "" || !ok {
			skipped++
			continue
		}
		// Trùng với một buổi Strava đang có thì đánh dấu để leaderboard không đếm đôi.
		if a.DistanceInMeters >= 500 {
			dupID, err := s.activities.preferredStravaDuplicate(ctx, uid, doc)
			if err != nil {
				return err
			}
			if dupID != "" {
				doc["duplicateOfActivityId"] = dupID
			}
		}
		id := stringValue(doc["id"])
		if _, err := s.db.Collection("users").Doc(uid).Collection("activities").Doc(id).Set(ctx, doc, firestore.MergeAll); err != nil {
			return err
		}
		started, _ := time.Parse(time.RFC3339Nano, stringValue(doc["startedAt"]))
		touched[uid] = append(touched[uid], started)
		stored++
	}
	for uid, instants := range touched {
		// Cause kèm thời điểm: Cloud Tasks giữ tên task đã chạy một lúc, nên
		// cause cố định thì lần sửa buổi ngay sau sẽ không được rebuild. Garmin
		// gửi lại push thì rebuild thêm lần nữa, vô hại.
		if err := s.activities.enqueueDerived(ctx, uid, fmt.Sprintf("garmin-push-%d", now.UnixNano())); err != nil {
			return err
		}
		if err := s.activities.enqueuePeriodStatsBatch(ctx, uid, instants); err != nil {
			return err
		}
		if _, err := s.db.Collection("garminConnections").Doc(uid).Set(ctx, map[string]any{
			"lastPushAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp,
		}, firestore.MergeAll); err != nil {
			return err
		}
	}
	if stored > 0 || skipped > 0 {
		slog.InfoContext(ctx, "garmin.push", "stored", stored, "skipped", skipped, "users", len(touched))
	}
	return nil
}

// garminUserIDOf đọc garminUserId của uid, rỗng khi chưa từng nối.
func garminUserIDOf(ctx context.Context, db *firestore.Client, uid string) (string, error) {
	snap, err := db.Collection("garminConnections").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", nil
	}
	if err != nil {
		return "", fmt.Errorf("read garmin connection: %w", err)
	}
	return stringValue(snap.Data()["garminUserId"]), nil
}
