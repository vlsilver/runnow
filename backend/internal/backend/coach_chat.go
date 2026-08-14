package backend

import (
	"context"
	"fmt"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/genai"
)

// Hỏi đáp riêng với AI Coach. Khác bot nhóm ở chỗ mọi câu trả lời đều đặt trong
// ngữ cảnh CỦA CHÍNH người hỏi: giáo án đang chạy (hoặc bản nháp chờ xác nhận)
// cộng lịch sử tập thật. Nhờ vậy "tuần này nặng quá làm sao" trả lời được bằng
// đúng số buổi trong lịch người đó, không phải lời khuyên chung.
//
// Lưu ở users/{uid}/coach/chat/messages/{id}, mỗi lượt hỏi và đáp là một doc.

const coachChatHistoryTurns = 12 // số lượt gần nhất đưa vào ngữ cảnh
const coachAnswerMaxChars = 1200 // chặn câu trả lời lê thê trên màn hình nhỏ

type coachMessage struct {
	Role string // "user" | "coach"
	Text string
}

const coachChatPrompt = `Bạn là HUẤN LUYỆN VIÊN CHẠY BỘ riêng của người này. Trả lời NGẮN, cụ thể, dựa
trên đúng giáo án và số liệu của họ bên dưới — không nói lời khuyên chung chung.

%s

%s

NGUYÊN TẮC TRẢ LỜI:
- Bám vào giáo án và số liệu ở trên. Nhắc tên buổi, số km, ngày cụ thể khi liên quan.
- Không có dữ liệu để trả lời thì nói thẳng là chưa đủ dữ liệu, đừng đoán.
- An toàn trước thành tích: đau bất thường, mệt kéo dài, chấn thương → khuyên nghỉ
  và đi khám, không khuyên cố.
- Bạn KHÔNG sửa được giáo án trong lúc trò chuyện. User muốn đổi lịch thì chỉ họ
  tạo giáo án mới ở màn Giáo án.
- Tối đa 6 câu. Tiếng Việt, xưng "mình", gọi người hỏi là "bạn".`

// AskCoach trả lời một câu hỏi của user trong ngữ cảnh giáo án của họ, rồi lưu
// cả câu hỏi lẫn câu trả lời vào lịch sử hội thoại.
func (s *BotService) AskCoach(ctx context.Context, uid, question string) (string, error) {
	if !s.Enabled() {
		return "", fmt.Errorf("bot chưa bật")
	}
	question = strings.TrimSpace(question)
	if question == "" {
		return "", fmt.Errorf("câu hỏi rỗng")
	}

	planCtx := s.coachPlanContext(ctx, uid)
	history := s.coachChatHistory(ctx, uid)

	prompt := fmt.Sprintf(coachChatPrompt, planCtx, formatCoachHistory(history, question))
	resp, err := s.genai.Models.GenerateContent(ctx, s.model,
		[]*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: prompt}}}}, nil)
	if err != nil {
		return "", fmt.Errorf("gemini: %w", err)
	}
	answer := strings.TrimSpace(resp.Text())
	if answer == "" {
		return "", fmt.Errorf("coach không trả lời được")
	}
	if len(answer) > coachAnswerMaxChars {
		answer = answer[:coachAnswerMaxChars]
	}

	// Ghi sau khi đã có câu trả lời: hỏi mà lỗi thì không để lại câu treo
	// trong lịch sử.
	msgs := s.db.Collection("users").Doc(uid).Collection("coach").
		Doc("chat").Collection("messages")
	now := time.Now()
	if _, _, err := msgs.Add(ctx, map[string]any{
		"role": "user", "text": question, "createdAt": now,
	}); err != nil {
		return answer, nil // trả lời được rồi thì đừng làm hỏng trải nghiệm vì lỗi ghi
	}
	_, _, _ = msgs.Add(ctx, map[string]any{
		"role": "coach", "text": answer, "createdAt": now.Add(time.Millisecond),
	})
	return answer, nil
}

// coachPlanContext tóm tắt giáo án đang chạy (ưu tiên) hoặc bản nháp chờ xác
// nhận, kèm phong độ gần đây. Chỉ đưa phần cần cho việc trả lời — cả 28 ngày
// dạng thô làm loãng ngữ cảnh mà không thêm được gì.
func (s *BotService) coachPlanContext(ctx context.Context, uid string) string {
	coach := s.db.Collection("users").Doc(uid).Collection("coach")
	var b strings.Builder

	doc, label := map[string]any(nil), ""
	if snap, err := coach.Doc("current").Get(ctx); err == nil && snap.Exists() {
		doc, label = snap.Data(), "GIÁO ÁN ĐANG CHẠY"
	} else if snap, err := coach.Doc("draft").Get(ctx); err == nil && snap.Exists() {
		doc, label = snap.Data(), "BẢN NHÁP CHỜ XÁC NHẬN (user chưa đồng ý)"
	}

	if doc == nil {
		b.WriteString("GIÁO ÁN: user chưa có giáo án nào.")
	} else {
		fmt.Fprintf(&b, "%s:\n", label)
		fmt.Fprintf(&b, "- Mục tiêu: %v\n", doc["goal"])
		if v := number(doc["goalDistanceKm"]); v > 0 {
			fmt.Fprintf(&b, "- Cự ly đích: %s\n", kmLabel(v))
		}
		if v := int(number(doc["targetPaceSec"])); v > 0 {
			fmt.Fprintf(&b, "- Pace đích: %s\n", fmtGoalPace(v))
		}
		fmt.Fprintf(&b, "- Dài %v tuần, từ %v tới %v\n", doc["weeks"], doc["startDate"], doc["targetDate"])
		if s, _ := doc["summary"].(string); s != "" {
			fmt.Fprintf(&b, "- Định hướng: %s\n", s)
		}
		if s, _ := doc["rationale"].(string); s != "" {
			fmt.Fprintf(&b, "- Lý do thiết kế: %s\n", s)
		}
		b.WriteString(coachUpcomingDays(doc, time.Now()))
	}

	h := s.gatherRunnerHistory(ctx, uid)
	fmt.Fprintf(&b, "\nPHONG ĐỘ GẦN ĐÂY:\n- 7 ngày: %s\n- Tháng này: %s trong %d ngày có chạy\n",
		kmLabel(h.weekKm), kmLabel(h.monthKm), h.activeDays)
	if h.avgPaceSec > 0 {
		fmt.Fprintf(&b, "- Pace trung bình: %d:%02d/km\n", h.avgPaceSec/60, h.avgPaceSec%60)
	}
	return strings.TrimRight(b.String(), "\n")
}

// coachUpcomingDays liệt kê buổi của tuần đang tập — đủ để trả lời "hôm nay
// chạy gì", "tuần này nặng không" mà không phải nhét cả giáo án vào prompt.
func coachUpcomingDays(doc map[string]any, now time.Time) string {
	raw, _ := doc["days"].([]any)
	start, err := time.Parse("2006-01-02", fmt.Sprint(doc["startDate"]))
	if err != nil || len(raw) == 0 {
		return ""
	}
	vn := time.FixedZone("Asia/Ho_Chi_Minh", 7*60*60)
	today := now.In(vn)
	todayIdx := int(today.Sub(start.In(vn)).Hours() / 24)

	from := todayIdx - 1 // hôm qua để trả lời "hôm qua chạy rồi thì hôm nay sao"
	if from < 0 {
		from = 0
	}
	to := from + 8
	if to > len(raw) {
		to = len(raw)
	}
	if from >= to {
		return ""
	}

	var b strings.Builder
	b.WriteString("- Các buổi quanh hôm nay:\n")
	for i := from; i < to; i++ {
		d, _ := raw[i].(map[string]any)
		if d == nil {
			continue
		}
		mark := "  "
		if i == todayIdx {
			mark = "→ " // HÔM NAY
		}
		line := fmt.Sprintf("%s%v %v · %v", mark, d["label"], d["type"], d["title"])
		if v := number(d["distanceKm"]); v > 0 {
			line += " · " + kmLabel(v)
		}
		if p, _ := d["paceHint"].(string); p != "" {
			line += " · pace " + p
		}
		if done, _ := d["done"].(bool); done {
			line += " (đã xong)"
		}
		b.WriteString(line + "\n")
	}
	return b.String()
}

// coachChatHistory đọc các lượt gần nhất, trả về theo thứ tự cũ → mới.
func (s *BotService) coachChatHistory(ctx context.Context, uid string) []coachMessage {
	it := s.db.Collection("users").Doc(uid).Collection("coach").
		Doc("chat").Collection("messages").
		OrderBy("createdAt", firestore.Desc).Limit(coachChatHistoryTurns).Documents(ctx)
	defer it.Stop()

	var out []coachMessage
	for {
		snap, err := it.Next()
		if err == iterator.Done || err != nil {
			break
		}
		d := snap.Data()
		text, _ := d["text"].(string)
		role, _ := d["role"].(string)
		if text == "" {
			continue
		}
		out = append(out, coachMessage{Role: role, Text: text})
	}
	// Firestore trả mới → cũ; prompt cần cũ → mới.
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

func formatCoachHistory(history []coachMessage, question string) string {
	var b strings.Builder
	if len(history) > 0 {
		b.WriteString("HỘI THOẠI TRƯỚC ĐÓ:\n")
		for _, m := range history {
			who := "Bạn"
			if m.Role == "coach" {
				who = "Coach"
			}
			fmt.Fprintf(&b, "%s: %s\n", who, m.Text)
		}
		b.WriteString("\n")
	}
	fmt.Fprintf(&b, "CÂU HỎI MỚI: %s", question)
	return b.String()
}
