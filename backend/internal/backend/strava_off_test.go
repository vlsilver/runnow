package backend

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// Strava tắt: webhook và task Strava trả 200 mà không đụng service nào (deps
// không có Webhook hay Activities, đi tiếp là panic).
func TestStravaOffSkipsWebhookAndTasks(t *testing.T) {
	deps := &Dependencies{StravaOff: true}
	cases := []struct {
		server http.Handler
		path   string
		body   string
	}{
		{NewAPIServer(Config{}, deps), "/v1/strava/webhook", `{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":2,"subscription_id":3,"event_time":4}`},
		{NewWorkerServer(Config{}, deps), "/tasks/strava-event", `{"eventKey":"k","event":{"object_type":"activity","object_id":1,"aspect_type":"create","owner_id":2,"subscription_id":3,"event_time":4}}`},
		{NewWorkerServer(Config{}, deps), "/tasks/backfill-page", `{"uid":"u","page":1,"runId":"r"}`},
		{NewWorkerServer(Config{}, deps), "/tasks/hydrate-activity", `{"uid":"u","activityId":"1"}`},
		{NewWorkerServer(Config{}, deps), "/tasks/reconcile-connections", `{}`},
	}
	for _, c := range cases {
		w := httptest.NewRecorder()
		c.server.ServeHTTP(w, httptest.NewRequest(http.MethodPost, c.path, strings.NewReader(c.body)))
		if w.Code != http.StatusOK {
			t.Errorf("%s: status %d, body %s", c.path, w.Code, w.Body.String())
		}
	}
}

func TestStravaOffRefusesRepairAndHydrate(t *testing.T) {
	s := &Server{deps: &Dependencies{StravaOff: true}}
	if err := s.requireStravaConnection(httptest.NewRequest(http.MethodPost, "/v1/strava/repair", nil), "u"); !errors.Is(err, errStravaOff) {
		t.Fatalf("err = %v, want errStravaOff", err)
	}
}

func TestStravaGatewayOffMakesNoRequest(t *testing.T) {
	hits := 0
	strava := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits++
		w.Write([]byte(`{}`))
	}))
	defer strava.Close()
	g := NewStravaGateway("id", "secret")
	g.baseURL = strava.URL
	g.off = true
	ctx := context.Background()
	if _, err := g.RefreshToken(ctx, "r"); !errors.Is(err, errStravaOff) {
		t.Fatalf("RefreshToken err = %v", err)
	}
	if _, err := g.GetActivity(ctx, "t", "1"); !errors.Is(err, errStravaOff) {
		t.Fatalf("GetActivity err = %v", err)
	}
	if err := g.Revoke(ctx, "t"); !errors.Is(err, errStravaOff) {
		t.Fatalf("Revoke err = %v", err)
	}
	if hits != 0 {
		t.Fatalf("Strava got %d requests while off", hits)
	}
}
