package backend

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

// GarminGateway gọi Garmin Connect Developer Program: OAuth 2.0 PKCE và
// Wellness API. Tài liệu: OAuth2PKCE.pdf trên developerportal.garmin.com.
// client_secret bắt buộc kể cả khi có PKCE, nên chỉ backend đổi mã lấy token.
type GarminGateway struct {
	clientID, clientSecret string
	client                 *http.Client
	authorizeURL, tokenURL string
	apiBaseURL             string
}

func NewGarminGateway(clientID, clientSecret string) *GarminGateway {
	return &GarminGateway{
		clientID: clientID, clientSecret: clientSecret,
		client:       &http.Client{Timeout: 20 * time.Second},
		authorizeURL: "https://connect.garmin.com/oauth2Confirm",
		tokenURL:     "https://connectapi.garmin.com/di-oauth2-service/oauth/token",
		apiBaseURL:   "https://apis.garmin.com/wellness-api/rest",
	}
}

// GarminAPIError là phản hồi không 2xx từ Garmin. Body đã cắt ngắn; phản hồi
// lỗi của Garmin không chứa token.
type GarminAPIError struct {
	Status int
	Body   string
}

func (e *GarminAPIError) Error() string { return fmt.Sprintf("Garmin API returned %d", e.Status) }

type garminToken struct {
	AccessToken           string `json:"access_token"`
	RefreshToken          string `json:"refresh_token"`
	ExpiresIn             int64  `json:"expires_in"`
	RefreshTokenExpiresIn int64  `json:"refresh_token_expires_in"`
	Scope                 string `json:"scope"`
}

// pkceChallenge là code_challenge S256 của verifier (RFC 7636 mục 4.2).
func pkceChallenge(verifier string) string {
	sum := sha256.Sum256([]byte(verifier))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}

func (g *GarminGateway) AuthorizationURL(redirectURI, state, verifier string) string {
	u, _ := url.Parse(g.authorizeURL)
	q := u.Query()
	q.Set("client_id", g.clientID)
	q.Set("response_type", "code")
	q.Set("code_challenge", pkceChallenge(verifier))
	q.Set("code_challenge_method", "S256")
	q.Set("redirect_uri", redirectURI)
	q.Set("state", state)
	u.RawQuery = q.Encode()
	return u.String()
}

// ExchangeCode gửi kèm redirect_uri vì bước authorize có gửi nó.
func (g *GarminGateway) ExchangeCode(ctx context.Context, code, verifier, redirectURI string) (garminToken, error) {
	return g.tokenRequest(ctx, url.Values{"grant_type": {"authorization_code"}, "code": {code}, "code_verifier": {verifier}, "redirect_uri": {redirectURI}})
}

// RefreshToken trả refresh token mới mỗi lần; bên gọi phải lưu lại nếu còn dùng.
func (g *GarminGateway) RefreshToken(ctx context.Context, refreshToken string) (garminToken, error) {
	return g.tokenRequest(ctx, url.Values{"grant_type": {"refresh_token"}, "refresh_token": {refreshToken}})
}

func (g *GarminGateway) tokenRequest(ctx context.Context, values url.Values) (garminToken, error) {
	values.Set("client_id", g.clientID)
	values.Set("client_secret", g.clientSecret)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, g.tokenURL, strings.NewReader(values.Encode()))
	if err != nil {
		return garminToken{}, err
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	var out garminToken
	if err := g.do(req, &out); err != nil {
		return garminToken{}, err
	}
	if out.AccessToken == "" || out.RefreshToken == "" {
		return garminToken{}, &GarminAPIError{Status: http.StatusBadGateway, Body: "token response without tokens"}
	}
	return out, nil
}

// UserID là id Garmin của người vừa cho quyền. Id này giữ nguyên qua các lần
// cho quyền lại, nên dùng làm khoá map push về uid.
func (g *GarminGateway) UserID(ctx context.Context, accessToken string) (string, error) {
	req, err := g.apiRequest(ctx, http.MethodGet, "/user/id", nil, accessToken)
	if err != nil {
		return "", err
	}
	var out struct {
		UserID string `json:"userId"`
	}
	if err := g.do(req, &out); err != nil {
		return "", err
	}
	if out.UserID == "" {
		return "", &GarminAPIError{Status: http.StatusBadGateway, Body: "user id response without userId"}
	}
	return out.UserID, nil
}

// Deregister gỡ đăng ký của user khỏi app. Garmin bắt gọi khi user ngắt kết nối.
func (g *GarminGateway) Deregister(ctx context.Context, accessToken string) error {
	req, err := g.apiRequest(ctx, http.MethodDelete, "/user/registration", nil, accessToken)
	if err != nil {
		return err
	}
	return g.do(req, nil)
}

// BackfillActivities xin Garmin đẩy lại các buổi trong [start, end). Garmin trả
// 202 rồi gửi dữ liệu qua push như bình thường. Mỗi lần tối đa 30 ngày, và chỉ
// gói Enterprise được dùng.
func (g *GarminGateway) BackfillActivities(ctx context.Context, accessToken string, start, end time.Time) error {
	q := url.Values{
		"summaryStartTimeInSeconds": {strconv.FormatInt(start.Unix(), 10)},
		"summaryEndTimeInSeconds":   {strconv.FormatInt(end.Unix(), 10)},
	}
	req, err := g.apiRequest(ctx, http.MethodGet, "/backfill/activities", q, accessToken)
	if err != nil {
		return err
	}
	return g.do(req, nil)
}

func (g *GarminGateway) apiRequest(ctx context.Context, method, path string, query url.Values, accessToken string) (*http.Request, error) {
	u := g.apiBaseURL + path
	if len(query) > 0 {
		u += "?" + query.Encode()
	}
	req, err := http.NewRequestWithContext(ctx, method, u, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	return req, nil
}

func (g *GarminGateway) do(req *http.Request, out any) error {
	resp, err := g.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return err
	}
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return &GarminAPIError{Status: resp.StatusCode, Body: truncateRunes(string(body), 300)}
	}
	if out == nil || len(body) == 0 {
		return nil
	}
	return json.Unmarshal(body, out)
}
