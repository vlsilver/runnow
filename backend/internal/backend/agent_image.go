package backend

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	gcs "cloud.google.com/go/storage"
	"google.golang.org/genai"
)

// Bot cá nhân vẽ ảnh bằng model ảnh của 3i, nhưng qua trần chi phí của bot cá
// nhân. Mỗi bot có hạn mức ảnh trong ngày (giờ VN) theo số km chủ chạy hôm
// nay, để bot có cớ giục chủ đi chạy. Chỉ vẽ ở chat riêng Telegram và Phòng bot
// trên Telegram, vì màn chat trong app chưa hiện ảnh.
//
// Ảnh gắn với tin đang trả lời (key): task chạy lại thì dùng lại ảnh đã vẽ,
// không vẽ lại, không đếm lại.

// agentImageTiers: chạy đủ km thì được vẽ images ảnh mỗi ngày. Xếp km giảm dần.
var agentImageTiers = []struct {
	km     float64
	images int64
}{{10, 10}, {5, 5}, {1, 3}}

func agentImageLimit(runKm float64) int64 {
	for _, t := range agentImageTiers {
		if runKm >= t.km {
			return t.images
		}
	}
	return 0
}

// agentImageNextTier là mốc kế tiếp trên runKm; ok false khi đã ở mốc cao nhất.
func agentImageNextTier(runKm float64) (km float64, images int64, ok bool) {
	for i := len(agentImageTiers) - 1; i >= 0; i-- {
		if t := agentImageTiers[i]; runKm < t.km {
			return t.km, t.images, true
		}
	}
	return 0, 0, false
}

// agentImageLLM là phần gọi model ảnh, tách ra để test thay bằng model giả.
type agentImageLLM interface {
	Image(ctx context.Context, parts []*genai.Part) (*genai.GenerateContentResponse, error)
}

type genaiImageLLM struct {
	client *genai.Client
	model  string
}

func (g genaiImageLLM) Image(ctx context.Context, parts []*genai.Part) (*genai.GenerateContentResponse, error) {
	started := time.Now()
	resp, err := g.client.Models.GenerateContent(ctx, g.model, []*genai.Content{{Role: genai.RoleUser, Parts: parts}}, funImageConfig())
	if err != nil {
		return nil, err
	}
	logLLMUsage(ctx, llmLabelOf(ctx).sub("image"), g.model, resp, started, 0)
	return resp, nil
}

type budgetImageLLM struct {
	inner  agentImageLLM
	model  string
	budget *AgentBudget
}

func (g budgetImageLLM) Image(ctx context.Context, parts []*genai.Part) (*genai.GenerateContentResponse, error) {
	return g.budget.meter(ctx, g.model, false, func() (*genai.GenerateContentResponse, error) {
		return g.inner.Image(ctx, parts)
	})
}

// agentImageStore giữ file ảnh bot vẽ. Get trả errAgentImageMissing khi không
// có file.
type agentImageStore interface {
	Put(ctx context.Context, path string, data []byte) error
	Get(ctx context.Context, path string) ([]byte, error)
}

var errAgentImageMissing = errors.New("agent image: không còn file ảnh")

type gcsImageStore struct{ bucket *gcs.BucketHandle }

func (s gcsImageStore) Put(ctx context.Context, path string, data []byte) error {
	w := s.bucket.Object(path).NewWriter(ctx)
	w.ContentType = "image/png"
	if _, err := w.Write(data); err != nil {
		_ = w.Close()
		return err
	}
	return w.Close()
}

func (s gcsImageStore) Get(ctx context.Context, path string) ([]byte, error) {
	r, err := s.bucket.Object(path).NewReader(ctx)
	if errors.Is(err, gcs.ErrObjectNotExist) {
		return nil, errAgentImageMissing
	}
	if err != nil {
		return nil, err
	}
	defer r.Close()
	return io.ReadAll(r)
}

// SetImages bật vẽ ảnh cho bot cá nhân. Gọi lúc dựng dependencies, trước khi
// nhận task. Không gọi thì bot không có tool generate_image.
func (a *AgentService) SetImages(gen agentImageLLM, store agentImageStore) {
	a.imageGen, a.imageStore = gen, store
}

// agentPhotoFunc tải ảnh Telegram theo file_id.
type agentPhotoFunc func(ctx context.Context, fileID string) ([]byte, error)

// SetPhotos cho bot nhìn ảnh người gửi trong Phòng bot và vẽ lại từ ảnh đó.
// fetch phải dùng token của 3i, vì file_id trong update của PSC là của 3i.
func (a *AgentService) SetPhotos(fetch agentPhotoFunc) {
	a.photos = fetch
}

var agentImageDecl = &genai.FunctionDeclaration{
	Name:        "generate_image",
	Description: "Vẽ một ảnh gửi kèm câu trả lời của bạn; mỗi tin tối đa một ảnh. Số ảnh mỗi ngày tuỳ số km chủ bạn chạy và đi bộ hôm nay, hết lượt thì tool báo lý do.",
	Parameters: &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{
		"imagePrompt": {Type: genai.TypeString, Description: "Mô tả ảnh bằng tiếng Anh, cụ thể: chủ thể, hành động, bối cảnh."},
		"style":       {Type: genai.TypeString, Enum: []string{"realistic", "anime", "cyberpunk", "cinematic", "3d", "watercolor", "comic", "pixel", "sticker"}, Description: "Phong cách. Bỏ trống là cinematic."},
	}, Required: []string{"imagePrompt"}},
}

const (
	agentDMImageRule   = "\n- Chủ nhờ vẽ ảnh thì gọi generate_image, imagePrompt viết bằng tiếng Anh. Vẽ xong thì câu trả lời của bạn thành chú thích ảnh, viết ngắn. Tool báo hết lượt thì nói đúng lý do nó trả về và giục chủ đi chạy để mở thêm lượt."
	agentRoomImageRule = "\n- Chỉ gọi generate_image khi có người trong phòng nhờ bạn vẽ, imagePrompt viết bằng tiếng Anh. Vẽ xong thì tin của bạn thành chú thích ảnh. Tool báo hết lượt thì nói lý do nó trả về."
	// agentImageNote đánh dấu tin cũ có kèm ảnh khi đưa lịch sử cho model.
	agentImageNote = "(kèm một ảnh bạn vẽ)"
)

// agentImageTurn là phần vẽ ảnh của một lượt trả lời của bot uid.
type agentImageTurn struct {
	a   *AgentService
	uid string
	// key là tin đang trả lời, vd "tg5" hay "room-tg-psc-12".
	key string
	// showKm là được nói số km của chủ trong lý do hết lượt.
	showKm bool
	wall   time.Time
	// path là ảnh đã vẽ trong lượt này; rỗng là chưa vẽ.
	path string
	// photo là ảnh người gửi kèm tin đang đáp; có thì vẽ lại từ ảnh này.
	photo []byte
}

// imageTurn trả nil khi chưa bật vẽ ảnh.
func (a *AgentService) imageTurn(uid, key string, showKm bool, wall time.Time) *agentImageTurn {
	if a.imageGen == nil || a.imageStore == nil {
		return nil
	}
	return &agentImageTurn{a: a, uid: uid, key: key, showKm: showKm, wall: wall}
}

func (t *agentImageTurn) decls() []*genai.FunctionDeclaration {
	if t == nil {
		return nil
	}
	return []*genai.FunctionDeclaration{agentImageDecl}
}

func (t *agentImageTurn) imagePath() string {
	if t == nil {
		return ""
	}
	return t.path
}

func (t *agentImageTurn) ref() *firestore.DocumentRef {
	return t.a.store.agentRef(t.uid).Collection("images").Doc(t.key)
}

// run chạy call nếu là generate_image; ok false khi không phải, hoặc lượt này
// không được vẽ (nil). Model hỏng hay không ra ảnh thì báo lý do cho model;
// chạm trần chi phí, Storage hay Firestore lỗi thì trả lỗi để task chạy lại.
func (t *agentImageTurn) run(ctx context.Context, call *genai.FunctionCall) (map[string]any, bool, error) {
	if t == nil || call.Name != agentImageDecl.Name {
		return nil, false, nil
	}
	out, err := t.draw(ctx, call)
	return out, true, err
}

func (t *agentImageTurn) draw(ctx context.Context, call *genai.FunctionCall) (map[string]any, error) {
	const done = "Đã vẽ xong, ảnh gửi kèm câu trả lời của bạn. Viết câu trả lời ngắn làm chú thích, đừng tả lại ảnh."
	if t.path != "" {
		return map[string]any{"ok": false, "reason": "tin này đã có một ảnh rồi"}, nil
	}
	prompt := strings.TrimSpace(stringValue(call.Args["imagePrompt"]))
	if prompt == "" {
		return map[string]any{"ok": false, "reason": "thiếu imagePrompt"}, nil
	}
	// Task chạy lại: ảnh của tin này đã vẽ và đã đếm.
	prev, err := getData(ctx, t.ref())
	if err != nil {
		return nil, err
	}
	if path := stringValue(prev["storagePath"]); path != "" {
		t.path = path
		return map[string]any{"ok": true, "note": done}, nil
	}
	q, err := t.a.store.imageQuota(ctx, t.uid, t.wall)
	if err != nil {
		return nil, err
	}
	if q.used >= q.limit {
		return t.over(q.runKm, q.used, q.limit), nil
	}
	resp, err := t.a.imageGen.Image(ctx, funImageParts(prompt, stringValue(call.Args["style"]), t.photo))
	if errors.Is(err, errAgentOverBudget) {
		return nil, err
	}
	if err != nil {
		slog.WarnContext(ctx, "agent.image_failed", "uid", t.uid, "key", t.key, "error", err)
		return map[string]any{"ok": false, "reason": "vẽ hỏng, xin lỗi và bảo thử lại sau"}, nil
	}
	img := imageFromResponse(resp)
	if len(img) == 0 {
		slog.WarnContext(ctx, "agent.image_empty", "uid", t.uid, "key", t.key)
		return map[string]any{"ok": false, "reason": "model không vẽ ảnh này, có thể do nội dung; gợi ý đổi ý khác"}, nil
	}
	path := fmt.Sprintf("users/%s/agentImages/%s.png", t.uid, t.key)
	if err := t.a.imageStore.Put(ctx, path, img); err != nil {
		return nil, err
	}
	used, ok, err := t.commit(ctx, q.limit, path, prompt)
	if err != nil {
		return nil, err
	}
	if !ok {
		// Lượt khác của cùng bot vừa dùng hết hạn mức trong lúc vẽ.
		return t.over(q.runKm, used, q.limit), nil
	}
	slog.InfoContext(ctx, "agent.image", "uid", t.uid, "key", t.key, "used", used, "limit", q.limit)
	return map[string]any{"ok": true, "note": done, "usedToday": used, "limitToday": q.limit}, nil
}

// agentImageQuota là hạn mức ảnh hôm nay (giờ VN) của một bot.
type agentImageQuota struct {
	runKm       float64
	used, limit int64
}

// ImagesToday là lượt vẽ ảnh hôm nay của bot uid cho GET me. Chỉ đọc
// Firestore, vì api không dựng AgentService (không có Vertex AI); việc vẽ thật
// chạy trên service bot.
func (s *AgentStore) ImagesToday(ctx context.Context, uid string, wall time.Time) (*AgentImagesToday, error) {
	q, err := s.imageQuota(ctx, uid, wall)
	if err != nil {
		return nil, err
	}
	out := &AgentImagesToday{Used: q.used, Limit: q.limit, RunKm: q.runKm}
	if km, images, ok := agentImageNextTier(q.runKm); ok {
		out.NextKm, out.NextLimit = &km, &images
	}
	return out, nil
}

// imageQuota đọc km chủ chạy và đi bộ hôm nay và số ảnh bot đã vẽ hôm nay.
func (s *AgentStore) imageQuota(ctx context.Context, uid string, wall time.Time) (agentImageQuota, error) {
	runKm, err := s.todayKm(ctx, uid, wall)
	if err != nil {
		return agentImageQuota{}, err
	}
	agent, err := getData(ctx, s.agentRef(uid))
	if err != nil {
		return agentImageQuota{}, err
	}
	return agentImageQuota{runKm: runKm, used: imagesUsedToday(agent, wall), limit: agentImageLimit(runKm)}, nil
}

// commit ghi ảnh của tin và tăng số ảnh trong ngày trong cùng transaction, nên
// hạn mức không bị vượt dù hai lượt vẽ cùng lúc. Ảnh của tin đã có (lượt chạy
// lại song song) thì dùng ảnh đó, không đếm lại.
func (t *agentImageTurn) commit(ctx context.Context, limit int64, path, prompt string) (used int64, ok bool, err error) {
	agentRef, imgRef := t.a.store.agentRef(t.uid), t.ref()
	err = t.a.store.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		ok = false
		img, err := getOptional(tx, imgRef)
		if err != nil {
			return err
		}
		agent, err := tx.Get(agentRef)
		if err != nil {
			return err
		}
		used = imagesUsedToday(agent.Data(), t.wall)
		if img.Exists() {
			path, ok = stringValue(img.Data()["storagePath"]), true
			return nil
		}
		if used >= limit {
			return nil
		}
		used, ok = used+1, true
		if err := tx.Create(imgRef, map[string]any{"storagePath": path, "prompt": prompt, "day": vnDay(t.wall), "at": t.wall}); err != nil {
			return err
		}
		return tx.Update(agentRef, []firestore.Update{{Path: "imgDay", Value: vnDay(t.wall)}, {Path: "imgDayCount", Value: used}})
	})
	if ok {
		t.path = path
	}
	return used, ok, err
}

// over là kết quả hết lượt vẽ: lý do kèm mốc km kế tiếp để bot giục chủ chạy.
// Không được nói số của chủ thì bỏ số km đã chạy.
func (t *agentImageTurn) over(runKm float64, used, limit int64) map[string]any {
	ran := fmt.Sprintf("chủ hôm nay mới chạy và đi bộ %.1f km", runKm)
	if !t.showKm {
		ran = "km chạy và đi bộ hôm nay của chủ chưa đủ"
	}
	nextKm, nextImages, more := agentImageNextTier(runKm)
	var reason string
	switch {
	case limit == 0:
		reason = fmt.Sprintf("Chưa được vẽ: %s. Chạy hay đi bộ đủ %.0f km thì mở %d ảnh hôm nay.", ran, nextKm, nextImages)
	case more:
		reason = fmt.Sprintf("Hôm nay đã vẽ đủ %d ảnh. Chạy hay đi bộ đủ %.0f km thì được %d ảnh.", used, nextKm, nextImages)
		if t.showKm {
			reason += fmt.Sprintf(" Hiện %s.", ran)
		}
	default:
		reason = fmt.Sprintf("Hôm nay đã vẽ đủ %d ảnh, mức cao nhất; mai vẽ tiếp.", used)
	}
	out := map[string]any{"ok": false, "reason": reason, "usedToday": used, "limitToday": limit}
	if t.showKm {
		out["runKmToday"] = runKm
	}
	return out
}

// imagesUsedToday là số ảnh bot đã vẽ hôm nay (giờ VN), đọc trên doc bot.
func imagesUsedToday(agent map[string]any, wall time.Time) int64 {
	if stringValue(agent["imgDay"]) != vnDay(wall) {
		return 0
	}
	return int64(number(agent["imgDayCount"]))
}

// withImageNote đánh dấu tin có kèm ảnh khi đưa vào lịch sử cho model, để
// model biết mình đã gửi ảnh và tin chỉ có ảnh không thành phần chữ rỗng.
func withImageNote(text, imagePath string) string {
	if imagePath == "" {
		return text
	}
	return strings.TrimSpace(agentImageNote + " " + text)
}
