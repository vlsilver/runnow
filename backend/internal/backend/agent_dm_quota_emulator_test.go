//go:build emulator

package backend

import (
	"errors"
	"reflect"
	"testing"
	"time"

	"google.golang.org/genai"
)

// noRunDMLimitReply là câu nghỉ khi chủ chưa chạy hôm nay và đã dùng hết 10
// câu sẵn, với config mặc định.
const noRunDMLimitReply = "Hôm nay mình hết lượt nói rồi. Bạn chạy hay đi bộ thêm 1 km là mình nói tiếp được 10 câu nữa, không thì qua 0h mình nói tiếp nhé."

func (e *agentEnv) wantDMByKm(uid string, dmMax float64, byKm map[string]any) {
	e.t.Helper()
	got := e.meToday(uid)
	if got["dmMax"] != dmMax || !reflect.DeepEqual(got["dmByKm"], byKm) {
		e.t.Fatalf("today của %s: dmMax %v, dmByKm %v; muốn %v, %v", uid, got["dmMax"], got["dmByKm"], dmMax, byKm)
	}
}

// Hạn mức chat riêng theo km: 10 câu sẵn, mỗi km chạy trọn hôm nay thêm 10 câu,
// không quá dmDailyMax. GET me trả dmMax đã tính kèm cách tính để app vẽ thẻ
// km; bot chặn đúng ở dmMax đó, và câu nghỉ chỉ chủ chạy thêm bao nhiêu.
func TestEmulatorAgentDMByKm(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	e.wantDMByKm("an", 10, map[string]any{"base": 10.0, "perKm": 10.0, "runKm": 0.0, "nextKm": 1.0, "nextMax": 20.0})

	e.seedRunKm("an", 4.1)
	e.wantDMByKm("an", 50, map[string]any{"base": 10.0, "perKm": 10.0, "runKm": 4.1, "nextKm": 5.0, "nextMax": 60.0})

	// Dùng hết 50 câu: bot nghỉ, câu nghỉ chỉ cách mở thêm, không gọi model.
	e.merge("agents/an", map[string]any{"dmDay": vnDay(e.clock), "dmDayCount": 50})
	if got := e.meToday("an"); got["resting"] != agentRestingDMLimit {
		t.Fatalf("hết 50/50 mà không nghỉ: %v", got)
	}
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "còn nói được không"}, ""), 200, "")
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 1})
	want := "Hôm nay mình hết lượt nói rồi. Bạn chạy hay đi bộ thêm 0,9 km là mình nói tiếp được 10 câu nữa, không thì qua 0h mình nói tiếp nhé."
	if msgs := messages(t, e.call("an", "GET", "/v1/agents/me/dm", nil, "")); len(e.llm.calls) != 0 || msgs[0]["text"] != want {
		t.Fatalf("câu nghỉ khi hết lượt: %v (gọi model %d lần)", msgs[0]["text"], len(e.llm.calls))
	}

	// Chạy thêm tới 5 km: câu thứ 51 được trả lời thật.
	e.seedRunKm("an", 5)
	e.tick(time.Second)
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "giờ thì sao"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{llmText("Nói tiếp nè")}
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 3})
	if msgs := messages(t, e.call("an", "GET", "/v1/agents/me/dm", nil, "")); msgs[0]["text"] != "Nói tiếp nè" || e.doc("agents/an")["dmDayCount"] != int64(51) {
		t.Fatalf("chạy đủ 5 km mà chưa mở câu 51: %v, dmDayCount %v", msgs[0]["text"], e.doc("agents/an")["dmDayCount"])
	}

	// Trần thấp hơn mốc kế thì nextMax là trần; chạm trần thì hết mốc.
	e.merge("agentState/config", map[string]any{"dmDailyMax": 65})
	e.wantDMByKm("an", 60, map[string]any{"base": 10.0, "perKm": 10.0, "runKm": 5.0, "nextKm": 6.0, "nextMax": 65.0})
	e.seedRunKm("an", 9.5)
	e.wantDMByKm("an", 65, map[string]any{"base": 10.0, "perKm": 10.0, "runKm": 9.5, "nextKm": nil, "nextMax": nil})

	// Người chưa tạo bot: dmMax là số câu sẵn, không đọc km, không có dmByKm.
	if got := e.meToday("cuong"); got["dmMax"] != 10.0 || got["dmByKm"] != nil {
		t.Fatalf("chưa tạo bot: %v", got)
	}
}

// Km hôm nay tính cả quãng đường Apple Health tự đồng bộ (đi bộ không bấm
// chạy): lấy số lớn hơn giữa buổi chính thức và Health, không cộng hai bên vì
// cùng một buổi chạy có mặt ở cả hai. Lượt vẽ ảnh đọc cùng số km đó.
func TestEmulatorAgentDMKmCountsHealth(t *testing.T) {
	e := newAgentEnv(t)
	e.deps.AgentBrain = e.brain
	e.createBot("an", "Sóc", "")
	e.enableImages()
	stepDay := func(km float64) {
		seed(t, e.store.db, "users/an/stepDays/"+dateKey(e.clock), map[string]any{"steps": 3006, "distanceMeters": km * 1000})
	}

	stepDay(1.66)
	e.wantDMByKm("an", 20, map[string]any{"base": 10.0, "perKm": 10.0, "runKm": 1.66, "nextKm": 2.0, "nextMax": 30.0})
	if images := e.meToday("an")["images"].(map[string]any); images["limit"] != 3.0 || images["runKm"] != 1.66 {
		t.Fatalf("đi bộ 1,66 km mà lượt vẽ ảnh: %v", images)
	}

	e.seedRunKm("an", 5)
	stepDay(6)
	e.wantDMByKm("an", 70, map[string]any{"base": 10.0, "perKm": 10.0, "runKm": 6.0, "nextKm": 7.0, "nextMax": 80.0})
	stepDay(3)
	e.wantDMByKm("an", 60, map[string]any{"base": 10.0, "perKm": 10.0, "runKm": 5.0, "nextKm": 6.0, "nextMax": 70.0})
}

// Task agent-dm chạy lại khi model lỗi thì tin đó chỉ đếm một lần, kể cả khi
// lần đếm đầu đã chạm hạn mức: tin đã được nhận thì lần chạy lại vẫn trả lời.
func TestEmulatorAgentDMRetryCountsOnce(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	e.merge("agents/an", map[string]any{"dmDay": vnDay(e.clock), "dmDayCount": 9})
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "chào"}, ""), 200, "")

	e.llm.err = errors.New("Error 504, DEADLINE_EXCEEDED")
	for i := range 2 {
		if code := e.runTask("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 1}); code == 200 {
			t.Fatalf("lần chạy %d: model lỗi mà task trả 200, tin bị đếm lại thành hết lượt? %v", i+1, messages(t, e.call("an", "GET", "/v1/agents/me/dm", nil, ""))[0]["text"])
		}
	}
	e.llm.err = nil
	e.llm.script = []*genai.GenerateContentResponse{llmText("Chào bạn")}
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 1})
	if msgs := messages(t, e.call("an", "GET", "/v1/agents/me/dm", nil, "")); msgs[0]["text"] != "Chào bạn" || e.doc("agents/an")["dmDayCount"] != int64(10) {
		t.Fatalf("chạy lại sau lỗi: trả %q, dmDayCount %v; muốn \"Chào bạn\", 10", msgs[0]["text"], e.doc("agents/an")["dmDayCount"])
	}
}
