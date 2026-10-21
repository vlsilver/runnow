package backend

import (
	"context"
	"log/slog"
	"time"

	"google.golang.org/genai"
)

// Mỗi lượt gọi Gemini thành công ghi một dòng llm.usage với số token, để đo chi
// phí theo từng tính năng trước khi đặt hạn mức. Chỉ ghi số đếm, không ghi
// prompt hay câu trả lời.

// llmLabel là nhãn của lượt gọi: tính năng nào gọi, cho ai.
type llmLabel struct {
	feature string
	uid     string
}

type llmLabelCtxKey struct{}

// withLLMLabel gắn nhãn vào ctx cho các lượt gọi đi qua wrapper dùng chung
// (generateWithRetry, googleSearch, genaiLearnLLM, generateFunImage). Wrapper
// không biết ai gọi mình, còn truyền nhãn qua tham số thì phải đổi chữ ký Answer
// cùng interface agentLLM/learnLLM và mọi model giả trong test.
func withLLMLabel(ctx context.Context, feature, uid string) context.Context {
	return context.WithValue(ctx, llmLabelCtxKey{}, llmLabel{feature: feature, uid: uid})
}

// llmLabelOf trả "unknown" khi chưa gắn nhãn: dòng log vẫn có để không hụt chi
// phí, và lọc feature=unknown là ra chỗ quên gắn.
func llmLabelOf(ctx context.Context) llmLabel {
	c, _ := ctx.Value(llmLabelCtxKey{}).(llmLabel)
	if c.feature == "" {
		c.feature = "unknown"
	}
	return c
}

// sub là lượt gọi phụ trong một tính năng (tra web, vẽ ảnh): tách được chi phí
// riêng mà vẫn biết nó thuộc tính năng nào.
func (c llmLabel) sub(name string) llmLabel {
	c.feature += "." + name
	return c
}

// logLLMUsage ghi một dòng cho một lượt gọi thành công. attempt đếm từ 0 như
// bot.genai_retry, để nối được với dòng retry; latencyMs chỉ tính lượt này.
// Lượt lỗi thì SDK không trả response nên không có số token để ghi.
func logLLMUsage(ctx context.Context, label llmLabel, model string, resp *genai.GenerateContentResponse, started time.Time, attempt int) {
	var u genai.GenerateContentResponseUsageMetadata
	if resp != nil && resp.UsageMetadata != nil {
		u = *resp.UsageMetadata
	}
	slog.InfoContext(ctx, "llm.usage",
		"feature", label.feature,
		"uid", label.uid,
		"model", model,
		"attempt", attempt,
		"latencyMs", time.Since(started).Milliseconds(),
		"promptTokenCount", u.PromptTokenCount,
		"candidatesTokenCount", u.CandidatesTokenCount,
		"thoughtsTokenCount", u.ThoughtsTokenCount,
		"cachedContentTokenCount", u.CachedContentTokenCount,
		"toolUsePromptTokenCount", u.ToolUsePromptTokenCount,
		"totalTokenCount", u.TotalTokenCount,
	)
}
