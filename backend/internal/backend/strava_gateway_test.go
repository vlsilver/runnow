package backend

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"testing"
)

func TestRevokeUsesStravaDeauthorizeWithBearerToken(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/oauth/deauthorize" {
			t.Fatalf("request = %s %s", r.Method, r.URL.Path)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer access-token" {
			t.Fatalf("authorization = %q", got)
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{}`))
	}))
	defer server.Close()
	gateway := NewStravaGateway("client", "secret")
	gateway.baseURL = server.URL
	if err := gateway.Revoke(context.Background(), "access-token"); err != nil {
		t.Fatal(err)
	}
}

func TestAuthorizationURLCarriesExactCallbackAndScope(t *testing.T) {
	gateway := NewStravaGateway("253789", "secret")
	raw := gateway.AuthorizationURL("https://example.test/v1/strava/callback", "state")
	parsed, err := url.Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	if got := parsed.Query().Get("redirect_uri"); got != "https://example.test/v1/strava/callback" {
		t.Fatalf("redirect_uri = %q", got)
	}
	if got := parsed.Query().Get("scope"); got != "activity:read_all" {
		t.Fatalf("scope = %q", got)
	}
}
