package backend

import (
	"context"
	"math"
	"testing"

	"google.golang.org/genai"
)

// Số mong đợi tính tay. Giá mỗi loại khác nhau để đổi chỗ hai loại là lệch.
//
//	input chưa cache: (10000 - 4000) + 1000 token tool = 7000 × 0.30 / 1M = 0.00210
//	cache:            4000 × 0.03 / 1M                                = 0.00012
//	output:           500 × 2.50 / 1M                                 = 0.00125
//	thinking:         800 × 2.00 / 1M                                 = 0.00160
//	cộng                                                              = 0.00507
//	tra Google: cộng thêm 0.014                                       = 0.01907
func TestLLMCostFromUsageAndPrice(t *testing.T) {
	p := llmPrice{input: 0.30, output: 2.50, thinking: 2.00, cached: 0.03, search: 0.014}
	u := &genai.GenerateContentResponseUsageMetadata{PromptTokenCount: 10000, CachedContentTokenCount: 4000, ToolUsePromptTokenCount: 1000, CandidatesTokenCount: 500, ThoughtsTokenCount: 800}
	if got := llmCost(p, u, false); math.Abs(got-0.00507) > 1e-12 {
		t.Fatalf("chi phí = %.8f, muốn 0.00507", got)
	}
	if got := llmCost(p, u, true); math.Abs(got-0.01907) > 1e-12 {
		t.Fatalf("chi phí kèm tra Google = %.8f, muốn 0.01907", got)
	}
	// Không có UsageMetadata: lượt tra Google vẫn tính phí theo lượt.
	if got := llmCost(p, nil, true); got != 0.014 {
		t.Fatalf("không có usage = %v, muốn 0.014", got)
	}
}

func TestParseAgentBudgetConfig(t *testing.T) {
	cfg := parseAgentBudgetConfig(map[string]any{
		"dailyBudgetUsd": 5.0,
		"llmPrices": []any{
			map[string]any{"model": "gemini-3.8-flash", "inputPer1M": 0.3, "outputPer1M": 2.5, "thinkingPer1M": 2.0, "cachedPer1M": 0.03, "searchPerCall": 0.014},
			// Thiếu thinking và cached: lấy giá output và input, không về 0.
			map[string]any{"model": "gemini-x", "inputPer1M": int64(1), "outputPer1M": int64(4)},
			map[string]any{"inputPer1M": 9.0},
		},
	})
	if cfg.dailyUsd != 5 {
		t.Fatalf("dailyUsd = %v", cfg.dailyUsd)
	}
	ctx := context.Background()
	if p := cfg.price(ctx, "gemini-3.8-flash"); p != (llmPrice{input: 0.3, output: 2.5, thinking: 2.0, cached: 0.03, search: 0.014}) {
		t.Fatalf("giá flash = %+v", p)
	}
	if p := cfg.price(ctx, "gemini-x"); p != (llmPrice{input: 1, output: 4, thinking: 4, cached: 1}) {
		t.Fatalf("giá thiếu field = %+v", p)
	}
	if p := cfg.price(ctx, "gemini-chua-khai"); p != agentFallbackPrice {
		t.Fatalf("model chưa khai giá = %+v, muốn giá dự phòng", p)
	}
	if len(cfg.prices) != 2 {
		t.Fatalf("dòng giá không có model phải bỏ: %+v", cfg.prices)
	}
	if c := parseAgentBudgetConfig(nil); c.dailyUsd != 0 || len(c.prices) != 0 {
		t.Fatalf("config rỗng = %+v", c)
	}
}
