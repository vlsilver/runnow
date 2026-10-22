//go:build emulator

package backend

import (
	"fmt"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

// seedOwnerRun cho An một buổi chạy 5,2 km sáng nay và một kèo club An đang
// chạy được 12/100 km.
func (e *agentEnv) seedOwnerRun() {
	e.t.Helper()
	seed(e.t, e.store.db, "users/an/activities/a1", map[string]any{
		"startedAt": agentClock.Add(-time.Hour).UTC().Format(time.RFC3339), "distanceMeters": 5200.0,
		"movingTimeSeconds": 1800, "sportType": "Run", "source": "strava",
	})
	seed(e.t, e.store.db, "runContracts/k1", map[string]any{
		"title": "Tháng 100 km", "metric": "distance", "status": "active", "visibility": "club",
		"targetValue": 100.0, "progressValue": 30.0, "participantUids": []any{"an", "binh"},
		"participants":   map[string]any{"an": map[string]any{"progressValue": 12.0}},
		"endAtExclusive": time.Now().Add(30 * 24 * time.Hour),
	})
}

// Chủ hỏi bot về buổi chạy và kèo trong chat riêng: bot đọc đúng số của chủ.
func TestEmulatorAgentDMOwnerRunData(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	e.seedOwnerRun()
	ask := func(script ...*genai.GenerateContentResponse) []fakeCall {
		t.Helper()
		e.tick(2 * time.Second)
		e.llm.calls, e.llm.script = nil, script
		e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "hôm nay mình chạy bao nhiêu"}, ""), 200, "")
		tasks := e.tasksTo("/tasks/agent-dm")
		e.mustRun("/tasks/agent-dm", tasks[len(tasks)-1].Payload)
		return e.llm.calls
	}

	calls := ask(llmCall("get_owner_today", nil), llmText("5,2 km rồi"))
	wantList(t, "tool chat riêng", toolNames(calls[0]), "web_search", "remember", "update_memory", "forget", "get_owner_today", "get_owner_recent_run", "get_owner_contracts", "get_club_contracts")
	if out := toolResult(t, calls[1]); fmt.Sprintf("%v %v %v", out["runKm"], out["runCount"], out["date"]) != "5.2 1 2026-10-20" {
		t.Fatalf("get_owner_today: %v", out)
	}
	calls = ask(llmCall("get_owner_recent_run", map[string]any{"offset": 0}), llmText("ok"))
	if out := toolResult(t, calls[1]); fmt.Sprintf("%v %v %v", out["found"], out["member"], out["distanceKm"]) != "true An 5.2" {
		t.Fatalf("get_owner_recent_run: %v", out)
	}
	calls = ask(llmCall("get_owner_contracts", nil), llmText("ok"))
	if out := toolResult(t, calls[1]); fmt.Sprintf("%v %v", out["contractCount"], out["contracts"]) != "1 [map[metric:distance progress:12 target:100 title:Tháng 100 km]]" {
		t.Fatalf("get_owner_contracts: %v", out)
	}
	calls = ask(llmCall("get_club_contracts", nil), llmText("ok"))
	if out := toolResult(t, calls[1]); !strings.Contains(fmt.Sprint(out["contracts"]), "currentValue:30") || !strings.Contains(fmt.Sprint(out["contracts"]), "participants:2") {
		t.Fatalf("get_club_contracts: %v", out)
	}
}

// Trong phòng ai cũng đọc được câu bot nói: chủ để hồ sơ riêng tư thì bot chỉ
// đọc được kèo của club, gọi tool về chủ cũng không ra số. Hồ sơ công khai thì
// đọc được như chat riêng.
func TestEmulatorAgentRoomOwnerRunDataPublicOnly(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	e.seedOwnerRun()
	turn := func(script ...*genai.GenerateContentResponse) []fakeCall {
		t.Helper()
		e.tick(time.Minute)
		e.llm.calls, e.llm.script = nil, script
		e.want(e.call("binh", "POST", "/v1/agents/room", map[string]any{"text": "Sóc ơi chủ bạn hôm nay chạy chưa"}, ""), 200, "")
		e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: lastTurn(t, e).AfterSeq})
		return e.llm.calls
	}

	calls := turn(llmCall("get_owner_today", nil), llmText("Không kể được đâu"))
	wantList(t, "tool phòng, hồ sơ riêng tư", toolNames(calls[0]), "web_search", "get_club_contracts")
	if out := toolResult(t, calls[1]); out["runKm"] != nil || out["error"] == nil {
		t.Fatalf("hồ sơ riêng tư mà tool về chủ vẫn ra số: %v", out)
	}

	seed(t, e.store.db, "publicProfiles/an", map[string]any{"displayName": "An", "profileVisibility": "public"})
	calls = turn(llmCall("get_owner_today", nil), llmText("Chủ mình chạy 5,2 km rồi"))
	wantList(t, "tool phòng, hồ sơ công khai", toolNames(calls[0]), "web_search", "get_owner_today", "get_owner_recent_run", "get_owner_contracts", "get_club_contracts")
	if out := toolResult(t, calls[1]); fmt.Sprint(out["runKm"]) != "5.2" {
		t.Fatalf("hồ sơ công khai: %v", out)
	}
}
