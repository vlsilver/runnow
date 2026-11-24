//go:build emulator

package backend

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

// budgetEnv gắn trần chi phí vào bot của agentEnv như dependencies.go làm, với
// đồng hồ giả của env và DM admin ghi vào alerts.
type budgetEnv struct {
	*agentEnv
	budget *AgentBudget
	alerts []string
}

const budgetModel = "gemini-test"

// Giá dễ tính tay: mỗi lượt usedResp tốn 1000 × 10/1M + 100 × 100/1M = 0.02 USD.
var budgetPrices = []any{map[string]any{"model": budgetModel, "inputPer1M": 10.0, "outputPer1M": 100.0, "searchPerCall": 0.5}}

func newBudgetEnv(t *testing.T, config map[string]any) *budgetEnv {
	t.Helper()
	e := &budgetEnv{agentEnv: newAgentEnv(t)}
	e.budget = NewAgentBudget(e.store.db, func(_ context.Context, text string) error {
		e.alerts = append(e.alerts, text)
		return nil
	})
	e.budget.now = func() time.Time { return e.clock }
	e.brain.llm = budgetAgentLLM{inner: e.llm, model: budgetModel, budget: e.budget}
	config["memberUids"] = []any{"cuong"}
	seed(t, e.store.db, "agentState/config", config)
	return e
}

func usedResp(text string) *genai.GenerateContentResponse {
	r := llmText(text)
	r.UsageMetadata = &genai.GenerateContentResponseUsageMetadata{PromptTokenCount: 1000, CandidatesTokenCount: 100}
	return r
}

func (e *budgetEnv) usage(day string) map[string]any {
	e.t.Helper()
	doc, err := docMap(e.store.db.Doc("agentState/usage/days/" + day).Get(context.Background()))
	if err != nil {
		e.t.Fatal(err)
	}
	return doc
}

// dm gửi một tin chat riêng của an, chạy task rồi trả câu bot vừa trả lời.
func (e *budgetEnv) dm(text string) string {
	e.t.Helper()
	e.tick(time.Second)
	r := e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": text}, "")
	e.want(r, 200, "")
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: int64(number(r.body["seq"]))})
	return stringValue(messages(e.t, e.call("an", "GET", "/v1/agents/me/dm", nil, ""))[0]["text"])
}

func TestEmulatorAgentBudgetDM(t *testing.T) {
	e := newBudgetEnv(t, map[string]any{"dailyBudgetUsd": 0.03, "llmPrices": budgetPrices})
	e.createBot("an", "Sóc", "")
	day := agentUsageDay(e.clock)

	// Lượt 1: dưới trần, gọi model và cộng 0.02.
	e.llm.script = []*genai.GenerateContentResponse{usedResp("một")}
	if got := e.dm("a"); got != "một" || len(e.llm.calls) != 1 {
		t.Fatalf("dưới trần: %q, %d lần gọi", got, len(e.llm.calls))
	}
	u := e.usage(day)
	if !near(number(u["costUsd"]), 0.02) || number(u["calls"]) != 1 || number(u["promptTokens"]) != 1000 || number(u["outputTokens"]) != 100 {
		t.Fatalf("usage sau lượt 1: %v", u)
	}

	// Lượt 2 có tra web: lúc bắt đầu mới tiêu 0.02 nên được gọi. Lượt gọi tool
	// không có usage (0), lượt tra tốn 0.5 phí tra + 0.02 token, tổng 0.54 vượt
	// trần. Lượt viết câu trả lời sau đó bị chặn, nên chủ nhận câu nghỉ chứ không
	// chờ mãi, và admin được DM.
	e.llm.searchResp = usedResp("nắng")
	e.llm.script = []*genai.GenerateContentResponse{llmCall("web_search", map[string]any{"query": "thời tiết"}), usedResp("hai")}
	if got := e.dm("b"); got != agentBudgetReply || len(e.llm.calls) != 2 || len(e.llm.searches) != 1 {
		t.Fatalf("lượt 2: %q, %d lần gọi, %d lần tra", got, len(e.llm.calls), len(e.llm.searches))
	}
	u = e.usage(day)
	if !near(number(u["costUsd"]), 0.54) || number(u["calls"]) != 3 || number(u["searchCalls"]) != 1 || u["budgetHitAt"] == nil || len(e.alerts) != 1 || !strings.Contains(e.alerts[0], day) {
		t.Fatalf("usage sau lượt 2: %v, alerts %v", u, e.alerts)
	}

	// Đã quá trần: không gọi model, trả câu nghỉ, không DM admin lần nữa.
	for _, text := range []string{"c", "d"} {
		if got := e.dm(text); got != agentBudgetReply || len(e.llm.calls) != 2 {
			t.Fatalf("quá trần: %q, %d lần gọi", got, len(e.llm.calls))
		}
	}
	if len(e.alerts) != 1 {
		t.Fatalf("DM admin phải đúng một lần trong ngày: %v", e.alerts)
	}

	// Sang ngày mới (giờ VN): trần tính lại từ 0, model chạy lại.
	e.tick(24 * time.Hour)
	next := agentUsageDay(e.clock)
	e.llm.script = []*genai.GenerateContentResponse{usedResp("ba")}
	if got := e.dm("e"); next == day || got != "ba" || len(e.llm.calls) != 3 || !near(number(e.usage(next)["costUsd"]), 0.02) {
		t.Fatalf("ngày mới: %q, %d lần gọi, usage %v", got, len(e.llm.calls), e.usage(next))
	}
	// Ngày mới chạm trần thì báo admin lại, vì cờ nằm ở doc của ngày.
	seed(t, e.store.db, "agentState/usage/days/"+next, map[string]any{"costUsd": 1.0})
	if got := e.dm("f"); got != agentBudgetReply || len(e.alerts) != 2 {
		t.Fatalf("ngày mới quá trần: %q, alerts %v", got, e.alerts)
	}
}

// Chưa đặt trần (thiếu field hay bằng 0): đã tiêu bao nhiêu cũng gọi model như
// trước, chỉ cộng số. Model chưa khai giá thì tính theo giá dự phòng.
func TestEmulatorAgentBudgetUnsetChangesNothing(t *testing.T) {
	for _, config := range []map[string]any{{}, {"dailyBudgetUsd": 0}} {
		e := newBudgetEnv(t, config)
		e.createBot("an", "Sóc", "")
		day := agentUsageDay(e.clock)
		seed(t, e.store.db, "agentState/usage/days/"+day, map[string]any{"costUsd": 1000.0})
		e.llm.script = []*genai.GenerateContentResponse{usedResp("vẫn nói")}
		if got := e.dm("a"); got != "vẫn nói" || len(e.llm.calls) != 1 || len(e.alerts) != 0 {
			t.Fatalf("config %v: %q, %d lần gọi, alerts %v", config, got, len(e.llm.calls), e.alerts)
		}
		want := 1000 + (1000*agentFallbackPrice.input+100*agentFallbackPrice.output)/1e6
		if u := e.usage(day); !near(number(u["costUsd"]), want) || number(u["calls"]) != 1 {
			t.Fatalf("config %v: usage %v, muốn costUsd %v", config, u, want)
		}
	}
}

// Phòng quá trần: một bot báo nghỉ rồi dừng chuỗi, không gọi model, không hẹn
// lượt kế; lượt bị hẹn lại do task chạy lại cũng không báo nghỉ lần hai.
func TestEmulatorAgentBudgetRoom(t *testing.T) {
	e := newBudgetEnv(t, map[string]any{"dailyBudgetUsd": 0.01, "llmPrices": budgetPrices})
	e.createBot("an", "Sóc", "")
	e.createBot("binh", "Mèo", "")
	seed(t, e.store.db, "agentState/usage/days/"+agentUsageDay(e.clock), map[string]any{"costUsd": 0.01})
	e.want(e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Chào cả nhà"}, ""), 200, "")
	before := len(roomTurnTasks(e.agentEnv))
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	msgs, err := e.store.db.Collection("agentRooms").Doc("main").Collection("messages").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(e.llm.calls) != 0 || len(msgs) != 2 || msgs[1].Data()["text"] != agentBudgetReply || msgs[1].Data()["kind"] != agentKindAgent {
		t.Fatalf("quá trần: %d lần gọi, %d tin", len(e.llm.calls), len(msgs))
	}
	if len(roomTurnTasks(e.agentEnv)) != before || len(e.alerts) != 1 {
		t.Fatalf("quá trần mà vẫn hẹn lượt kế (%d task) hoặc DM admin sai (%v)", len(roomTurnTasks(e.agentEnv))-before, e.alerts)
	}
	// Task chạy lại: nhánh turnOf hẹn lượt 2; lượt 2 thấy câu nghỉ đứng cuối nên thôi.
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 2})
	room, err := docMap(e.store.db.Doc("agentRooms/main").Get(context.Background()))
	if err != nil {
		t.Fatal(err)
	}
	if number(room["seq"]) != 2 || len(e.llm.calls) != 0 {
		t.Fatalf("lượt hẹn lại báo nghỉ lần hai: seq %v", room["seq"])
	}
}

// Tự học chạm trần giữa lô: dừng ở scope đó, không lỗi để task khỏi chạy lại,
// lô vẫn ở pending và cursor chưa tiến. Hôm sau học tiếp đúng các scope còn lại.
func TestEmulatorAgentBudgetLearnKeepsBatch(t *testing.T) {
	e := newLearnEnv(t)
	now := e.t0.Add(20 * time.Minute)
	clock := now
	budget := NewAgentBudget(e.db, nil)
	budget.now = func() time.Time { return clock }
	e.svc.llm = budgetLearnLLM{inner: e.llm, model: budgetModel, budget: budget}
	seed(t, e.db, "agentState/config", map[string]any{"dailyBudgetUsd": 0.5, "llmPrices": budgetPrices})
	e.llm.reply = func(system, input string) (string, error) {
		if system == learnGroupPrompt {
			// Lượt đầu (ký ức nhóm) tiêu vượt trần.
			seed(t, e.db, "agentState/usage/days/"+agentUsageDay(clock), map[string]any{"costUsd": 1.0})
		}
		return addOne(system, input)
	}
	if err := e.run(now); err != nil {
		t.Fatalf("chạm trần mà Run báo lỗi, task sẽ chạy lại vô ích: %v", err)
	}
	wantList(t, "scope trước khi chạm trần", e.llm.scopes(), agentGroupScope)
	state := e.data("agentState/learn")
	if state["pending"] == nil || state["cursor"] != nil {
		t.Fatalf("chạm trần mà mất lô hoặc cursor đã tiến: %v", state)
	}
	if err := e.run(now.Add(30 * time.Minute)); err != nil || len(e.llm.calls) != 0 {
		t.Fatalf("vẫn quá trần mà gọi model: %v, %d lần", err, len(e.llm.calls))
	}

	clock = clock.Add(24 * time.Hour)
	e.mustRun(clock)
	wantList(t, "scope hôm sau", e.llm.scopes(), "An", "Bình", "Cường", "Dũng")
	state = e.data("agentState/learn")
	if c := cursorFrom(state["cursor"]); state["pending"] != nil || c.RoomSeq != 3 {
		t.Fatalf("hôm sau phải học xong lô cũ: %v", state)
	}
	wantList(t, "ký ức nhóm học một lần", e.factTexts(agentGroupScope), "f1 học: Dũng: mình đi được")
}

// Lỗi model không bị nhầm là chạm trần: vẫn trả lỗi để task chạy lại.
func TestEmulatorAgentBudgetModelErrorStillRetries(t *testing.T) {
	e := newBudgetEnv(t, map[string]any{"dailyBudgetUsd": 1.0, "llmPrices": budgetPrices})
	e.createBot("an", "Sóc", "")
	e.tick(time.Second)
	e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "a"}, "")
	e.llm.err = errors.New("vertex 503")
	if code := e.runTask("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 1}); code < 500 {
		t.Fatalf("model lỗi mà task trả %d", code)
	}
	if u := e.usage(agentUsageDay(e.clock)); u["calls"] != nil {
		t.Fatalf("lượt lỗi không có token mà vẫn cộng: %v", u)
	}
}
