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
	wantList(t, "tool khi chưa học", toolNames(e.llm.calls[0]), "web_search", "remember", "update_memory", "forget", "get_owner_today", "get_owner_recent_run", "get_owner_contracts", "get_club_contracts")

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
	wantList(t, "tool khi đã học", toolNames(e.llm.calls[0]), "web_search", "remember", "update_memory", "forget", "recall_person", "forget_learned", "get_owner_today", "get_owner_recent_run", "get_owner_contracts", "get_club_contracts")
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
	wantList(t, "tool phòng", toolNames(e.llm.calls[0]), "web_search", "recall_person", "get_club_contracts")
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

func TestEmulatorAgentLearnedAPI(t *testing.T) {
	e := newAgentEnv(t)
	seed(t, e.store.db, "telegramLinks/cuong", map[string]any{"tgUserId": int64(333)})
	e.seedLearned("cuong", map[string]string{"f1": "Cường tập full Đà Nẵng"})
	seed(t, e.store.db, "agentRooms/main/learned/tg-333", map[string]any{"facts": []any{
		map[string]any{"id": "f2", "text": "Cường đau gối", "source": "migrated", "updatedAt": e.clock},
	}})
	seed(t, e.store.db, "agentRooms/main/learned/"+agentGroupScope, map[string]any{"facts": []any{
		map[string]any{"id": "f1", "text": "Nhóm chạy 6h thứ 7", "updatedAt": e.clock},
		map[string]any{"id": "f2", "text": "Nhóm hay ăn phở sau chạy", "updatedAt": e.clock},
	}})
	learnedOf := func(r apiResp) []string {
		var out []string
		for _, v := range anyList(r.body["learned"]) {
			m := v.(map[string]any)
			out = append(out, stringValue(m["id"])+" "+stringValue(m["source"])+" "+stringValue(m["text"]))
		}
		return out
	}
	factsOf := func(r apiResp) []string {
		var out []string
		for _, v := range anyList(r.body["facts"]) {
			out = append(out, stringValue(v.(map[string]any)["id"]))
		}
		return out
	}

	// Người ngoài danh sách: không thấy gì, không xoá được.
	if r := e.call("dung", "GET", "/v1/agents/me", nil, ""); r.status != 200 || r.body["learned"] == nil || len(anyList(r.body["learned"])) != 0 {
		t.Fatalf("người ngoài: %d %s", r.status, r.raw)
	}
	e.want(e.call("dung", "DELETE", "/v1/agents/me/learned/f1", nil, ""), 403, "agent_disabled")
	e.want(e.call("dung", "GET", "/v1/agents/group-facts", nil, ""), 403, "agent_disabled")

	// Chưa tạo bot vẫn thấy ký ức về mình, gồm cả doc tg đang liên kết.
	r := e.call("cuong", "GET", "/v1/agents/me", nil, "")
	if r.status != 200 || r.body["learnedLimit"] != float64(agentLearnedLimit) {
		t.Fatalf("me: %d %s", r.status, r.raw)
	}
	wantList(t, "learned", learnedOf(r), "f1 learned Cường tập full Đà Nẵng", "tg-f2 migrated Cường đau gối")
	for i := 0; i < 2; i++ {
		e.want(e.call("cuong", "DELETE", "/v1/agents/me/learned/tg-f2", nil, ""), 200, "")
	}
	wantList(t, "learned sau xoá", learnedOf(e.call("cuong", "GET", "/v1/agents/me", nil, "")), "f1 learned Cường tập full Đà Nẵng")
	if l := e.doc("agentRooms/main/learnLog/forget-tg-333-f2"); l["by"] != "owner:cuong" {
		t.Fatalf("learnLog: %v", l)
	}

	// Ký ức nhóm: thành viên xem được, chỉ admin xoá.
	r = e.call("cuong", "GET", "/v1/agents/group-facts", nil, "")
	if r.status != 200 || r.body["canDelete"] != false {
		t.Fatalf("group-facts thành viên: %d %s", r.status, r.raw)
	}
	wantList(t, "group-facts", factsOf(r), "f1", "f2")
	e.want(e.call("cuong", "DELETE", "/v1/agents/group-facts/f1", nil, ""), 403, "not_admin")
	if r = e.call("an", "GET", "/v1/agents/group-facts", nil, ""); r.body["canDelete"] != true {
		t.Fatalf("group-facts admin: %s", r.raw)
	}
	for i := 0; i < 2; i++ {
		e.want(e.call("an", "DELETE", "/v1/agents/group-facts/f1", nil, ""), 200, "")
	}
	wantList(t, "group-facts sau xoá", factsOf(e.call("an", "GET", "/v1/agents/group-facts", nil, "")), "f2")
	if l := e.doc("agentRooms/main/learnLog/forget-_group-f1"); l["by"] != "admin:an" || l["before"] != "Nhóm chạy 6h thứ 7" {
		t.Fatalf("learnLog nhóm: %v", l)
	}
}

// "Đừng học về tôi": bật thì xoá ký ức đã học và các lượt học sau bỏ tin của
// người đó ở cả phòng bot lẫn Telegram đã liên kết; tắt thì học lại từ tin mới.
func TestEmulatorAgentNoLearn(t *testing.T) {
	e := newAgentEnv(t)
	db := e.store.db
	linkUser(t, e.apiHarness, "an", "111", true)
	e.seedLearned("an", map[string]string{"f1": "An đau gối"})
	e.seedLearned("tg-111", map[string]string{"f1": "An đi giày Pegasus"})
	e.seedLearned("cuong", map[string]string{"f1": "Cường tập full"})
	le := &learnEnv{t: t, db: db, llm: &fakeLearn{reply: addOne}, t0: e.clock}
	le.svc = NewLearnService(e.deps.Agents, le.llm, "-100")
	noLearn := func(uid string) any { return e.call(uid, "GET", "/v1/agents/me", nil, "").body["noLearn"] }

	if v := noLearn("an"); v != false {
		t.Fatalf("chưa bật mà noLearn = %v", v)
	}
	e.want(e.call("an", "POST", "/v1/agents/me/no-learn", map[string]any{}, ""), 400, "invalid_request")
	e.want(e.call("dung", "POST", "/v1/agents/me/no-learn", map[string]any{"on": true}, ""), 403, "agent_disabled")
	for i := 0; i < 2; i++ { // bấm lại sau lần lỗi giữa chừng
		if r := e.call("an", "POST", "/v1/agents/me/no-learn", map[string]any{"on": true}, ""); r.status != 200 || r.body["noLearn"] != true {
			t.Fatalf("bật: %d %s", r.status, r.raw)
		}
	}
	for _, key := range []string{"an", "tg-111"} {
		if doc := e.learned(key); len(doc) != 0 {
			t.Fatalf("bật rồi mà còn ký ức %s: %v", key, doc)
		}
	}
	if len(anyList(e.learned("cuong")["facts"])) != 1 {
		t.Fatal("bật cho An mà mất ký ức của Cường")
	}
	r := e.call("an", "GET", "/v1/agents/me", nil, "")
	if r.body["noLearn"] != true || len(anyList(r.body["learned"])) != 0 {
		t.Fatalf("me sau khi bật: %s", r.raw)
	}

	at := e.clock.Add(-20 * time.Minute)
	le.roomMsg(1, agentKindHuman, "an", "mình chạy hồ Tây", at)
	le.roomMsg(2, agentKindHuman, "binh", "mình đau gối", at.Add(time.Minute))
	le.tgMsg("t1", "user", "111", "An TG", "mình đăng ký VMM", at.Add(2*time.Minute))
	le.tgMsg("t2", "user", "222", "Dũng", "mình đi được", at.Add(3*time.Minute))
	le.mustRun(e.clock)
	wantList(t, "scope được học", le.llm.scopes(), agentGroupScope, "Bình", "Dũng")
	for _, leak := range []string{"hồ Tây", "VMM"} {
		if strings.Contains(le.llm.calls[0].input, leak) {
			t.Errorf("ký ức nhóm vẫn thấy tin của An %q:\n%s", leak, le.llm.calls[0].input)
		}
	}
	for _, key := range []string{"an", "tg-111"} {
		if doc := e.learned(key); len(doc) != 0 {
			t.Fatalf("bật rồi mà vẫn học về An vào %s: %v", key, doc)
		}
	}
	wantList(t, "ký ức Bình", le.factTexts("binh"), "f1 học: Bình: mình đau gối")

	// Tắt: học từ tin mới, ký ức đã xoá và tin lúc đang bật không quay về.
	if r := e.call("an", "POST", "/v1/agents/me/no-learn", map[string]any{"on": false}, ""); r.status != 200 || r.body["noLearn"] != false {
		t.Fatalf("tắt: %d %s", r.status, r.raw)
	}
	if v := noLearn("an"); v != false {
		t.Fatalf("tắt rồi mà noLearn = %v", v)
	}
	le.roomMsg(3, agentKindHuman, "an", "mình đổi sang chạy chủ nhật", e.clock.Add(time.Minute))
	le.mustRun(e.clock.Add(30 * time.Minute))
	wantList(t, "ký ức An sau khi tắt", le.factTexts("an"), "f1 học: An: mình đổi sang chạy chủ nhật")
}

// Xoá tài khoản gỡ uid khỏi danh sách "Đừng học về tôi", người khác giữ nguyên.
func TestEmulatorAccountDeleteRemovesLearnOptOut(t *testing.T) {
	db := emulatorDB(t)
	accounts := &AccountService{db: db}
	if err := accounts.removeLearnOptOut(context.Background(), "an"); err != nil {
		t.Fatalf("chưa ai bật: %v", err)
	}
	seed(t, db, "agentState/learnOptOut", map[string]any{"uids": []any{"an", "binh"}})
	for i := 0; i < 2; i++ {
		if err := accounts.removeLearnOptOut(context.Background(), "an"); err != nil {
			t.Fatal(err)
		}
	}
	optOut, err := learnOptOut(context.Background(), db)
	if err != nil || optOut["an"] || !optOut["binh"] {
		t.Fatalf("sau khi xoá An: %v %v", optOut, err)
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
