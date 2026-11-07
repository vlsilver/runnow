package backend

import (
	"testing"
	"time"
)

func TestVoiceTokenSignsLiveKitAccessToken(t *testing.T) {
	v := VoiceTokens{URL: "wss://voice.example.test", Key: "APIdemo", Secret: "s3cret-demo-key-0123456789abcdef"}
	now := time.Date(2026, 10, 31, 12, 0, 0, 0, time.UTC)

	got, err := v.Token("r1", "u1", "Minh Anh", now)
	if err != nil {
		t.Fatal(err)
	}
	// Ký tay bằng Python (hmac + base64url) theo claim của LiveKit
	// protocol/auth/grants.go: iss là API key, sub là uid, chỉ được phát micro.
	want := "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." +
		"eyJpc3MiOiJBUElkZW1vIiwic3ViIjoidTEiLCJuYW1lIjoiTWluaCBBbmgiLCJuYmYiOjE3OTM0NDgwMDAsImV4cCI6MTc5MzQ0ODYwMCwidmlkZW8iOnsicm9vbSI6InJ1bi1yb29tLXIxIiwicm9vbUpvaW4iOnRydWUsImNhblB1Ymxpc2giOnRydWUsImNhblN1YnNjcmliZSI6dHJ1ZSwiY2FuUHVibGlzaERhdGEiOmZhbHNlLCJjYW5QdWJsaXNoU291cmNlcyI6WyJtaWNyb3Bob25lIl19fQ." +
		"8H6DlKvoLtJ_9zIoPAVk8S6pLo-l4CCEzhtlccSQMTI"
	if got != want {
		t.Fatalf("token\n got %s\nwant %s", got, want)
	}
}

func TestVoiceTokensEnabledNeedsAllThree(t *testing.T) {
	if (VoiceTokens{URL: "wss://x", Key: "k"}).Enabled() {
		t.Fatal("thiếu secret mà vẫn bật voice")
	}
	if !(VoiceTokens{URL: "wss://x", Key: "k", Secret: "s"}).Enabled() {
		t.Fatal("đủ cấu hình mà voice vẫn tắt")
	}
}
