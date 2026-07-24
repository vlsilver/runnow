package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// botSystemPrompt định hình tính cách và, quan trọng hơn, các ràng buộc.
//
// Dòng cấm bịa số là dòng đáng giá nhất ở đây: model rất sẵn lòng dựng ra
// một con số nghe hợp lý khi tool trả về rỗng, và trong một group chạy bộ
// thì một thành tích bịa sẽ được tin ngay và lan đi.
const botSystemPrompt = `Bạn là trợ lý của nhóm chạy bộ 3i Run trong group Telegram.

Tính cách: một đàn anh chạy bộ lâu năm. Nói ngắn, tự nhiên như người Việt nhắn
tin, hài hước có duyên, biết cà khịa nhẹ để giữ không khí vui. Không lên lớp,
không sáo rỗng, không dùng emoji tràn lan.

VỀ APP 3i RUN (dùng đúng thông tin dưới đây khi ai hỏi, KHÔNG bịa thêm):
- Tên "3i" viết tắt của INTENT · IMPROVE · INVOLVE (Ý chí · Tiến bộ · Gắn kết).
- 3i Run là app của cộng đồng chạy bộ: biến những buổi chạy lẻ của từng người
  thành hành trình chung của cả nhóm.
- Tính năng chính:
  • Kèo chạy: chốt mục tiêu cùng nhóm (quãng đường, số buổi), tiến độ tự cập nhật.
  • Bảng xếp hạng câu lạc bộ theo tuần/tháng: quãng đường, số buổi, độ đều, pace,
    buổi dài nhất.
  • Hành trình: mỗi km tích vào một cung đường có thật — Marathon Athens, Tour du
    Mont Blanc, Xuyên Việt (Lũng Cú đến Đất Mũi).
  • Chỉ số sức mạnh: một điểm 0–100 gói gọn phong độ.
  • Ghi buổi chạy bằng GPS, đồng bộ tự động từ Strava.
  • Giao diện theo ngũ hành Kim Mộc Thuỷ Hoả Thổ, có sáng/tối.
- App miễn phí, có trên App Store, đang phát triển thêm.
- Nếu ai hỏi thứ ngoài danh sách này (giá gói, ngày ra mắt tính năng mới, kế
  hoạch...) thì nói thẳng là chưa rõ, đừng đoán.

Quy tắc bắt buộc:
- CHỈ nói những con số THÀNH TÍCH lấy được từ tool. TUYỆT ĐỐI không bịa, không ước
  lượng, không suy ra số liệu không có trong kết quả tool.
- Tool trả về rỗng hoặc không tìm thấy thì nói thẳng là chưa có dữ liệu.
- Câu hỏi về app hoặc tán gẫu không cần số liệu thì trả lời trực tiếp, đừng gọi tool.
- Tối đa 4 câu. Ngắn hơn thì càng tốt.
- Chỉ nhắc tên thành viên mà tool trả về.`

// BotService nối Telegram với Gemini và bộ tool Firestore.
type BotService struct {
	genai    *genai.Client
	telegram *TelegramService
	tools    *BotTools
	db       *firestore.Client
	model    string
	hourly   int
}

func NewBotService(gc *genai.Client, telegram *TelegramService, tools *BotTools, db *firestore.Client, model string, hourlyLimit int) *BotService {
	return &BotService{genai: gc, telegram: telegram, tools: tools, db: db, model: model, hourly: hourlyLimit}
}

func (s *BotService) Enabled() bool { return s != nil && s.genai != nil && s.telegram.Enabled() }

// toolDeclarations là bề mặt duy nhất model nhìn thấy về dữ liệu.
//
// Description viết theo kiểu "dùng khi nào", không chỉ "làm gì" — đó là thứ
// quyết định model có gọi đúng tool hay không.
func (s *BotService) toolDeclarations() []*genai.Tool {
	period := &genai.Schema{
		Type:        genai.TypeString,
		Enum:        []string{"week", "month", "rolling7"},
		Description: "Kỳ thống kê: week = tuần này, month = tháng này, rolling7 = 7 ngày qua. Mặc định week.",
	}
	return []*genai.Tool{{FunctionDeclarations: []*genai.FunctionDeclaration{
		{
			Name:        "get_leaderboard",
			Description: "Bảng xếp hạng thành viên club. Dùng khi hỏi ai chạy nhiều nhất, ai đứng đầu, ai chăm nhất, xếp hạng, so sánh cả nhóm.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"period": period,
					"metric": {
						Type:        genai.TypeString,
						Enum:        []string{"distance", "sessions", "activeDays", "longest", "pace"},
						Description: "Tiêu chí: distance = tổng km, sessions = số buổi, activeDays = số ngày có chạy, longest = buổi dài nhất, pace = tốc độ tốt nhất.",
					},
					"limit": {Type: genai.TypeInteger, Description: "Số người trả về, mặc định 5. Hỏi 'ai nhất' thì để 3 để có cái mà so."},
				},
				Required: []string{"period", "metric"},
			},
		},
		{
			Name:        "get_member_stats",
			Description: "Chỉ số của MỘT thành viên. Chỉ dùng khi câu hỏi nhắc tới tên riêng cụ thể.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"name":   {Type: genai.TypeString, Description: "Tên hoặc một phần tên thành viên."},
					"period": period,
				},
				Required: []string{"name"},
			},
		},
		{
			Name:        "get_club_summary",
			Description: "Tổng kết cả club trong kỳ: tổng km, tổng số buổi, bao nhiêu người có chạy. Dùng khi hỏi chung về tình hình nhóm.",
			Parameters: &genai.Schema{
				Type:       genai.TypeObject,
				Properties: map[string]*genai.Schema{"period": period},
			},
		},
		{
			Name:        "get_run_contracts",
			Description: "Các kèo chạy đang diễn ra và tiến độ. Dùng khi hỏi về kèo, thử thách, mục tiêu nhóm.",
			Parameters:  &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{}},
		},
	}}}
}

func (s *BotService) dispatch(ctx context.Context, name string, args map[string]any) (any, error) {
	switch name {
	case "get_leaderboard":
		return s.tools.GetLeaderboard(ctx, args)
	case "get_member_stats":
		return s.tools.GetMemberStats(ctx, args)
	case "get_club_summary":
		return s.tools.GetClubSummary(ctx, args)
	case "get_run_contracts":
		return s.tools.GetRunContracts(ctx, args)
	}
	return nil, fmt.Errorf("tool không tồn tại: %s", name)
}

// maxToolRounds chặn vòng lặp vô hạn nếu model cứ gọi tool mãi không chốt.
const maxToolRounds = 4

// botHistoryLimit là số tin (cả hỏi lẫn đáp) nạp lại làm ngữ cảnh.
const botHistoryLimit = 50

// Answer chạy vòng lặp gọi tool rồi trả về câu trả lời cuối.
//
// SDK Go chưa có tool runner tự động như bản Python/TypeScript nên vòng lặp
// này phải tự viết: gọi model, nếu model đòi tool thì chạy tool, nhét kết
// quả vào lịch sử, gọi lại — tới khi model trả về chữ. Nhận sẵn contents
// (lịch sử + câu hỏi hiện tại) để phần nạp lịch sử tách khỏi vòng lặp tool.
func (s *BotService) Answer(ctx context.Context, contents []*genai.Content) (string, error) {
	config := &genai.GenerateContentConfig{
		SystemInstruction: &genai.Content{Parts: []*genai.Part{{Text: botSystemPrompt}}},
		Tools:             s.toolDeclarations(),
	}

	for round := 0; round < maxToolRounds; round++ {
		resp, err := s.generateWithRetry(ctx, contents, config)
		if err != nil {
			return "", err
		}
		if len(resp.Candidates) == 0 || resp.Candidates[0].Content == nil {
			return "", fmt.Errorf("model trả về rỗng")
		}
		modelContent := resp.Candidates[0].Content
		calls := resp.FunctionCalls()
		if len(calls) == 0 {
			if text := strings.TrimSpace(resp.Text()); text != "" {
				return text, nil
			}
			return "", fmt.Errorf("model không trả về nội dung")
		}

		contents = append(contents, modelContent)
		results := make([]*genai.Part, 0, len(calls))
		for _, call := range calls {
			out, err := s.dispatch(ctx, call.Name, call.Args)
			if err != nil {
				// Trả lỗi vào cho model thay vì bỏ cuộc: nó thường tự
				// sửa tham số và gọi lại đúng ở vòng sau.
				slog.WarnContext(ctx, "bot.tool_failed", "tool", call.Name, "error", err)
				out = map[string]any{"error": err.Error()}
			}
			results = append(results, genai.NewPartFromFunctionResponse(call.Name, toJSONMap(out)))
		}
		contents = append(contents, &genai.Content{Role: genai.RoleUser, Parts: results})
	}
	return "", fmt.Errorf("model gọi tool quá %d vòng mà chưa trả lời", maxToolRounds)
}

// generateWithRetry thử lại khi Vertex trả 429.
//
// Vertex chạy trên capacity dùng chung (`ON_DEMAND`), thỉnh thoảng hết chỗ
// dù mình chưa vượt quota — đã gặp khi test tay. Không retry thì bot im
// lặng không rõ lý do.
func (s *BotService) generateWithRetry(ctx context.Context, contents []*genai.Content, config *genai.GenerateContentConfig) (*genai.GenerateContentResponse, error) {
	delay := 400 * time.Millisecond
	var lastErr error
	for attempt := 0; attempt < 3; attempt++ {
		resp, err := s.genai.Models.GenerateContent(ctx, s.model, contents, config)
		if err == nil {
			return resp, nil
		}
		lastErr = err
		if !isRetryableGenAIError(err) {
			return nil, err
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(delay):
		}
		delay *= 2
	}
	return nil, lastErr
}

func isRetryableGenAIError(err error) bool {
	msg := err.Error()
	return strings.Contains(msg, "429") ||
		strings.Contains(msg, "RESOURCE_EXHAUSTED") ||
		strings.Contains(msg, "503") ||
		strings.Contains(msg, "UNAVAILABLE")
}

// toJSONMap ép kết quả tool về map để SDK serialize được.
func toJSONMap(v any) map[string]any {
	if m, ok := v.(map[string]any); ok {
		return m
	}
	raw, err := json.Marshal(v)
	if err != nil {
		return map[string]any{"error": err.Error()}
	}
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		return map[string]any{"result": string(raw)}
	}
	return out
}

// allowChat đếm số câu hỏi mỗi group theo từng giờ.
//
// Bộ đếm phải nằm ở Firestore chứ không phải trong bộ nhớ: Cloud Run chạy
// nhiều instance và tự scale, đếm cục bộ thì mỗi instance có hạn mức riêng
// và tổng vượt xa giới hạn. Transaction để hai tin nhắn đến cùng lúc không
// cùng đọc ra một giá trị cũ.
func (s *BotService) allowChat(ctx context.Context, chatID string) (bool, error) {
	hour := time.Now().UTC().Format("2006010215")
	ref := s.db.Collection("botRateLimits").Doc(chatID + ":" + hour)
	allowed := false
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		count := int64(0)
		snap, err := tx.Get(ref)
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		if err == nil {
			count = int64(number(snap.Data()["count"]))
		}
		if count >= int64(s.hourly) {
			allowed = false
			return nil
		}
		allowed = true
		return tx.Set(ref, map[string]any{
			"count":     count + 1,
			"chatId":    chatID,
			"updatedAt": firestore.ServerTimestamp,
			// TTL dọn rác: bộ đếm hết giờ là vô dụng.
			"expiresAt": time.Now().Add(3 * time.Hour),
		}, firestore.MergeAll)
	})
	return allowed, err
}

// historyMessages truy vấn subcollection tin của một group.
func (s *BotService) historyRef(chatID string) *firestore.CollectionRef {
	return s.db.Collection("botConversations").Doc(chatID).Collection("botMessages")
}

// loadHistory nạp botHistoryLimit tin gần nhất, xếp theo thời gian tăng dần
// và bỏ tuỳ hoà.
//
// Firestore chỉ order được giảm dần từ mới nhất, nên phải đảo lại. Và lịch
// sử phải mở đầu bằng lượt "user" — Gemini từ chối chuỗi bắt đầu bằng lượt
// model — nên cắt các lượt model dư ở đầu.
func (s *BotService) loadHistory(ctx context.Context, chatID string) ([]*genai.Content, error) {
	docs, err := s.historyRef(chatID).
		OrderBy("createdAt", firestore.Desc).
		Limit(botHistoryLimit).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	rows := make([]map[string]any, len(docs))
	for i, d := range docs {
		rows[i] = d.Data()
	}
	return buildHistoryContents(rows), nil
}

// buildHistoryContents biến các doc (thứ tự mới→cũ như Firestore trả) thành
// chuỗi content cũ→mới, hợp lệ với Gemini.
func buildHistoryContents(rowsNewestFirst []map[string]any) []*genai.Content {
	contents := make([]*genai.Content, 0, len(rowsNewestFirst))
	for i := len(rowsNewestFirst) - 1; i >= 0; i-- {
		data := rowsNewestFirst[i]
		role := stringValue(data["role"])
		text := stringValue(data["text"])
		if text == "" || (role != genai.RoleUser && role != genai.RoleModel) {
			continue
		}
		// Gắn tên người hỏi vào lượt user để model biết ai đang nói.
		if role == genai.RoleUser {
			if name := stringValue(data["name"]); name != "" {
				text = name + ": " + text
			}
		}
		contents = append(contents, &genai.Content{Role: role, Parts: []*genai.Part{{Text: text}}})
	}
	// Gemini từ chối chuỗi mở đầu bằng lượt model — cắt các lượt dư ở đầu.
	for len(contents) > 0 && contents[0].Role != genai.RoleUser {
		contents = contents[1:]
	}
	return contents
}

// saveExchange lưu lại đúng một cặp hỏi–đáp.
//
// Chỉ lưu chữ, KHÔNG lưu các lượt gọi tool: câu hỏi mới phải truy vấn dữ
// liệu tươi (bảng xếp hạng đổi mỗi ngày), nên nhồi kết quả tool cũ vào lịch
// sử vừa thừa vừa dễ khiến model bám số liệu lỗi thời. Ngữ cảnh cần giữ chỉ
// là mạch trò chuyện.
//
// Hai tin cách nhau 1ms để thứ tự user-trước-model luôn ổn định khi order
// theo createdAt.
func (s *BotService) saveExchange(ctx context.Context, chatID, name, question, answer string) error {
	col := s.historyRef(chatID)
	now := time.Now().UTC()
	expires := now.Add(30 * 24 * time.Hour)
	if _, _, err := col.Add(ctx, map[string]any{
		"role": genai.RoleUser, "name": name, "text": question,
		"createdAt": now, "expiresAt": expires,
	}); err != nil {
		return err
	}
	_, _, err := col.Add(ctx, map[string]any{
		"role": genai.RoleModel, "text": answer,
		"createdAt": now.Add(time.Millisecond), "expiresAt": expires,
	})
	return err
}

// HandleMessage xử lý một tin nhắn đã được lọc là có nhắc tới bot.
func (s *BotService) HandleMessage(ctx context.Context, chatID, name, question string) error {
	if !s.Enabled() {
		return nil
	}
	question = strings.TrimSpace(question)
	if question == "" {
		return nil
	}
	allowed, err := s.allowChat(ctx, chatID)
	if err != nil {
		return err
	}
	if !allowed {
		slog.InfoContext(ctx, "bot.rate_limited", "chatId", chatID)
		return nil
	}

	// Lịch sử hỏng thì vẫn trả lời được, chỉ là mất ngữ cảnh — không đáng để
	// chặn cả câu trả lời.
	history, err := s.loadHistory(ctx, chatID)
	if err != nil {
		slog.WarnContext(ctx, "bot.history_load_failed", "error", err)
		history = nil
	}
	currentText := question
	if name != "" {
		currentText = name + ": " + question
	}
	contents := append(history, &genai.Content{Role: genai.RoleUser, Parts: []*genai.Part{{Text: currentText}}})

	answer, err := s.Answer(ctx, contents)
	if err != nil {
		slog.ErrorContext(ctx, "bot.answer_failed", "error", err)
		// Im lặng còn hơn phun stack trace vào group.
		answer = "Đang bị đơ tí, thử lại sau nhé."
	}
	if err := s.telegram.SendChatMessage(ctx, chatID, answer); err != nil {
		return err
	}
	// Lưu sau khi gửi thành công. Lưu trước mà gửi hỏng thì lịch sử có câu
	// trả lời người dùng chưa từng thấy.
	if saveErr := s.saveExchange(ctx, chatID, name, question, answer); saveErr != nil {
		slog.WarnContext(ctx, "bot.history_save_failed", "error", saveErr)
	}
	return nil
}
