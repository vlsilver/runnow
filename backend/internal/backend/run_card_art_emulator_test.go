//go:build emulator

package backend

import (
	"context"
	"errors"
	"math"
	"strings"
	"testing"
	"time"

	"google.golang.org/genai"
)

// artLLM giả model ảnh: mỗi lượt trả một ảnh và 1290 token output như model
// ảnh thật, hoặc lỗi, hoặc không có ảnh (bị chặn).
type artLLM struct {
	prompts []string
	photos  [][]byte
	mimes   []string
	err     error
	blocked bool
}

func (f *artLLM) Image(_ context.Context, parts []*genai.Part) (*genai.GenerateContentResponse, error) {
	var photo []byte
	var mime string
	for _, p := range parts {
		if p.InlineData != nil {
			photo, mime = p.InlineData.Data, p.InlineData.MIMEType
		}
	}
	f.prompts = append(f.prompts, parts[len(parts)-1].Text)
	f.photos = append(f.photos, photo)
	f.mimes = append(f.mimes, mime)
	if f.err != nil {
		return nil, f.err
	}
	usage := &genai.GenerateContentResponseUsageMetadata{PromptTokenCount: 300, CandidatesTokenCount: 1290}
	if f.blocked {
		return &genai.GenerateContentResponse{Candidates: []*genai.Candidate{{FinishReason: genai.FinishReasonImageSafety}}, UsageMetadata: usage}, nil
	}
	return &genai.GenerateContentResponse{UsageMetadata: usage, Candidates: []*genai.Candidate{{Content: &genai.Content{Role: genai.RoleModel, Parts: []*genai.Part{
		{InlineData: &genai.Blob{MIMEType: "image/png", Data: []byte("art-png")}},
	}}}}}, nil
}

type artEnv struct {
	*apiHarness
	t      *testing.T
	gen    *artLLM
	files  *memImageStore
	tasks  []PublishTask
	alerts []string
	clock  time.Time
}

// Giá model ảnh: 30 USD mỗi 1M token output, một ảnh 1290 token là 0,0387 USD
// cộng 300 token input là 0,00009 USD.
var artPrices = []any{map[string]any{"model": "img-model", "inputPer1M": 0.3, "outputPer1M": 30.0}}

const artCostPerImage = 1290*30.0/1e6 + 300*0.3/1e6

func newArtEnv(t *testing.T, config map[string]any) *artEnv {
	t.Helper()
	e := &artEnv{apiHarness: runCardHarness(t, 0), t: t, gen: &artLLM{}, files: &memImageStore{files: map[string][]byte{}}, clock: time.Date(2026, 10, 25, 1, 0, 0, 0, time.UTC)}
	cards := e.deps.RunCards
	cards.now = func() time.Time { return e.clock }
	budget := NewRunCardArtBudget(e.store.db, func(_ context.Context, text string) error {
		e.alerts = append(e.alerts, text)
		return nil
	})
	budget.now = func() time.Time { return e.clock }
	cards.SetArtist(budgetImageLLM{inner: e.gen, model: "img-model", budget: budget}, e.files, "img-model")
	e.deps.EnqueueTask = func(_ context.Context, task PublishTask) (string, error) {
		e.tasks = append(e.tasks, task)
		return "created", nil
	}
	config["llmPrices"] = artPrices
	seed(t, e.store.db, "agentState/config", config)
	return e
}

// card lật thẻ cho một buổi chạy mới id.
func (e *artEnv) card(id string, extra map[string]any) {
	e.t.Helper()
	seedRun(e.t, e.apiHarness, "u1", id, extra)
	e.want(e.call("u1", "POST", "/v1/activities/"+id+"/card", nil, ""), 200, "")
}

func (e *artEnv) ask(id, style, photo string) apiResp {
	e.t.Helper()
	return e.call("u1", "POST", "/v1/activities/"+id+"/card/art", map[string]any{"style": style, "photoPath": photo}, "")
}

func (e *artEnv) lastTask() runCardArtTask {
	e.t.Helper()
	if len(e.tasks) == 0 {
		e.t.Fatal("chưa có task vẽ nào")
	}
	task := e.tasks[len(e.tasks)-1]
	if task.HandlerPath != runCardArtQueuePath || task.Queue != QueueBotInbound {
		e.t.Fatalf("task = %+v", task)
	}
	return task.Payload.(runCardArtTask)
}

func (e *artEnv) draw(task runCardArtTask) {
	e.t.Helper()
	if err := e.deps.RunCards.DrawArt(context.Background(), task); err != nil {
		e.t.Fatal(err)
	}
}

func (e *artEnv) art(id string) map[string]any {
	e.t.Helper()
	snap, err := e.store.db.Doc("users/u1/runCards/" + id).Get(context.Background())
	if err != nil {
		e.t.Fatal(err)
	}
	art, _ := snap.Data()["art"].(map[string]any)
	return art
}

func TestEmulatorRunCardArtDrawOnceThenFixed(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	e.card("a1", nil)

	r := e.ask("a1", "anime_cel", "")
	e.want(r, 200, "")
	if art := r.body["card"].(map[string]any)["art"].(map[string]any); art["status"] != "drawing" || art["attempt"] != 1.0 || art["requestedAt"] != "2026-10-25T01:00:00Z" {
		t.Fatalf("art sau khi xin vẽ = %v", art)
	}
	first := e.lastTask()
	// Bấm lại khi đang vẽ: trả như cũ, đẩy lại đúng task đó.
	e.want(e.ask("a1", "anime_cel", ""), 200, "")
	if len(e.tasks) != 2 || e.tasks[1].TaskID != e.tasks[0].TaskID {
		t.Fatalf("đẩy lại phải cùng TaskID: %+v", e.tasks)
	}
	e.want(e.ask("a1", "linocut", ""), 409, "art_drawing")

	e.draw(first)
	art := e.art("a1")
	if art["status"] != "done" || art["path"] != "users/u1/runCards/a1/art-1.png" || art["model"] != "img-model" || art["styleVersion"] != int64(1) {
		t.Fatalf("art sau khi vẽ = %v", art)
	}
	if string(e.files.files["users/u1/runCards/a1/art-1.png"]) != "art-png" {
		t.Fatal("chưa lưu file tranh")
	}
	prompt := e.gen.prompts[0]
	if art["prompt"] != prompt || !strings.Contains(prompt, "Render it as a cel-shaded anime illustration:") {
		t.Fatalf("prompt = %q", prompt)
	}
	// 23,5 km bắt đầu 6h sáng giờ VN, không có ảnh; tên buổi chạy và bậc thẻ
	// không vào prompt.
	if !strings.Contains(prompt, "a lone runner in mid-stride along a quiet open road in the early morning light, capturing the feeling of a long-distance run.") ||
		strings.Contains(prompt, "Buổi") || strings.Contains(prompt, "rare") || strings.Contains(prompt, "23") {
		t.Fatalf("prompt = %q", prompt)
	}

	// Task chạy lại sau khi xong: không gọi model lần hai.
	e.draw(first)
	if len(e.gen.prompts) != 1 {
		t.Fatalf("gọi model %d lần, muốn 1", len(e.gen.prompts))
	}
	e.want(e.ask("a1", "anime_cel", ""), 200, "")
	e.want(e.ask("a1", "linocut", ""), 409, "art_fixed")
	if len(e.tasks) != 2 {
		t.Fatalf("thẻ đã vẽ không được đẩy thêm task: %d", len(e.tasks))
	}

	usage, err := getData(context.Background(), e.store.db.Doc("agentState/runCardArtUsage/days/"+agentUsageDay(e.clock)))
	if err != nil || math.Abs(number(usage["costUsd"])-artCostPerImage) > 1e-9 || number(usage["calls"]) != 1 {
		t.Fatalf("usage vẽ thẻ = %v (%v), muốn %.5f USD 1 lượt", usage, err, artCostPerImage)
	}
	if bot, _ := getData(context.Background(), e.store.db.Doc("agentState/usage/days/"+agentUsageDay(e.clock))); bot != nil {
		t.Fatalf("vẽ thẻ không được cộng vào trần bot cá nhân: %v", bot)
	}
}

func TestEmulatorRunCardArtFailuresAllowAnotherStyle(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	e.card("a1", nil)

	e.gen.err = errors.New("vertex 503")
	e.want(e.ask("a1", "anime_cel", ""), 200, "")
	e.draw(e.lastTask())
	if art := e.art("a1"); art["status"] != "failed" || art["reason"] != "model_error" {
		t.Fatalf("art = %v, muốn failed model_error", art)
	}

	// Hỏng thì chọn phong cách khác được; model chặn ảnh thì báo blocked.
	e.gen.err, e.gen.blocked = nil, true
	r := e.ask("a1", "linocut", "")
	e.want(r, 200, "")
	if task := e.lastTask(); task.Attempt != 2 {
		t.Fatalf("lần khoá thứ hai phải là attempt 2: %+v", task)
	}
	e.draw(e.lastTask())
	if art := e.art("a1"); art["status"] != "failed" || art["reason"] != "blocked" || art["style"] != "linocut" {
		t.Fatalf("art = %v, muốn failed blocked", art)
	}

	// Khoá treo quá 3 phút thì khoá lại được; task cũ chạy muộn thì bỏ.
	e.gen.blocked = false
	e.want(e.ask("a1", "anime_cel", ""), 200, "")
	stale := e.lastTask()
	e.clock = e.clock.Add(runCardArtStale + time.Second)
	e.want(e.ask("a1", "oil_impasto", ""), 200, "")
	fresh := e.lastTask()
	if fresh.Attempt != stale.Attempt+1 {
		t.Fatalf("khoá lại phải tăng attempt: %d -> %d", stale.Attempt, fresh.Attempt)
	}
	calls := len(e.gen.prompts)
	e.draw(stale)
	if len(e.gen.prompts) != calls || e.art("a1")["status"] != "drawing" {
		t.Fatal("task cũ không được vẽ đè khoá mới")
	}
	e.draw(fresh)
	// Mỗi lượt vẽ ra file riêng: app giữ cache ảnh theo đường dẫn, trùng tên
	// thì vẽ lại xong vẫn hiện tranh cũ.
	if art := e.art("a1"); art["status"] != "done" || art["style"] != "oil_impasto" || art["path"] != "users/u1/runCards/a1/art-4.png" {
		t.Fatalf("art = %v, muốn done oil_impasto ở art-4.png", art)
	}
}

func TestEmulatorRunCardArtBudgetCap(t *testing.T) {
	// Trần nhỏ hơn giá một ảnh: ảnh đầu vẫn vẽ (lúc kiểm chưa tiêu gì), ảnh sau
	// báo hết lượt và admin nhận đúng một tin.
	e := newArtEnv(t, map[string]any{"runCardArtDailyBudgetUsd": 0.03})
	e.card("a1", nil)
	e.card("a2", map[string]any{"startedAt": "2026-10-25T10:00:00Z"})
	e.card("a3", map[string]any{"startedAt": "2026-10-25T12:00:00Z"})

	for _, id := range []string{"a1", "a2", "a3"} {
		e.want(e.ask(id, "anime_cel", ""), 200, "")
		e.draw(e.lastTask())
	}
	if e.art("a1")["status"] != "done" || e.art("a2")["reason"] != "budget" || e.art("a3")["reason"] != "budget" {
		t.Fatalf("a1 %v, a2 %v, a3 %v", e.art("a1"), e.art("a2"), e.art("a3"))
	}
	if len(e.gen.prompts) != 1 || len(e.alerts) != 1 || !strings.Contains(e.alerts[0], "Vẽ thẻ buổi chạy chạm trần") {
		t.Fatalf("gọi model %d lần, tin báo %v", len(e.gen.prompts), e.alerts)
	}
	// Sang ngày mới thì vẽ lại được.
	e.clock = e.clock.Add(24 * time.Hour)
	e.want(e.ask("a2", "anime_cel", ""), 200, "")
	e.draw(e.lastTask())
	if e.art("a2")["status"] != "done" {
		t.Fatalf("a2 = %v, muốn done sau 0h", e.art("a2"))
	}
}

func TestEmulatorRunCardArtPhoto(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	own := "users/u1/activities/a1/photos/p1.jpg"
	e.card("a1", map[string]any{"photos": []any{map[string]any{"id": "p1", "storagePath": own}}})
	e.card("a2", map[string]any{"startedAt": "2026-10-25T10:00:00Z"})
	e.files.files[own] = []byte("run-photo")

	for _, p := range []string{"users/u2/activities/x/photos/p.jpg", "users/u1/runCards/a2/src.jpg", "users/u1/activities/a2/photos/p1.jpg"} {
		e.want(e.ask("a1", "anime_cel", p), 400, "invalid_photo")
	}
	e.want(e.ask("a1", "anime_cel", own), 200, "")
	e.draw(e.lastTask())
	if string(e.gen.photos[0]) != "run-photo" || e.gen.mimes[0] != "image/jpeg" || !strings.HasPrefix(e.gen.prompts[0], "Transform the provided photograph") {
		t.Fatalf("vẽ từ ảnh: ảnh %q prompt %q", e.gen.photos[0], e.gen.prompts[0])
	}
	if art := e.art("a1"); art["status"] != "done" || art["photoPath"] != own {
		t.Fatalf("art = %v", art)
	}

	// Ảnh tải lên cho thẻ mà file không có thì báo photo_missing, không gọi model.
	e.want(e.ask("a2", "anime_cel", "users/u1/runCards/a2/src.jpg"), 200, "")
	e.draw(e.lastTask())
	if art := e.art("a2"); art["status"] != "failed" || art["reason"] != "photo_missing" || len(e.gen.prompts) != 1 {
		t.Fatalf("art = %v, model gọi %d lần", art, len(e.gen.prompts))
	}

	// Ảnh chụp màn hình lên dưới dạng PNG thì model nhận đúng loại PNG.
	png := append([]byte("\x89PNG\r\n\x1a\n"), "screenshot"...)
	e.files.files["users/u1/runCards/a2/src.jpg"] = png
	e.want(e.ask("a2", "anime_cel", "users/u1/runCards/a2/src.jpg"), 200, "")
	e.draw(e.lastTask())
	if art := e.art("a2"); art["status"] != "done" || e.gen.mimes[1] != "image/png" {
		t.Fatalf("art = %v, mime %q", art, e.gen.mimes[1])
	}
}

func TestEmulatorRunCardArtNote(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	e.card("a1", nil)
	art := func(note string) map[string]any {
		return map[string]any{"style": "anime_cel", "note": note}
	}

	// 200 ký tự có dấu là 200 rune, 600 byte: vẫn nhận; 201 thì từ chối.
	e.want(e.call("u1", "POST", "/v1/activities/a1/card/art", art(strings.Repeat("ệ", 201)), ""), 400, "note_too_long")
	if len(e.tasks) != 0 {
		t.Fatalf("mô tả quá dài không được đẩy task: %d", len(e.tasks))
	}
	e.want(e.call("u1", "POST", "/v1/activities/a1/card/art", art("  mặc áo đỏ,\n  chạy cạnh   biển "), ""), 200, "")
	if a := e.art("a1"); a["note"] != "mặc áo đỏ, chạy cạnh biển" {
		t.Fatalf("note = %q, muốn đã gộp khoảng trắng", a["note"])
	}
	// Đang vẽ: cùng mô tả thì đẩy lại task, mô tả khác thì báo đang vẽ.
	e.want(e.call("u1", "POST", "/v1/activities/a1/card/art", art("mặc áo đỏ, chạy cạnh biển"), ""), 200, "")
	e.want(e.call("u1", "POST", "/v1/activities/a1/card/art", art("áo xanh"), ""), 409, "art_drawing")

	e.draw(e.lastTask())
	if !strings.Contains(e.gen.prompts[0], `used only where they fit the art style below: "mặc áo đỏ, chạy cạnh biển". Render it as`) {
		t.Fatalf("prompt = %q", e.gen.prompts[0])
	}

	e.card("a2", map[string]any{"startedAt": "2026-10-25T10:00:00Z"})
	e.want(e.call("u1", "POST", "/v1/activities/a2/card/art", art(strings.Repeat("ệ", 200)), ""), 200, "")
	e.card("a3", map[string]any{"startedAt": "2026-10-25T14:00:00Z"})
	e.want(e.call("u1", "POST", "/v1/activities/a3/card/art", map[string]any{"style": "anime_cel", "note": " \n "}, ""), 200, "")
	if a := e.art("a3"); a["note"] != nil {
		t.Fatalf("mô tả toàn khoảng trắng thì không lưu note: %v", a)
	}
}

func TestEmulatorRunCardArtRejects(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	seedRun(t, e.apiHarness, "u1", "a1", nil)
	e.want(e.ask("a1", "anime_cel", ""), 404, "card_not_found")
	e.want(e.call("u1", "POST", "/v1/activities/a1/card", nil, ""), 200, "")
	for _, style := range []string{"", "khong_co", "manga_ink"} {
		e.want(e.ask("a1", style, ""), 400, "invalid_style")
	}
	e.want(e.call("u1", "POST", "/v1/activities/a1/card/art", map[string]any{"style": "anime_cel", "rarity": "mythic"}, ""), 400, "")
	// Người khác không vẽ được thẻ của u1.
	e.want(e.call("u2", "POST", "/v1/activities/a1/card/art", map[string]any{"style": "anime_cel"}, ""), 404, "card_not_found")
	if len(e.tasks) != 0 {
		t.Fatalf("yêu cầu bị từ chối không được đẩy task: %d", len(e.tasks))
	}
}
