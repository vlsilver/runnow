package backend

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// Tranh của thẻ buổi chạy: chủ thẻ chọn một phong cách (và tuỳ chọn một ảnh),
// Gemini vẽ một lần nền 2:3 cho mặt trước, app vẽ khung, bậc và chữ đè lên.
// Vẽ xong thì phong cách và tranh cố định; vẽ hỏng thì chọn lại được.
//
// api chỉ khoá trạng thái "drawing" trên doc thẻ rồi đẩy task, vì api không có
// Gemini; bot nhận task, vẽ, lưu file và ghi "done" hay "failed". App nghe doc
// thẻ để thấy kết quả.
//
//	art.status       drawing | done | failed
//	art.attempt      tăng mỗi lần khoá; task mang attempt, lệch thì bỏ
//	art.reason       lý do hỏng: budget, blocked, model_error, photo_missing, style_unavailable
//	art.path         users/{uid}/runCards/{activityId}/art-{attempt}.png khi done;
//	                 mỗi lượt một tên vì app cache ảnh theo đường dẫn
//
// Mọi lượt vẽ đi qua trần chi phí ngày riêng runCardArtDailyBudgetUsd.
//
// Số lần vẽ lại một thẻ hỏng không có giới hạn, theo thẻ hay theo người đều
// không. Một người cứ vẽ lại ảnh bị model từ chối thì tiêu được hết trần chung,
// và mọi người khác không vẽ được tới 0h. Chấp nhận vì lúc này ít người dùng, mỗi
// lần vẽ phải qua hộp xác nhận, và mất nhiều nhất là trần một ngày. Muốn chặn
// thì giới hạn art.attempt trong RequestArt.

var runCardArtPool = budgetPool{
	capKey: "runCardArtDailyBudgetUsd", capDefault: 10, usageDoc: "runCardArtUsage",
	hitText: "Vẽ thẻ buổi chạy chạm trần chi phí hôm nay (%s): đã tiêu %.2f USD, trần %.2f USD. Lượt vẽ mới báo hết lượt tới 0h giờ VN. Muốn mở lại thì nâng trần vẽ thẻ trên trang Admin.",
}

// NewRunCardArtBudget là trần chi phí của việc vẽ thẻ.
func NewRunCardArtBudget(db *firestore.Client, notify func(ctx context.Context, text string) error) *AgentBudget {
	return &AgentBudget{db: db, notify: notify, pool: runCardArtPool}
}

const (
	runCardArtQueuePath = "/tasks/run-card-art"
	// runCardArtStale: khoá "drawing" quá lâu thì coi như task đã mất, cho khoá lại.
	runCardArtStale = 3 * time.Minute
	// runCardArtTimeout là thời gian tối đa của một lượt gọi model ảnh.
	runCardArtTimeout  = 120 * time.Second
	runCardArtAspect   = "2:3"
	runCardArtSrcPhoto = "src.jpg"
)

var (
	errRunCardNoCard     = &HTTPError{Status: http.StatusNotFound, Code: "card_not_found", Message: "Buổi này chưa lật thẻ."}
	errRunCardBadStyle   = &HTTPError{Status: http.StatusBadRequest, Code: "invalid_style", Message: "Phong cách này không có hoặc đã tắt."}
	errRunCardBadPhoto   = &HTTPError{Status: http.StatusBadRequest, Code: "invalid_photo", Message: "Chỉ dùng được ảnh của buổi chạy này hoặc ảnh bạn vừa tải lên cho thẻ."}
	errRunCardArtFixed   = &HTTPError{Status: http.StatusConflict, Code: "art_fixed", Message: "Thẻ đã có tranh, không vẽ lại được."}
	errRunCardArtDrawing = &HTTPError{Status: http.StatusConflict, Code: "art_drawing", Message: "Thẻ đang được vẽ."}
	errRunCardLongNote   = &HTTPError{Status: http.StatusBadRequest, Code: "note_too_long", Message: fmt.Sprintf("Mô tả thêm tối đa %d ký tự.", runCardArtNoteMax)}
)

func runCardArtPath(uid, activityID, file string) string {
	return fmt.Sprintf("users/%s/runCards/%s/%s", uid, activityID, file)
}

type RunCardArtRequest struct {
	Style     string `json:"style"`
	PhotoPath string `json:"photoPath"`
	// Note là mô tả thêm của chủ thẻ, tuỳ chọn; xem runCardArtNote.
	Note string `json:"note"`
}

// runCardArtNoteMax là số ký tự (rune) tối đa của mô tả thêm; app đếm cùng cách.
const runCardArtNoteMax = 200

// runCardArtNote gộp mọi khoảng trắng, kể cả xuống dòng, thành một dấu cách để
// mô tả nằm gọn một câu trong prompt. Dài quá thì từ chối chứ không cắt, vì cắt
// giữa chừng làm sai ý người viết.
func runCardArtNote(raw string) (string, error) {
	note := strings.Join(strings.Fields(raw), " ")
	if utf8.RuneCountInString(note) > runCardArtNoteMax {
		return "", errRunCardLongNote
	}
	return note, nil
}

type runCardArtTask struct {
	UID        string `json:"uid"`
	ActivityID string `json:"activityId"`
	Attempt    int64  `json:"attempt"`
}

func runCardArtTaskFor(t runCardArtTask) PublishTask {
	return PublishTask{Queue: QueueBotInbound, HandlerPath: runCardArtQueuePath, Payload: t, TaskID: StableTaskID("run-card-art", t)}
}

// runCardArtJSON đổi giờ trong art sang chuỗi cho app.
func runCardArtJSON(art map[string]any) map[string]any {
	out := cloneMap(art)
	for _, k := range []string{"requestedAt", "doneAt", "failedAt"} {
		if t, ok := art[k].(time.Time); ok {
			out[k] = t.UTC().Format(time.RFC3339Nano)
		}
	}
	return out
}

// checkPhoto nhận ảnh nguồn: ảnh chủ thẻ tải lên cho thẻ này, hoặc một ảnh của
// buổi chạy. Ảnh của người khác hay file bất kỳ trong bucket thì không.
func (s *RunCardStore) checkPhoto(ctx context.Context, uid, activityID, path string) error {
	if path == "" || path == runCardArtPath(uid, activityID, runCardArtSrcPhoto) {
		return nil
	}
	act, err := getData(ctx, s.activityRef(uid, activityID))
	if err != nil {
		return err
	}
	for _, p := range anyList(act["photos"]) {
		m, _ := p.(map[string]any)
		if stringValue(m["storagePath"]) == path {
			return nil
		}
	}
	return errRunCardBadPhoto
}

// RequestArt khoá thẻ để vẽ rồi đẩy task cho bot. Gửi lại cùng phong cách khi
// đang vẽ hay đã vẽ xong thì trả thẻ như cũ; khi đang vẽ thì đẩy lại cùng task
// (Cloud Tasks bỏ bản trùng theo TaskID), nên lần đẩy trước hỏng vẫn có task.
func (s *RunCardStore) RequestArt(ctx context.Context, uid, activityID string, req RunCardArtRequest, enqueue taskPublishFunc) (map[string]any, error) {
	style, ok := artStyleFor(req.Style, artKindRun)
	if !ok {
		return nil, errRunCardBadStyle
	}
	note, err := runCardArtNote(req.Note)
	if err != nil {
		return nil, err
	}
	if err := s.checkPhoto(ctx, uid, activityID, req.PhotoPath); err != nil {
		return nil, err
	}
	ref := s.cardRef(uid, activityID)
	var card map[string]any
	var task *runCardArtTask
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		task = nil
		snap, err := getOptional(tx, ref)
		if err != nil {
			return err
		}
		if !snap.Exists() {
			return errRunCardNoCard
		}
		card = snap.Data()
		art, _ := card["art"].(map[string]any)
		attempt := int64(number(art["attempt"]))
		same := stringValue(art["style"]) == style.Key && stringValue(art["photoPath"]) == req.PhotoPath && stringValue(art["note"]) == note
		now := s.now()
		switch stringValue(art["status"]) {
		case "done":
			if stringValue(art["style"]) == style.Key {
				return nil
			}
			return errRunCardArtFixed
		case "drawing":
			if now.Sub(timeValue(art["requestedAt"])) < runCardArtStale {
				if !same {
					return errRunCardArtDrawing
				}
				task = &runCardArtTask{UID: uid, ActivityID: activityID, Attempt: attempt}
				return nil
			}
		}
		lock := map[string]any{"status": "drawing", "style": style.Key, "styleVersion": style.Version, "attempt": attempt + 1, "requestedAt": now}
		if req.PhotoPath != "" {
			lock["photoPath"] = req.PhotoPath
		}
		if note != "" {
			lock["note"] = note
		}
		card["art"] = lock
		task = &runCardArtTask{UID: uid, ActivityID: activityID, Attempt: attempt + 1}
		return tx.Update(ref, []firestore.Update{{Path: "art", Value: lock}})
	})
	if err != nil {
		return nil, err
	}
	if task != nil {
		if enqueue == nil {
			return nil, errors.New("run card art: chưa cấu hình hàng đợi task")
		}
		if _, err := enqueue(ctx, runCardArtTaskFor(*task)); err != nil {
			return nil, err
		}
	}
	return runCardJSON(activityID, card), nil
}

// photoMIME đoán loại ảnh gốc theo nội dung, vì máy chọn ảnh giữ nguyên PNG
// (ảnh chụp màn hình) chứ không đổi hết sang JPEG.
func photoMIME(b []byte) string {
	if t := http.DetectContentType(b); t == "image/png" || t == "image/webp" {
		return t
	}
	return "image/jpeg"
}

// runCardArtist vẽ tranh thẻ trên service bot.
type runCardArtist struct {
	store  *RunCardStore
	gen    agentImageLLM
	images agentImageStore
	model  string
}

// SetArtist bật vẽ tranh thẻ. Chỉ gọi trên service có Gemini (bot).
func (s *RunCardStore) SetArtist(gen agentImageLLM, images agentImageStore, model string) {
	s.artist = &runCardArtist{store: s, gen: gen, images: images, model: model}
}

// DrawArt chạy task vẽ. Task cũ (attempt lệch) hay thẻ không còn ở "drawing"
// thì bỏ. Model hỏng, bị chặn hay chạm trần thì ghi "failed" và không trả lỗi,
// để Cloud Tasks không gọi lại model; Firestore hay Storage lỗi thì trả lỗi để
// task chạy lại.
func (s *RunCardStore) DrawArt(ctx context.Context, t runCardArtTask) error {
	a := s.artist
	if a == nil {
		return errors.New("run card art: service này không vẽ được")
	}
	card, err := getData(ctx, s.cardRef(t.UID, t.ActivityID))
	if err != nil {
		return err
	}
	art, _ := card["art"].(map[string]any)
	if stringValue(art["status"]) != "drawing" || int64(number(art["attempt"])) != t.Attempt {
		return nil
	}
	i := slices.IndexFunc(artStyles, func(st artStyle) bool { return st.Key == stringValue(art["style"]) })
	if i < 0 {
		return s.finishArt(ctx, t, map[string]any{"status": "failed", "reason": "style_unavailable"})
	}
	style := artStyles[i]
	var photo []byte
	if path := stringValue(art["photoPath"]); path != "" {
		photo, err = a.images.Get(ctx, path)
		if errors.Is(err, errAgentImageMissing) {
			return s.finishArt(ctx, t, map[string]any{"status": "failed", "reason": "photo_missing"})
		}
		if err != nil {
			return err
		}
	}
	snapshot, _ := card["snapshot"].(map[string]any)
	prompt := runCardArtPrompt(snapshot, style, len(photo) > 0, stringValue(art["note"]))
	parts := []*genai.Part{}
	if len(photo) > 0 {
		parts = append(parts, &genai.Part{InlineData: &genai.Blob{MIMEType: photoMIME(photo), Data: photo}})
	}
	parts = append(parts, genai.NewPartFromText(prompt))
	drawCtx, cancel := context.WithTimeout(ctx, runCardArtTimeout)
	resp, err := a.gen.Image(withLLMLabel(drawCtx, "run_card_art", t.UID), parts)
	cancel()
	if errors.Is(err, errAgentOverBudget) {
		return s.finishArt(ctx, t, map[string]any{"status": "failed", "reason": "budget"})
	}
	if err != nil {
		slog.WarnContext(ctx, "run_card.art_failed", "uid", t.UID, "activityId", t.ActivityID, "style", style.Key, "error", err)
		return s.finishArt(ctx, t, map[string]any{"status": "failed", "reason": "model_error"})
	}
	img := imageFromResponse(resp)
	if len(img) == 0 {
		finish, block := imageRefusal(resp)
		slog.WarnContext(ctx, "run_card.art_blocked", "uid", t.UID, "activityId", t.ActivityID, "style", style.Key, "photo", len(photo) > 0, "finishReason", finish, "blockReason", block)
		return s.finishArt(ctx, t, map[string]any{"status": "failed", "reason": "blocked"})
	}
	path := runCardArtPath(t.UID, t.ActivityID, fmt.Sprintf("art-%d.png", t.Attempt))
	if err := a.images.Put(ctx, path, img); err != nil {
		return err
	}
	slog.InfoContext(ctx, "run_card.art", "uid", t.UID, "activityId", t.ActivityID, "style", style.Key, "photo", len(photo) > 0, "model", a.model)
	return s.finishArt(ctx, t, map[string]any{"status": "done", "path": path, "model": a.model, "prompt": prompt, "styleVersion": style.Version})
}

// finishArt ghi kết quả lên khoá đang giữ, nếu khoá vẫn là của task này.
func (s *RunCardStore) finishArt(ctx context.Context, t runCardArtTask, result map[string]any) error {
	ref := s.cardRef(t.UID, t.ActivityID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := getOptional(tx, ref)
		if err != nil || !snap.Exists() {
			return err
		}
		art, _ := snap.Data()["art"].(map[string]any)
		if stringValue(art["status"]) != "drawing" || int64(number(art["attempt"])) != t.Attempt {
			return nil
		}
		// Thẻ đang khoe thì tranh xong hiện luôn ở thẻ khoe.
		shared, err := getOptional(tx, s.clubCardRef(t.UID, t.ActivityID))
		if err != nil {
			return err
		}
		next := cloneMap(art)
		for k, v := range result {
			next[k] = v
		}
		if result["status"] == "done" {
			next["doneAt"] = s.now()
		} else {
			next["failedAt"] = s.now()
		}
		if err := tx.Update(ref, []firestore.Update{{Path: "art", Value: next}}); err != nil {
			return err
		}
		if shared.Exists() && clubCardArt(next) != nil {
			return tx.Update(shared.Ref, []firestore.Update{{Path: "art", Value: clubCardArt(next)}})
		}
		return nil
	})
}

// imageRefusal là lý do model không trả ảnh, để log.
func imageRefusal(resp *genai.GenerateContentResponse) (finish, block string) {
	if resp == nil {
		return "", ""
	}
	if resp.PromptFeedback != nil {
		block = string(resp.PromptFeedback.BlockReason)
	}
	if len(resp.Candidates) > 0 {
		finish = string(resp.Candidates[0].FinishReason)
	}
	return finish, block
}

// runCardArtPrompt ráp prompt vẽ nền thẻ. Không có ảnh thì vẽ cảnh buổi chạy:
// giờ trong ngày lấy từ giờ bắt đầu, quãng đường thành cảm giác chứ không thành
// số. Có ảnh thì vẽ lại ảnh theo phong cách, giữ người trong ảnh nhận ra được.
// Không đưa tên buổi chạy hay bậc thẻ vào prompt. note là mô tả thêm của chủ
// thẻ (đã qua runCardArtNote), nằm trước phong cách, bố cục và luật cấm chữ để
// mấy phần đó vẫn thắng khi mô tả đòi khác.
func runCardArtPrompt(snapshot map[string]any, style artStyle, photo bool, note string) string {
	if photo {
		return artPrompt(withRunnerNote("Transform the provided photograph into the art style described below. "+
			"Keep every person in it recognizable, with the same pose, body proportions, face, hairstyle and clothing colors; "+
			"if there is no person, keep the main subject and layout.", note), style,
			"Vertical composition. Keep the main subject in the middle of the frame; the top fifth and the bottom quarter stay calm and low-detail.")
	}
	started, _ := time.Parse(time.RFC3339, stringValue(snapshot["startedAt"]))
	// "scene" chứ không "illustration": chữ chỉ chất liệu ở đây kéo các phong
	// cách ảnh chụp, 3D, hologram về tranh minh hoạ; chất liệu để "Render it as" quyết.
	task := fmt.Sprintf("Create an image: a single full-bleed scene of a lone runner in mid-stride %s %s, capturing the feeling of %s.",
		runCardPlace(stringValue(snapshot["sportType"])), runCardTimeOfDay(started), runCardFeel(number(snapshot["distanceMeters"])))
	return artPrompt(withRunnerNote(task, note), style, "Vertical composition. The runner fills the middle of the frame; the top fifth is calm, open background and the bottom quarter is quiet, low-detail ground.")
}

// withRunnerNote nối mô tả thêm vào sau phần việc cần vẽ. Dấu " đổi thành ' để
// mô tả không đóng được đoạn trích.
func withRunnerNote(task, note string) string {
	if note == "" {
		return task
	}
	return task + ` Extra details from the runner, used only where they fit the art style below: "` + strings.ReplaceAll(note, `"`, "'") + `".`
}

func runCardPlace(sport string) string {
	switch sport {
	case "TrailRun":
		return "on a winding forest trail"
	case "VirtualRun":
		return "on a treadmill in a bright gym"
	}
	return "along a quiet open road"
}

func runCardTimeOfDay(t time.Time) string {
	if t.IsZero() {
		return "in soft daylight"
	}
	h := t.In(vietnam).Hour()
	switch {
	case h >= 4 && h < 6:
		return "at dawn"
	case h >= 6 && h < 10:
		return "in the early morning light"
	case h >= 10 && h < 15:
		return "in bright midday sun"
	case h >= 15 && h < 18:
		return "in warm late-afternoon light"
	case h >= 18 && h < 20:
		return "at dusk"
	}
	return "at night under streetlights"
}

func runCardFeel(meters float64) string {
	switch km := meters / 1000; {
	case km < 3:
		return "a short, brisk run"
	case km < 10:
		return "a steady run"
	case km < 21:
		return "a long run"
	case km < 42:
		return "a long-distance run"
	}
	return "an epic marathon-length run"
}
