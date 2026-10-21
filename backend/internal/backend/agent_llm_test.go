package backend

import (
	"context"
	"net/http"
	"strings"
	"testing"
	"time"
)

// Bot trong app gọi cùng model với 3i nên gặp cùng đuôi trễ của Vertex: một
// lượt treo phải bị cắt rồi gọi lại, không giữ người dùng chờ tới hết task.
func TestAgentLLMRetriesHungAttempt(t *testing.T) {
	f := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) {
		if n == 1 {
			<-r.Context().Done()
			return
		}
		writeGeminiText(w, "giãn cơ đi")
	}}
	llm := genaiAgentLLM{client: newFakeGeminiClient(t, f), model: "m", attemptTimeout: 200 * time.Millisecond}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	resp, err := llm.Generate(ctx, "sys", askOnce(), nil)
	if err != nil {
		t.Fatalf("Generate: %v", err)
	}
	if got := resp.Text(); got != "giãn cơ đi" || len(f.requests()) != 2 {
		t.Fatalf("got %q after %d requests, want reply after 2", got, len(f.requests()))
	}
}

func TestAgentLLMThinkingLevel(t *testing.T) {
	f := &fakeGemini{reply: func(n int, w http.ResponseWriter, r *http.Request) { writeGeminiText(w, "ok") }}
	llm := genaiAgentLLM{client: newFakeGeminiClient(t, f), model: "m", thinking: "LOW"}
	if _, err := llm.Generate(context.Background(), "sys", askOnce(), nil); err != nil {
		t.Fatal(err)
	}
	if body := f.requests()[0]; !strings.Contains(body, `"thinkingConfig":{"thinkingLevel":"LOW"}`) {
		t.Fatalf("body lacks thinking LOW: %s", body)
	}
}
