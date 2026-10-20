//go:build emulator

package backend

import (
	"context"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

func toolNames(call fakeCall) []string {
	var out []string
	for _, tool := range call.tools {
		for _, d := range tool.FunctionDeclarations {
			out = append(out, d.Name)
		}
	}
	return out
}

func (e *agentEnv) seedLearned(key string, facts map[string]string) {
	e.t.Helper()
	var list []any
	for id, text := range facts {
		list = append(list, map[string]any{"id": id, "text": text, "createdAt": e.clock, "updatedAt": e.clock})
	}
	seed(e.t, e.store.db, "agentRooms/main/learned/"+key, map[string]any{"facts": list})
}

func (e *agentEnv) doc(path string) map[string]any {
	e.t.Helper()
	m, err := docMap(e.store.db.Doc(path).Get(context.Background()))
	if err != nil {
		e.t.Fatalf("đọc %s: %v", path, err)
	}
	return m
}

func (e *agentEnv) learned(key string) map[string]any {
	return e.doc("agentRooms/main/learned/" + key)
}

func TestEmulatorAgentDMLearned(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	dm := func(text string, script ...*genai.GenerateContentResponse) {
		t.Helper()
		e.tick(2 * time.Second)
		e.llm.calls, e.llm.script = nil, script
		e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": text}, ""), 200, "")
		tasks := e.tasksTo("/tasks/agent-dm")
		e.mustRun("/tasks/agent-dm", tasks[len(tasks)-1].Payload)
	}

	// Chưa học được gì: prompt và tool như trước khi có tính năng học.
	dm("chào", llmText("chào chủ"))
	if sys := e.llm.calls[0].system; strings.Contains(sys, "TỰ HỌC") || strings.Contains(sys, "BẠN BIẾT VỀ NHÓM") {
		t.Fatalf("chưa học mà prompt có ký ức tự học:\n%s", sys)
	}
	wantList(t, "tool khi chưa học", toolNames(e.llm.calls[0]), "web_search", "remember", "update_memory", "forget")

	seed(t, e.store.db, "telegramLinks/an", map[string]any{"tgUserId": int64(111)})
	e.seedLearned("an", map[string]string{"f1": "An chạy hồ Tây"})
	e.seedLearned("tg-111", map[string]string{"f2": "An đi giày Pegasus"})
	e.seedLearned(agentGroupScope, map[string]string{"f1": "Nhóm chạy 6h thứ 7"})
	e.seedLearned("binh", map[string]string{"f1": "Bình đau gối"})
	seed(t, e.store.db, "agentRooms/main/learned/an", map[string]any{"facts": []any{
		map[string]any{"id": "f1", "text": "An chạy hồ Tây", "updatedAt": e.clock},
		map[string]any{"id": "f9", "text": "An bỏ giải từ lâu", "updatedAt": e.clock.Add(-100 * 24 * time.Hour)},
	}})

	dm("quên chuyện giày đi, mà Bình dạo này sao", llmCall("forget_learned", map[string]any{"id": "tg-f2"}), llmCall("recall_person", map[string]any{"name": "Bình"}), llmText("quên rồi"))
	sys := e.llm.calls[0].system
	for _, line := range []string{"BẠN TỰ HỌC ĐƯỢC VỀ CHỦ", "[f1] An chạy hồ Tây\n", "[tg-f2] An đi giày Pegasus\n", "BẠN BIẾT VỀ NHÓM", "- Nhóm chạy 6h thứ 7\n", "forget_learned"} {
		if !strings.Contains(sys, line) {
			t.Errorf("prompt chat riêng thiếu %q:\n%s", line, sys)
		}
	}
	for _, leak := range []string{"Bình đau gối", "bỏ giải"} {
		if strings.Contains(sys, leak) {
			t.Errorf("prompt chat riêng có %q", leak)
		}
	}
	wantList(t, "tool khi đã học", toolNames(e.llm.calls[0]), "web_search", "remember", "update_memory", "forget", "recall_person", "forget_learned")
	if r := toolResult(t, e.llm.calls[1]); r["ok"] != true {
		t.Fatalf("forget_learned: %v", r)
	}
	if r := toolResult(t, e.llm.calls[2]); r["ok"] != true || strings.Join(toStrings(r["facts"]), ",") != "Bình đau gối" {
		t.Fatalf("recall_person ở chat riêng: %v", r)
	}
	if facts := anyList(e.learned("tg-111")["facts"]); len(facts) != 0 {
		t.Fatalf("còn ký ức đã quên: %v", facts)
	}
	if l := e.doc("agentRooms/main/learnLog/forget-tg-111-f2"); l["by"] != "owner:an" || l["before"] != "An đi giày Pegasus" || l["op"] != "FORGET" {
		t.Fatalf("learnLog: %v", l)
	}

	// id không có, kể cả id của người khác: báo cho model, không xoá gì.
	dm("quên nốt", llmCall("forget_learned", map[string]any{"id": "f7"}), llmCall("forget_learned", map[string]any{"id": "tg-f2"}), llmText("không thấy"))
	for _, c := range e.llm.calls[1:] {
		if r := toolResult(t, c); r["error"] != errLearnedNotFound.Message {
			t.Fatalf("quên id không có: %v", r)
		}
	}
	if len(anyList(e.learned("binh")["facts"])) != 1 {
		t.Fatal("xoá nhầm ký ức người khác")
	}
}

func TestEmulatorAgentRoomLearned(t *testing.T) {
	e := newAgentEnv(t)
	e.brain.chatID = "-100"
	e.createBot("an", "Sóc", "")
	seed(t, e.store.db, "agentState/config", map[string]any{"memberUids": []any{"cuong", "dung"}})
	e.seedLearned("an", map[string]string{"f1": "An mê trail"})
	e.seedLearned("cuong", map[string]string{"f1": "Cường tập full Đà Nẵng"})
	e.seedLearned("dung", map[string]string{"f1": "Dũng đau gối"})
	e.seedLearned(agentGroupScope, map[string]string{"f1": "Nhóm chạy 6h thứ 7"})
	// Hà chỉ có trên Telegram, chưa liên kết app.
	seed(t, e.store.db, "botConversations/-100/botMessages/m1", map[string]any{"role": "user", "name": "Hà", "tgUserId": "555"})
	e.seedLearned("tg-555", map[string]string{"f1": "Hà mới tập chạy 3km"})

	e.want(e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Dũng với Hà dạo này sao?"}, ""), 200, "")
	e.llm.script = []*genai.GenerateContentResponse{
		llmCall("recall_person", map[string]any{"name": "dũng"}),
		llmCall("recall_person", map[string]any{"name": "Hà"}),
		llmText("Dũng đang đau gối, Hà mới tập 3km."),
	}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	sys := e.llm.calls[0].system
	for _, line := range []string{"BẠN TỰ HỌC ĐƯỢC VỀ CHỦ (", "- An mê trail\n", "- Nhóm chạy 6h thứ 7\n", "BẠN BIẾT VỀ NGƯỜI TRONG ĐOẠN CHAT", "Cường:\n- Cường tập full Đà Nẵng\n", "recall_person"} {
		if !strings.Contains(sys, line) {
			t.Errorf("prompt phòng thiếu %q:\n%s", line, sys)
		}
	}
	// Dũng không có mặt trong đoạn chat: chỉ biết qua recall_person. Chủ đã có
	// mục riêng nên không lặp lại thành "An:".
	if strings.Contains(sys, "Dũng đau gối") || strings.Contains(sys, "An:\n") || strings.Contains(sys, "[f1]") || strings.Contains(sys, "forget_learned") {
		t.Errorf("prompt phòng:\n%s", sys)
	}
	wantList(t, "tool phòng", toolNames(e.llm.calls[0]), "web_search", "recall_person")
	got := []string{}
	for _, c := range e.llm.calls[1:] {
		r := toolResult(t, c)
		got = append(got, strings.TrimSpace(strings.Join([]string{stringValue(r["reason"]), strings.Join(toStrings(r["facts"]), ",")}, " ")))
	}
	wantList(t, "recall_person", got, "Dũng đau gối", "Hà mới tập chạy 3km")

	r, err := e.brain.recallPerson(context.Background(), &genai.FunctionCall{Args: map[string]any{"name": "Linh"}}, e.clock)
	if err != nil || r["ok"] != false || r["reason"] != "không thấy tên trong group Telegram" {
		t.Fatalf("tên lạ: %v %v", r, err)
	}
}

func toStrings(v any) []string {
	switch x := v.(type) {
	case []string:
		return x
	case []any:
		out := make([]string, len(x))
		for i, s := range x {
			out[i] = stringValue(s)
		}
		return out
	}
	return nil
}
