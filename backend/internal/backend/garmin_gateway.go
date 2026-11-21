package backend

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strconv"
	"strings"
	"time"
)

// GarminGateway gọi Garmin Connect Developer Program bằng OAuth 1.0a (RFC 5849,
// HMAC-SHA1). Key cũ của app chưa được Garmin bật OAuth 2.0, nên dùng luồng
// OAuth 1.0a mà key vẫn chạy: xin request token, user cho phép ở oauthConfirm,
// đổi verifier lấy access token. Access token của user không hết hạn.
type GarminGateway struct {
	consumerKey, consumerSecret   string
	client                        *http.Client
	requestTokenURL, authorizeURL string
	accessTokenURL, apiBaseURL    string
	now                           func() time.Time
}

func NewGarminGateway(consumerKey, consumerSecret string) *GarminGateway {
	return &GarminGateway{
		consumerKey: consumerKey, consumerSecret: consumerSecret,
		client:          &http.Client{Timeout: 20 * time.Second},
		requestTokenURL: "https://connectapi.garmin.com/oauth-service/oauth/request_token",
		authorizeURL:    "https://connect.garmin.com/oauthConfirm",
		accessTokenURL:  "https://connectapi.garmin.com/oauth-service/oauth/access_token",
		apiBaseURL:      "https://apis.garmin.com/wellness-api/rest",
		now:             time.Now,
	}
}

// GarminAPIError là phản hồi không 2xx từ Garmin. Body đã cắt ngắn; phản hồi
// lỗi của Garmin không chứa token.
type GarminAPIError struct {
	Status int
	Body   string
}

func (e *GarminAPIError) Error() string { return fmt.Sprintf("Garmin API returned %d", e.Status) }

// garminCredentials là một cặp token OAuth 1.0a: request token lúc xin quyền,
// access token sau khi user cho phép.
type garminCredentials struct {
	Token, Secret string
}

// oauthEscape là percent-encoding của RFC 5849 mục 3.6: chỉ giữ ký tự
// unreserved. url.QueryEscape đổi dấu cách thành "+" nên không dùng được.
func oauthEscape(s string) string {
	var b strings.Builder
	for _, c := range []byte(s) {
		if 'A' <= c && c <= 'Z' || 'a' <= c && c <= 'z' || '0' <= c && c <= '9' || c == '-' || c == '.' || c == '_' || c == '~' {
			b.WriteByte(c)
		} else {
			fmt.Fprintf(&b, "%%%02X", c)
		}
	}
	return b.String()
}

// oauthSignature ký theo RFC 5849 mục 3.4 với HMAC-SHA1. params gồm các
// tham số oauth_*, query và form body; baseURL không kèm query.
func oauthSignature(method, baseURL string, params url.Values, consumerSecret, tokenSecret string) string {
	pairs := make([]string, 0, len(params))
	for k, vs := range params {
		for _, v := range vs {
			pairs = append(pairs, oauthEscape(k)+"="+oauthEscape(v))
		}
	}
	sort.Strings(pairs)
	base := method + "&" + oauthEscape(baseURL) + "&" + oauthEscape(strings.Join(pairs, "&"))
	mac := hmac.New(sha1.New, []byte(oauthEscape(consumerSecret)+"&"+oauthEscape(tokenSecret)))
	mac.Write([]byte(base))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

// authorize gắn header Authorization OAuth vào req. extra là tham số oauth_*
// thêm (oauth_callback). form là body đã encode, phải nằm trong chữ ký.
func (g *GarminGateway) authorize(req *http.Request, token garminCredentials, extra map[string]string, form url.Values) error {
	nonce := make([]byte, 16)
	if _, err := rand.Read(nonce); err != nil {
		return err
	}
	oauth := map[string]string{
		"oauth_consumer_key":     g.consumerKey,
		"oauth_nonce":            hex.EncodeToString(nonce),
		"oauth_signature_method": "HMAC-SHA1",
		"oauth_timestamp":        strconv.FormatInt(g.now().Unix(), 10),
		"oauth_version":          "1.0",
	}
	if token.Token != "" {
		oauth["oauth_token"] = token.Token
	}
	for k, v := range extra {
		oauth[k] = v
	}
	signed := url.Values{}
	for k, vs := range req.URL.Query() {
		signed[k] = vs
	}
	for k, vs := range form {
		signed[k] = append(signed[k], vs...)
	}
	for k, v := range oauth {
		signed.Set(k, v)
	}
	base := *req.URL
	base.RawQuery, base.Fragment = "", ""
	oauth["oauth_signature"] = oauthSignature(req.Method, base.String(), signed, g.consumerSecret, token.Secret)

	keys := make([]string, 0, len(oauth))
	for k := range oauth {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, len(keys))
	for i, k := range keys {
		parts[i] = oauthEscape(k) + `="` + oauthEscape(oauth[k]) + `"`
	}
	req.Header.Set("Authorization", "OAuth "+strings.Join(parts, ", "))
	return nil
}

// RequestToken xin request token. callbackURL gửi trong chữ ký theo OAuth 1.0a
// và gửi lại ở trang cho phép như Garmin yêu cầu.
func (g *GarminGateway) RequestToken(ctx context.Context, callbackURL string) (garminCredentials, error) {
	return g.tokenRequest(ctx, g.requestTokenURL, garminCredentials{}, map[string]string{"oauth_callback": callbackURL}, nil)
}

func (g *GarminGateway) AuthorizationURL(requestToken, callbackURL string) string {
	return g.authorizeURL + "?" + url.Values{"oauth_token": {requestToken}, "oauth_callback": {callbackURL}}.Encode()
}

// AccessToken đổi verifier Garmin trả về callback lấy access token của user.
// oauth_verifier là tham số giao thức nên nằm trong header; Garmin không đọc
// nó trong form body.
func (g *GarminGateway) AccessToken(ctx context.Context, request garminCredentials, verifier string) (garminCredentials, error) {
	return g.tokenRequest(ctx, g.accessTokenURL, request, map[string]string{"oauth_verifier": verifier}, nil)
}

func (g *GarminGateway) tokenRequest(ctx context.Context, endpoint string, token garminCredentials, extra map[string]string, form url.Values) (garminCredentials, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return garminCredentials{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if err := g.authorize(req, token, extra, form); err != nil {
		return garminCredentials{}, err
	}
	body, err := g.do(req)
	if err != nil {
		return garminCredentials{}, err
	}
	values, err := url.ParseQuery(string(body))
	if err != nil {
		return garminCredentials{}, &GarminAPIError{Status: http.StatusBadGateway, Body: "token response is not form encoded"}
	}
	out := garminCredentials{Token: values.Get("oauth_token"), Secret: values.Get("oauth_token_secret")}
	if out.Token == "" || out.Secret == "" {
		return garminCredentials{}, &GarminAPIError{Status: http.StatusBadGateway, Body: "token response without tokens"}
	}
	return out, nil
}

// UserID là id Garmin của người vừa cho quyền. Id này giữ nguyên qua các lần
// cho quyền lại, nên dùng làm khoá map push về uid.
func (g *GarminGateway) UserID(ctx context.Context, access garminCredentials) (string, error) {
	body, err := g.api(ctx, http.MethodGet, "/user/id", nil, access)
	if err != nil {
		return "", err
	}
	var out struct {
		UserID string `json:"userId"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		return "", err
	}
	if out.UserID == "" {
		return "", &GarminAPIError{Status: http.StatusBadGateway, Body: "user id response without userId"}
	}
	return out.UserID, nil
}

// Deregister gỡ đăng ký của user khỏi app. Garmin bắt gọi khi user ngắt kết nối.
func (g *GarminGateway) Deregister(ctx context.Context, access garminCredentials) error {
	_, err := g.api(ctx, http.MethodDelete, "/user/registration", nil, access)
	return err
}

// BackfillActivities xin Garmin đẩy lại các buổi trong [start, end). Garmin trả
// 202 rồi gửi dữ liệu qua push như bình thường. Mỗi lần tối đa 30 ngày.
func (g *GarminGateway) BackfillActivities(ctx context.Context, access garminCredentials, start, end time.Time) error {
	q := url.Values{
		"summaryStartTimeInSeconds": {strconv.FormatInt(start.Unix(), 10)},
		"summaryEndTimeInSeconds":   {strconv.FormatInt(end.Unix(), 10)},
	}
	_, err := g.api(ctx, http.MethodGet, "/backfill/activities", q, access)
	return err
}

func (g *GarminGateway) api(ctx context.Context, method, path string, query url.Values, access garminCredentials) ([]byte, error) {
	u := g.apiBaseURL + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, method, u, nil)
	if err != nil {
		return nil, err
	}
	if err := g.authorize(req, access, nil, nil); err != nil {
		return nil, err
	}
	return g.do(req)
}

func (g *GarminGateway) do(req *http.Request) ([]byte, error) {
	resp, err := g.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return nil, &GarminAPIError{Status: resp.StatusCode, Body: truncateRunes(string(body), 300)}
	}
	return body, nil
}
