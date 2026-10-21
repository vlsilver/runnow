package backend

import (
	"context"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// botSchedule là một lịch bot TỰ đặt để đăng vào group. Điểm cốt lõi chống
// spam: nó lưu một Ý ĐỊNH ("đến giờ này, cân nhắc đăng về X"), KHÔNG phải một
// tin cố định. Lúc tới hạn bot mới tự quyết có đăng hay không (xem
// generateScheduledPost) — nên tuần nào không có gì đáng nói thì tự bỏ qua.
type botSchedule struct {
	ID            string
	ChatID        string    // group để đăng vào (luôn là club group, kể cả tạo từ DM)
	Title         string    // nhãn ngắn cho người + để list/huỷ/tránh trùng
	Intent        string    // hướng dẫn sinh nội dung lúc tới hạn
	Kind          string    // "once" | "recurring"
	IntervalHours int       // khoảng lặp (24=ngày, 168=tuần); 0 nếu once
	RunAt         time.Time // mốc chạy kế
	Active        bool
	CreatedByName string
	PostCount     int
	MaxPosts      int       // 0 = không giới hạn (trong khoảng until)
	ExpiresAt     time.Time // hết hạn thì tự dọn (zero = không hạn)
	LastPostedAt  time.Time
}

// maxActiveSchedules chặn một chat đẻ vô hạn lịch.
const maxActiveSchedules = 12

type ScheduleStore struct{ db *firestore.Client }

func NewScheduleStore(db *firestore.Client) *ScheduleStore { return &ScheduleStore{db: db} }

func (s *ScheduleStore) col() *firestore.CollectionRef { return s.db.Collection("botSchedules") }

func (s *ScheduleStore) Create(ctx context.Context, sch botSchedule) (string, error) {
	doc := map[string]any{
		"chatId": sch.ChatID, "title": sch.Title, "intent": sch.Intent,
		"kind": sch.Kind, "intervalHours": sch.IntervalHours, "runAt": sch.RunAt,
		"active": true, "createdByName": sch.CreatedByName, "postCount": 0,
		"maxPosts": sch.MaxPosts, "createdAt": firestore.ServerTimestamp,
	}
	if !sch.ExpiresAt.IsZero() {
		doc["expiresAt"] = sch.ExpiresAt
	}
	ref, _, err := s.col().Add(ctx, doc)
	if err != nil {
		return "", err
	}
	return ref.ID, nil
}

func scheduleFromDoc(d *firestore.DocumentSnapshot) botSchedule {
	m := d.Data()
	sch := botSchedule{
		ID: d.Ref.ID, ChatID: stringValue(m["chatId"]), Title: stringValue(m["title"]),
		Intent: stringValue(m["intent"]), Kind: stringValue(m["kind"]),
		IntervalHours: int(number(m["intervalHours"])), Active: m["active"] == true,
		CreatedByName: stringValue(m["createdByName"]), PostCount: int(number(m["postCount"])),
		MaxPosts: int(number(m["maxPosts"])),
	}
	if t, ok := m["runAt"].(time.Time); ok {
		sch.RunAt = t
	}
	if t, ok := m["expiresAt"].(time.Time); ok {
		sch.ExpiresAt = t
	}
	if t, ok := m["lastPostedAt"].(time.Time); ok {
		sch.LastPostedAt = t
	}
	return sch
}

// Due trả các lịch active tới hạn. Chỉ lọc bằng inequality trên runAt (single
// field, tự index) rồi lọc active trong code → khỏi cần composite index.
func (s *ScheduleStore) Due(ctx context.Context, now time.Time) ([]botSchedule, error) {
	docs, err := s.col().Where("runAt", "<=", now).OrderBy("runAt", firestore.Asc).Limit(50).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]botSchedule, 0, len(docs))
	for _, d := range docs {
		if sch := scheduleFromDoc(d); sch.Active {
			out = append(out, sch)
		}
	}
	return out, nil
}

func (s *ScheduleStore) ListActive(ctx context.Context, chatID string) ([]botSchedule, error) {
	docs, err := s.col().Where("chatId", "==", chatID).Limit(50).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]botSchedule, 0, len(docs))
	for _, d := range docs {
		if sch := scheduleFromDoc(d); sch.Active {
			out = append(out, sch)
		}
	}
	return out, nil
}

// Cancel tắt (xoá) lịch khớp id hoặc một phần title trong group.
func (s *ScheduleStore) Cancel(ctx context.Context, chatID, query string) (int, error) {
	list, err := s.ListActive(ctx, chatID)
	if err != nil {
		return 0, err
	}
	q := strings.ToLower(strings.TrimSpace(query))
	n := 0
	for _, sch := range list {
		if sch.ID == query || (q != "" && strings.Contains(strings.ToLower(sch.Title), q)) {
			if _, err := s.col().Doc(sch.ID).Delete(ctx); err == nil {
				n++
			}
		}
	}
	return n, nil
}

// advance cập nhật lịch sau khi tick xử lý. once → xoá. recurring → dời runAt
// tới slot TƯƠNG LAI kế (bỏ qua slot đã lỡ để không dồn spam khi bot nghỉ lâu);
// quá hạn / đủ maxPosts thì xoá.
func (s *ScheduleStore) advance(ctx context.Context, sch botSchedule, posted bool, now time.Time) error {
	if sch.Kind != "recurring" {
		_, err := s.col().Doc(sch.ID).Delete(ctx)
		return err
	}
	interval := time.Duration(sch.IntervalHours) * time.Hour
	if interval <= 0 {
		interval = 24 * time.Hour
	}
	next := sch.RunAt.Add(interval)
	for !next.After(now) {
		next = next.Add(interval)
	}
	newCount := sch.PostCount
	if posted {
		newCount++
	}
	if (!sch.ExpiresAt.IsZero() && next.After(sch.ExpiresAt)) || (sch.MaxPosts > 0 && newCount >= sch.MaxPosts) {
		_, err := s.col().Doc(sch.ID).Delete(ctx)
		return err
	}
	update := map[string]any{"runAt": next, "lastRunAt": now, "postCount": newCount}
	if posted {
		update["lastPostedAt"] = now
	}
	_, err := s.col().Doc(sch.ID).Set(ctx, update, firestore.MergeAll)
	return err
}

// ---- BotService: tool xử lý lịch + vòng chạy lịch (tick) ----

// scheduledPostInstruction dạy bot tự quyết ĐĂNG hay BỎ QUA lúc lịch tới hạn.
// Đây là lá chắn spam ở thời điểm chạy.
const scheduledPostInstruction = `

NHIỆM VỤ: một lịch bạn đã đặt vừa tới giờ. Dựa trên Ý ĐỊNH của lịch + tình hình
nhóm hiện tại + những tin bạn VỪA đăng, hãy tự quyết:
- Nếu THẬT SỰ có gì đáng nói (đúng dịp, có nội dung tươi, không lặp lại tin vừa
  đăng) → viết đúng tin để đăng vào group, bằng giọng của bạn, sống động, 2-4 câu.
- Nếu chỉ là lấp chỗ, chưa tới lúc, hoặc lặp điều vừa nói → trả về ĐÚNG một từ:
  SKIP
Cần số liệu/thành tích thì gọi tool lấy số thật, không bịa. Chỉ trả về tin đăng
hoặc "SKIP", không lời dẫn.`

// RunDueSchedules chạy mọi lịch tới hạn (tick gọi). Lỗi một lịch không chặn
// các lịch khác.
func (s *BotService) RunDueSchedules(ctx context.Context, now time.Time) error {
	if !s.Enabled() || s.schedules == nil {
		return nil
	}
	due, err := s.schedules.Due(ctx, now)
	if err != nil {
		return err
	}
	for _, sch := range due {
		s.runOneSchedule(ctx, sch, now)
	}
	return nil
}

func (s *BotService) runOneSchedule(ctx context.Context, sch botSchedule, now time.Time) {
	if !sch.ExpiresAt.IsZero() && now.After(sch.ExpiresAt) {
		if err := s.schedules.advance(ctx, sch, false, now); err != nil {
			slog.WarnContext(ctx, "schedule.advance_failed", "id", sch.ID, "error", err)
		}
		return
	}
	text := s.generateScheduledPost(ctx, sch)
	posted := false
	if text != "" {
		// Trần đăng chủ động/ngày: dù bao nhiêu lịch, không vượt (chống spam cứng).
		allowed, err := s.allowDailyGlobal(ctx, "proactivePost", botDailyProactiveLimit)
		if err == nil && allowed {
			if sendErr := s.telegram.SendChatMessage(ctx, sch.ChatID, text); sendErr == nil {
				posted = true
				if recErr := s.RecordBroadcast(ctx, sch.ChatID, text); recErr != nil {
					slog.WarnContext(ctx, "schedule.record_failed", "error", recErr)
				}
			} else {
				slog.WarnContext(ctx, "schedule.send_failed", "id", sch.ID, "error", sendErr)
			}
		} else {
			slog.InfoContext(ctx, "schedule.proactive_capped", "id", sch.ID)
		}
	}
	if err := s.schedules.advance(ctx, sch, posted, now); err != nil {
		slog.WarnContext(ctx, "schedule.advance_failed", "id", sch.ID, "error", err)
	}
}

func (s *BotService) generateScheduledPost(ctx context.Context, sch botSchedule) string {
	now := time.Now().In(vietnam)
	desc := fmt.Sprintf("Ý ĐỊNH của lịch: %s\n(tiêu đề: %s)\nBÂY GIỜ (VN): %s (%s)",
		sch.Intent, sch.Title, now.Format("2006-01-02 15:04"), now.Weekday().String())
	// Nạp ĐẦY ĐỦ bộ nhớ dùng chung theo group để bot đăng đúng ngữ cảnh: trí
	// nhớ nhóm, các tin vừa đăng (tránh lặp), và các lịch khác đang đặt. Dữ
	// liệu thành tích thì bot tự gọi tool lấy tươi khi cần (vd tổng kết).
	systemPrompt := botSystemPrompt + scheduledPostInstruction
	if mem := s.memory.Load(ctx, sch.ChatID); mem != "" {
		systemPrompt += "\n\nTRÍ NHỚ NHÓM:\n" + mem
	}
	if recent := s.recentGroupPosts(ctx, sch.ChatID, 6); recent != "" {
		systemPrompt += "\n\nCÁC TIN BOT VỪA ĐĂNG GẦN ĐÂY (đừng lặp lại):\n" + recent
	}
	if sched := s.schedulesSummary(ctx, sch.ChatID); sched != "" {
		systemPrompt += "\n\nCÁC LỊCH KHÁC ĐANG ĐẶT (để không dẫm chân nhau):\n" + sched
	}
	contents := []*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: desc}}}}
	text, err := s.Answer(ctx, systemPrompt, contents, false)
	if err != nil {
		slog.WarnContext(ctx, "schedule.generate_failed", "id", sch.ID, "error", err)
		return ""
	}
	text = strings.TrimSpace(text)
	if text == "" || strings.EqualFold(text, "SKIP") || strings.HasPrefix(strings.ToUpper(text), "SKIP") {
		return ""
	}
	return text
}

// recentGroupPosts lấy vài tin bot đã đăng gần nhất (role=model) để tránh lặp.
func (s *BotService) recentGroupPosts(ctx context.Context, chatID string, n int) string {
	docs, err := s.historyRef(chatID).OrderBy("createdAt", firestore.Desc).Limit(30).Documents(ctx).GetAll()
	if err != nil {
		return ""
	}
	var b strings.Builder
	count := 0
	for _, d := range docs {
		data := d.Data()
		if stringValue(data["role"]) != genai.RoleModel {
			continue
		}
		if t := stringValue(data["text"]); t != "" {
			b.WriteString("- ")
			b.WriteString(t)
			b.WriteString("\n")
			if count++; count >= n {
				break
			}
		}
	}
	return strings.TrimSpace(b.String())
}

// schedulesSummary liệt kê lịch đang đặt của group — nạp vào ngữ cảnh DM để bot
// biết mình đã hẹn gì (tránh trùng khi tạo lịch mới, trả lời được "đã hẹn gì").
func (s *BotService) schedulesSummary(ctx context.Context, chatID string) string {
	list, err := s.schedules.ListActive(ctx, chatID)
	if err != nil || len(list) == 0 {
		return ""
	}
	var b strings.Builder
	for _, sch := range list {
		when := sch.RunAt.In(vietnam).Format("15:04 02/01")
		rec := "một lần"
		if sch.Kind == "recurring" {
			rec = fmt.Sprintf("lặp mỗi %dh", sch.IntervalHours)
		}
		fmt.Fprintf(&b, "- [%s] %s — kế: %s, %s\n", sch.ID, sch.Title, when, rec)
	}
	return strings.TrimSpace(b.String())
}

// ---- tool handlers (bot gọi trong lúc chat) ----

func (s *BotService) createScheduleTool(ctx context.Context, args map[string]any) (any, error) {
	title := strings.TrimSpace(stringValue(args["title"]))
	intent := strings.TrimSpace(stringValue(args["intent"]))
	if title == "" || intent == "" {
		return map[string]any{"created": false, "reason": "thiếu title hoặc intent"}, nil
	}
	runAtStr := strings.TrimSpace(stringValue(args["runAtISO"]))
	runAt, err := time.Parse(time.RFC3339, runAtStr)
	if err != nil {
		// Bot lỡ đưa thiếu offset (naive datetime) → HIỂU LÀ GIỜ VIỆT NAM (+7),
		// không từ chối và tuyệt đối không rơi về UTC (lệch 7 tiếng là toang).
		for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02T15:04", "2006-01-02 15:04"} {
			if runAt, err = time.ParseInLocation(layout, runAtStr, vietnam); err == nil {
				break
			}
		}
		if err != nil {
			return map[string]any{"created": false, "reason": "runAtISO không đọc được; đưa dạng 2006-01-02T15:04:05+07:00 (giờ VN)"}, nil
		}
	}
	kind, interval := "once", 0
	switch strings.ToLower(strings.TrimSpace(stringValue(args["recurrence"]))) {
	case "daily":
		kind, interval = "recurring", 24
	case "weekly":
		kind, interval = "recurring", 168
	case "", "once", "none":
	default:
		return map[string]any{"created": false, "reason": "recurrence chỉ nhận once/daily/weekly"}, nil
	}
	var expires time.Time
	if u := strings.TrimSpace(stringValue(args["untilISO"])); u != "" {
		if expires, err = time.Parse(time.RFC3339, u); err != nil {
			for _, layout := range []string{"2006-01-02T15:04:05", "2006-01-02T15:04", "2006-01-02 15:04", "2006-01-02"} {
				if expires, err = time.ParseInLocation(layout, u, vietnam); err == nil {
					break
				}
			}
		}
	}
	groupID := s.telegram.ChatID()
	existing, _ := s.schedules.ListActive(ctx, groupID)
	if len(existing) >= maxActiveSchedules {
		return map[string]any{"created": false, "reason": fmt.Sprintf("đã đạt trần %d lịch, huỷ bớt trước", maxActiveSchedules)}, nil
	}
	id, err := s.schedules.Create(ctx, botSchedule{
		ChatID: groupID, Title: title, Intent: intent, Kind: kind,
		IntervalHours: interval, RunAt: runAt, ExpiresAt: expires,
	})
	if err != nil {
		return nil, err
	}
	return map[string]any{"created": true, "id": id, "title": title,
		"runAt": runAt.In(vietnam).Format("15:04 02/01/2006"), "recurrence": kind}, nil
}

func (s *BotService) listSchedulesTool(ctx context.Context) (any, error) {
	groupID := s.telegram.ChatID()
	list, err := s.schedules.ListActive(ctx, groupID)
	if err != nil {
		return nil, err
	}
	out := make([]map[string]any, 0, len(list))
	for _, sch := range list {
		out = append(out, map[string]any{
			"id": sch.ID, "title": sch.Title,
			"runAt":      sch.RunAt.In(vietnam).Format("15:04 02/01/2006"),
			"recurrence": sch.Kind, "intervalHours": sch.IntervalHours,
		})
	}
	return map[string]any{"count": len(out), "schedules": out}, nil
}

func (s *BotService) cancelScheduleTool(ctx context.Context, args map[string]any) (any, error) {
	n, err := s.schedules.Cancel(ctx, s.telegram.ChatID(), strings.TrimSpace(stringValue(args["query"])))
	if err != nil {
		return nil, err
	}
	return map[string]any{"cancelled": n}, nil
}
