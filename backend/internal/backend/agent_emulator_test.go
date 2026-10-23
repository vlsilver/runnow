//go:build emulator

package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// fakeLLM trả lần lượt các câu trong script và ghi lại mỗi lần gọi. onCall
// chạy trước khi trả, để test chen tin vào lúc "model đang viết". Search trả
// searchResp hoặc searchErr và ghi lại query.
type fakeLLM struct {
	script     []*genai.GenerateContentResponse
	err        error
	calls      []fakeCall
	onCall     func()
	searchResp *genai.GenerateContentResponse
	searchErr  error
	searches   []string
}

type fakeCall struct {
	system   string
	contents []*genai.Content
	tools    []*genai.Tool
}

func (f *fakeLLM) Generate(_ context.Context, system string, contents []*genai.Content, tools []*genai.Tool) (*genai.GenerateContentResponse, error) {
	f.calls = append(f.calls, fakeCall{system: system, contents: contents, tools: tools})
	if f.onCall != nil {
		f.onCall()
	}
	if f.err != nil {
		return nil, f.err
	}
	if len(f.script) == 0 {
		return nil, errors.New("fakeLLM: hết script")
	}
	resp := f.script[0]
	f.script = f.script[1:]
	return resp, nil
}

func (f *fakeLLM) Search(_ context.Context, query string) (*genai.GenerateContentResponse, error) {
	f.searches = append(f.searches, query)
	return f.searchResp, f.searchErr
}

// grounded là câu trả lời Google Search kèm nguồn, như Vertex trả.
func grounded(text string, titles ...string) *genai.GenerateContentResponse {
	resp := llmText(text)
	gm := &genai.GroundingMetadata{}
	for _, t := range titles {
		gm.GroundingChunks = append(gm.GroundingChunks, &genai.GroundingChunk{Web: &genai.GroundingChunkWeb{Title: t}})
	}
	resp.Candidates[0].GroundingMetadata = gm
	return resp
}

// toolResult là kết quả tool cuối cùng gửi lại model trong lần gọi call.
func toolResult(t *testing.T, call fakeCall) map[string]any {
	t.Helper()
	last := call.contents[len(call.contents)-1]
	if len(last.Parts) == 0 || last.Parts[0].FunctionResponse == nil {
		t.Fatalf("lần gọi model không kèm kết quả tool: %+v", last)
	}
	return last.Parts[0].FunctionResponse.Response
}

func llmText(text string) *genai.GenerateContentResponse {
	return &genai.GenerateContentResponse{Candidates: []*genai.Candidate{{Content: &genai.Content{Role: genai.RoleModel, Parts: []*genai.Part{{Text: text}}}}}}
}

func llmCall(name string, args map[string]any) *genai.GenerateContentResponse {
	return &genai.GenerateContentResponse{Candidates: []*genai.Candidate{{Content: &genai.Content{Role: genai.RoleModel, Parts: []*genai.Part{{FunctionCall: &genai.FunctionCall{Name: name, Args: args}}}}}}}
}

// agentEnv là api thật (qua apiHarness) cộng bot service thật, chung một đồng
// hồ giả và một Cloud Tasks giả.
type agentEnv struct {
	*apiHarness
	llm   *fakeLLM
	brain *AgentService
	bot   http.Handler
	clock time.Time
	tasks []PublishTask
}

var agentClock = time.Date(2026, 10, 20, 8, 0, 0, 0, vietnam)

func newAgentEnv(t *testing.T) *agentEnv {
	t.Helper()
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	e := &agentEnv{apiHarness: h, llm: &fakeLLM{}, clock: agentClock}
	store := NewAgentStore(db)
	now := func() time.Time { return e.clock }
	h.deps.Agents, h.deps.EnqueueTask, h.deps.Now = store, e.publish, now
	e.brain = NewAgentService(store, e.llm, e.publish)
	e.bot = NewBotServer(Config{}, &Dependencies{
		Firestore: db, Agents: store, AgentBrain: e.brain, EnqueueTask: e.publish, Now: now,
	})
	seed(t, db, "gameState/config", map[string]any{"adminUids": []any{"an", "binh"}})
	seed(t, db, "agentState/config", map[string]any{"memberUids": []any{"cuong"}})
	for uid, name := range map[string]string{"an": "An", "binh": "Bình", "cuong": "Cường", "dung": "Dũng"} {
		seed(t, db, "publicProfiles/"+uid, map[string]any{"displayName": name})
	}
	return e
}

func (e *agentEnv) publish(_ context.Context, p PublishTask) (string, error) {
	e.tasks = append(e.tasks, p)
	return "created", nil
}

func (e *agentEnv) tasksTo(path string) []PublishTask {
	var out []PublishTask
	for _, t := range e.tasks {
		if t.HandlerPath == path {
			out = append(out, t)
		}
	}
	return out
}

func (e *agentEnv) tick(d time.Duration) { e.clock = e.clock.Add(d) }

// runTask gọi handler task trên bot service, trả status.
func (e *agentEnv) runTask(path string, payload any) int {
	e.t.Helper()
	body, _ := json.Marshal(payload)
	rec := httptest.NewRecorder()
	e.bot.ServeHTTP(rec, httptest.NewRequest("POST", path, bytes.NewReader(body)))
	return rec.Code
}

func (e *agentEnv) mustRun(path string, payload any) {
	e.t.Helper()
	if code := e.runTask(path, payload); code != 200 {
		e.t.Fatalf("%s %v: status %d", path, payload, code)
	}
}

func (e *agentEnv) createBot(uid, name, persona string) {
	e.t.Helper()
	e.want(e.call(uid, "POST", "/v1/agents/me", map[string]any{"name": name, "persona": persona}, ""), 200, "")
}

func messages(t *testing.T, r apiResp) []map[string]any {
	t.Helper()
	var out []map[string]any
	for _, m := range anyList(r.body["messages"]) {
		out = append(out, m.(map[string]any))
	}
	return out
}

func TestEmulatorAgentProfileAndMemory(t *testing.T) {
	e := newAgentEnv(t)

	// Người ngoài danh sách: GET báo tắt, ghi thì 403.
	if r := e.call("dung", "GET", "/v1/agents/me", nil, ""); r.status != 200 || r.body["enabled"] != false || r.body["agent"] != nil {
		t.Fatalf("người ngoài: %d %s", r.status, r.raw)
	}
	e.want(e.call("dung", "POST", "/v1/agents/me", map[string]any{"name": "X"}, ""), 403, "agent_disabled")
	e.want(e.call("dung", "GET", "/v1/agents/room", nil, ""), 403, "agent_disabled")

	// Thành viên qua agentState/config, chưa tạo bot: tên mặc định theo tên chủ.
	r := e.call("cuong", "GET", "/v1/agents/me", nil, "")
	agent, _ := r.body["agent"].(map[string]any)
	if r.body["enabled"] != true || agent["name"] != "Bot của Cường" || agent["created"] != false || r.body["memoryLimit"] != float64(50) {
		t.Fatalf("chưa tạo bot: %s", r.raw)
	}
	e.want(e.call("cuong", "POST", "/v1/agents/me/memories", map[string]any{"text": "a"}, ""), 404, "agent_not_found")
	e.want(e.call("cuong", "POST", "/v1/agents/me/dm", map[string]any{"text": "a"}, ""), 404, "agent_not_found")

	e.want(e.call("cuong", "POST", "/v1/agents/me", map[string]any{"name": "  "}, ""), 400, "invalid_name")
	e.want(e.call("cuong", "POST", "/v1/agents/me", map[string]any{"name": strings.Repeat("á", 41)}, ""), 400, "invalid_name")
	e.want(e.call("cuong", "POST", "/v1/agents/me", map[string]any{"name": "Cú", "persona": strings.Repeat("a", 1501)}, ""), 400, "invalid_persona")
	e.want(e.call("cuong", "POST", "/v1/agents/me", map[string]any{"name": "Cú", "extra": 1}, ""), 400, "")
	e.createBot("cuong", " Cú ", "Hay đùa")
	r = e.call("cuong", "GET", "/v1/agents/me", nil, "")
	agent, _ = r.body["agent"].(map[string]any)
	if agent["name"] != "Cú" || agent["persona"] != "Hay đùa" || agent["created"] != true {
		t.Fatalf("sau khi tạo: %s", r.raw)
	}

	// Thêm, sửa, xoá mục nhớ; xoá lần hai vẫn 200, sửa mục đã xoá thì 404.
	e.want(e.call("cuong", "POST", "/v1/agents/me/memories", map[string]any{"text": " "}, ""), 400, "invalid_memory")
	r = e.call("cuong", "POST", "/v1/agents/me/memories", map[string]any{"text": "Thích chạy đêm"}, "")
	e.want(r, 200, "")
	id, _ := r.body["id"].(string)
	if id == "" || r.body["source"] != agentSourceManual {
		t.Fatalf("thêm mục nhớ: %s", r.raw)
	}
	e.tick(time.Second)
	e.want(e.call("cuong", "POST", "/v1/agents/me/memories", map[string]any{"text": "Ghét mưa"}, ""), 200, "")
	e.want(e.call("cuong", "POST", "/v1/agents/me/memories/"+id, map[string]any{"text": "Thích chạy sáng"}, ""), 200, "")
	r = e.call("cuong", "GET", "/v1/agents/me", nil, "")
	mems := anyList(r.body["memories"])
	if len(mems) != 2 || mems[0].(map[string]any)["text"] != "Thích chạy sáng" || mems[1].(map[string]any)["text"] != "Ghét mưa" {
		t.Fatalf("bộ nhớ phải theo thứ tự thêm, mục đầu đã sửa: %s", r.raw)
	}
	e.want(e.call("cuong", "DELETE", "/v1/agents/me/memories/"+id, nil, ""), 200, "")
	e.want(e.call("cuong", "DELETE", "/v1/agents/me/memories/"+id, nil, ""), 200, "")
	e.want(e.call("cuong", "POST", "/v1/agents/me/memories/"+id, map[string]any{"text": "x"}, ""), 404, "memory_not_found")

	// Đủ 50 mục thì 409; sửa mục đang có vẫn được.
	for i := 0; i < agentMemoryLimit-1; i++ {
		seed(t, e.store.db, fmt.Sprintf("agents/cuong/memories/m%02d", i), map[string]any{"text": "x", "source": "manual", "createdAt": agentClock, "updatedAt": agentClock})
	}
	e.want(e.call("cuong", "POST", "/v1/agents/me/memories", map[string]any{"text": "thêm nữa"}, ""), 409, "memory_full")
	e.want(e.call("cuong", "POST", "/v1/agents/me/memories/m00", map[string]any{"text": "sửa"}, ""), 200, "")
}

func TestEmulatorAgentDM(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "Lắm mồm")

	e.llm.script = []*genai.GenerateContentResponse{
		llmCall("remember", map[string]any{"text": "Chủ chạy 5 km mỗi sáng"}),
		llmText("Ok, mình nhớ rồi nhé."),
	}
	r := e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "Mình chạy 5 km mỗi sáng"}, "")
	e.want(r, 200, "")
	if r.body["seq"] != float64(1) || r.body["role"] != agentRoleUser {
		t.Fatalf("gửi tin: %s", r.raw)
	}
	dmTasks := e.tasksTo("/tasks/agent-dm")
	if len(dmTasks) != 1 || dmTasks[0].Queue != QueueBotInbound || dmTasks[0].TaskID != StableTaskID("agent-dm", []any{"an", int64(1)}) {
		t.Fatalf("task agent-dm: %+v", dmTasks)
	}
	if r = e.call("an", "GET", "/v1/agents/me/dm", nil, ""); r.body["waiting"] != true || len(messages(t, r)) != 1 {
		t.Fatalf("trước khi bot trả lời: %s", r.raw)
	}

	e.mustRun("/tasks/agent-dm", dmTasks[0].Payload)
	if len(e.llm.calls) != 2 || !strings.Contains(e.llm.calls[0].system, "Sóc") || !strings.Contains(e.llm.calls[0].system, "Lắm mồm") {
		t.Fatalf("lần gọi model: %d", len(e.llm.calls))
	}
	r = e.call("an", "GET", "/v1/agents/me/dm", nil, "")
	msgs := messages(t, r)
	if r.body["waiting"] != false || len(msgs) != 2 || msgs[0]["seq"] != float64(2) || msgs[0]["role"] != agentRoleAgent || msgs[0]["text"] != "Ok, mình nhớ rồi nhé." {
		t.Fatalf("sau khi bot trả lời (mới trước): %s", r.raw)
	}
	r = e.call("an", "GET", "/v1/agents/me", nil, "")
	mems := anyList(r.body["memories"])
	if len(mems) != 1 || mems[0].(map[string]any)["id"] != "dm1-1" || mems[0].(map[string]any)["source"] != agentSourceChat {
		t.Fatalf("tool remember: %s", r.raw)
	}

	// Task chạy lại: không gọi model, không thêm tin.
	e.mustRun("/tasks/agent-dm", dmTasks[0].Payload)
	if len(e.llm.calls) != 2 || len(messages(t, e.call("an", "GET", "/v1/agents/me/dm", nil, ""))) != 2 {
		t.Fatal("task chạy lại mà vẫn gọi model hoặc ghi thêm tin")
	}

	// Gửi dồn trong 1 giây thì 429.
	e.tick(time.Second)
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "a"}, ""), 200, "")
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "b"}, ""), 429, "too_fast")

	// Hai tin liên tiếp: task tin cũ bỏ, task tin mới trả lời gộp cả hai.
	e.tick(time.Second)
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "Quên chuyện 5 km đi"}, ""), 200, "")
	e.tick(time.Second)
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "Giờ mình chạy tối"}, ""), 200, "")
	dmTasks = e.tasksTo("/tasks/agent-dm")
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 4})
	if len(e.llm.calls) != 2 {
		t.Fatal("tin đã có tin mới hơn mà vẫn gọi model")
	}
	e.llm.script = []*genai.GenerateContentResponse{
		llmCall("forget", map[string]any{"id": "dm1-1"}),
		llmCall("remember", map[string]any{"text": "Chủ chạy buổi tối"}),
		llmText("Đã quên chuyện sáng, nhớ là bạn chạy tối."),
	}
	e.mustRun("/tasks/agent-dm", dmTasks[len(dmTasks)-1].Payload)
	last := e.llm.calls[2].contents
	if len(last) != 5 || last[0].Role != genai.RoleUser || last[1].Role != genai.RoleModel || last[4].Parts[0].Text != "Giờ mình chạy tối" {
		t.Fatalf("lịch sử gửi model phải đủ 5 tin cũ trước, lượt đầu là user: %d", len(last))
	}
	r = e.call("an", "GET", "/v1/agents/me", nil, "")
	mems = anyList(r.body["memories"])
	if len(mems) != 1 || mems[0].(map[string]any)["id"] != "dm5-1" || mems[0].(map[string]any)["text"] != "Chủ chạy buổi tối" {
		t.Fatalf("forget rồi remember: %s", r.raw)
	}

	// Model lỗi: task 5xx để chạy lại, tin vẫn chờ.
	e.tick(time.Second)
	e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "còn đó không"}, "")
	e.llm.err = errors.New("vertex 503")
	if code := e.runTask("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 7}); code < 500 {
		t.Fatalf("model lỗi mà task trả %d", code)
	}
	if r = e.call("an", "GET", "/v1/agents/me/dm", nil, ""); r.body["waiting"] != true {
		t.Fatalf("model lỗi mà không còn chờ: %s", r.raw)
	}

	// Hết lượt chat riêng hôm nay: tin mới nhận câu nghỉ, không gọi model.
	e.llm.err = nil
	calls := len(e.llm.calls)
	if _, err := e.store.db.Doc("agents/an").Update(context.Background(), []firestore.Update{{Path: "dmDay", Value: vnDay(e.clock)}, {Path: "dmDayCount", Value: agentDMBaseDaily}}); err != nil {
		t.Fatal(err)
	}
	e.tick(time.Second)
	e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "còn đó không?"}, "")
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "an", Seq: 8})
	msgs = messages(t, e.call("an", "GET", "/v1/agents/me/dm", nil, ""))
	if len(e.llm.calls) != calls || msgs[0]["text"] != noRunDMLimitReply {
		t.Fatalf("hết lượt chat riêng: %v", msgs[0])
	}

	// Cửa sổ 20 tin cắt trúng tin bot: bỏ tin đó để lượt đầu gửi model là user.
	e.createBot("binh", "Mèo", "")
	for seq := int64(1); seq <= 21; seq++ {
		role := agentRoleAgent
		if seq%2 == 1 {
			role = agentRoleUser
		}
		seed(t, e.store.db, "agents/binh/dm/"+seqDocID(seq), map[string]any{"seq": seq, "role": role, "text": fmt.Sprint("tin ", seq), "channel": "app", "at": e.clock})
	}
	if _, err := e.store.db.Doc("agents/binh").Update(context.Background(), []firestore.Update{{Path: "dmSeq", Value: 21}, {Path: "dmUserSeq", Value: 21}, {Path: "answeredSeq", Value: 20}}); err != nil {
		t.Fatal(err)
	}
	e.llm.script = []*genai.GenerateContentResponse{llmText("ok")}
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "binh", Seq: 21})
	sent := e.llm.calls[len(e.llm.calls)-1].contents
	if len(sent) != agentDMHistory-1 || sent[0].Role != genai.RoleUser || sent[0].Parts[0].Text != "tin 3" {
		t.Fatalf("lịch sử phải bỏ tin bot ở đầu cửa sổ: %d tin", len(sent))
	}

	// Tra web: kết quả grounded và nguồn về lại model, model trả lời bằng chữ.
	e.tick(time.Second)
	e.want(e.call("binh", "POST", "/v1/agents/me/dm", map[string]any{"text": "VnExpress Marathon Hà Nội ngày nào?"}, ""), 200, "")
	e.llm.searchResp = grounded("Ngày 29/11/2026.", "vnexpress.net", "vnexpress.net", "bestmarathon.vn")
	e.llm.script = []*genai.GenerateContentResponse{
		llmCall("web_search", map[string]any{"query": "VnExpress Marathon Hà Nội 2026 ngày"}),
		llmText("29/11 nha, theo vnexpress.net."),
	}
	calls = len(e.llm.calls)
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "binh", Seq: 23})
	out := toolResult(t, e.llm.calls[calls+1])
	if len(e.llm.searches) != 1 || e.llm.searches[0] != "VnExpress Marathon Hà Nội 2026 ngày" || out["ok"] != true || out["answer"] != "Ngày 29/11/2026." || fmt.Sprint(out["sources"]) != "[vnexpress.net bestmarathon.vn]" {
		t.Fatalf("web_search: query %v, kết quả %v", e.llm.searches, out)
	}
	if msgs = messages(t, e.call("binh", "GET", "/v1/agents/me/dm", nil, "")); msgs[0]["text"] != "29/11 nha, theo vnexpress.net." {
		t.Fatalf("trả lời sau khi tra: %v", msgs[0])
	}

	// Tra hỏng: model được báo để xin lỗi, task vẫn xong, không chạy lại.
	e.tick(time.Second)
	e.want(e.call("binh", "POST", "/v1/agents/me/dm", map[string]any{"text": "Mai mưa không?"}, ""), 200, "")
	e.llm.searchResp, e.llm.searchErr = nil, errors.New("grounding 503")
	e.llm.script = []*genai.GenerateContentResponse{
		llmCall("web_search", map[string]any{"query": "thời tiết Hà Nội"}),
		llmText("Mình tra không được, lát hỏi lại nhé."),
	}
	calls = len(e.llm.calls)
	e.mustRun("/tasks/agent-dm", agentDMTask{UID: "binh", Seq: 25})
	if out = toolResult(t, e.llm.calls[calls+1]); out["ok"] != false || out["reason"] == nil {
		t.Fatalf("tra hỏng phải báo model: %v", out)
	}
	e.llm.searchErr = nil

	// Payload hỏng: 204 cho task thôi chạy lại.
	if code := e.runTask("/tasks/agent-dm", map[string]any{"uid": "an"}); code != 204 {
		t.Fatalf("payload hỏng: %d", code)
	}
}

func roomTurnTasks(e *agentEnv) []PublishTask { return e.tasksTo("/tasks/agent-turn") }

func lastTurn(t *testing.T, e *agentEnv) agentTurnTask {
	t.Helper()
	tasks := roomTurnTasks(e)
	if len(tasks) == 0 {
		t.Fatal("không có task agent-turn")
	}
	return tasks[len(tasks)-1].Payload.(agentTurnTask)
}

func TestEmulatorAgentRoom(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "Lắm mồm")
	e.createBot("binh", "Mèo", "Ít nói")
	e.createBot("cuong", "Cú", "")
	e.want(e.call("an", "POST", "/v1/agents/me/memories", map[string]any{"text": "Chủ mê trail"}, ""), 200, "")
	// Dũng vào danh sách nhưng chưa tạo bot.
	seed(t, e.store.db, "agentState/config", map[string]any{"memberUids": []any{"cuong", "dung"}})

	r := e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Chào cả nhà"}, "")
	e.want(r, 200, "")
	turns := roomTurnTasks(e)
	if r.body["seq"] != float64(1) || len(turns) != 1 || turns[0].Payload.(agentTurnTask).AfterSeq != 1 || !turns[0].ScheduleTime.Equal(e.clock.Add(agentFirstTurnDelay)) {
		t.Fatalf("tin người phải hẹn lượt bot sau 3s: %s %+v", r.raw, turns)
	}

	// Lượt 1: chưa bot nào nói, hoà thì theo uid nên Sóc (an) nói trước.
	e.llm.script = []*genai.GenerateContentResponse{llmText("Sóc (bot của An): Chào Cường!")}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	sys := e.llm.calls[0].system
	if !strings.Contains(sys, `"Sóc"`) || !strings.Contains(sys, "Chủ mê trail") || !strings.Contains(sys, "Mèo (bot của Bình)") || !strings.Contains(sys, "Cường (người)") {
		t.Fatalf("prompt phòng thiếu persona, bộ nhớ hoặc danh sách: %s", sys)
	}
	if next := lastTurn(t, e); next.AfterSeq != 2 || len(roomTurnTasks(e)) != 2 {
		t.Fatalf("lượt kế: %+v", roomTurnTasks(e))
	}

	// Chạy lại lượt 1: không gọi model, không ghi, chỉ hẹn lại lượt 2 (cùng TaskID).
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1})
	turns = roomTurnTasks(e)
	if len(e.llm.calls) != 1 || len(turns) != 3 || turns[2].TaskID != turns[1].TaskID {
		t.Fatalf("chạy lại lượt 1: calls %d, tasks %+v", len(e.llm.calls), turns)
	}

	// Lượt 2: không cho Sóc nói hai tin liền, nên tới Mèo.
	e.llm.script = []*genai.GenerateContentResponse{llmText("Hello Cường, Sóc ơi chạy không?")}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 2})
	// Lượt 3: Cú lâu chưa nói nhất, nhưng Mèo gọi tên Sóc nên Sóc đi trước.
	e.llm.script = []*genai.GenerateContentResponse{llmText("Chạy chứ!")}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 3})

	r = e.call("binh", "GET", "/v1/agents/room", nil, "")
	msgs := messages(t, r)
	if len(msgs) != 4 {
		t.Fatalf("phòng phải có 4 tin: %s", r.raw)
	}
	want := []struct{ uid, kind, name, owner, text string }{
		{"an", agentKindAgent, "Sóc", "An", "Chạy chứ!"},
		{"binh", agentKindAgent, "Mèo", "Bình", "Hello Cường, Sóc ơi chạy không?"},
		{"an", agentKindAgent, "Sóc", "An", "Chào Cường!"},
		{"cuong", agentKindHuman, "Cường", "", "Chào cả nhà"},
	}
	for i, w := range want {
		m := msgs[i]
		owner, _ := m["owner"].(string)
		if m["uid"] != w.uid || m["kind"] != w.kind || m["name"] != w.name || owner != w.owner || m["text"] != w.text {
			t.Fatalf("tin %d: %v, mong đợi %+v", i, m, w)
		}
	}
	members := anyList(r.body["members"])
	if len(members) != 4 || members[3].(map[string]any)["uid"] != "dung" || members[3].(map[string]any)["botName"] != nil || members[0].(map[string]any)["botName"] != "Sóc" {
		t.Fatalf("danh sách thành viên: %v", members)
	}
	if r = e.call("binh", "GET", "/v1/agents/room?after=4", nil, ""); len(messages(t, r)) != 0 || r.body["hasNewer"] != false {
		t.Fatalf("poll không có tin mới: %s", r.raw)
	}

	// Chuỗi bot dừng ở 6 tin sau tin người, không hẹn thêm.
	for seq := int64(4); seq < 1+agentChainMax; seq++ {
		e.llm.script = []*genai.GenerateContentResponse{llmText(fmt.Sprintf("tin %d", seq))}
		e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: seq})
	}
	if next := lastTurn(t, e); next.AfterSeq != agentChainMax {
		t.Fatalf("task cuối phải là lượt sau tin %d: %+v", agentChainMax, next)
	}
	calls := len(e.llm.calls)
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: 1 + agentChainMax})
	if len(e.llm.calls) != calls || lastTurn(t, e).AfterSeq != agentChainMax {
		t.Fatal("chuỗi đã đủ 6 tin mà bot vẫn nói hoặc vẫn hẹn lượt")
	}

	// Người nói tiếp thì chuỗi mới bắt đầu; bot nhường lượt thì dừng chuỗi.
	e.tick(time.Second)
	e.want(e.call("an", "POST", "/v1/agents/room", map[string]any{"text": "Thôi ngủ"}, ""), 200, "")
	e.want(e.call("an", "POST", "/v1/agents/room", map[string]any{"text": "nữa"}, ""), 429, "too_fast")
	seq := lastTurn(t, e).AfterSeq
	e.llm.script = []*genai.GenerateContentResponse{llmText("[PASS]")}
	tasks := len(roomTurnTasks(e))
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: seq})
	if len(roomTurnTasks(e)) != tasks || len(messages(t, e.call("an", "GET", "/v1/agents/room?after="+fmt.Sprint(seq), nil, ""))) != 0 {
		t.Fatal("[PASS] mà vẫn ghi tin hoặc hẹn lượt")
	}

	// Có người hỏi thông tin thực tế: bot tra web rồi mới nói.
	e.tick(time.Second)
	e.want(e.call("binh", "POST", "/v1/agents/room", map[string]any{"text": "Vòng hồ Tây bao nhiêu km nhỉ?"}, ""), 200, "")
	seq = lastTurn(t, e).AfterSeq
	e.llm.searchResp = grounded("Khoảng 17 km.", "vinpearl.com")
	e.llm.script = []*genai.GenerateContentResponse{
		llmCall("web_search", map[string]any{"query": "chu vi hồ Tây"}),
		llmText("Khoảng 17 km đó Bình."),
	}
	calls = len(e.llm.calls)
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: seq})
	if out := toolResult(t, e.llm.calls[calls+1]); len(e.llm.searches) != 1 || out["answer"] != "Khoảng 17 km." {
		t.Fatalf("web_search trong phòng: %v %v", e.llm.searches, out)
	}
	if msgs = messages(t, e.call("an", "GET", "/v1/agents/room?after="+fmt.Sprint(seq), nil, "")); len(msgs) != 1 || msgs[0]["text"] != "Khoảng 17 km đó Bình." {
		t.Fatalf("tin bot sau khi tra: %v", msgs)
	}

	// Người chen vào lúc model đang viết: tin bot bỏ, không hẹn lượt từ tin cũ.
	e.tick(time.Second)
	e.want(e.call("binh", "POST", "/v1/agents/room", map[string]any{"text": "Mai chạy nhé"}, ""), 200, "")
	seq = lastTurn(t, e).AfterSeq
	e.llm.script = []*genai.GenerateContentResponse{llmText("Ok!")}
	e.llm.onCall = func() {
		e.tick(time.Second)
		e.call("cuong", "POST", "/v1/agents/room", map[string]any{"text": "Mấy giờ?"}, "")
	}
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: seq})
	e.llm.onCall = nil
	msgs = messages(t, e.call("an", "GET", "/v1/agents/room?after="+fmt.Sprint(seq), nil, ""))
	if len(msgs) != 1 || msgs[0]["text"] != "Mấy giờ?" {
		t.Fatalf("có người chen vào mà tin bot vẫn ghi: %v", msgs)
	}
	if lastTurn(t, e).AfterSeq != seq+1 {
		t.Fatalf("lượt kế phải theo tin của Cường: %+v", lastTurn(t, e))
	}

	// Hết ngân sách ngày: bot không nói nữa.
	if _, err := e.store.db.Doc("agentRooms/main").Update(context.Background(), []firestore.Update{{Path: "day", Value: vnDay(e.clock)}, {Path: "dayCount", Value: agentRoomDailyMax}}); err != nil {
		t.Fatal(err)
	}
	calls = len(e.llm.calls)
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: seq + 1})
	if len(e.llm.calls) != calls {
		t.Fatal("hết ngân sách mà vẫn gọi model")
	}
}
