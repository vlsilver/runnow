//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// fakeLearn là model rút ký ức giả: reply quyết câu trả lời theo prompt, mỗi
// lần gọi được ghi lại.
type fakeLearn struct {
	calls []learnCall
	reply func(system, input string) (string, error)
}

type learnCall struct{ system, input string }

func (f *fakeLearn) Learn(_ context.Context, system, input string, _ *genai.Schema) (*genai.GenerateContentResponse, error) {
	f.calls = append(f.calls, learnCall{system, input})
	text, err := f.reply(system, input)
	if err != nil {
		return nil, err
	}
	return llmText(text), nil
}

var learnWho = regexp.MustCompile(`(?m)^NGƯỜI: (.+)$`)

// addOne trả một lệnh ADD chép lại tin cuối: "học: <tên>: <tin>".
func addOne(_, input string) (string, error) {
	lines := strings.Split(strings.TrimSpace(input), "\n")
	last := lines[len(lines)-1]
	out, err := json.Marshal([]learnAction{{Op: "ADD", Text: "học: " + last[strings.Index(last, "] ")+2:]}})
	return string(out), err
}

// who là scope của một lần gọi: "_group" hoặc tên ở dòng NGƯỜI.
func (c learnCall) who() string {
	if c.system == learnGroupPrompt {
		return agentGroupScope
	}
	return learnWho.FindStringSubmatch(c.input)[1]
}

func (f *fakeLearn) scopes() []string {
	var out []string
	for _, c := range f.calls {
		out = append(out, c.who())
	}
	return out
}

type learnEnv struct {
	t   *testing.T
	db  *firestore.Client
	llm *fakeLearn
	svc *LearnService
	t0  time.Time
}

// newLearnEnv dựng phòng bot có tin của người lẫn bot, và group Telegram -100
// có tin của người đã liên kết (111 → cuong), người chưa liên kết (222) và 3i.
func newLearnEnv(t *testing.T) *learnEnv {
	db := emulatorDB(t)
	e := &learnEnv{t: t, db: db, llm: &fakeLearn{reply: addOne}, t0: time.Date(2026, 10, 20, 7, 0, 0, 0, vietnam)}
	e.svc = NewLearnService(NewAgentStore(db), e.llm, "-100")
	for uid, name := range map[string]string{"an": "An", "binh": "Bình", "cuong": "Cường"} {
		seed(t, db, "publicProfiles/"+uid, map[string]any{"displayName": name})
	}
	seed(t, db, "tgLinks/111", map[string]any{"uid": "cuong"})
	e.roomMsg(1, agentKindHuman, "an", "sáng thứ 7 này mình chạy hồ Tây", e.t0)
	e.roomMsg(2, agentKindAgent, "an", "An chạy nhanh nhất Hà Nội", e.t0.Add(time.Minute))
	e.roomMsg(3, agentKindHuman, "binh", "mình đau gối", e.t0.Add(2*time.Minute))
	e.tgMsg("t1", "user", "111", "Cuong TG", "chốt đội tiếp sức\nEcopark", e.t0.Add(3*time.Minute))
	e.tgMsg("t2", "user", "222", "Dũng", "mình đi được", e.t0.Add(4*time.Minute))
	e.tgMsg("t3", "model", "", "", "3i: ok cả nhà", e.t0.Add(5*time.Minute))
	return e
}

func (e *learnEnv) roomMsg(seq int64, kind, uid, text string, at time.Time) {
	seed(e.t, e.db, "agentRooms/main/messages/"+seqDocID(seq), map[string]any{"seq": seq, "kind": kind, "uid": uid, "name": "Sóc", "text": text, "at": at})
	seed(e.t, e.db, "agentRooms/main", map[string]any{"seq": seq})
}

func (e *learnEnv) tgMsg(id, role, tg, name, text string, at time.Time) {
	doc := map[string]any{"role": role, "name": name, "text": text, "createdAt": at}
	if tg != "" {
		doc["tgUserId"] = tg
	}
	seed(e.t, e.db, "botConversations/-100/botMessages/"+id, doc)
}

func (e *learnEnv) run(now time.Time) error {
	e.llm.calls = nil
	return e.svc.Run(context.Background(), now)
}

func (e *learnEnv) mustRun(now time.Time) {
	e.t.Helper()
	if err := e.run(now); err != nil {
		e.t.Fatal(err)
	}
}

func (e *learnEnv) data(path string) map[string]any {
	e.t.Helper()
	doc, err := docMap(e.db.Doc(path).Get(context.Background()))
	if err != nil {
		e.t.Fatal(err)
	}
	return doc
}

func (e *learnEnv) factTexts(scope string) []string {
	var out []string
	for _, f := range liveFacts(e.data("agentRooms/main/learned/" + scope)["facts"], e.t0) {
		out = append(out, f.ID+" "+f.Text)
	}
	return out
}

func wantList(t *testing.T, label string, got []string, want ...string) {
	t.Helper()
	if strings.Join(got, "|") != strings.Join(want, "|") {
		t.Fatalf("%s = %q, muốn %q", label, got, want)
	}
}

func TestEmulatorAgentLearnSourcesAndScopes(t *testing.T) {
	e := newLearnEnv(t)
	now := e.t0.Add(20 * time.Minute)
	// Tin vừa ghi chưa quá agentLearnLag: để lô sau.
	e.tgMsg("t4", "user", "222", "Dũng", "tin vừa gửi", now.Add(-30*time.Second))
	e.mustRun(now)

	wantList(t, "scope được học", e.llm.scopes(), agentGroupScope, "An", "Bình", "Cường", "Dũng")
	group := e.llm.calls[0].input
	for _, line := range []string{
		"[T3 20/10/2026 07:00] An: sáng thứ 7 này mình chạy hồ Tây",
		"[T3 20/10/2026 07:02] Bình: mình đau gối",
		// Người đã liên kết mang tên trong app; tin nhiều dòng gộp thành một dòng.
		"[T3 20/10/2026 07:03] Cường: chốt đội tiếp sức Ecopark",
		"[T3 20/10/2026 07:04] Dũng: mình đi được",
	} {
		if !strings.Contains(group, line+"\n") {
			t.Errorf("ký ức nhóm thiếu dòng %q:\n%s", line, group)
		}
	}
	for _, leak := range []string{"An chạy nhanh nhất", "3i: ok", "tin vừa gửi", "Cuong TG"} {
		if strings.Contains(group, leak) {
			t.Errorf("ký ức nhóm có %q:\n%s", leak, group)
		}
	}
	if !strings.Contains(group, "CÒN TRỐNG: 50\n\nKÝ ỨC ĐÃ CÓ:\n(chưa có)") {
		t.Errorf("thiếu phần ký ức đã có:\n%s", group)
	}
	an := e.llm.calls[1].input
	if !strings.Contains(an, "NGƯỜI: An\n") || !strings.Contains(an, "An: sáng thứ 7") || strings.Contains(an, "Bình") || strings.Contains(an, "nhanh nhất") {
		t.Errorf("ký ức An thấy tin không phải của An:\n%s", an)
	}
	if c := e.llm.calls[3].input; !strings.Contains(c, "Cường: chốt đội") || strings.Contains(c, "Dũng") {
		t.Errorf("ký ức Cường:\n%s", c)
	}
	// Người Telegram chưa liên kết app vẫn có ký ức riêng, theo tg id.
	if d := e.llm.calls[4].input; !strings.Contains(d, "NGƯỜI: Dũng\n") || strings.Contains(d, "Cường") || strings.Contains(d, "An:") {
		t.Errorf("ký ức Dũng:\n%s", d)
	}
	wantList(t, "ký ức nhóm", e.factTexts(agentGroupScope), "f1 học: Dũng: mình đi được")
	wantList(t, "ký ức Cường", e.factTexts("cuong"), "f1 học: Cường: chốt đội tiếp sức Ecopark")
	wantList(t, "ký ức Dũng", e.factTexts("tg-222"), "f1 học: Dũng: mình đi được")
	state := e.data("agentState/learn")
	if state["pending"] != nil {
		t.Fatalf("học xong mà còn pending: %v", state)
	}
	if c := cursorFrom(state["cursor"]); c.RoomSeq != 3 || !c.TgAt.Equal(now.Add(-agentLearnLag)) {
		t.Fatalf("cursor = %+v", c)
	}

	// Không có tin mới: không gọi model.
	e.mustRun(now)
	if len(e.llm.calls) != 0 {
		t.Fatalf("không có tin mới mà vẫn gọi model %d lần", len(e.llm.calls))
	}

	// Lô sau chỉ có tin mới, kèm ký ức đã học.
	e.roomMsg(4, agentKindHuman, "an", "mình đổi sang chạy chủ nhật", now.Add(time.Minute))
	e.mustRun(now.Add(30 * time.Minute))
	wantList(t, "scope lô 2", e.llm.scopes(), agentGroupScope, "An", "Dũng")
	group = e.llm.calls[0].input
	if !strings.Contains(group, "CÒN TRỐNG: 49\n\nKÝ ỨC ĐÃ CÓ:\n[f1] học: Dũng: mình đi được\n") || !strings.Contains(group, "Dũng: tin vừa gửi") || !strings.Contains(group, "An: mình đổi sang") || strings.Contains(group, "hồ Tây") {
		t.Errorf("lô 2 nhóm:\n%s", group)
	}
	if !strings.Contains(e.llm.calls[1].input, "[f1] học: An: sáng thứ 7") {
		t.Errorf("lô 2 An không thấy ký ức cũ:\n%s", e.llm.calls[1].input)
	}
	wantList(t, "ký ức An", e.factTexts("an"), "f1 học: An: sáng thứ 7 này mình chạy hồ Tây", "f2 học: An: mình đổi sang chạy chủ nhật")
}

func TestEmulatorAgentLearnRetryFinishesSameBatch(t *testing.T) {
	e := newLearnEnv(t)
	now := e.t0.Add(20 * time.Minute)
	failed := false
	e.llm.reply = func(system, input string) (string, error) {
		if !failed && strings.Contains(input, "NGƯỜI: Bình") {
			failed = true
			return "", errors.New("vertex 503")
		}
		return addOne(system, input)
	}
	if err := e.run(now); err == nil {
		t.Fatal("model lỗi mà Run không báo lỗi, task sẽ không chạy lại")
	}
	if e.data("agentState/learn")["pending"] == nil {
		t.Fatal("lỗi giữa lô mà mất pending")
	}
	// Tin tới lúc đang chờ chạy lại: không được lọt vào lô đang dở.
	e.roomMsg(4, agentKindHuman, "binh", "gối mình đỡ rồi", now.Add(time.Minute))
	e.mustRun(now.Add(2 * time.Minute))
	wantList(t, "scope lúc chạy lại", e.llm.scopes(), "Bình", "Cường", "Dũng")
	if strings.Contains(e.llm.calls[0].input, "đỡ rồi") {
		t.Fatalf("lô chạy lại lấy cả tin mới:\n%s", e.llm.calls[0].input)
	}
	wantList(t, "ký ức nhóm", e.factTexts(agentGroupScope), "f1 học: Dũng: mình đi được")
	if c := cursorFrom(e.data("agentState/learn")["cursor"]); c.RoomSeq != 3 {
		t.Fatalf("cursor sau lô dở = %+v", c)
	}
	e.mustRun(now.Add(30 * time.Minute))
	wantList(t, "scope lô sau", e.llm.scopes(), agentGroupScope, "Bình")
	wantList(t, "ký ức Bình", e.factTexts("binh"), "f1 học: Bình: mình đau gối", "f2 học: Bình: gối mình đỡ rồi")
}

func TestEmulatorAgentLearnStaleBatchNotApplied(t *testing.T) {
	e := newLearnEnv(t)
	now := e.t0.Add(20 * time.Minute)
	e.mustRun(now)
	done := &learnBatch{ID: stringValue(e.data("agentRooms/main/learned/_group")["batch"])}
	// Task thứ hai của cùng lô tới muộn, sau khi lô đã xong và có lô mới đang dở.
	e.roomMsg(4, agentKindHuman, "an", "tin lô sau", now.Add(time.Minute))
	e.llm.reply = func(string, string) (string, error) { return "", errors.New("vertex 503") }
	if err := e.run(now.Add(30 * time.Minute)); err == nil {
		t.Fatal("muốn lô sau dừng ở pending")
	}
	// Scope lô cũ chưa ghi, nên chỉ còn kiểm pending chặn được.
	if err := e.svc.apply(context.Background(), done, "moi", []learnAction{{Op: "ADD", Text: "ghi từ lô đã xong"}}, now); err != nil {
		t.Fatal(err)
	}
	if doc := e.data("agentRooms/main/learned/moi"); len(doc) != 0 {
		t.Fatalf("lô đã xong vẫn ghi: %v", doc)
	}
}

// Hai task cùng học một lô (Cloud Tasks giao trùng): cả hai qua bước kiểm ở
// learnScope trước khi bên kia ghi, nên apply phải tự chặn lần ghi thứ hai.
func TestEmulatorAgentLearnConcurrentApplyOnce(t *testing.T) {
	e := newLearnEnv(t)
	now := e.t0.Add(20 * time.Minute)
	e.llm.reply = func(string, string) (string, error) { return "", errors.New("vertex 503") }
	if err := e.run(now); err == nil {
		t.Fatal("muốn lô dừng ở pending")
	}
	b := pendingBatch(e.data("agentState/learn"))
	if b == nil {
		t.Fatal("không có pending")
	}
	for _, text := range []string{"lần một", "lần hai"} {
		if err := e.svc.apply(context.Background(), b, agentGroupScope, []learnAction{{Op: "ADD", Text: text}}, now); err != nil {
			t.Fatal(err)
		}
	}
	wantList(t, "ký ức nhóm", e.factTexts(agentGroupScope), "f1 lần một")
}

func TestEmulatorAgentLearnModelUpdateDeleteLogged(t *testing.T) {
	e := newLearnEnv(t)
	now := e.t0.Add(20 * time.Minute)
	seed(t, e.db, "agentRooms/main/learned/_group", map[string]any{"nextId": 2, "facts": []any{
		map[string]any{"id": "f1", "text": "chạy chung 6h thứ 7", "createdAt": e.t0, "updatedAt": e.t0},
		map[string]any{"id": "f2", "text": "đội gồm An, Chi", "createdAt": e.t0, "updatedAt": e.t0},
	}})
	e.llm.reply = func(system, input string) (string, error) {
		if system == learnGroupPrompt {
			return `[{"op":"UPDATE","id":"f1","text":"chạy chung 6h30 thứ 7"},{"op":"DELETE","id":"f2"},{"op":"UPDATE","id":"f7","text":"id bịa"}]`, nil
		}
		return "[]", nil
	}
	e.mustRun(now)
	wantList(t, "ký ức nhóm", e.factTexts(agentGroupScope), "f1 chạy chung 6h30 thứ 7")
	logs, err := e.db.Collection("agentRooms/main/learnLog").OrderBy("op", firestore.Desc).Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, d := range logs {
		m := d.Data()
		got = append(got, fmt.Sprintf("%s %s %s → %s", m["op"], m["factId"], m["before"], m["after"]))
		if !timeValue(m["expiresAt"]).Equal(now.Add(agentLearnedTTL)) {
			t.Errorf("log thiếu expiresAt cho TTL: %v", m)
		}
	}
	wantList(t, "learnLog", got, "UPDATE f1 chạy chung 6h thứ 7 → chạy chung 6h30 thứ 7", "DELETE f2 đội gồm An, Chi → ")
}

func TestEmulatorForgetLearned(t *testing.T) {
	db := emulatorDB(t)
	at := time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)
	fact := func(id, text string) map[string]any {
		return map[string]any{"id": id, "text": text, "createdAt": at, "updatedAt": at}
	}
	for path, doc := range map[string]map[string]any{
		"publicProfiles/an":                   {"displayName": "An"},
		"tgLinks/111":                         {"uid": "an", "displayName": "Ân Link", "username": "an_run"},
		"botConversations/-100/botMessages/x": {"role": "user", "name": "Ân TG", "tgUserId": "111", "text": "hi", "createdAt": at},
		"agentRooms/main/learned/an":          {"facts": []any{fact("f1", "An đau gối")}},
		// Học từ Telegram trước khi liên kết app.
		"agentRooms/main/learned/tg-111": {"facts": []any{fact("f1", "Ân TG đi giày Pegasus")}},
		"agentRooms/main/learned/_group": {"facts": []any{
			fact("f1", "Đội gồm An, Bình"), fact("f2", "Ân TG đổi lịch sang 6h30"), fact("f3", "Anh Tuấn dẫn đoàn"),
			fact("f4", "Ân Link và @an_run hẹn chạy"),
		}},
		"agentRooms/main/learned/binh": {"facts": []any{fact("f1", "Bình hay chạy cùng An")}},
		"agentRooms/main/learnLog/l1":  {"scope": "an", "op": "DELETE", "before": "An bỏ giải"},
		"agentRooms/main/learnLog/l4":  {"scope": "tg-111", "op": "DELETE", "before": "Ân TG bỏ giải"},
		"agentRooms/main/learnLog/l2":  {"scope": "_group", "op": "UPDATE", "before": "An dẫn đoàn", "after": "Ân TG dẫn đoàn"},
		"agentRooms/main/learnLog/l3":  {"scope": "binh", "op": "DELETE", "before": "Bình chạy sáng", "after": ""},
	} {
		seed(t, db, path, doc)
	}
	for i := 0; i < 2; i++ { // xoá tài khoản lỗi giữa chừng thì chạy lại
		if err := forgetLearned(context.Background(), db, "an"); err != nil {
			t.Fatal(err)
		}
	}
	e := &learnEnv{t: t, db: db, t0: at}
	for _, path := range []string{"learned/an", "learned/tg-111", "learnLog/l1", "learnLog/l4"} {
		if len(e.data("agentRooms/main/"+path)) != 0 {
			t.Fatalf("còn %s về người đã xoá", path)
		}
	}
	wantList(t, "ký ức nhóm", e.factTexts(agentGroupScope), "f1 Đội gồm một thành viên, Bình", "f2 một thành viên đổi lịch sang 6h30", "f3 Anh Tuấn dẫn đoàn", "f4 một thành viên và @một thành viên hẹn chạy")
	wantList(t, "ký ức Bình", e.factTexts("binh"), "f1 Bình hay chạy cùng một thành viên")
	if l := e.data("agentRooms/main/learnLog/l2"); l["before"] != "một thành viên dẫn đoàn" || l["after"] != "một thành viên dẫn đoàn" {
		t.Fatalf("log nhóm còn tên: %v", l)
	}
	if l := e.data("agentRooms/main/learnLog/l3"); l["before"] != "Bình chạy sáng" {
		t.Fatalf("log người khác bị sửa: %v", l)
	}
}

func TestEmulatorAgentLearnTaskRoute(t *testing.T) {
	db := emulatorDB(t)
	var tasks []PublishTask
	publish := func(_ context.Context, p PublishTask) (string, error) {
		tasks = append(tasks, p)
		return "created", nil
	}
	now := time.Date(2026, 10, 20, 7, 0, 0, 0, vietnam)
	deps := &Dependencies{Firestore: db, EnqueueTask: publish, Now: func() time.Time { return now }}
	bot := NewBotServer(Config{}, deps)
	post := func(path string) int {
		rec := httptest.NewRecorder()
		bot.ServeHTTP(rec, httptest.NewRequest("POST", path, strings.NewReader("{}")))
		return rec.Code
	}
	// Cờ tắt: tick không hẹn, task còn sót trong queue thì 204 cho thôi chạy lại.
	if code := post("/tasks/schedule-tick"); code != 200 || len(tasks) != 0 {
		t.Fatalf("cờ tắt: tick %d, tasks %+v", code, tasks)
	}
	if code := post("/tasks/agent-learn"); code != 204 {
		t.Fatalf("cờ tắt: agent-learn %d", code)
	}
	deps.Learn = NewLearnService(NewAgentStore(db), &fakeLearn{reply: addOne}, "")
	if code := post("/tasks/schedule-tick"); code != 200 || len(tasks) != 1 || tasks[0].TaskID != agentLearnTaskFor(now).TaskID {
		t.Fatalf("cờ bật: tick %d, tasks %+v", code, tasks)
	}
	if code := post("/tasks/agent-learn"); code != 200 {
		t.Fatalf("cờ bật: agent-learn %d", code)
	}
}

// Lần bật đầu học lại cả lịch sử: mỗi lô tối đa agentLearnMaxMsgs tin mỗi
// nguồn, phần còn lại để lô sau.
func TestEmulatorAgentLearnBacklogInChunks(t *testing.T) {
	db := emulatorDB(t)
	llm := &fakeLearn{reply: func(string, string) (string, error) { return "[]", nil }}
	svc := NewLearnService(NewAgentStore(db), llm, "-100")
	seed(t, db, "publicProfiles/an", map[string]any{"displayName": "An"})
	t0 := time.Date(2026, 10, 1, 7, 0, 0, 0, vietnam)
	bw := db.BulkWriter(context.Background())
	n := agentLearnMaxMsgs + 1
	for i := 1; i <= n; i++ {
		at := t0.Add(time.Duration(i) * time.Minute)
		if _, err := bw.Set(db.Doc("agentRooms/main/messages/"+seqDocID(int64(i))), map[string]any{"seq": i, "kind": agentKindHuman, "uid": "an", "text": fmt.Sprintf("phòng %d", i), "at": at}); err != nil {
			t.Fatal(err)
		}
		if _, err := bw.Set(db.Doc(fmt.Sprintf("botConversations/-100/botMessages/m%03d", i)), map[string]any{"role": "user", "name": "Dũng", "text": fmt.Sprintf("tg %d", i), "createdAt": at}); err != nil {
			t.Fatal(err)
		}
	}
	bw.End()
	seed(t, db, "agentRooms/main", map[string]any{"seq": n})
	now := t0.Add(24 * time.Hour)
	count := func(input, prefix string) int { return strings.Count(input, ": "+prefix+" ") }
	for i, want := range []int{agentLearnMaxMsgs, 1} {
		llm.calls = nil
		if err := svc.Run(context.Background(), now); err != nil {
			t.Fatal(err)
		}
		group := llm.calls[0].input
		if count(group, "phòng") != want || count(group, "tg") != want {
			t.Fatalf("lô %d: %d tin phòng, %d tin tg, muốn %d mỗi loại", i+1, count(group, "phòng"), count(group, "tg"), want)
		}
	}
	llm.calls = nil
	if err := svc.Run(context.Background(), now); err != nil || len(llm.calls) != 0 {
		t.Fatalf("hết tồn mà vẫn học: %v, %d lần gọi", err, len(llm.calls))
	}
}
