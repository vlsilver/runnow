package backend

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
	"time"
)

// URL lấy từ Garmin OAuth2.0 PKCE Specification, mục STEP 1, STEP 2 và User ID.
func TestGarminGatewayUsesSpecEndpoints(t *testing.T) {
	g := NewGarminGateway("c", "s")
	if g.authorizeURL != "https://connect.garmin.com/oauth2Confirm" ||
		g.tokenURL != "https://diauth.garmin.com/di-oauth2-service/oauth/token" ||
		g.apiBaseURL != "https://apis.garmin.com/wellness-api/rest" {
		t.Fatalf("endpoints = %s %s %s", g.authorizeURL, g.tokenURL, g.apiBaseURL)
	}
}

// Vector ở RFC 7636 phụ lục B.
func TestGarminPKCEChallengeMatchesRFC7636(t *testing.T) {
	if got := pkceChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"); got != "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM" {
		t.Fatalf("challenge = %s", got)
	}
}

func TestGarminAuthorizationURLCarriesPKCE(t *testing.T) {
	g := NewGarminGateway("client-1", "secret")
	u, err := url.Parse(g.AuthorizationURL("https://api.example/v1/garmin/callback", "st", "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"))
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	want := map[string]string{
		"client_id": "client-1", "response_type": "code", "state": "st",
		"code_challenge": "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM", "code_challenge_method": "S256",
		"redirect_uri": "https://api.example/v1/garmin/callback",
	}
	for k, v := range want {
		if q.Get(k) != v {
			t.Errorf("%s = %q, muốn %q", k, q.Get(k), v)
		}
	}
	if q.Has("client_secret") {
		t.Error("client_secret không được nằm trong URL gửi ra trình duyệt")
	}
}

func TestGarminTokenExchangeSendsSecretAndVerifier(t *testing.T) {
	var form url.Values
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_ = r.ParseForm()
		form = r.PostForm
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"access_token":"at","refresh_token":"rt","expires_in":86400,"refresh_token_expires_in":7776000,"scope":"ACTIVITY_EXPORT"}`))
	}))
	defer srv.Close()
	g := NewGarminGateway("client-1", "secret-1")
	g.tokenURL = srv.URL
	token, err := g.ExchangeCode(context.Background(), "code-1", "verifier-1", "https://api.example/cb")
	if err != nil {
		t.Fatal(err)
	}
	if token.AccessToken != "at" || token.RefreshToken != "rt" || token.ExpiresIn != 86400 || token.RefreshTokenExpiresIn != 7776000 {
		t.Fatalf("token = %+v", token)
	}
	want := map[string]string{
		"grant_type": "authorization_code", "code": "code-1", "code_verifier": "verifier-1",
		"redirect_uri": "https://api.example/cb", "client_id": "client-1", "client_secret": "secret-1",
	}
	for k, v := range want {
		if form.Get(k) != v {
			t.Errorf("%s = %q, muốn %q", k, form.Get(k), v)
		}
	}
}

func TestGarminGatewayReturnsAPIErrorStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"error":"invalid_grant"}`))
	}))
	defer srv.Close()
	g := NewGarminGateway("c", "s")
	g.tokenURL = srv.URL
	_, err := g.RefreshToken(context.Background(), "rt")
	var api *GarminAPIError
	if !errors.As(err, &api) || api.Status != http.StatusBadRequest {
		t.Fatalf("err = %v, muốn GarminAPIError 400", err)
	}
}

// Một summary theo mẫu ở Activity API mục 7.1.
func sampleGarminRun() garminActivity {
	return garminActivity{
		UserID: "g-1", SummaryID: "x153a9f3-5a8c4e78-6", ActivityID: "5001968355",
		ActivityName: "Hà Nội Running", ActivityType: "RUNNING",
		StartTimeInSeconds: time.Date(2026, 10, 20, 23, 1, 0, 0, time.UTC).Unix(),
		DurationInSeconds:  1500, DistanceInMeters: 5012.3,
		AverageHeartRateInBeatsPerMinute: 151, AverageRunCadenceInStepsPerMinute: 168,
		ActiveKilocalories: 320, DeviceName: "Forerunner 265",
	}
}

func TestGarminActivityDocMapsRun(t *testing.T) {
	now := time.Date(2026, 10, 21, 0, 0, 0, 0, time.UTC)
	doc, ok := garminActivityDoc(sampleGarminRun(), now)
	if !ok {
		t.Fatal("buổi chạy hợp lệ bị bỏ")
	}
	want := map[string]any{
		"id": "garmin-5001968355", "source": "garmin", "sourceActivityId": "5001968355",
		"sportType": "Run", "name": "Hà Nội Running", "recordingDevice": "Garmin Forerunner 265",
		"startedAt": "2026-10-20T23:01:00Z", "distanceMeters": 5012.3,
		"movingTimeSeconds": int64(1500), "elapsedTimeSeconds": int64(1500),
		"averageHeartRate": 151.0, "averageCadence": 168.0, "caloriesKcal": 320.0, "hydrated": true,
	}
	for k, v := range want {
		if doc[k] != v {
			t.Errorf("%s = %#v, muốn %#v", k, doc[k], v)
		}
	}
	if _, has := doc["elevationGainMeters"]; has {
		t.Error("không có độ cao thì không ghi trường")
	}
}

func TestGarminActivityDocSkipsUnsupportedAndBroken(t *testing.T) {
	now := time.Date(2026, 10, 21, 0, 0, 0, 0, time.UTC)
	cases := map[string]func(*garminActivity){
		"cycling":       func(a *garminActivity) { a.ActivityType = "CYCLING" },
		"multisport":    func(a *garminActivity) { a.ActivityType = "MULTI_SPORT" },
		"no distance":   func(a *garminActivity) { a.DistanceInMeters = 0 },
		"no duration":   func(a *garminActivity) { a.DurationInSeconds = 0 },
		"over a week":   func(a *garminActivity) { a.DurationInSeconds = 7*24*60*60 + 1 },
		"future":        func(a *garminActivity) { a.StartTimeInSeconds = now.Add(11 * time.Minute).Unix() },
		"slash in id":   func(a *garminActivity) { a.ActivityID = "a/b" },
		"no ids at all": func(a *garminActivity) { a.ActivityID = nil; a.SummaryID = "" },
	}
	for name, mutate := range cases {
		a := sampleGarminRun()
		mutate(&a)
		if _, ok := garminActivityDoc(a, now); ok {
			t.Errorf("%s: phải bị bỏ", name)
		}
	}
}

// activityId là số lớn trong JSON. Đọc thành float64 thì mất chữ số hoặc in
// ra dạng 5.001968355e+09, doc id sẽ lệch giữa các lần đẩy.
func TestDecodeGarminPushKeepsNumericActivityID(t *testing.T) {
	body := `{"activities":[{"userId":"g-1","summaryId":"s-1","activityId":21468990741,"activityType":"TRAIL_RUNNING",
		"startTimeInSeconds":1792537260,"durationInSeconds":1500,"distanceInMeters":5000,"someNewField":{"x":1}}]}`
	push, err := decodeGarminPush(strings.NewReader(body))
	if err != nil {
		t.Fatal(err)
	}
	doc, ok := garminActivityDoc(push.Activities[0], time.Unix(1792537260, 0).Add(time.Hour))
	if !ok || doc["id"] != "garmin-21468990741" {
		t.Fatalf("doc = %v, %v", doc["id"], ok)
	}
	if doc["name"] == "" {
		t.Fatal("thiếu activityName thì phải có tên mặc định")
	}
}

func TestGarminPushTokenCheck(t *testing.T) {
	on := NewGarminService(nil, nil, nil, Config{GarminClientID: "c", GarminClientSecret: "s", GarminWebhookToken: "tok-1"})
	off := NewGarminService(nil, nil, nil, Config{GarminWebhookToken: "tok-1"})
	if !on.ValidPushToken("tok-1") || on.ValidPushToken("tok-2") || on.ValidPushToken("") {
		t.Fatal("kiểm token sai khi Garmin bật")
	}
	if off.ValidPushToken("tok-1") {
		t.Fatal("Garmin chưa cấu hình đủ thì không nhận push")
	}
}

func TestGarminDeviceLabel(t *testing.T) {
	for in, want := range map[string]string{"": "Garmin", "unknown": "Garmin", "Forerunner 265": "Garmin Forerunner 265", "Garmin Venu 3": "Garmin Venu 3"} {
		if got := garminDeviceLabel(in); got != want {
			t.Errorf("%q → %q, muốn %q", in, got, want)
		}
	}
}
