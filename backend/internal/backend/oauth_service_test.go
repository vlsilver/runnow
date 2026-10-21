package backend

import "testing"

func TestStravaConnectionStatusRequiresServerTokens(t *testing.T) {
	status := stravaConnectionStatus(map[string]any{
		"status":    "active",
		"athleteId": "42",
	})
	if status.Connected {
		t.Fatal("connection without server tokens must not be reported connected")
	}
}

func TestStravaConnectionStatusReportsActiveConnection(t *testing.T) {
	status := stravaConnectionStatus(map[string]any{
		"status":       "active",
		"athleteId":    "42",
		"accessToken":  "access",
		"refreshToken": "refresh",
	})
	if !status.Connected || status.AthleteID != "42" || status.Status != "active" {
		t.Fatalf("unexpected connection status: %+v", status)
	}
}

func TestStravaConnectionStatusRejectsRevokedConnection(t *testing.T) {
	status := stravaConnectionStatus(map[string]any{
		"status":       "revoked",
		"accessToken":  "access",
		"refreshToken": "refresh",
	})
	if status.Connected {
		t.Fatal("revoked connection must not be reported connected")
	}
}
