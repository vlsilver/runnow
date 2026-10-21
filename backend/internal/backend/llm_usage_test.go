package backend

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"sync"
	"testing"
	"time"

	"google.golang.org/genai"
)

// captureHandler giữ lại các dòng llm.usage để test đọc từng field.
type captureHandler struct {
	mu   sync.Mutex
	recs []map[string]slog.Value
}

func (h *captureHandler) Enabled(context.Context, slog.Level) bool { return true }
func (h *captureHandler) WithAttrs([]slog.Attr) slog.Handler       { return h }
func (h *captureHandler) WithGroup(string) slog.Handler            { return h }
func (h *captureHandler) Handle(_ context.Context, r slog.Record) error {
	if r.Message != "llm.usage" {
		return nil
	}
	m := map[string]slog.Value{}
	r.Attrs(func(a slog.Attr) bool {
		m[a.Key] = a.Value
		return true
	})
	h.mu.Lock()
	h.recs = append(h.recs, m)
	h.mu.Unlock()
	return nil
}

func (h *captureHandler) records() []map[string]slog.Value {
	h.mu.Lock()
	defer h.mu.Unlock()
	return append([]map[string]slog.Value{}, h.recs...)
}

// captureUsage thay logger mặc định trong một test. Test trong package không
// chạy t.Parallel nên đổi logger toàn cục ở đây không dẫm lên test khác.
func captureUsage(t *testing.T) *captureHandler {
	t.Helper()
	h := &captureHandler{}
	prev := slog.Default()
	slog.SetDefault(slog.New(h))
	t.Cleanup(func() { slog.SetDefault(prev) })
	return h
}

func wantAttrs(t *testing.T, rec map[string]slog.Value, want map[string]any) {
	t.Helper()
	for k, v := range want {
		got, ok := rec[k]
		if !ok {
			t.Errorf("thiếu field %s", k)
			continue
		}
		if got.Any() != slog.AnyValue(v).Any() {
			t.Errorf("%s = %v, want %v", k, got.Any(), v)
		}
	}
}

func TestLogLLMUsageTakesCountsFromUsageMetadata(t *testing.T) {
	h := captureUsage(t)
	resp := &genai.GenerateContentResponse{UsageMetadata: &genai.GenerateContentResponseUsageMetadata{
		PromptTokenCount:        1200,
		CandidatesTokenCount:    85,
		ThoughtsTokenCount:      310,
		CachedContentTokenCount: 640,
		ToolUsePromptTokenCount: 42,
		TotalTokenCount:         1637,
	}}
	logLLMUsage(context.Background(), llmLabel{feature: "coach.chat", uid: "u1"}, "gemini-x", resp, time.Now(), 2)

	recs := h.records()
	if len(recs) != 1 {
		t.Fatalf("%d dòng llm.usage, want 1", len(recs))
	}
	wantAttrs(t, recs[0], map[string]any{
		"feature": "coach.chat", "uid": "u1", "model": "gemini-x", "attempt": 2,
		"promptTokenCount": int32(1200), "candidatesTokenCount": int32(85),
		"thoughtsTokenCount": int32(310), "cachedContentTokenCount": int32(640),
		"toolUsePromptTokenCount": int32(42), "totalTokenCount": int32(1637),
	})
	if _, ok := recs[0]["latencyMs"]; !ok {
		t.Error("thiếu field latencyMs")
	}
}

// Model ảnh và fake trong test có thể trả response không kèm usageMetadata: vẫn
// ghi một dòng số 0 chứ không panic.
func TestLogLLMUsageNilUsage(t *testing.T) {
	h := captureUsage(t)
	for _, resp := range []*genai.GenerateContentResponse{nil, {}} {
		logLLMUsage(context.Background(), llmLabelOf(context.Background()), "m", resp, time.Now(), 0)
	}
	recs := h.records()
	if len(recs) != 2 {
		t.Fatalf("%d dòng llm.usage, want 2", len(recs))
	}
	for _, rec := range recs {
		wantAttrs(t, rec, map[string]any{"feature": "unknown", "uid": "", "promptTokenCount": int32(0), "totalTokenCount": int32(0)})
	}
}

// Lượt đầu treo bị cắt, lượt hai trả lời: chỉ lượt hai có dòng usage, mang nhãn
// từ ctx của nơi gọi Answer và đúng số đếm Vertex trả về.
func TestAnswerLogsUsageOfSuccessfulAttempt(t *testing.T) {
	h := captureUsage(t)
	f := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		if n == 1 {
			<-r.Context().Done()
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_, _ = io.WriteString(w, `{"candidates":[{"content":{"role":"model","parts":[{"text":"ok"}]}}],`+
			`"usageMetadata":{"promptTokenCount":900,"candidatesTokenCount":12,"thoughtsTokenCount":77,"totalTokenCount":989}}`)
	}}
	bot := newFakeGeminiBot(t, f)
	bot.attemptTimeout = 200 * time.Millisecond

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if _, err := bot.Answer(withLLMLabel(ctx, "bot.activity_announce", "u7"), "sys", askOnce(), false); err != nil {
		t.Fatalf("Answer: %v", err)
	}
	recs := h.records()
	if len(recs) != 1 {
		t.Fatalf("%d dòng llm.usage, want 1", len(recs))
	}
	wantAttrs(t, recs[0], map[string]any{
		"feature": "bot.activity_announce", "uid": "u7", "model": "m", "attempt": 1,
		"promptTokenCount": int32(900), "candidatesTokenCount": int32(12),
		"thoughtsTokenCount": int32(77), "totalTokenCount": int32(989),
	})
}

// Lượt tra web tính vào tính năng đang gọi nó, có hậu tố để tách chi phí riêng.
func TestGoogleSearchLogsUnderParentFeature(t *testing.T) {
	h := captureUsage(t)
	f := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) { writeGeminiText(w, "ok") }}
	client := newFakeGeminiClient(t, f)
	if _, err := googleSearch(withLLMLabel(context.Background(), "agent.dm", "u3"), client, "m", "giải chạy tháng 11"); err != nil {
		t.Fatal(err)
	}
	recs := h.records()
	if len(recs) != 1 {
		t.Fatalf("%d dòng llm.usage, want 1", len(recs))
	}
	wantAttrs(t, recs[0], map[string]any{"feature": "agent.dm.web_search", "uid": "u3", "attempt": 0})
}
