package backend

import (
	"bytes"
	"context"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestTelegramActivityAlertSendsPhotoCard(t *testing.T) {
	var capturedPath string
	var capturedFields map[string]string
	var capturedPhoto []byte
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path
		if err := r.ParseMultipartForm(2 << 20); err != nil {
			t.Fatalf("ParseMultipartForm: %v", err)
		}
		capturedFields = map[string]string{}
		for key, values := range r.MultipartForm.Value {
			if len(values) > 0 {
				capturedFields[key] = values[0]
			}
		}
		file, _, err := r.FormFile("photo")
		if err != nil {
			t.Fatalf("FormFile(photo): %v", err)
		}
		defer file.Close()
		capturedPhoto, err = io.ReadAll(file)
		if err != nil {
			t.Fatalf("ReadAll(photo): %v", err)
		}
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}))
	defer server.Close()

	service := NewTelegramService("token", "chat")
	service.apiBaseURL = server.URL
	fact := ActivityFact{
		StartedAt:           time.Date(2026, 7, 20, 6, 30, 0, 0, time.UTC),
		DistanceMeters:      5030,
		MovingTimeSeconds:   1812,
		ElevationGainMeters: 24,
	}
	if err := service.SendActivityAlert(context.Background(), "vlsilver", "Morning Run", fact, "https://example.test/activity"); err != nil {
		t.Fatalf("SendActivityAlert: %v", err)
	}
	if capturedPath != "/bottoken/sendPhoto" {
		t.Fatalf("path = %s", capturedPath)
	}
	if capturedFields["chat_id"] != "chat" {
		t.Fatalf("chat_id = %q", capturedFields["chat_id"])
	}
	if !strings.Contains(capturedFields["caption"], "vlsilver") || !strings.Contains(capturedFields["caption"], "Morning Run") {
		t.Fatalf("caption = %q", capturedFields["caption"])
	}
	if !strings.Contains(capturedFields["reply_markup"], "https://example.test/activity") {
		t.Fatalf("reply_markup = %q", capturedFields["reply_markup"])
	}
	if _, err := png.Decode(bytes.NewReader(capturedPhoto)); err != nil {
		t.Fatalf("photo is not a png: %v", err)
	}
}

func TestTelegramActivityAlertSkipsWhenDisabled(t *testing.T) {
	service := NewTelegramService("", "")
	if err := service.SendActivityAlert(context.Background(), "runner", "Run", ActivityFact{}, "https://example.test"); err != nil {
		t.Fatalf("SendActivityAlert disabled = %v", err)
	}
}
