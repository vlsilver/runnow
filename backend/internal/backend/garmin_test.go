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

// Ví dụ ở OAuth Core 1.0 phụ lục A.5.1–A.5.2 (RFC 5849 giữ nguyên thuật
// toán): chữ ký in trong spec là tR3+Ty81lMeYAr/Fid0kMTYa/WM=.
func TestOAuthSignatureMatchesSpecExample(t *testing.T) {
	params := url.Values{
		"file": {"vacation.jpg"}, "size": {"original"},
		"oauth_consumer_key": {"dpf43f3p2l4k3l03"}, "oauth_token": {"nnch734d00sl2jdk"},
		"oauth_signature_method": {"HMAC-SHA1"}, "oauth_timestamp": {"1191242096"},
		"oauth_nonce": {"kllo9940pd9333jh"}, "oauth_version": {"1.0"},
	}
	got := oauthSignature("GET", "http://photos.example.net/photos", params, "kd94hf93k423kf44", "pfkkdhi9sl3r4s00")
	if got != "tR3+Ty81lMeYAr/Fid0kMTYa/WM=" {
		t.Fatalf("signature = %s", got)
	}
}

// RFC 5849 mục 3.6: chỉ ký tự unreserved giữ nguyên, dấu cách là %20.
func TestOAuthEscape(t *testing.T) {
	if got := oauthEscape("a b+c~d.e_f-g/h=é"); got != "a%20b%2Bc~d.e_f-g%2Fh%3D%C3%A9" {
		t.Fatalf("escape = %s", got)
	}
}

// parseOAuthHeader đọc header Authorization: OAuth k="v", ... thành map. Chạy
// được trong handler của httptest nên báo lỗi bằng Errorf, không Fatalf.
func parseOAuthHeader(t *testing.T, header string) map[string]string {
	t.Helper()
	out := map[string]string{}
	if !strings.HasPrefix(header, "OAuth ") {
		t.Errorf("Authorization = %q", header)
		return out
	}
	for _, part := range strings.Split(strings.TrimPrefix(header, "OAuth "), ", ") {
		k, v, ok := strings.Cut(part, "=")
		if !ok {
			t.Errorf("phần header hỏng: %q", part)
			continue
		}
		key, _ := url.PathUnescape(k)
		val, _ := url.PathUnescape(strings.Trim(v, `"`))
		out[key] = val
	}
	return out
}

// verifyOAuthRequest kiểm chữ ký của request Garmin nhận được với hai secret
// đúng, gồm cả tham số query và form body.
func verifyOAuthRequest(t *testing.T, r *http.Request, consumerSecret, tokenSecret string) map[string]string {
	t.Helper()
	oauth := parseOAuthHeader(t, r.Header.Get("Authorization"))
	_ = r.ParseForm()
	params := url.Values{}
	for k, vs := range r.Form {
		params[k] = vs
	}
	for k, v := range oauth {
		if k != "oauth_signature" {
			params.Set(k, v)
		}
	}
	base := "http://" + r.Host + r.URL.Path
	if want := oauthSignature(r.Method, base, params, consumerSecret, tokenSecret); oauth["oauth_signature"] != want {
		t.Errorf("%s %s: chữ ký sai", r.Method, r.URL.Path)
	}
	return oauth
}

func TestGarminAccessTokenSignsVerifierWithRequestSecret(t *testing.T) {
	var oauth map[string]string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		oauth = verifyOAuthRequest(t, r, "consumer-secret", "request-secret")
		_, _ = w.Write([]byte("oauth_token=at&oauth_token_secret=as"))
	}))
	defer srv.Close()
	g := NewGarminGateway("consumer-1", "consumer-secret")
	g.accessTokenURL = srv.URL + "/access_token"
	got, err := g.AccessToken(context.Background(), garminCredentials{Token: "rt", Secret: "request-secret"}, "v-1")
	if err != nil {
		t.Fatal(err)
	}
	if got != (garminCredentials{Token: "at", Secret: "as"}) {
		t.Fatalf("access = %+v", got)
	}
	// oauth_verifier là tham số giao thức (RFC 5849 mục 2.3), nằm trong header
	// Authorization. Garmin không đọc nó trong form body và trả 401.
	if oauth["oauth_token"] != "rt" || oauth["oauth_consumer_key"] != "consumer-1" || oauth["oauth_signature_method"] != "HMAC-SHA1" || oauth["oauth_verifier"] != "v-1" {
		t.Fatalf("oauth = %v", oauth)
	}
}

func TestGarminAuthorizationURLCarriesTokenAndCallback(t *testing.T) {
	g := NewGarminGateway("consumer-1", "consumer-secret")
	u, err := url.Parse(g.AuthorizationURL("rt", "https://api.example/v1/garmin/callback"))
	if err != nil {
		t.Fatal(err)
	}
	if u.Host != "connect.garmin.com" || u.Path != "/oauthConfirm" ||
		u.Query().Get("oauth_token") != "rt" || u.Query().Get("oauth_callback") != "https://api.example/v1/garmin/callback" {
		t.Fatalf("url = %s", u)
	}
	if strings.Contains(u.String(), "consumer-secret") {
		t.Fatal("secret không được nằm trong URL gửi ra trình duyệt")
	}
}

func TestGarminGatewayReturnsAPIErrorStatus(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`invalid consumer`))
	}))
	defer srv.Close()
	g := NewGarminGateway("c", "s")
	g.requestTokenURL = srv.URL
	_, err := g.RequestToken(context.Background(), "https://api.example/cb")
	var api *GarminAPIError
	if !errors.As(err, &api) || api.Status != http.StatusUnauthorized {
		t.Fatalf("err = %v, muốn GarminAPIError 401", err)
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
