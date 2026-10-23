//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

func configField(t *testing.T, r apiResp, key string) map[string]any {
	t.Helper()
	for _, f := range anyList(r.body["fields"]) {
		if m := f.(map[string]any); m["key"] == key {
			return m
		}
	}
	t.Fatalf("không có field %s: %s", key, r.raw)
	return nil
}

// Trang Admin đọc và sửa config bot cá nhân: chỉ admin, kiểm khoảng hợp lệ,
// không ghi đè bản admin khác vừa lưu, null đưa về mặc định.
func TestEmulatorAgentAdminConfig(t *testing.T) {
	e := newAgentEnv(t)
	e.srv = NewAPIServer(Config{AgentModel: "m-chat", AgentLearnModel: "m-learn"}, e.deps)
	seed(t, e.store.db, "agentState/usage/days/"+agentUsageDay(e.clock), map[string]any{"costUsd": 1.25, "calls": 7, "searchCalls": 2, "budgetHitAt": e.clock})

	e.want(e.call("cuong", "GET", "/v1/admin/agent-config", nil, ""), 403, "not_admin")
	e.want(e.call("cuong", "PATCH", "/v1/admin/agent-config", map[string]any{"values": map[string]any{"chainMax": 1}}, ""), 403, "not_admin")

	r := e.call("an", "GET", "/v1/admin/agent-config", nil, "")
	e.want(r, 200, "")
	if f := configField(t, r, "dmDailyMax"); f["value"] != nil || f["default"] != 100.0 || f["kind"] != "int" || f["help"] == "" || f["label"] == "" || f["unit"] == "" {
		t.Fatalf("dmDailyMax: %v", f)
	}
	if f := configField(t, r, "dailyBudgetUsd"); f["value"] != nil || f["default"] != 0.0 {
		t.Fatalf("dailyBudgetUsd: %v", f)
	}
	usage, _ := r.body["usage"].(map[string]any)
	if usage["costUsd"] != 1.25 || usage["calls"] != 7.0 || usage["searchCalls"] != 2.0 || usage["budgetHit"] != true || usage["day"] != "2026-10-20" {
		t.Fatalf("usage: %v", usage)
	}
	models := anyList(r.body["models"])
	if len(models) != 2 || models[0].(map[string]any)["model"] != "m-chat" || models[1].(map[string]any)["priced"] != false {
		t.Fatalf("models: %v", models)
	}
	if r.body["version"] != "" || len(anyList(r.body["priceFields"])) != 5 {
		t.Fatalf("version, priceFields: %s", r.raw)
	}

	// Sai thì 400 và không ghi gì.
	for _, body := range []map[string]any{
		{"values": map[string]any{"chainMax": 0}},
		{"values": map[string]any{"dmDailyMax": 2.5}},
		{"values": map[string]any{"dailyBudgetUsd": -1}},
		{"values": map[string]any{"open": 1}},
		{"values": map[string]any{}},
		{"prices": []any{map[string]any{"model": "m-chat", "outputPer1M": 1}}},
		{"prices": []any{map[string]any{"model": "m-chat", "inputPer1M": 1, "outputPer1M": 1}, map[string]any{"model": "m-chat", "inputPer1M": 1, "outputPer1M": 1}}},
		{"prices": []any{map[string]any{"model": "", "inputPer1M": 1, "outputPer1M": 1}}},
		{"prices": []any{map[string]any{"model": "m-chat", "inputPer1M": -1, "outputPer1M": 1}}},
	} {
		body["version"] = ""
		e.want(e.call("an", "PATCH", "/v1/admin/agent-config", body, ""), 400, "invalid_request")
	}
	if cfg := e.doc("agentState/config"); len(cfg) != 1 {
		t.Fatalf("PATCH sai mà vẫn ghi: %v", cfg)
	}

	r = e.call("an", "PATCH", "/v1/admin/agent-config", map[string]any{"version": "", "values": map[string]any{"dmDailyMax": 1, "dailyBudgetUsd": 3},
		"prices": []any{map[string]any{"model": "m-chat", "inputPer1M": 0.75, "outputPer1M": 3.75, "cachedPer1M": 0.075, "thinkingPer1M": nil}}}, "")
	e.want(r, 200, "")
	if configField(t, r, "dmDailyMax")["value"] != 1.0 || configField(t, r, "dailyBudgetUsd")["value"] != 3.0 {
		t.Fatalf("sau khi lưu: %s", r.raw)
	}
	if models := anyList(r.body["models"]); models[0].(map[string]any)["priced"] != true || models[1].(map[string]any)["priced"] != false {
		t.Fatalf("models sau khi khai giá: %v", models)
	}
	price := anyList(e.doc("agentState/config")["llmPrices"])[0].(map[string]any)
	if _, ok := price["thinkingPer1M"]; ok || price["inputPer1M"] != 0.75 {
		t.Fatalf("cột để trống phải không ghi, để tính theo giá output: %v", price)
	}
	if e.doc("agentState/config")["adminUpdatedBy"] != "an" || anyList(e.doc("agentState/config")["memberUids"])[0] != "cuong" {
		t.Fatalf("doc config sau khi lưu: %v", e.doc("agentState/config"))
	}
	version := r.body["version"].(string)
	if version == "" {
		t.Fatal("lưu xong mà version rỗng")
	}

	// Trang mở từ trước (version cũ) không ghi đè được.
	e.want(e.call("binh", "PATCH", "/v1/admin/agent-config", map[string]any{"version": "", "values": map[string]any{"dmDailyMax": 50}}, ""), 409, "config_changed")
	if e.doc("agentState/config")["dmDailyMax"] != 1.0 {
		t.Fatal("PATCH bị từ chối mà vẫn ghi")
	}

	// null đưa về mặc định: xoá field, GET trả value null.
	e.tick(time.Second)
	r = e.call("binh", "PATCH", "/v1/admin/agent-config", map[string]any{"version": version, "values": map[string]any{"dailyBudgetUsd": nil}}, "")
	e.want(r, 200, "")
	if _, ok := e.doc("agentState/config")["dailyBudgetUsd"]; ok || configField(t, r, "dailyBudgetUsd")["value"] != nil {
		t.Fatalf("null phải xoá field: %v", e.doc("agentState/config"))
	}
}

// Ba giới hạn đếm theo tin lấy từ config ở task kế, không cần deploy.
func TestEmulatorAgentLimitsFromConfig(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	e.createBot("binh", "Mèo", "")
	setCfg := func(values map[string]any) {
		t.Helper()
		if _, err := e.store.db.Doc("agentState/config").Set(context.Background(), values, firestore.MergeAll); err != nil {
			t.Fatal(err)
		}
	}

	// dmDailyMax = 1: câu thứ hai trong ngày là câu nghỉ, không gọi model.
	setCfg(map[string]any{"dmDailyMax": 1})
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{llmText("Chào An")}
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 1})
	e.tick(time.Second)
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "còn đó không"}, ""), 200, "")
	calls := len(e.llm.calls)
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 3})
	if msgs := messages(t, e.call("an", "GET", "/v1/agents/me/dm", nil, "")); len(e.llm.calls) != calls || msgs[0]["text"] != agentBudgetReply {
		t.Fatalf("dmDailyMax 1 mà câu thứ hai vẫn gọi model: %v", msgs[0])
	}

	// chainMax = 1: một bot đáp rồi thôi, không hẹn lượt kế.
	setCfg(map[string]any{"chainMax": 1})
	e.want(e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Sóc ơi chạy không"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{llmText("Chạy!")}
	turns := len(e.tasksTo("/tasks/agent-turn"))
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	if msgs := messages(t, e.call("cuong", "GET", "/v1/agents/room?after=1", nil, "")); len(msgs) != 1 {
		t.Fatalf("lượt đầu phải có một bot nói: %v", msgs)
	}
	if len(e.tasksTo("/tasks/agent-turn")) != turns {
		t.Fatal("chainMax 1 mà vẫn hẹn lượt bot kế")
	}

	// roomDailyMax = 1: hôm nay phòng đã có một tin bot, bot không nói nữa.
	setCfg(map[string]any{"roomDailyMax": 1, "chainMax": 6})
	e.tick(time.Second)
	e.want(e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Mèo thì sao"}, ""), 200, "")
	calls = len(e.llm.calls)
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 3})
	if len(e.llm.calls) != calls {
		t.Fatal("roomDailyMax 1 đã dùng hết mà bot vẫn gọi model")
	}
}
