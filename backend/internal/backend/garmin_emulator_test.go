//go:build emulator

package backend

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// fakeGarmin đóng vai OAuth 1.0a và Wellness API của Garmin, kiểm chữ ký từng
// request với đúng secret: consumer khi xin request token, request token khi
// đổi access token, access token khi gọi API.
type fakeGarmin struct {
	t            *testing.T
	mu           sync.Mutex
	userID       string
	issued       int
	callbacks    []string
	verifiers    []string
	deregistered int
	backfillCode int
}

func (f *fakeGarmin) handler(w http.ResponseWriter, r *http.Request) {
	f.mu.Lock()
	defer f.mu.Unlock()
	switch {
	case r.URL.Path == "/request_token":
		oauth := verifyOAuthRequest(f.t, r, "secret-1", "")
		f.callbacks = append(f.callbacks, oauth["oauth_callback"])
		f.issued++
		_, _ = fmt.Fprintf(w, "oauth_token=rt-%d&oauth_token_secret=rs-%d&oauth_callback_confirmed=true", f.issued, f.issued)
		return
	case r.URL.Path == "/access_token":
		oauth := parseOAuthHeader(f.t, r.Header.Get("Authorization"))
		verifyOAuthRequest(f.t, r, "secret-1", strings.Replace(oauth["oauth_token"], "rt-", "rs-", 1))
		f.verifiers = append(f.verifiers, r.PostForm.Get("oauth_verifier"))
		_, _ = w.Write([]byte("oauth_token=at&oauth_token_secret=as"))
		return
	}
	if oauth := verifyOAuthRequest(f.t, r, "secret-1", "as"); oauth["oauth_token"] != "at" {
		f.t.Errorf("%s gọi bằng token %q, muốn access token", r.URL.Path, oauth["oauth_token"])
	}
	w.Header().Set("Content-Type", "application/json")
	switch {
	case r.URL.Path == "/user/id":
		_, _ = fmt.Fprintf(w, `{"userId":%q}`, f.userID)
	case r.URL.Path == "/backfill/activities":
		w.WriteHeader(f.backfillCode)
	case r.URL.Path == "/user/registration" && r.Method == http.MethodDelete:
		f.deregistered++
		w.WriteHeader(http.StatusNoContent)
	default:
		w.WriteHeader(http.StatusNotFound)
	}
}

type garminHarness struct {
	db     *firestore.Client
	svc    *GarminService
	fake   *fakeGarmin
	tasks  *recordingTasks
	mobile string
}

func newGarminHarness(t *testing.T) *garminHarness {
	t.Helper()
	db := emulatorDB(t)
	fake := &fakeGarmin{t: t, userID: "g-1", backfillCode: http.StatusForbidden}
	srv := httptest.NewServer(http.HandlerFunc(fake.handler))
	t.Cleanup(srv.Close)
	gateway := NewGarminGateway("client-1", "secret-1")
	gateway.requestTokenURL = srv.URL + "/request_token"
	gateway.accessTokenURL = srv.URL + "/access_token"
	gateway.apiBaseURL = srv.URL
	tasks, rec := newRecordingTaskPublisher(t)
	activities := NewActivityService(db, nil, nil, tasks, nil, "", "")
	config := Config{
		GarminClientID: "client-1", GarminClientSecret: "secret-1", GarminWebhookToken: "tok-1",
		PublicBaseURL: "https://api.example", MobileReturnURI: "com.threei.run://localhost/oauth", WebReturnURI: "https://web.example/oauth",
	}
	return &garminHarness{db: db, svc: NewGarminService(db, gateway, activities, config), fake: fake, tasks: rec, mobile: config.MobileReturnURI}
}

// connect chạy trọn Authorization rồi Callback như trình duyệt, trả URL app nhận.
func (h *garminHarness) connect(t *testing.T, uid string) *url.URL {
	t.Helper()
	ctx := context.Background()
	raw, err := h.svc.Authorization(ctx, uid, "mobile")
	if err != nil {
		t.Fatal(err)
	}
	auth, _ := url.Parse(raw)
	redirect, err := h.svc.Callback(ctx, auth.Query().Get("oauth_token"), "v-"+uid)
	if err != nil {
		t.Fatal(err)
	}
	h.fake.mu.Lock()
	callback, verifier := h.fake.callbacks[len(h.fake.callbacks)-1], h.fake.verifiers[len(h.fake.verifiers)-1]
	h.fake.mu.Unlock()
	if callback != "https://api.example/v1/garmin/callback" || auth.Query().Get("oauth_callback") != callback || verifier != "v-"+uid {
		t.Fatalf("callback = %q, url = %s, verifier = %q", callback, raw, verifier)
	}
	u, err := url.Parse(redirect)
	if err != nil {
		t.Fatal(err)
	}
	return u
}

func (h *garminHarness) push(t *testing.T, body string) {
	t.Helper()
	p, err := decodeGarminPush(strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	if err := h.svc.HandlePush(context.Background(), p); err != nil {
		t.Fatal(err)
	}
}

func (h *garminHarness) data(t *testing.T, path string) map[string]any {
	t.Helper()
	snap, err := h.db.Doc(path).Get(context.Background())
	if err != nil {
		return nil
	}
	return snap.Data()
}

func garminRunJSON(userID string, activityID int64, kind string, start time.Time, meters float64) string {
	return fmt.Sprintf(`{"userId":%q,"summaryId":"s-%d","activityId":%d,"activityType":%q,"activityName":"Chạy sáng",
		"startTimeInSeconds":%d,"durationInSeconds":1500,"distanceInMeters":%v,"deviceName":"Forerunner 265"}`,
		userID, activityID, activityID, kind, start.Unix(), meters)
}

func TestEmulatorGarminConnectThenPushStoresRuns(t *testing.T) {
	h := newGarminHarness(t)
	got := h.connect(t, "u1")
	if got.Query().Get("garmin") != "connected" || !strings.HasPrefix(got.String(), h.mobile) {
		t.Fatalf("redirect = %s", got)
	}
	if link := h.data(t, "garminUserLinks/g-1"); link["uid"] != "u1" {
		t.Fatalf("link = %v", link)
	}
	conn := h.data(t, "garminConnections/u1")
	if conn["status"] != "active" || conn["accessToken"] != "at" || conn["accessTokenSecret"] != "as" || conn["aiConsentAt"] == nil {
		t.Fatalf("connection = %v", conn)
	}
	// Gói không có backfill: Garmin trả 403 mà vẫn nối xong.
	if conn["backfillStatus"] != "rejected" {
		t.Fatalf("backfillStatus = %v", conn["backfillStatus"])
	}
	if h.data(t, "users/u1")["garminConnected"] != true {
		t.Fatal("users/u1.garminConnected chưa bật")
	}

	start := time.Date(2026, 10, 20, 23, 0, 0, 0, time.UTC)
	seedActivity(t, h.db, "u1", "9001", "strava", start.Format(time.RFC3339), 5000, 25)
	body := `{"activities":[` +
		garminRunJSON("g-1", 21468990741, "RUNNING", start.Add(time.Minute), 5012.3) + `,` +
		garminRunJSON("g-1", 21468990742, "TRAIL_RUNNING", start.Add(5*time.Hour), 8000) + `,` +
		garminRunJSON("g-1", 21468990743, "CYCLING", start.Add(9*time.Hour), 20000) + `,` +
		garminRunJSON("g-unknown", 21468990744, "RUNNING", start, 5000) +
		`],"activityDetails":[{"userId":"g-1","summaryId":"s-1-detail"}]}`
	h.push(t, body)

	dup := h.data(t, "users/u1/activities/garmin-21468990741")
	if dup == nil || dup["source"] != "garmin" || dup["distanceMeters"] != 5012.3 || dup["recordingDevice"] != "Garmin Forerunner 265" {
		t.Fatalf("buổi trùng Strava = %v", dup)
	}
	if dup["duplicateOfActivityId"] != "9001" {
		t.Fatalf("duplicateOfActivityId = %v, muốn 9001", dup["duplicateOfActivityId"])
	}
	trail := h.data(t, "users/u1/activities/garmin-21468990742")
	if trail == nil || trail["sportType"] != "Run" || trail["duplicateOfActivityId"] != nil {
		t.Fatalf("buổi trail = %v", trail)
	}
	if h.data(t, "users/u1/activities/garmin-21468990743") != nil {
		t.Fatal("đạp xe không được lưu")
	}
	if n := len(h.tasks.bodiesTo(t, "/tasks/rebuild-derived-data")); n != 1 {
		t.Fatalf("rebuild-derived-data = %d task, muốn 1", n)
	}
	if h.data(t, "garminConnections/u1")["lastPushAt"] == nil {
		t.Fatal("thiếu lastPushAt")
	}

	// Garmin gửi lại đúng lần đẩy đó: ghi đè, không sinh doc mới.
	h.push(t, body)
	docs, err := h.db.Collection("users").Doc("u1").Collection("activities").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(docs) != 3 {
		t.Fatalf("có %d doc, muốn 3 (Strava + 2 Garmin)", len(docs))
	}
}

// Garmin trả về không kèm verifier là không cấp quyền: báo app và để lại dấu
// vết, không đổi token.
func TestEmulatorGarminCallbackWithoutVerifierIsReported(t *testing.T) {
	h := newGarminHarness(t)
	ctx := context.Background()
	raw, err := h.svc.Authorization(ctx, "u1", "mobile")
	if err != nil {
		t.Fatal(err)
	}
	auth, _ := url.Parse(raw)
	redirect, err := h.svc.Callback(ctx, auth.Query().Get("oauth_token"), "")
	if err != nil {
		t.Fatal(err)
	}
	got, _ := url.Parse(redirect)
	if got.Query().Get("garminError") != "garmin_authorization_failed" {
		t.Fatalf("redirect = %s", redirect)
	}
	if code := h.data(t, "garminConnections/u1")["lastErrorCode"]; code != "garmin_authorization_failed" {
		t.Fatalf("lastErrorCode = %v", code)
	}
	if len(h.fake.verifiers) != 0 {
		t.Fatal("không có verifier thì không được gọi access_token")
	}
	// Request token chỉ dùng được một lần.
	if _, err := h.svc.Callback(ctx, auth.Query().Get("oauth_token"), "v-1"); err == nil {
		t.Fatal("request token dùng lại được")
	}
}

func TestEmulatorGarminAccountLinkedToAnotherUserIsRejected(t *testing.T) {
	h := newGarminHarness(t)
	h.connect(t, "u1")
	got := h.connect(t, "u2")
	if got.Query().Get("garminError") != "garmin_user_already_linked" || got.Query().Get("error") != "" {
		t.Fatalf("redirect = %s", got)
	}
	if link := h.data(t, "garminUserLinks/g-1"); link["uid"] != "u1" {
		t.Fatalf("link = %v, phải giữ u1", link)
	}
	if h.data(t, "users/u2")["garminConnected"] == true {
		t.Fatal("u2 không được nối")
	}
}

func TestEmulatorGarminRelinkToOtherAccountDropsOldLink(t *testing.T) {
	h := newGarminHarness(t)
	h.connect(t, "u1")
	h.fake.userID = "g-2"
	h.connect(t, "u1")
	if h.data(t, "garminUserLinks/g-1") != nil {
		t.Fatal("link g-1 cũ còn: push của tài khoản cũ vẫn đổ về u1")
	}
	if link := h.data(t, "garminUserLinks/g-2"); link["uid"] != "u1" {
		t.Fatalf("link g-2 = %v", link)
	}
}

func TestEmulatorGarminDeregistrationPushRevokes(t *testing.T) {
	h := newGarminHarness(t)
	h.connect(t, "u1")
	h.push(t, `{"deregistrations":[{"userId":"g-1"}]}`)
	if h.data(t, "garminUserLinks/g-1") != nil {
		t.Fatal("link còn sau deregistration")
	}
	conn := h.data(t, "garminConnections/u1")
	if conn["status"] != "revoked" || conn["accessToken"] != nil || conn["accessTokenSecret"] != nil {
		t.Fatalf("connection = %v", conn)
	}
	if h.data(t, "users/u1")["garminConnected"] != false {
		t.Fatal("garminConnected chưa tắt")
	}
	// Push tới sau khi user gỡ thì bỏ qua.
	h.push(t, `{"activities":[`+garminRunJSON("g-1", 1, "RUNNING", time.Date(2026, 10, 20, 1, 0, 0, 0, time.UTC), 5000)+`]}`)
	if h.data(t, "users/u1/activities/garmin-1") != nil {
		t.Fatal("push sau deregistration vẫn được ghi")
	}
}

func TestEmulatorGarminDisconnectDeregisters(t *testing.T) {
	h := newGarminHarness(t)
	h.connect(t, "u1")
	if err := h.svc.Disconnect(context.Background(), "u1"); err != nil {
		t.Fatal(err)
	}
	if h.fake.deregistered != 1 {
		t.Fatalf("deregister = %d, muốn 1", h.fake.deregistered)
	}
	if h.data(t, "garminUserLinks/g-1") != nil || h.data(t, "garminConnections/u1")["status"] != "revoked" {
		t.Fatal("chưa gỡ link hay connection")
	}
	st, err := h.svc.Status(context.Background(), "u1")
	if err != nil || st.Connected || !st.Available {
		t.Fatalf("status = %+v, %v", st, err)
	}
}

// Xoá tài khoản không được xoá link Garmin mà người khác đã nối lại.
func TestEmulatorAccountDeleteKeepsGarminLinkOfOtherUser(t *testing.T) {
	db := emulatorDB(t)
	seed(t, db, "garminConnections/u1", map[string]any{"garminUserId": "g-1", "status": "revoked"})
	seed(t, db, "garminUserLinks/g-1", map[string]any{"uid": "u2"})
	seed(t, db, "garminConnections/u3", map[string]any{"garminUserId": "g-3", "status": "active"})
	seed(t, db, "garminUserLinks/g-3", map[string]any{"uid": "u3"})
	accounts := NewAccountService(db, nil, nil, nil)
	ctx := context.Background()
	if err := accounts.deleteGarmin(ctx, "u1", "g-1"); err != nil {
		t.Fatal(err)
	}
	if err := accounts.deleteGarmin(ctx, "u3", "g-3"); err != nil {
		t.Fatal(err)
	}
	if snap, err := db.Doc("garminUserLinks/g-1").Get(ctx); err != nil || snap.Data()["uid"] != "u2" {
		t.Fatal("link của u2 bị xoá")
	}
	for _, path := range []string{"garminConnections/u1", "garminConnections/u3", "garminUserLinks/g-3"} {
		if snap, _ := db.Doc(path).Get(ctx); snap != nil && snap.Exists() {
			t.Errorf("%s còn", path)
		}
	}
}
