package backend

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestAPIHealthEndpoint(t *testing.T) {
	assertHealthEndpoint(t, NewAPIServer(Config{}, nil), "runnow-api")
}

func TestWorkerHealthEndpoint(t *testing.T) {
	assertHealthEndpoint(t, NewWorkerServer(Config{}, nil), "runnow-worker")
}

func assertHealthEndpoint(t *testing.T, handler http.Handler, service string) {
	t.Helper()

	request := httptest.NewRequest(http.MethodGet, "/health", nil)
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("health status = %d, want %d", response.Code, http.StatusOK)
	}
	var body struct {
		OK      bool   `json:"ok"`
		Service string `json:"service"`
	}
	if err := json.NewDecoder(response.Body).Decode(&body); err != nil {
		t.Fatalf("decode health response: %v", err)
	}
	if !body.OK || body.Service != service {
		t.Fatalf("health response = %+v, want ok service %q", body, service)
	}
}
