package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type StravaGateway struct {
	clientID, clientSecret string
	client                 *http.Client
	baseURL                string
}

func NewStravaGateway(clientID, clientSecret string) *StravaGateway {
	return &StravaGateway{clientID: clientID, clientSecret: clientSecret, client: &http.Client{Timeout: 25 * time.Second}, baseURL: "https://www.strava.com"}
}

func (g *StravaGateway) AuthorizationURL(redirectURI, state string) string {
	u, _ := url.Parse(g.baseURL + "/oauth/authorize")
	q := u.Query()
	q.Set("client_id", g.clientID)
	q.Set("redirect_uri", redirectURI)
	q.Set("response_type", "code")
	q.Set("approval_prompt", "auto")
	q.Set("scope", "activity:read_all")
	q.Set("state", state)
	u.RawQuery = q.Encode()
	return u.String()
}

func (g *StravaGateway) ExchangeCode(ctx context.Context, code, redirectURI string) (StravaTokenResponse, error) {
	return g.tokenRequest(ctx, url.Values{"code": {code}, "redirect_uri": {redirectURI}, "grant_type": {"authorization_code"}})
}
func (g *StravaGateway) RefreshToken(ctx context.Context, token string) (StravaTokenResponse, error) {
	return g.tokenRequest(ctx, url.Values{"refresh_token": {token}, "grant_type": {"refresh_token"}})
}
func (g *StravaGateway) tokenRequest(ctx context.Context, values url.Values) (StravaTokenResponse, error) {
	values.Set("client_id", g.clientID)
	values.Set("client_secret", g.clientSecret)
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, g.baseURL+"/oauth/token", strings.NewReader(values.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	var out StravaTokenResponse
	err := g.doJSON(req, &out)
	return out, err
}
func (g *StravaGateway) Revoke(ctx context.Context, token string) error {
	req, _ := http.NewRequestWithContext(ctx, http.MethodPost, g.baseURL+"/oauth/deauthorize", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	return g.doJSON(req, nil)
}
func (g *StravaGateway) ListActivities(ctx context.Context, token string, page, perPage int, after *int64) ([]StravaActivity, error) {
	u, _ := url.Parse(g.baseURL + "/api/v3/athlete/activities")
	q := u.Query()
	q.Set("page", strconv.Itoa(page))
	q.Set("per_page", strconv.Itoa(perPage))
	if after != nil {
		q.Set("after", strconv.FormatInt(*after, 10))
	}
	u.RawQuery = q.Encode()
	var out []StravaActivity
	err := g.authorized(ctx, token, u.String(), &out)
	return out, err
}
func (g *StravaGateway) GetActivity(ctx context.Context, token, id string) (StravaActivity, error) {
	var out StravaActivity
	err := g.authorized(ctx, token, g.baseURL+"/api/v3/activities/"+url.PathEscape(id), &out)
	return out, err
}
func (g *StravaGateway) GetStreams(ctx context.Context, token, id string) (map[string]any, error) {
	u, _ := url.Parse(g.baseURL + "/api/v3/activities/" + url.PathEscape(id) + "/streams")
	q := u.Query()
	q.Set("keys", "distance,time,velocity_smooth,heartrate,altitude,cadence,watts,latlng")
	q.Set("key_by_type", "true")
	u.RawQuery = q.Encode()
	var out map[string]any
	err := g.authorized(ctx, token, u.String(), &out)
	return out, err
}
func (g *StravaGateway) authorized(ctx context.Context, token, target string, out any) error {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	req.Header.Set("Authorization", "Bearer "+token)
	return g.doJSON(req, out)
}
func (g *StravaGateway) doJSON(req *http.Request, out any) error {
	resp, err := g.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 2000))
		return &StravaAPIError{Status: resp.StatusCode, Body: string(body), RetryAfter: resp.Header.Get("Retry-After")}
	}
	if out == nil {
		io.Copy(io.Discard, resp.Body)
		return nil
	}
	if err = json.NewDecoder(resp.Body).Decode(out); err != nil {
		return fmt.Errorf("decode Strava response: %w", err)
	}
	return nil
}
