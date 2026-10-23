package backend

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"google.golang.org/genai"
)

// fakeGemini trả lời generateContent theo hàm reply, ghi lại body từng request.
type fakeGemini struct {
	mu     sync.Mutex
	bodies []string
	reply  func(n int, w http.ResponseWriter, r *http.Request)
}

func newFakeGeminiBot(t *testing.T, f *fakeGemini) *BotService {
	t.Helper()
	return &BotService{genai: newFakeGeminiClient(t, f), model: "m"}
}

func newFakeGeminiClient(t *testing.T, f *fakeGemini) *genai.Client {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		f.mu.Lock()
		f.bodies = append(f.bodies, string(body))
		n := len(f.bodies)
		f.mu.Unlock()
		f.reply(n, w, r)
	}))
	t.Cleanup(srv.Close)
	gc, err := genai.NewClient(context.Background(), &genai.ClientConfig{APIKey: "test", Backend: genai.BackendGeminiAPI, HTTPOptions: genai.HTTPOptions{BaseURL: srv.URL}})
	if err != nil {
		t.Fatal(err)
	}
	return gc
}

func (f *fakeGemini) requests() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]string{}, f.bodies...)
}

func writeGeminiText(w http.ResponseWriter, text string) {
	w.Header().Set("Content-Type", "application/json")
	_, _ = io.WriteString(w, `{"candidates":[{"content":{"role":"model","parts":[{"text":"`+text+`"}]}}]}`)
}

func askOnce() []*genai.Content {
	return []*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: "chạy xong 10km rồi"}}}}
}

// Vertex có lúc giữ một request vài phút rồi trả 504. Một lượt treo không được
// ăn hết thời gian của cả câu trả lời: cắt lượt đó và gọi lại.
func TestAnswerRetriesHungAttempt(t *testing.T) {
	f := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		if n == 1 {
			<-r.Context().Done()
			return
		}
		writeGeminiText(w, "giãn cơ đi")
	}}
	bot := newFakeGeminiBot(t, f)
	bot.attemptTimeout = 200 * time.Millisecond

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	got, err := bot.Answer(ctx, "sys", askOnce(), false)
	if err != nil {
		t.Fatalf("Answer: %v", err)
	}
	if got != "giãn cơ đi" || len(f.requests()) != 2 {
		t.Fatalf("got %q after %d requests, want reply after 2", got, len(f.requests()))
	}
}

// Vertex tự cắt theo x-server-timeout thì trả 504 trước khi ctx phía mình hết.
func TestAnswerRetriesVertex504(t *testing.T) {
	f := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		if n == 1 {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusGatewayTimeout)
			_, _ = io.WriteString(w, `{"error":{"code":504,"message":"Deadline expired before operation could complete.","status":"DEADLINE_EXCEEDED"}}`)
			return
		}
		writeGeminiText(w, "giãn cơ đi")
	}}
	bot := newFakeGeminiBot(t, f)
	got, err := bot.Answer(context.Background(), "sys", askOnce(), false)
	if err != nil || got != "giãn cơ đi" {
		t.Fatalf("got %q, %v; want reply after retry", got, err)
	}
}

// Hết giờ của cả task thì dừng luôn, gọi thêm chỉ tốn tiền mà không kịp trả lời.
func TestAnswerStopsWhenTaskDeadlinePassed(t *testing.T) {
	f := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		<-r.Context().Done()
	}}
	bot := newFakeGeminiBot(t, f)
	bot.attemptTimeout = 5 * time.Second

	ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
	defer cancel()
	if _, err := bot.Answer(ctx, "sys", askOnce(), false); err == nil {
		t.Fatal("want error when the task deadline passes")
	}
	if n := len(f.requests()); n != 1 {
		t.Fatalf("%d requests, want 1", n)
	}
}

func TestAnswerThinkingLevel(t *testing.T) {
	for _, tc := range []struct {
		level, want string
	}{
		{"LOW", `"thinkingConfig":{"thinkingLevel":"LOW"}`},
		{"low", `"thinkingConfig":{"thinkingLevel":"LOW"}`},
		{"default", ""},
	} {
		f := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) { writeGeminiText(w, "ok") }}
		bot := newFakeGeminiBot(t, f)
		bot.thinking = tc.level
		if _, err := bot.Answer(context.Background(), "sys", askOnce(), false); err != nil {
			t.Fatalf("%s: %v", tc.level, err)
		}
		body := f.requests()[0]
		if tc.want == "" {
			if strings.Contains(body, "thinkingConfig") {
				t.Errorf("%s: sent thinkingConfig, want model default: %s", tc.level, body)
			}
		} else if !strings.Contains(body, tc.want) {
			t.Errorf("%s: body lacks %s", tc.level, tc.want)
		}
	}
}

func writeGeminiError(w http.ResponseWriter, code int, status string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_, _ = io.WriteString(w, `{"error":{"code":`+strconv.Itoa(code)+`,"message":"x","status":"`+status+`"}}`)
}

// Pool dùng chung của model chính hết chỗ cả loạt retry thì 3i vẫn phải trả
// lời, bằng model dự phòng ở location khác.
func TestAnswerFallsBackWhenPrimaryExhausted(t *testing.T) {
	primary := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		writeGeminiError(w, http.StatusTooManyRequests, "RESOURCE_EXHAUSTED")
	}}
	backup := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		if !strings.Contains(r.URL.Path, "models/du-phong:") {
			t.Errorf("fallback called %s, want model du-phong", r.URL.Path)
		}
		writeGeminiText(w, "giãn cơ đi")
	}}
	bot := newFakeGeminiBot(t, primary)
	bot.fallback = genaiRoute{client: newFakeGeminiClient(t, backup), model: "du-phong"}

	got, err := bot.Answer(context.Background(), "sys", askOnce(), false)
	if err != nil || got != "giãn cơ đi" {
		t.Fatalf("got %q, %v; want the fallback's reply", got, err)
	}
	if p, b := len(primary.requests()), len(backup.requests()); p != 3 || b != 1 {
		t.Fatalf("primary %d, fallback %d requests; want 3 then 1", p, b)
	}
}

// Request hỏng (400) thì model nào cũng hỏng như nhau: không gọi dự phòng.
func TestAnswerNoFallbackOnBadRequest(t *testing.T) {
	primary := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		writeGeminiError(w, http.StatusBadRequest, "INVALID_ARGUMENT")
	}}
	backup := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) { writeGeminiText(w, "ok") }}
	bot := newFakeGeminiBot(t, primary)
	bot.fallback = genaiRoute{client: newFakeGeminiClient(t, backup), model: "du-phong"}

	if _, err := bot.Answer(context.Background(), "sys", askOnce(), false); err == nil {
		t.Fatal("want the 400 error")
	}
	if n := len(backup.requests()); n != 0 {
		t.Fatalf("fallback got %d requests, want 0", n)
	}
}

// MyBot đi cùng đường gọi model với 3i nên cũng có dự phòng.
func TestAgentLLMFallsBackWhenPrimaryExhausted(t *testing.T) {
	primary := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		writeGeminiError(w, http.StatusTooManyRequests, "RESOURCE_EXHAUSTED")
	}}
	backup := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) { writeGeminiText(w, "chào chủ") }}
	llm := genaiAgentLLM{client: newFakeGeminiClient(t, primary), model: "m", fallback: genaiRoute{client: newFakeGeminiClient(t, backup), model: "du-phong"}}

	resp, err := llm.Generate(context.Background(), "sys", askOnce(), nil)
	if err != nil || resp.Text() != "chào chủ" {
		t.Fatalf("got %v; want the fallback's reply", err)
	}
}
