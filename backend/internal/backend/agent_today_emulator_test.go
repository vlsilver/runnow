//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

func (e *agentEnv) merge(path string, data map[string]any) {
	e.t.Helper()
	if _, err := e.store.db.Doc(path).Set(context.Background(), data, firestore.MergeAll); err != nil {
		e.t.Fatal(err)
	}
}

// meToday là field today của GET /v1/agents/me, nil khi không có.
func (e *agentEnv) meToday(uid string) map[string]any {
	e.t.Helper()
	r := e.call(uid, "GET", "/v1/agents/me", nil, "")
	e.want(r, 200, "")
	today, _ := r.body["today"].(map[string]any)
	return today
}

func (e *agentEnv) wantToday(uid string, dmUsed, dmMax, roomUsed, roomMax float64, resting any) {
	e.t.Helper()
	got := e.meToday(uid)
	if got == nil || got["dmUsed"] != dmUsed || got["dmMax"] != dmMax || got["roomUsed"] != roomUsed || got["roomMax"] != roomMax || got["resting"] != resting {
		e.t.Fatalf("today của %s = %v, muốn dm %v/%v, room %v/%v, resting %v", uid, got, dmUsed, dmMax, roomUsed, roomMax, resting)
	}
}

// GET me báo lượt đã dùng hôm nay và lý do bot đang nghỉ, đọc đúng bộ đếm bot
// dùng để chặn.
func TestEmulatorAgentMeToday(t *testing.T) {
	e := newAgentEnv(t)

	// Người chưa được mời không có today; thành viên chưa tạo bot thì 0.
	if got := e.meToday("dung"); got != nil {
		t.Fatalf("người chưa được mời mà có today: %v", got)
	}
	e.wantToday("cuong", 0, 100, 0, 300, nil)

	// Một câu trả lời thật làm dmUsed lên 1.
	e.createBot("an", "Sóc", "")
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{llmText("Chào An")}
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 1})
	e.wantToday("an", 1, 100, 0, 300, nil)

	today := vnDay(e.clock)
	e.merge("agents/an", map[string]any{"dmDay": today, "dmDayCount": 3})
	e.merge("agentRooms/main", map[string]any{"day": today, "dayCount": 12})
	e.wantToday("an", 3, 100, 12, 300, nil)

	// Admin hạ dmDailyMax về 3: dmMax theo config, đủ lượt là dm_limit.
	e.merge("agentState/config", map[string]any{"dmDailyMax": 3, "roomDailyMax": 50})
	e.wantToday("an", 3, 3, 12, 50, agentRestingDMLimit)

	// Trần tiền 0 là không giới hạn, tiêu bao nhiêu cũng không nghỉ vì budget.
	e.merge("agentState/config", map[string]any{"dmDailyMax": 10, "dailyBudgetUsd": 0})
	e.merge("agentState/usage/days/"+agentUsageDay(e.clock), map[string]any{"costUsd": 5.0})
	e.wantToday("an", 3, 10, 12, 50, nil)

	// Có trần: chưa tới thì không nghỉ, chạm đúng trần là nghỉ.
	e.merge("agentState/config", map[string]any{"dailyBudgetUsd": 5.5})
	e.wantToday("an", 3, 10, 12, 50, nil)
	e.merge("agentState/usage/days/"+agentUsageDay(e.clock), map[string]any{"costUsd": 5.5})
	e.wantToday("an", 3, 10, 12, 50, agentRestingBudget)
	// Cả hai cùng chạm thì báo budget, vì nâng lượt chat riêng cũng không mở lại.
	e.merge("agentState/config", map[string]any{"dmDailyMax": 3})
	e.wantToday("an", 3, 3, 12, 50, agentRestingBudget)
	// Người chưa tạo bot cũng thấy bot đang nghỉ vì budget.
	e.wantToday("cuong", 0, 3, 12, 50, agentRestingBudget)

	// Qua 0h giờ VN: bộ đếm ngày cũ không tính, doc usage ngày mới chưa có.
	e.tick(16 * time.Hour)
	e.wantToday("an", 0, 3, 0, 50, nil)
}
