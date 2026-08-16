package backend

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"net/url"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type OAuthService struct {
	db                                         *firestore.Client
	gateway                                    *StravaGateway
	tasks                                      *TaskPublisher
	callbackURL, mobileReturnURI, webReturnURI string
}

func NewOAuthService(db *firestore.Client, g *StravaGateway, t *TaskPublisher, c Config) *OAuthService {
	return &OAuthService{db: db, gateway: g, tasks: t, callbackURL: c.PublicBaseURL + "/v1/strava/callback", mobileReturnURI: c.MobileReturnURI, webReturnURI: c.WebReturnURI}
}

func (s *OAuthService) Authorization(ctx context.Context, uid, target string) (string, error) {
	if target != "mobile" && target != "web" {
		return "", &HTTPError{Status: 400, Code: "invalid_request", Message: "Invalid OAuth return target"}
	}
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", err
	}
	state := base64.RawURLEncoding.EncodeToString(raw)
	_, err := s.db.Collection("oauthStates").Doc(hashState(state)).Create(ctx, map[string]any{"provider": "strava", "uid": uid, "returnTarget": target, "createdAt": firestore.ServerTimestamp, "expiresAt": time.Now().Add(10 * time.Minute)})
	if err != nil {
		return "", err
	}
	return s.gateway.AuthorizationURL(s.callbackURL, state), nil
}

type OAuthCallback struct{ State, Code, OAuthError, Scope string }

type StravaConnectionStatus struct {
	Connected bool   `json:"connected"`
	Status    string `json:"status"`
	AthleteID string `json:"athleteId,omitempty"`
}

func (s *OAuthService) Status(ctx context.Context, uid string) (StravaConnectionStatus, error) {
	snap, err := s.db.Collection("stravaConnections").Doc(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return StravaConnectionStatus{Status: "disconnected"}, nil
	}
	if err != nil {
		return StravaConnectionStatus{}, err
	}
	return stravaConnectionStatus(snap.Data()), nil
}

func stravaConnectionStatus(data map[string]any) StravaConnectionStatus {
	connectionStatus := stringValue(data["status"])
	connected := connectionStatus != "revoked" && connectionStatus != "error" &&
		stringValue(data["accessToken"]) != "" && stringValue(data["refreshToken"]) != ""
	if connectionStatus == "" {
		connectionStatus = "disconnected"
	}
	return StravaConnectionStatus{
		Connected: connected,
		Status:    connectionStatus,
		AthleteID: stringValue(data["athleteId"]),
	}
}

func (s *OAuthService) Callback(ctx context.Context, input OAuthCallback) (string, error) {
	state, err := s.consumeState(ctx, input.State)
	if err != nil {
		return "", err
	}
	returnURI := s.returnURI(state.Target)
	if input.OAuthError != "" || input.Code == "" {
		return withQuery(returnURI, map[string]string{"error": "strava_authorization_denied"}), nil
	}
	token, err := s.gateway.ExchangeCode(ctx, input.Code, s.callbackURL)
	if err != nil {
		return s.oauthFailure(ctx, state.UID, returnURI, err)
	}
	if token.Athlete == nil || token.Athlete.ID <= 0 {
		return s.oauthFailure(ctx, state.UID, returnURI, &HTTPError{Status: 400, Code: "missing_strava_athlete", Message: "Strava athlete is missing"})
	}
	scopes := parseScopes(input.Scope)
	if len(scopes) == 0 {
		scopes = parseScopes(token.Scope)
	}
	if !contains(scopes, "activity:read_all") {
		_ = s.gateway.Revoke(ctx, token.AccessToken)
		return s.oauthFailure(ctx, state.UID, returnURI, &HTTPError{Status: 403, Code: "missing_strava_scope", Message: "Strava activity:read_all scope is required"})
	}
	athleteID := itoa64(token.Athlete.ID)
	if err = s.linkConnection(ctx, state.UID, athleteID, token, scopes); err != nil {
		return s.oauthFailure(ctx, state.UID, returnURI, err)
	}
	runID := uuid.NewString()
	_, err = s.tasks.Publish(ctx, PublishTask{Queue: QueueBackfill, HandlerPath: "/tasks/backfill-page", Payload: map[string]any{"uid": state.UID, "page": 1, "runId": runID}, TaskID: "backfill-" + state.UID + "-" + runID + "-1"})
	if err != nil {
		return s.oauthFailure(ctx, state.UID, returnURI, err)
	}
	return withQuery(returnURI, map[string]string{"strava": "connected"}), nil
}

func (s *OAuthService) Disconnect(ctx context.Context, uid string) error {
	ref := s.db.Collection("stravaConnections").Doc(uid)
	snap, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	token, _ := snap.Data()["accessToken"].(string)
	// Chỉ giảm bộ đếm nếu connection đang CÒN active — disconnect lại khi đã
	// revoked (idempotent) không trừ oan.
	wasActive := stringValue(snap.Data()["status"]) != "revoked"
	if token != "" {
		if revokeErr := s.gateway.Revoke(ctx, token); revokeErr != nil {
			var api *StravaAPIError
			if !errors.As(revokeErr, &api) || api.Status >= 500 {
				return revokeErr
			}
		}
	}
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		if err := tx.Set(ref, map[string]any{"status": "revoked", "accessToken": firestore.Delete, "refreshToken": firestore.Delete, "disconnectedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
			return err
		}
		if err := tx.Set(s.db.Collection("users").Doc(uid), map[string]any{"stravaConnected": false, "stravaAthleteId": firestore.Delete, "athleteId": firestore.Delete, "stravaDisconnectedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
			return err
		}
		if wasActive {
			if err := tx.Set(s.db.Collection("appConfig").Doc("integrations"), map[string]any{"stravaConnectedCount": firestore.Increment(-1), "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
				return err
			}
		}
		return tx.Set(s.db.Collection("publicProfiles").Doc(uid), map[string]any{"stravaConnected": false, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	})
}

type oauthState struct{ UID, Target string }

func (s *OAuthService) consumeState(ctx context.Context, state string) (oauthState, error) {
	if state == "" {
		return oauthState{}, &HTTPError{Status: 400, Code: "invalid_oauth_state", Message: "Missing OAuth state"}
	}
	ref := s.db.Collection("oauthStates").Doc(hashState(state))
	var out oauthState
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if err != nil {
			return &HTTPError{Status: 400, Code: "invalid_oauth_state", Message: "OAuth state is invalid or already used"}
		}
		data := snap.Data()
		if data["provider"] != "strava" {
			return &HTTPError{Status: 400, Code: "invalid_oauth_state", Message: "OAuth state is invalid"}
		}
		expiry, ok := data["expiresAt"].(time.Time)
		if !ok || !expiry.After(time.Now()) {
			_ = tx.Delete(ref)
			return &HTTPError{Status: 400, Code: "expired_oauth_state", Message: "OAuth state expired"}
		}
		out = oauthState{UID: stringValue(data["uid"]), Target: stringValue(data["returnTarget"])}
		if out.UID == "" || (out.Target != "mobile" && out.Target != "web") {
			return &HTTPError{Status: 400, Code: "invalid_oauth_state", Message: "OAuth state is invalid"}
		}
		return tx.Delete(ref)
	})
	return out, err
}
func (s *OAuthService) linkConnection(ctx context.Context, uid, athleteID string, token StravaTokenResponse, scopes []string) error {
	connection := s.db.Collection("stravaConnections").Doc(uid)
	link := s.db.Collection("stravaAthleteLinks").Doc(athleteID)
	user := s.db.Collection("users").Doc(uid)
	public := s.db.Collection("publicProfiles").Doc(uid)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		userSnap, userErr := tx.Get(user)
		if userErr != nil && status.Code(userErr) != codes.NotFound {
			return userErr
		}
		linkSnap, linkErr := tx.Get(link)
		if linkErr != nil && status.Code(linkErr) != codes.NotFound {
			return linkErr
		}
		userData := map[string]any{}
		if userErr == nil {
			userData = userSnap.Data()
		}
		// Đếm số user đang kết nối Strava để gate theo cap (app chưa được Strava
		// review, tối đa 10 athlete). Chỉ tăng khi user CHUYỂN từ chưa-connect →
		// connect (re-link cùng tài khoản không cộng thêm).
		wasConnected, _ := userData["stravaConnected"].(bool)
		locked := firstString(userData, "lockedStravaAthleteId", "stravaAthleteId", "athleteId")
		if locked != "" && locked != athleteID {
			return &HTTPError{Status: 409, Code: "strava_uid_mismatch", Message: "Firebase account is locked to a different Strava athlete"}
		}
		if linkErr == nil {
			if existing := stringValue(linkSnap.Data()["uid"]); existing != "" && existing != uid {
				return &HTTPError{Status: 409, Code: "strava_athlete_already_linked", Message: "Strava athlete is linked to another Firebase account"}
			}
		}
		if err := tx.Set(link, map[string]any{"uid": uid, "athleteId": athleteID, "linkedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
			return err
		}
		if err := tx.Set(connection, map[string]any{"uid": uid, "athleteId": athleteID, "accessToken": token.AccessToken, "refreshToken": token.RefreshToken, "expiresAt": token.ExpiresAt, "scopes": scopes, "status": "backfilling", "tokenVersion": firestore.Increment(1), "linkedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
			return err
		}
		if locked == "" {
			locked = athleteID
		}
		if err := tx.Set(user, map[string]any{"stravaConnected": true, "lockedStravaAthleteId": locked, "stravaAthleteId": athleteID, "athleteId": athleteID, "stravaLinkedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
			return err
		}
		if !wasConnected {
			if err := tx.Set(s.db.Collection("appConfig").Doc("integrations"), map[string]any{"stravaConnectedCount": firestore.Increment(1), "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
				return err
			}
		}
		return tx.Set(public, map[string]any{"stravaConnected": true, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	})
}
func (s *OAuthService) oauthFailure(ctx context.Context, uid, returnURI string, cause error) (string, error) {
	code := "oauth_callback_failed"
	var httpErr *HTTPError
	if errors.As(cause, &httpErr) {
		code = httpErr.Code
	}
	ref := s.db.Collection("stravaConnections").Doc(uid)
	_, getErr := ref.Get(ctx)
	payload := map[string]any{"lastErrorCode": code, "updatedAt": firestore.ServerTimestamp}
	if status.Code(getErr) == codes.NotFound {
		payload["status"] = "error"
	}
	if _, err := ref.Set(ctx, payload, firestore.MergeAll); err != nil {
		return "", err
	}
	return withQuery(returnURI, map[string]string{"error": code}), nil
}
func (s *OAuthService) returnURI(target string) string {
	if target == "web" {
		return s.webReturnURI
	}
	return s.mobileReturnURI
}

func parseScopes(raw string) []string {
	raw = strings.ReplaceAll(raw, ",", " ")
	return strings.Fields(raw)
}
func contains(values []string, want string) bool {
	for _, v := range values {
		if v == want {
			return true
		}
	}
	return false
}
func hashState(state string) string {
	sum := sha256.Sum256([]byte(state))
	return hex.EncodeToString(sum[:])
}
func withQuery(raw string, values map[string]string) string {
	u, err := url.Parse(raw)
	if err != nil {
		return raw
	}
	q := u.Query()
	for k, v := range values {
		q.Set(k, v)
	}
	u.RawQuery = q.Encode()
	return u.String()
}
func stringValue(v any) string {
	if value, ok := v.(string); ok {
		return value
	}
	return ""
}
func firstString(m map[string]any, keys ...string) string {
	for _, k := range keys {
		if v := stringValue(m[k]); v != "" {
			return v
		}
	}
	return ""
}
func itoa64(value int64) string {
	if value == 0 {
		return "0"
	}
	neg := value < 0
	if neg {
		value = -value
	}
	var b [24]byte
	i := len(b)
	for value > 0 {
		i--
		b[i] = byte('0' + value%10)
		value /= 10
	}
	if neg {
		i--
		b[i] = '-'
	}
	return string(b[i:])
}
