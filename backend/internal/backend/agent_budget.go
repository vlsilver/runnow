package backend

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// Trần chi phí mỗi ngày của bot cá nhân: chặn số tiền model tối đa khi mở bot
// cho mọi người. Chỉ tính lượt gọi của bot cá nhân (trả lời chat riêng, nói
// trong phòng, tra web của hai việc đó, tự học). 3i trên Telegram và coach
// không đi qua đây: chúng có giới hạn riêng và không lớn theo số người dùng bot,
// gộp vào thì bot cá nhân tiêu hết trần là 3i của group cũng câm theo.
//
//	agentState/config.dailyBudgetUsd   trần USD mỗi ngày giờ VN; thiếu hoặc <= 0 là không có trần
//	agentState/config.llmPrices        [{model, inputPer1M, outputPer1M, thinkingPer1M, cachedPer1M, searchPerCall}]
//	agentState/usage/days/{yyyy-mm-dd} chi phí và số token đã cộng trong ngày, budgetHitAt
//
// Giá để trong Firestore chứ không viết cứng hay để env, vì Google đổi giá theo
// đời model và sửa config là có hiệu lực ngay, không cần deploy. llmPrices là
// mảng chứ không phải map theo tên model, vì tên model có dấu chấm.
//
// Mỗi lượt gọi kiểm trần ngay trước khi gọi, nên lượt nào bắt đầu sau khi đã
// chạm trần thì không gọi. Lượt đã qua kiểm lúc chưa chạm vẫn chạy xong và được
// cộng, nên tổng có thể vượt trần, tối đa bằng chi phí của các lượt đang chạy
// cùng lúc ở thời điểm vượt.

var errAgentOverBudget = errors.New("bot cá nhân: chạm trần chi phí hôm nay")

// llmPrice là giá của một model: USD mỗi 1M token, riêng search là USD mỗi lượt
// tra Google (grounding tính phí theo lượt, không theo token).
type llmPrice struct {
	input, output, thinking, cached, search float64
}

// agentFallbackPrice dùng khi config chưa có giá của model đang chạy. Cố ý đặt
// cao hơn hẳn giá Flash (khoảng bậc Pro), để quên khai giá thì trần chạm sớm chứ
// không thành vô hiệu. Đây là lưới an toàn, không phải giá thật.
var agentFallbackPrice = llmPrice{input: 2.5, output: 15, thinking: 15, cached: 0.625, search: 0.035}

type agentBudgetConfig struct {
	dailyUsd float64
	prices   map[string]llmPrice
}

func parseAgentBudgetConfig(cfg map[string]any) agentBudgetConfig {
	out := agentBudgetConfig{dailyUsd: number(cfg["dailyBudgetUsd"]), prices: map[string]llmPrice{}}
	for _, v := range anyList(cfg["llmPrices"]) {
		m, _ := v.(map[string]any)
		model := stringValue(m["model"])
		if model == "" {
			continue
		}
		p := llmPrice{input: number(m["inputPer1M"]), output: number(m["outputPer1M"]), cached: number(m["cachedPer1M"]), search: number(m["searchPerCall"])}
		// Vertex tính token thinking theo giá output, token cache rẻ hơn input;
		// thiếu field thì lấy giá đó thay vì 0 để không tính thiếu.
		p.thinking = p.output
		if _, ok := m["thinkingPer1M"]; ok {
			p.thinking = number(m["thinkingPer1M"])
		}
		if _, ok := m["cachedPer1M"]; !ok {
			p.cached = p.input
		}
		out.prices[model] = p
	}
	return out
}

func (c agentBudgetConfig) price(ctx context.Context, model string) llmPrice {
	if p, ok := c.prices[model]; ok {
		return p
	}
	slog.WarnContext(ctx, "agent.budget_no_price", "model", model)
	return agentFallbackPrice
}

// llmCost là chi phí USD của một lượt gọi. PromptTokenCount đã gồm phần cache,
// nên tách phần cache ra tính giá cache; token tool (kết quả grounding đưa vào
// prompt) tính như input.
func llmCost(p llmPrice, u *genai.GenerateContentResponseUsageMetadata, search bool) float64 {
	cost := 0.0
	if search {
		cost = p.search
	}
	if u == nil {
		return cost
	}
	uncached := max(0, u.PromptTokenCount-u.CachedContentTokenCount) + u.ToolUsePromptTokenCount
	return cost + (float64(uncached)*p.input+float64(u.CachedContentTokenCount)*p.cached+
		float64(u.CandidatesTokenCount)*p.output+float64(u.ThoughtsTokenCount)*p.thinking)/1e6
}

type AgentBudget struct {
	db *firestore.Client
	// notify DM admin lần đầu chạm trần trong ngày; nil thì chỉ log.
	notify func(ctx context.Context, text string) error
	// now thay time.Now trong test, để đổi ngày mà không phải chờ.
	now func() time.Time
}

func NewAgentBudget(db *firestore.Client, notify func(ctx context.Context, text string) error) *AgentBudget {
	return &AgentBudget{db: db, notify: notify}
}

func (b *AgentBudget) wall() time.Time {
	if b.now != nil {
		return b.now()
	}
	return time.Now()
}

// agentUsageDay là ngày giờ VN, cùng múi với trần tin của phòng và chat riêng.
func agentUsageDay(t time.Time) string { return t.In(vietnam).Format("2006-01-02") }

func (b *AgentBudget) usageRef(day string) *firestore.DocumentRef {
	return b.db.Collection("agentState").Doc("usage").Collection("days").Doc(day)
}

// admit đọc config và trả errAgentOverBudget khi hôm nay đã tiêu tới trần.
// Config trả về để record dùng đúng bảng giá lúc kiểm.
func (b *AgentBudget) admit(ctx context.Context, day string, wall time.Time) (agentBudgetConfig, error) {
	raw, err := docMap(b.db.Collection("agentState").Doc("config").Get(ctx))
	if err != nil {
		return agentBudgetConfig{}, err
	}
	cfg := parseAgentBudgetConfig(raw)
	if cfg.dailyUsd <= 0 {
		return cfg, nil
	}
	usage, err := docMap(b.usageRef(day).Get(ctx))
	if err != nil {
		return cfg, err
	}
	spent := number(usage["costUsd"])
	if spent < cfg.dailyUsd {
		return cfg, nil
	}
	slog.WarnContext(ctx, "agent.budget_hit", "feature", llmLabelOf(ctx).feature, "day", day, "costUsd", spent, "budgetUsd", cfg.dailyUsd)
	// Cờ trong doc của ngày: mỗi ngày chỉ một lượt claim được, kể cả khi nhiều
	// task chạm trần cùng lúc. DM hỏng sau khi claim thì mất, như claimOnce.
	first, err := claimOnce(ctx, b.db, b.usageRef(day), "budgetHitAt", map[string]any{"budgetHitAt": wall})
	if err != nil {
		return cfg, err
	}
	if first && b.notify != nil {
		text := fmt.Sprintf("Bot cá nhân chạm trần chi phí hôm nay (%s): đã tiêu %.2f USD, trần %.2f USD. Bot trả câu nghỉ tới 0h giờ VN. Muốn mở lại thì nâng agentState/config.dailyBudgetUsd.", day, spent, cfg.dailyUsd)
		// Không trả lỗi: cờ đã đặt nên task chạy lại cũng không gửi lại, chỉ làm
		// người dùng chờ thêm.
		if err := b.notify(ctx, text); err != nil {
			slog.WarnContext(ctx, "agent.budget_alert_failed", "day", day, "error", err)
		}
	}
	return cfg, errAgentOverBudget
}

// record cộng chi phí và số token của một lượt vào doc của ngày. Increment để
// hai lượt chạy cùng lúc không ghi đè nhau.
func (b *AgentBudget) record(ctx context.Context, cfg agentBudgetConfig, day, model string, resp *genai.GenerateContentResponse, search bool, wall time.Time) error {
	var u genai.GenerateContentResponseUsageMetadata
	if resp != nil && resp.UsageMetadata != nil {
		u = *resp.UsageMetadata
	}
	update := map[string]any{
		"costUsd":        firestore.Increment(llmCost(cfg.price(ctx, model), &u, search)),
		"calls":          firestore.Increment(1),
		"promptTokens":   firestore.Increment(u.PromptTokenCount),
		"cachedTokens":   firestore.Increment(u.CachedContentTokenCount),
		"toolUseTokens":  firestore.Increment(u.ToolUsePromptTokenCount),
		"outputTokens":   firestore.Increment(u.CandidatesTokenCount),
		"thinkingTokens": firestore.Increment(u.ThoughtsTokenCount),
		"updatedAt":      wall,
	}
	if search {
		update["searchCalls"] = firestore.Increment(1)
	}
	_, err := b.usageRef(day).Set(ctx, update, firestore.MergeAll)
	return err
}

// meter bọc một lượt gọi model: kiểm trần, gọi, rồi cộng chi phí. Ngày lấy lúc
// bắt đầu, nên lượt gọi vắt qua 0h tính cho ngày cũ.
func (b *AgentBudget) meter(ctx context.Context, model string, search bool, call func() (*genai.GenerateContentResponse, error)) (*genai.GenerateContentResponse, error) {
	wall := b.wall()
	day := agentUsageDay(wall)
	cfg, err := b.admit(ctx, day, wall)
	if err != nil {
		return nil, err
	}
	resp, err := call()
	if err != nil {
		return nil, err
	}
	if err := b.record(ctx, cfg, day, model, resp, search, wall); err != nil {
		return nil, err
	}
	return resp, nil
}

// budgetAgentLLM là agentLLM có tính trần. Bọc ở đây chứ không ở
// generateWithRetry hay googleSearch, vì hai hàm đó 3i cũng dùng.
type budgetAgentLLM struct {
	inner  agentLLM
	model  string
	budget *AgentBudget
}

func (g budgetAgentLLM) Generate(ctx context.Context, system string, contents []*genai.Content, tools []*genai.Tool) (*genai.GenerateContentResponse, error) {
	return g.budget.meter(ctx, g.model, false, func() (*genai.GenerateContentResponse, error) {
		return g.inner.Generate(ctx, system, contents, tools)
	})
}

func (g budgetAgentLLM) Search(ctx context.Context, query string) (*genai.GenerateContentResponse, error) {
	return g.budget.meter(ctx, g.model, true, func() (*genai.GenerateContentResponse, error) {
		return g.inner.Search(ctx, query)
	})
}

type budgetLearnLLM struct {
	inner  learnLLM
	model  string
	budget *AgentBudget
}

func (g budgetLearnLLM) Learn(ctx context.Context, system, input string, schema *genai.Schema) (*genai.GenerateContentResponse, error) {
	return g.budget.meter(ctx, g.model, false, func() (*genai.GenerateContentResponse, error) {
		return g.inner.Learn(ctx, system, input, schema)
	})
}

// adminNotifier DM mọi admin đã liên kết Telegram, cùng đường với báo cáo chat.
func adminNotifier(games *GameStore, tg *TelegramService) func(ctx context.Context, text string) error {
	return func(ctx context.Context, text string) error {
		if games == nil || tg == nil || !tg.Enabled() {
			return errors.New("chưa cấu hình Telegram")
		}
		chats, err := games.adminChats(ctx)
		if err != nil {
			return err
		}
		if len(chats) == 0 {
			return errors.New("không admin nào liên kết Telegram")
		}
		return sendToAny(ctx, tg, chats, []string{text})
	}
}
