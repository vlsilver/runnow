//go:build emulator

package backend

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"reflect"
	"slices"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// fakeImageLLM trả một ảnh cố định và ghi prompt của từng lần vẽ.
type fakeImageLLM struct {
	prompts []string
	// refs là ảnh gốc gửi kèm từng lần vẽ; nil là vẽ không có ảnh gốc.
	refs [][]byte
	err  error
}

func (f *fakeImageLLM) Image(_ context.Context, parts []*genai.Part) (*genai.GenerateContentResponse, error) {
	f.prompts = append(f.prompts, parts[len(parts)-1].Text)
	var ref []byte
	for _, p := range parts {
		if p.InlineData != nil {
			ref = p.InlineData.Data
		}
	}
	f.refs = append(f.refs, ref)
	if f.err != nil {
		return nil, f.err
	}
	return &genai.GenerateContentResponse{Candidates: []*genai.Candidate{{Content: &genai.Content{Role: genai.RoleModel, Parts: []*genai.Part{
		{InlineData: &genai.Blob{MIMEType: "image/png", Data: []byte("png-bytes")}},
	}}}}}, nil
}

type memImageStore struct {
	mu    sync.Mutex
	files map[string][]byte
}

func (s *memImageStore) Put(_ context.Context, path string, data []byte) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.files[path] = data
	return nil
}

func (s *memImageStore) Get(_ context.Context, path string) ([]byte, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	data, ok := s.files[path]
	if !ok {
		return nil, errAgentImageMissing
	}
	return data, nil
}

func (e *agentEnv) enableImages() (*fakeImageLLM, *memImageStore) {
	gen, store := &fakeImageLLM{}, &memImageStore{files: map[string][]byte{}}
	e.brain.SetImages(gen, store)
	return gen, store
}

// seedRunKm cho uid một buổi chạy km sáng nay.
func (e *agentEnv) seedRunKm(uid string, km float64) {
	e.t.Helper()
	seed(e.t, e.store.db, "users/"+uid+"/activities/r1", map[string]any{
		"startedAt": agentClock.Add(-time.Hour).UTC().Format(time.RFC3339), "distanceMeters": km * 1000,
		"movingTimeSeconds": 1800, "sportType": "Run", "source": "strava",
	})
}

// setImagesUsed đặt số ảnh bot của uid đã vẽ hôm nay.
func (e *agentEnv) setImagesUsed(uid string, n int64) {
	e.t.Helper()
	if _, err := e.deps.Agents.agentRef(uid).Update(context.Background(), []firestore.Update{{Path: "imgDay", Value: vnDay(e.clock)}, {Path: "imgDayCount", Value: n}}); err != nil {
		e.t.Fatal(err)
	}
}

func drawCall(prompt string) *genai.GenerateContentResponse {
	return llmCall("generate_image", map[string]any{"imagePrompt": prompt, "style": "3d"})
}

// Chủ nhờ bot vẽ trong chat riêng Telegram: chạy 5,2 km thì được 5 ảnh, ảnh đi
// ra bằng bot con kèm câu trả lời làm chú thích. Lượt trả lời hỏng sau khi đã
// vẽ thì task chạy lại dùng ảnh cũ, không vẽ lại, không đếm lại. Hết lượt thì
// tool báo mốc km kế tiếp; chưa chạy đủ 1 km thì không vẽ.
func TestEmulatorAgentImageTelegramDM(t *testing.T) {
	e := newMybotEnv(t)
	gen, store := e.enableImages()
	e.m.images = store
	tok := e.linkBot("an", "5002", 8002, "Sóc", 10)
	e.seedRunKm("an", 5.2)

	e.llm.script = []*genai.GenerateContentResponse{drawCall("a squirrel running")}
	e.child(8002, dmUpd(50, 5002, "vẽ con sóc chạy bộ đi"))
	task := e.tasksTo("/tasks/agent-dm")[0]
	if code := e.runTask(task.HandlerPath, task.Payload); code == 200 {
		t.Fatal("model hết script mà lượt trả lời vẫn xong")
	}
	if len(gen.prompts) != 1 || !strings.Contains(gen.prompts[0], "a squirrel running") {
		t.Fatalf("lần vẽ đầu = %q", gen.prompts)
	}
	if !slices.Contains(toolNames(e.llm.calls[0]), "generate_image") || !strings.Contains(e.llm.calls[0].system, "generate_image") {
		t.Fatalf("chat riêng Telegram thiếu tool vẽ: %v", toolNames(e.llm.calls[0]))
	}

	e.llm.calls, e.llm.script = nil, []*genai.GenerateContentResponse{drawCall("a squirrel running"), llmText("Sóc tặng chủ nè")}
	e.drain()
	if len(gen.prompts) != 1 {
		t.Fatalf("task chạy lại vẽ lại: %d lần", len(gen.prompts))
	}
	if out := toolResult(t, e.llm.calls[1]); out["ok"] != true {
		t.Fatalf("chạy lại không dùng ảnh cũ: %v", out)
	}
	path := "users/an/agentImages/tg1.png"
	if img := e.fsDoc("agents/an/images/tg1"); img["storagePath"] != path || string(store.files[path]) != "png-bytes" {
		t.Fatalf("ảnh tg1 = %v", img)
	}
	if got := e.fsDoc("agents/an")["imgDayCount"]; got != int64(1) {
		t.Fatalf("imgDayCount = %v", got)
	}
	photos := e.tg.CallsBy(tok, "sendPhoto")
	if len(photos) != 1 || photos[0].Params["chat_id"] != "5002" || photos[0].Params["caption"] != "Sóc tặng chủ nè" || len(e.tg.CallsBy(tok, "sendMessage")) != 0 {
		t.Fatalf("sendPhoto = %+v, sendMessage = %+v", photos, e.tg.CallsBy(tok, "sendMessage"))
	}
	if reply := e.fsDoc("agents/an/tgdm/" + seqDocID(2)); reply["imagePath"] != path {
		t.Fatalf("tin trả lời = %v", reply)
	}
	// Task trả lời chạy lại lần nữa sau khi đã gửi: không gửi ảnh thứ hai.
	e.mustRun("/tasks/agent-dm", task.Payload)
	e.drain()
	if n := len(e.tg.CallsBy(tok, "sendPhoto")); n != 1 || len(gen.prompts) != 1 {
		t.Fatalf("chạy lại sau khi gửi: sendPhoto=%d vẽ=%d", n, len(gen.prompts))
	}

	// Lần sau model thấy mình đã gửi ảnh.
	ask := func(update int64, script ...*genai.GenerateContentResponse) map[string]any {
		t.Helper()
		e.tick(2 * time.Second)
		e.llm.calls, e.llm.script = nil, script
		e.child(8002, dmUpd(update, 5002, "vẽ nữa đi"))
		e.drain()
		return toolResult(t, e.llm.calls[1])
	}
	e.setImagesUsed("an", 5)
	out := ask(51, drawCall("another squirrel"), llmText("Hết lượt rồi chủ ơi"))
	if history := fmt.Sprint(e.llm.calls[0].contents[1].Parts[0].Text); !strings.HasPrefix(history, agentImageNote) {
		t.Fatalf("lịch sử không đánh dấu tin có ảnh: %q", history)
	}
	reason, _ := out["reason"].(string)
	if out["ok"] != false || !strings.Contains(reason, "10 km") || !strings.Contains(reason, "5.2 km") || out["runKmToday"] != 5.2 {
		t.Fatalf("hết lượt ở mốc 5 km: %v", out)
	}
	if len(gen.prompts) != 1 || e.fsDoc("agents/an")["imgDayCount"] != int64(5) {
		t.Fatalf("hết lượt mà vẫn vẽ hay đếm: vẽ=%d", len(gen.prompts))
	}
	if sends := e.tg.CallsBy(tok, "sendMessage"); len(sends) != 1 || sends[0].Params["text"] != "Hết lượt rồi chủ ơi" {
		t.Fatalf("câu hết lượt = %+v", sends)
	}

	// Chủ chưa chạy hôm nay: không vẽ, chỉ mốc 1 km.
	cuongTok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 11)
	e.llm.calls, e.llm.script = nil, []*genai.GenerateContentResponse{drawCall("an owl"), llmText("Chạy đi đã")}
	e.child(8001, dmUpd(60, 5001, "vẽ con cú"))
	e.drain()
	out = toolResult(t, e.llm.calls[1])
	if reason, _ = out["reason"].(string); out["ok"] != false || !strings.Contains(reason, "1 km thì mở 3 ảnh") || !strings.Contains(reason, "0.0 km") {
		t.Fatalf("0 km: %v", out)
	}
	if len(gen.prompts) != 1 || len(e.tg.CallsBy(cuongTok, "sendPhoto")) != 0 {
		t.Fatalf("0 km mà vẫn vẽ: %d", len(gen.prompts))
	}
}

// Model ảnh hỏng thì bot báo cho chủ chứ không bắt cả lượt chạy lại, và không
// mất lượt vẽ.
func TestEmulatorAgentImageModelFailure(t *testing.T) {
	e := newMybotEnv(t)
	gen, store := e.enableImages()
	e.m.images = store
	tok := e.linkBot("an", "5002", 8002, "Sóc", 10)
	e.seedRunKm("an", 1)
	gen.err = errors.New("vertex 503")
	e.llm.script = []*genai.GenerateContentResponse{drawCall("a squirrel"), llmText("Vẽ hỏng rồi, lát thử lại nhé")}
	e.child(8002, dmUpd(50, 5002, "vẽ đi"))
	e.drain()
	if out := toolResult(t, e.llm.calls[1]); out["ok"] != false || out["reason"] == nil {
		t.Fatalf("model hỏng: %v", out)
	}
	if e.fsDoc("agents/an")["imgDayCount"] != nil || e.fsDoc("agents/an/images/tg1") != nil || len(store.files) != 0 {
		t.Fatal("vẽ hỏng mà vẫn đếm hay ghi ảnh")
	}
	if sends := e.tg.CallsBy(tok, "sendMessage"); len(sends) != 1 || len(e.tg.CallsBy(tok, "sendPhoto")) != 0 {
		t.Fatalf("gửi = %+v", sends)
	}
}

// File ảnh không còn trong Storage thì tin bị bỏ, không gửi lại mãi.
func TestEmulatorAgentImageMissingFileFails(t *testing.T) {
	e := newMybotEnv(t)
	_, store := e.enableImages()
	e.m.images = store
	tok := e.linkBot("an", "5002", 8002, "Sóc", 10)
	if err := e.m.enqueueReply(context.Background(), "8002", "5002", 0, "ảnh nè", "users/an/agentImages/tg9.png", "dm-an-10"); err != nil {
		t.Fatal(err)
	}
	e.drain()
	if got := e.fsDoc("managedBots/8002/tgOutbox/dm-an-10")["status"]; got != outboxFailed || len(e.tg.CallsBy(tok, "sendPhoto")) != 0 {
		t.Fatalf("outbox status = %v", got)
	}
}

// Kênh app và phòng main chưa hiện ảnh nên không có tool vẽ, kể cả khi đã bật.
func TestEmulatorAgentImageNotInApp(t *testing.T) {
	e := newAgentEnv(t)
	e.enableImages()
	e.createBot("an", "Sóc", "")
	e.seedRunKm("an", 12)
	e.llm.script = []*genai.GenerateContentResponse{llmText("chào")}
	e.want(e.call("an", "POST", "/v1/agents/me/dm", map[string]any{"text": "vẽ đi"}, ""), 200, "")
	e.mustRun("/tasks/agent-dm", e.tasksTo("/tasks/agent-dm")[0].Payload)
	if names := toolNames(e.llm.calls[0]); slices.Contains(names, "generate_image") || strings.Contains(e.llm.calls[0].system, "generate_image") {
		t.Fatalf("chat riêng app có tool vẽ: %v", names)
	}
	e.llm.calls, e.llm.script = nil, []*genai.GenerateContentResponse{llmText("ừ")}
	e.want(e.call("binh", "POST", "/v1/agents/room", map[string]any{"text": "Sóc vẽ gì đi"}, ""), 200, "")
	e.mustRun("/tasks/agent-turn", agentTurnTask{AfterSeq: lastTurn(t, e).AfterSeq})
	if names := toolNames(e.llm.calls[0]); slices.Contains(names, "generate_image") {
		t.Fatalf("phòng main có tool vẽ: %v", names)
	}
}

// Trong Phòng bot trên Telegram, người nhờ bot vẽ thì ảnh ra đúng topic bằng
// bot con của chủ. Chủ để hồ sơ riêng tư thì lý do hết lượt không có số km.
func TestEmulatorAgentImageTelegramRoom(t *testing.T) {
	e := newMybotEnv(t)
	gen, store := e.enableImages()
	e.m.images = store
	cuongTok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	e.linkBot("an", "5002", 8002, "Sóc", 11)
	if _, err := e.store.db.Doc("agentState/config").Set(context.Background(), map[string]any{"tgRoomThreadId": tgRoomThread}, firestore.MergeAll); err != nil {
		t.Fatal(err)
	}
	e.child(8001, pscMemberUpd(200, 8001, "member"))
	e.drain()
	e.seedRunKm("cuong", 1.5)

	say := func(update int64, text string, script ...*genai.GenerateContentResponse) {
		t.Helper()
		e.tick(time.Minute)
		e.llm.calls, e.llm.script = nil, script
		e.manager(topicMsg(update, 5002, tgRoomThread, text))
		e.drain()
	}
	say(300, "Cú Mèo vẽ con cú đi", drawCall("an owl"), llmText("Cú đây"))
	if !slices.Contains(toolNames(e.llm.calls[0]), "generate_image") {
		t.Fatalf("Phòng bot thiếu tool vẽ: %v", toolNames(e.llm.calls[0]))
	}
	if out := toolResult(t, e.llm.calls[1]); fmt.Sprintf("%v %v %v", out["ok"], out["usedToday"], out["limitToday"]) != "true 1 3" {
		t.Fatalf("vẽ ở 1,5 km: %v", out)
	}
	photos := e.tg.CallsBy(cuongTok, "sendPhoto")
	if len(photos) != 1 || photos[0].Params["chat_id"] != testPscChat || photos[0].Params["message_thread_id"] != fmt.Sprint(tgRoomThread) || photos[0].Params["caption"] != "Cú đây" {
		t.Fatalf("sendPhoto = %+v", photos)
	}
	msgs := e.roomMessages(agentTelegramRoom)
	if last := msgs[len(msgs)-1]; last["uid"] != "cuong" || last["imagePath"] != "users/cuong/agentImages/room-tg-psc-1.png" {
		t.Fatalf("tin bot trong phòng = %v", last)
	}
	// Lượt chạy lại không gửi ảnh thứ hai.
	e.mustRun("/tasks/agent-turn", agentTurnTask{RoomID: agentTelegramRoom, AfterSeq: 1})
	e.drain()
	if n := len(e.tg.CallsBy(cuongTok, "sendPhoto")); n != 1 || len(gen.prompts) != 1 {
		t.Fatalf("chạy lại: sendPhoto=%d vẽ=%d", n, len(gen.prompts))
	}

	e.setImagesUsed("cuong", 3)
	say(301, "Cú Mèo vẽ nữa", drawCall("another owl"), llmText("Chủ mình phải chạy thêm đã"))
	out := toolResult(t, e.llm.calls[1])
	if reason, _ := out["reason"].(string); out["ok"] != false || strings.Contains(reason, "1.5") || out["runKmToday"] != nil || !strings.Contains(reason, "5 km") {
		t.Fatalf("hết lượt, hồ sơ riêng tư: %v", out)
	}
	if len(gen.prompts) != 1 {
		t.Fatalf("hết lượt mà vẫn vẽ: %d", len(gen.prompts))
	}
}

// Chủ xem lại ảnh bot mình đã vẽ: mới trước, theo trang, chỉ ảnh của bot mình.
func TestEmulatorAgentMeImageList(t *testing.T) {
	e := newAgentEnv(t)
	e.createBot("an", "Sóc", "")
	for i, key := range []string{"tg1", "room-tg-psc-4", "tg9"} {
		seed(t, e.store.db, "agents/an/images/"+key, map[string]any{
			"storagePath": "users/an/agentImages/" + key + ".png", "prompt": "p", "day": "2026-10-20",
			"at": agentClock.Add(time.Duration(i-3) * time.Hour),
		})
	}
	seed(t, e.store.db, "agents/binh/images/tg1", map[string]any{"storagePath": "users/binh/agentImages/tg1.png", "at": agentClock})
	paths := func(r apiResp) string {
		t.Helper()
		e.want(r, 200, "")
		var out []string
		for _, img := range r.body["images"].([]any) {
			out = append(out, img.(map[string]any)["path"].(string))
		}
		return strings.Join(out, " ")
	}

	first := e.call("an", "GET", "/v1/agents/me/images?limit=2", nil, "")
	if got := paths(first); got != "users/an/agentImages/tg9.png users/an/agentImages/room-tg-psc-4.png" {
		t.Fatalf("trang đầu = %s", got)
	}
	cursor, _ := first.body["cursor"].(string)
	if cursor == "" {
		t.Fatalf("còn ảnh mà không có cursor: %s", first.raw)
	}
	next := e.call("an", "GET", "/v1/agents/me/images?limit=2&cursor="+url.QueryEscape(cursor), nil, "")
	if got := paths(next); got != "users/an/agentImages/tg1.png" || next.body["cursor"] != nil {
		t.Fatalf("trang sau = %s, cursor %v", got, next.body["cursor"])
	}
	if at := next.body["images"].([]any)[0].(map[string]any)["at"]; at != agentClock.Add(-3*time.Hour).UTC().Format(time.RFC3339Nano) {
		t.Fatalf("at = %v", at)
	}
	if got := paths(e.call("cuong", "GET", "/v1/agents/me/images", nil, "")); got != "" {
		t.Fatalf("chưa có bot mà có ảnh: %s", got)
	}
	e.want(e.call("an", "GET", "/v1/agents/me/images?limit=0", nil, ""), 400, "")
	e.want(e.call("an", "GET", "/v1/agents/me/images?cursor=abc", nil, ""), 400, "")
}

func topicPhoto(updateID, from, thread int64, caption, fileID string) map[string]any {
	u := topicMsg(updateID, from, thread, "")
	msg := u["message"].(map[string]any)
	delete(msg, "text")
	msg["photo"] = []any{map[string]any{"file_id": fileID + "-nho"}, map[string]any{"file_id": fileID}}
	if caption != "" {
		msg["caption"] = caption
	}
	return u
}

// hasInlineImage: tin cuối gửi model chat có kèm ảnh data.
func hasInlineImage(call fakeCall, data string) bool {
	last := call.contents[len(call.contents)-1]
	for _, p := range last.Parts {
		if p.InlineData != nil && string(p.InlineData.Data) == data {
			return true
		}
	}
	return false
}

// Người gửi ảnh kèm chú thích trong Phòng bot thì bot nhìn thấy ảnh và vẽ lại
// từ chính ảnh đó, như 3i. Ảnh lấy bản lớn nhất. Ảnh không chú thích thì vẫn
// không vào phòng.
func TestEmulatorAgentImageTelegramRoomPhoto(t *testing.T) {
	e := newMybotEnv(t)
	gen, store := e.enableImages()
	e.m.images = store
	e.brain.SetPhotos(func(_ context.Context, fileID string) ([]byte, error) {
		return []byte("jpeg-" + fileID), nil
	})
	cuongTok := e.linkBot("cuong", "5001", 8001, "Cú Mèo", 10)
	e.linkBot("an", "5002", 8002, "Sóc", 11)
	if _, err := e.store.db.Doc("agentState/config").Set(context.Background(), map[string]any{"tgRoomThreadId": tgRoomThread}, firestore.MergeAll); err != nil {
		t.Fatal(err)
	}
	e.child(8001, pscMemberUpd(200, 8001, "member"))
	e.drain()
	e.seedRunKm("cuong", 1.5)

	e.tick(time.Minute)
	e.llm.calls, e.llm.script = nil, []*genai.GenerateContentResponse{drawCall("everyone as xianxia cultivators"), llmText("Tu tiên hết rồi nhé")}
	e.manager(topicPhoto(300, 5002, tgRoomThread, "Cú Mèo biến đám này thành tu tiên giả hết cho tao", "anh"))
	e.drain()
	msgs := e.roomMessages(agentTelegramRoom)
	if len(msgs) != 2 || msgs[0]["text"] != "Cú Mèo biến đám này thành tu tiên giả hết cho tao" || msgs[0]["photoFileId"] != "anh" {
		t.Fatalf("phòng tg-psc = %v", msgs)
	}
	if !hasInlineImage(e.llm.calls[0], "jpeg-anh") {
		t.Fatalf("model chat không thấy ảnh: %+v", e.llm.calls[0].contents)
	}
	if len(gen.refs) != 1 || string(gen.refs[0]) != "jpeg-anh" {
		t.Fatalf("vẽ không theo ảnh gốc: %q", gen.refs)
	}
	if photos := e.tg.CallsBy(cuongTok, "sendPhoto"); len(photos) != 1 || photos[0].Params["caption"] != "Tu tiên hết rồi nhé" {
		t.Fatalf("sendPhoto = %+v", photos)
	}

	e.tick(time.Minute)
	e.manager(topicPhoto(301, 5002, tgRoomThread, "", "anh2"))
	e.drain()
	if n := len(e.roomMessages(agentTelegramRoom)); n != 2 {
		t.Fatalf("ảnh không chú thích vào phòng: %d tin", n)
	}
}

// GET me báo lượt vẽ ảnh hôm nay và mốc km kế tiếp, đọc cùng bộ đếm mà lượt vẽ
// dùng để chặn. Api không dựng AgentService (không có Vertex AI), nên số này
// chỉ đọc Firestore. Chưa tạo bot thì không có images.
func TestEmulatorAgentMeImages(t *testing.T) {
	e := newAgentEnv(t)
	e.deps.AgentBrain = nil
	e.createBot("an", "Sóc", "")
	if got := e.meToday("cuong")["images"]; got != nil {
		t.Fatalf("chưa tạo bot mà có images: %v", got)
	}
	// Bảng mốc đi kèm để app vẽ đủ các bậc mà không giữ bảng riêng.
	tiers := []any{
		map[string]any{"km": 1.0, "limit": 3.0},
		map[string]any{"km": 5.0, "limit": 5.0},
		map[string]any{"km": 10.0, "limit": 10.0},
	}
	wantImages := func(step string, want map[string]any) {
		t.Helper()
		want["tiers"] = tiers
		if got := e.meToday("an")["images"]; !reflect.DeepEqual(got, want) {
			t.Fatalf("%s: images = %v, muốn %v", step, got, want)
		}
	}
	wantImages("chưa chạy", map[string]any{"used": 0.0, "limit": 0.0, "runKm": 0.0, "nextKm": 1.0, "nextLimit": 3.0})
	e.seedRunKm("an", 5.2)
	e.setImagesUsed("an", 2)
	wantImages("chạy 5,2 km, vẽ 2 ảnh", map[string]any{"used": 2.0, "limit": 5.0, "runKm": 5.2, "nextKm": 10.0, "nextLimit": 10.0})
	e.seedRunKm("an", 12)
	wantImages("mốc cao nhất", map[string]any{"used": 2.0, "limit": 10.0, "runKm": 12.0, "nextKm": nil, "nextLimit": nil})
	// Qua 0h giờ VN: buổi chạy và số ảnh của hôm qua không tính.
	e.tick(16 * time.Hour)
	wantImages("ngày mới", map[string]any{"used": 0.0, "limit": 0.0, "runKm": 0.0, "nextKm": 1.0, "nextLimit": 3.0})
}
