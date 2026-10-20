//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// fake3i là một server đóng cả Gemini API lẫn Telegram Bot API cho BotService
// thật: ghi lại request gửi model và tin gửi Telegram, trả lời model theo script.
type fake3i struct {
	t      *testing.T
	db     *firestore.Client
	bot    *BotService
	mu     sync.Mutex
	script []map[string]any // từng part model trả, lần lượt
	reqs   []map[string]any
	sent   []string
}

const fake3iGroup = "-100"

func newFake3i(t *testing.T, groupFacts bool) *fake3i {
	t.Helper()
	f := &fake3i{t: t, db: emulatorDB(t)}
	srv := httptest.NewServer(http.HandlerFunc(f.serve))
	t.Cleanup(srv.Close)
	gc, err := genai.NewClient(context.Background(), &genai.ClientConfig{APIKey: "test", Backend: genai.BackendGeminiAPI, HTTPOptions: genai.HTTPOptions{BaseURL: srv.URL}})
	if err != nil {
		t.Fatal(err)
	}
	tg := NewTelegramService("token", fake3iGroup)
	tg.apiBaseURL = srv.URL
	f.bot = &BotService{genai: gc, telegram: tg, db: f.db, model: "m", hourly: 100, memory: NewMemoryService(gc, f.db, "m")}
	if groupFacts {
		f.bot.learned = NewAgentStore(f.db)
	}
	return f
}

func (f *fake3i) serve(w http.ResponseWriter, r *http.Request) {
	body, _ := io.ReadAll(r.Body)
	f.mu.Lock()
	defer f.mu.Unlock()
	if strings.HasSuffix(r.URL.Path, "/sendMessage") {
		var m map[string]any
		_ = json.Unmarshal(body, &m)
		f.sent = append(f.sent, stringValue(m["text"]))
		_, _ = w.Write([]byte(`{"ok":true,"result":{"message_id":1}}`))
		return
	}
	if !strings.Contains(r.URL.Path, ":generateContent") {
		http.Error(w, "fake3i: không biết "+r.URL.Path, 404)
		return
	}
	var req map[string]any
	_ = json.Unmarshal(body, &req)
	f.reqs = append(f.reqs, req)
	if len(f.script) == 0 {
		http.Error(w, "fake3i: hết script", 500)
		return
	}
	part := f.script[0]
	f.script = f.script[1:]
	_ = json.NewEncoder(w).Encode(map[string]any{"candidates": []any{map[string]any{"content": map[string]any{"role": "model", "parts": []any{part}}}}})
}

func say(text string) map[string]any { return map[string]any{"text": text} }

func callTool(name string, args map[string]any) map[string]any {
	return map[string]any{"functionCall": map[string]any{"name": name, "args": args}}
}

// system là system prompt của request thứ i gửi model.
func (f *fake3i) system(i int) string {
	f.t.Helper()
	si, _ := f.reqs[i]["systemInstruction"].(map[string]any)
	var b strings.Builder
	for _, p := range anyList(si["parts"]) {
		b.WriteString(stringValue(p.(map[string]any)["text"]))
	}
	return b.String()
}

func (f *fake3i) tools(i int) []string {
	var out []string
	for _, tool := range anyList(f.reqs[i]["tools"]) {
		for _, d := range anyList(tool.(map[string]any)["functionDeclarations"]) {
			out = append(out, stringValue(d.(map[string]any)["name"]))
		}
	}
	return out
}

// toolResult là kết quả tool gửi lại model ở request thứ i.
func (f *fake3i) toolResult(i int) map[string]any {
	f.t.Helper()
	contents := anyList(f.reqs[i]["contents"])
	last := contents[len(contents)-1].(map[string]any)
	part := anyList(last["parts"])[0].(map[string]any)
	resp, _ := part["functionResponse"].(map[string]any)
	if resp == nil {
		f.t.Fatalf("request %d không kèm kết quả tool: %v", i, last)
	}
	out, _ := resp["response"].(map[string]any)
	return out
}

func (f *fake3i) seedFacts(key string, facts map[string]string) {
	f.t.Helper()
	var list []any
	for id, text := range facts {
		list = append(list, map[string]any{"id": id, "text": text, "updatedAt": time.Now()})
	}
	seed(f.t, f.db, "agentRooms/main/learned/"+key, map[string]any{"facts": list})
}

// seedClub: An (tg 111) đã liên kết app, Bình (tg 222) chỉ có trên Telegram,
// Cường nhắn trước khi tin có tgUserId.
func (f *fake3i) seedClub() {
	seed(f.t, f.db, "tgLinks/111", map[string]any{"uid": "an", "displayName": "An"})
	seed(f.t, f.db, "telegramLinks/an", map[string]any{"tgUserId": int64(111)})
	seed(f.t, f.db, "publicProfiles/an", map[string]any{"displayName": "An"})
	f.seedFacts(agentGroupScope, map[string]string{"f1": "Nhóm chạy 6h thứ 7 ở hồ Tây"})
	f.seedFacts("an", map[string]string{"f1": "An mê trail"})
	f.seedFacts("tg-111", map[string]string{"f1": "An đi giày Pegasus"})
	f.seedFacts("tg-222", map[string]string{"f1": "Bình mới tập 3km"})
	f.seedFacts("cuong", map[string]string{"f1": "Cường đau gối"})
	seed(f.t, f.db, "botMemory/"+fake3iGroup, map[string]any{"text": "TÓM TẮT CŨ của group"})
	at := time.Now().Add(-time.Minute)
	seed(f.t, f.db, "botConversations/"+fake3iGroup+"/botMessages/m1", map[string]any{"role": "user", "name": "Bình", "tgUserId": "222", "text": "mai ai chạy", "createdAt": at})
	seed(f.t, f.db, "botConversations/"+fake3iGroup+"/botMessages/m2", map[string]any{"role": "user", "name": "Cường", "text": "mình nghỉ", "createdAt": at.Add(-time.Second)})
}

func TestEmulatorBotGroupFactsInGroup(t *testing.T) {
	f := newFake3i(t, true)
	f.seedClub()
	f.script = []map[string]any{say("Sáng thứ 7 hồ Tây nhé")}
	if err := f.bot.HandleMessage(context.Background(), fake3iGroup, 0, "111", "An", "@3i mai chạy đâu", ""); err != nil {
		t.Fatal(err)
	}
	sys := f.system(0)
	for _, want := range []string{"BẠN BIẾT VỀ GROUP CLUB", "- Nhóm chạy 6h thứ 7 ở hồ Tây\n", "An:\n- An mê trail\n- An đi giày Pegasus\n", "Bình:\n- Bình mới tập 3km", "recall_person"} {
		if !strings.Contains(sys, want) {
			t.Errorf("prompt group thiếu %q:\n%s", want, sys)
		}
	}
	// Cường nhắn khi tin chưa có tgUserId nên không biết là ai; tóm tắt cũ không
	// còn dùng; trong group không có id để quên.
	for _, leak := range []string{"Cường đau gối", "TÓM TẮT CŨ", "[f1]", "forget_my_fact", "NGƯỜI ĐANG CHAT VỚI BẠN"} {
		if strings.Contains(sys, leak) {
			t.Errorf("prompt group có %q", leak)
		}
	}
	tools := f.tools(0)
	wantContains(t, tools, "recall_person")
	wantMissing(t, tools, "forget_my_fact")
	if len(f.sent) != 1 || f.sent[0] != "Sáng thứ 7 hồ Tây nhé" {
		t.Fatalf("tin gửi: %v", f.sent)
	}
}

func TestEmulatorBotGroupFactsOff(t *testing.T) {
	f := newFake3i(t, false)
	f.seedClub()
	f.script = []map[string]any{say("ok"), say("ok")}
	ctx := context.Background()
	if err := f.bot.HandleMessage(ctx, fake3iGroup, 0, "111", "An", "@3i mai chạy đâu", ""); err != nil {
		t.Fatal(err)
	}
	if err := f.bot.HandleMessage(ctx, "111", 0, "111", "An", "chào", ""); err != nil {
		t.Fatal(err)
	}
	for i, heading := range []string{"TRÍ NHỚ VỀ NHÓM NÀY (điều bạn đã biết về các thành viên):\nTÓM TẮT CŨ", "TRÍ NHỚ VỀ GROUP CLUB (nội dung công khai đã bàn trong nhóm):\nTÓM TẮT CŨ"} {
		sys := f.system(i)
		if !strings.Contains(sys, heading) || strings.Contains(sys, "An mê trail") || strings.Contains(sys, "GROUP CLUB (rút từ") {
			t.Errorf("tắt cờ thì prompt %d phải như cũ:\n%s", i, sys)
		}
		wantMissing(t, f.tools(i), "recall_person", "forget_my_fact")
	}
}

func TestEmulatorBotGroupFactsDM(t *testing.T) {
	f := newFake3i(t, true)
	f.seedClub()
	ctx := context.Background()
	f.script = []map[string]any{
		callTool("forget_my_fact", map[string]any{"id": "tg-f1"}),
		callTool("recall_person", map[string]any{"name": "Bình"}),
		say("Quên rồi nhé"),
	}
	if err := f.bot.HandleMessage(ctx, "111", 0, "111", "An", "quên vụ giày đi, mà Bình sao rồi", ""); err != nil {
		t.Fatal(err)
	}
	sys := f.system(0)
	for _, want := range []string{"- Nhóm chạy 6h thứ 7 ở hồ Tây\n", "BẠN BIẾT VỀ An, NGƯỜI ĐANG CHAT VỚI BẠN", "[f1] An mê trail\n[tg-f1] An đi giày Pegasus\n", "forget_my_fact"} {
		if !strings.Contains(sys, want) {
			t.Errorf("prompt chat riêng thiếu %q:\n%s", want, sys)
		}
	}
	// Chat riêng không kéo người trong group vào prompt, muốn biết thì gọi tool.
	if strings.Contains(sys, "Bình mới tập") || strings.Contains(sys, "TÓM TẮT CŨ") {
		t.Errorf("prompt chat riêng:\n%s", sys)
	}
	wantContains(t, f.tools(0), "recall_person", "forget_my_fact")
	if r := f.toolResult(1); r["ok"] != true {
		t.Fatalf("forget_my_fact: %v", r)
	}
	if r := f.toolResult(2); r["ok"] != true || strings.Join(toStrings(r["facts"]), ",") != "Bình mới tập 3km" {
		t.Fatalf("recall_person: %v", r)
	}
	if facts := anyList(f.learned("tg-111")["facts"]); len(facts) != 0 {
		t.Fatalf("còn ký ức đã quên: %v", facts)
	}
	if l := f.doc("agentRooms/main/learnLog/forget-tg-111-f1"); l["by"] != "tg:111" || l["before"] != "An đi giày Pegasus" {
		t.Fatalf("learnLog: %v", l)
	}

	// Người chưa liên kết quên ký ức của mình; id của người khác thì không có.
	f.script = []map[string]any{
		callTool("forget_my_fact", map[string]any{"id": "f1"}),
		callTool("forget_my_fact", map[string]any{"id": "f1"}),
		say("xong"),
	}
	if err := f.bot.HandleMessage(ctx, "222", 0, "222", "Bình", "quên hết về mình đi", ""); err != nil {
		t.Fatal(err)
	}
	if r := f.toolResult(4); r["ok"] != true {
		t.Fatalf("Bình quên ký ức của mình: %v", r)
	}
	if r := f.toolResult(5); r["ok"] != false || r["error"] != errLearnedNotFound.Message {
		t.Fatalf("quên lần hai: %v", r)
	}
	if len(anyList(f.learned("tg-222")["facts"])) != 0 || len(anyList(f.learned("an")["facts"])) != 1 {
		t.Fatal("xoá sai doc")
	}
}

func TestEmulatorBotGroupFactsTools(t *testing.T) {
	f := newFake3i(t, true)
	f.seedClub()
	ctx := context.Background()
	out, err := f.bot.dispatch(ctx, "recall_group", map[string]any{}, false)
	if err != nil {
		t.Fatal(err)
	}
	if r := out.(map[string]any); r["groupSummary"] != "- Nhóm chạy 6h thứ 7 ở hồ Tây" {
		t.Fatalf("recall_group: %v", r)
	}
	// An tới qua uid lẫn qua tg đã liên kết: chỉ một mục.
	people, err := f.bot.learned.learnedPeople(ctx, []learnedSubject{{uid: "an", name: "An"}, {tg: "111", name: "An tg"}, {tg: "222", name: "Bình"}}, time.Now())
	if err != nil || len(people) != 2 || people[0].name != "An" || people[1].name != "Bình" {
		t.Fatalf("learnedPeople: %+v %v", people, err)
	}
	// forget_my_fact chỉ có trong chat riêng.
	if _, err := f.bot.dispatch(ctx, "forget_my_fact", map[string]any{"id": "f1"}, false); err == nil {
		t.Fatal("forget_my_fact chạy được trong group")
	}
	off := newFake3i(t, false)
	if _, err := off.bot.dispatch(ctx, "recall_person", map[string]any{"name": "An"}, true); err == nil {
		t.Fatal("tắt cờ mà recall_person vẫn chạy")
	}
}

func TestEmulatorBotGroupFactsAnnouncements(t *testing.T) {
	f := newFake3i(t, true)
	f.seedClub()
	ctx := context.Background()
	f.script = []map[string]any{say("An về đích"), say("An xuất phát"), say("Cà khịa Cường")}
	f.bot.ActivityAnnouncement(ctx, "an", "An", "Chạy sáng", ActivityFact{SportType: "Run", DistanceMeters: 5000, MovingTimeSeconds: 1800})
	f.bot.LiveAnnouncement(ctx, "an", "An", "start", 0, 0, 0)
	f.bot.ContractRoast(ctx, "Kèo 100km", "100 km", []roastFailer{{uid: "cuong", name: "Cường", progress: "20 km"}})
	for i, want := range []string{"An:\n- An mê trail\n- An đi giày Pegasus", "An:\n- An mê trail\n- An đi giày Pegasus", "Cường:\n- Cường đau gối"} {
		if sys := f.system(i); !strings.Contains(sys, want) || !strings.Contains(sys, "- Nhóm chạy 6h thứ 7") || strings.Contains(sys, "TÓM TẮT CŨ") {
			t.Errorf("prompt thông báo %d thiếu %q:\n%s", i, want, sys)
		}
	}
}

func (f *fake3i) doc(path string) map[string]any {
	f.t.Helper()
	m, err := docMap(f.db.Doc(path).Get(context.Background()))
	if err != nil {
		f.t.Fatal(err)
	}
	return m
}

func (f *fake3i) learned(key string) map[string]any { return f.doc("agentRooms/main/learned/" + key) }

func wantContains(t *testing.T, got []string, want ...string) {
	t.Helper()
	for _, w := range want {
		if !strings.Contains(","+strings.Join(got, ",")+",", ","+w+",") {
			t.Errorf("thiếu %q trong %v", w, got)
		}
	}
}

func wantMissing(t *testing.T, got []string, unwanted ...string) {
	t.Helper()
	for _, w := range unwanted {
		if strings.Contains(","+strings.Join(got, ",")+",", ","+w+",") {
			t.Errorf("không được có %q trong %v", w, got)
		}
	}
}
