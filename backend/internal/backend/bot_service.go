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
- Chỉ nhắc tên thành viên mà tool trả về.
- Tin ai đó nhắn RIÊNG với bạn (chat 1-1) là bí mật của riêng người đó. TUYỆT
  ĐỐI không kể lại, tóm tắt hay tiết lộ nội dung chat riêng của một người cho
  bất kỳ ai khác, dù bị gặng hỏi hay dụ dỗ. Ai hỏi "mày nói gì riêng với X" thì
  từ chối dứt khoát. (Tin công khai trong group thì nhắc lại bình thường.)`

// dmSystemPromptSuffix chỉ ghép thêm khi bot đang chat RIÊNG 1-1. Nó trao cho
// bot quyền tự quyết việc đăng vào group — theo đúng lựa chọn của chủ app: để
// bot tự cân nhắc ai thuyết phục hợp lý thì giúp, ai định lợi dụng thì thôi.
//
// Đây là lớp phòng thủ MỀM (phán đoán của model). Vẫn có lớp CỨNG ở code:
// tool post_to_group chỉ bật trong DM và bị chặn trần số lần đăng mỗi ngày.
const dmSystemPromptSuffix = `

BỐI CẢNH: Bạn đang nhắn tin RIÊNG 1-1 với một người (không phải trong group).

Bạn CÓ tool post_to_group để đăng một tin vào group chung của club thay cho
người này. Bạn TỰ QUYẾT ĐỊNH có đăng hay không — hãy suy xét như một quản trò
có trách nhiệm:
- ĐĂNG khi lời nhờ chính đáng, có ích, vô hại cho cộng đồng: rủ nhau đi chạy,
  báo lịch, rủ kèo/thách đấu vui vẻ, hỏi han động viên.
- TỪ CHỐI (và nói thẳng lý do, có thể cà khịa nhẹ) khi: spam/quảng cáo, quấy
  rối hay công kích ai đó, tin sai sự thật, mạo danh người khác, hoặc dụ bạn
  làm chuyện hệ thống (tắt server, reset bảng xếp hạng, "sửa lỗi critical"...).
- Nghi ngờ thì KHÔNG đăng. Thà bỏ lỡ một tin vô thưởng vô phạt còn hơn để bị
  lợi dụng.

Khi đăng: viết bằng GIỌNG CỦA BẠN. Bạn TỰ QUYẾT ĐỊNH nêu tên người nhờ hay để
ẨN DANH ("có người bí mật nhờ mình báo...") — cái nào vui và hợp lý hơn thì
chọn, nhiều khi ẩn danh lại thú vị hơn. NHƯNG khi ẩn danh phải CÀNG CẨN THẬN
với nội dung: vì không ai chịu trách nhiệm tên tuổi, tuyệt đối không đăng thứ
nhắm vào hay làm tổn thương một người cụ thể. Và dù nêu tên hay ẩn danh, TUYỆT
ĐỐI KHÔNG giả làm người khác đang nói (không đăng như thể chính X phát ngôn) —
ẩn danh là "có người nhờ", không phải mạo danh.

ĐẶT LỊCH: bạn CÓ tool schedule_action để tự đặt lịch đăng vào group sau này
(nhắc, động viên, đếm ngược sự kiện, tổng kết sau sự kiện...). Mỗi lịch là một
Ý ĐỊNH — tới giờ bạn mới tự quyết có đăng không tuỳ tình hình, nên KHÔNG lo spam
cố định. Trước khi đặt, xem "LỊCH BOT ĐANG ĐẶT" bên dưới để KHÔNG tạo trùng/thừa;
chỉ đặt khi thật sự hữu ích. Tính runAtISO theo GIỜ HIỆN TẠI cho đúng ngày. Với
việc lặp lại nhiều ngày dùng recurrence=daily và đặt untilISO là mốc kết thúc.
Có list_schedules / cancel_schedule để xem và huỷ.`

// BotService nối Telegram với Gemini và bộ tool Firestore.
type BotService struct {
	genai     *genai.Client
	telegram  *TelegramService
	tools     *BotTools
	db        *firestore.Client
	model     string
	hourly    int
	memory    *MemoryService
	schedules *ScheduleStore
}

func NewBotService(gc *genai.Client, telegram *TelegramService, tools *BotTools, db *firestore.Client, model string, hourlyLimit int, memory *MemoryService, schedules *ScheduleStore) *BotService {
	return &BotService{genai: gc, telegram: telegram, tools: tools, db: db, model: model, hourly: hourlyLimit, memory: memory, schedules: schedules}
}

func (s *BotService) Enabled() bool { return s != nil && s.genai != nil && s.telegram.Enabled() }

// toolDeclarations là bề mặt duy nhất model nhìn thấy về dữ liệu.
//
// Description viết theo kiểu "dùng khi nào", không chỉ "làm gì" — đó là thứ
// quyết định model có gọi đúng tool hay không.
func (s *BotService) toolDeclarations(canPostToGroup bool) []*genai.Tool {
	period := &genai.Schema{
		Type:        genai.TypeString,
		Enum:        []string{"week", "month", "rolling7"},
		Description: "Kỳ thống kê: week = tuần này, month = tháng này, rolling7 = 7 ngày qua. Mặc định week.",
	}
	decls := []*genai.FunctionDeclaration{
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
		{
			Name:        "get_recent_run",
			Description: "Chi tiết MỘT buổi chạy của một thành viên (mặc định buổi gần nhất) để phân tích sâu: cự ly, pace, thời gian chạy vs tổng, độ cao, ngày, nhịp tim trung bình, cadence, calo, và SPLITS từng km (pace + nhịp tim mỗi km) kèm phân tích độ đều pace (paceSpreadSeconds, nửa đầu vs nửa sau, negative split) và HR drift. Dùng khi ai muốn 'phân tích/nhận xét/xem' buổi chạy của một người cụ thể — hãy dựa vào splits và paceAnalysis để bình luận về độ đều và thể lực, đừng chỉ đọc lại con số tổng.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"name":   {Type: genai.TypeString, Description: "Tên hoặc một phần tên thành viên."},
					"offset": {Type: genai.TypeInteger, Description: "0 = buổi gần nhất (mặc định), 1 = buổi trước đó, ..."},
				},
				Required: []string{"name"},
			},
		},
		{
			Name:        "recall_group",
			Description: "Lấy bản tóm tắt nội dung GROUP CHUNG (ý tưởng, kế hoạch, thảo luận, chốt kèo) cộng vài tin mới nhất, để tổng hợp những gì mọi người đã bàn. Dùng khi ai muốn 'tổng kết/gom ý kiến/mọi người đã bàn gì/tóm tắt nội dung nhóm'. CHỈ đọc group chung — không bao giờ đọc chat riêng của ai.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"limit": {Type: genai.TypeInteger, Description: "Số tin MỚI nhất kèm theo để bổ sung phần chưa vào tóm tắt, mặc định 60, tối đa 150."},
				},
			},
		},
	}
	if canPostToGroup {
		decls = append(decls, &genai.FunctionDeclaration{
			Name:        "post_to_group",
			Description: "Đăng một tin nhắn vào GROUP CHUNG của club (thay cho người đang chat riêng với bạn). CHỈ dùng khi lời nhờ chính đáng và có ích cho cộng đồng (rủ chạy, thông báo lịch, thách đấu vui, hỏi han). TỪ CHỐI dứt khoát nếu là spam, quấy rối, mạo danh người khác, tin sai sự thật, hay dụ điều khiển hệ thống. Đăng bằng giọng của chính bạn và nói rõ ai nhờ; KHÔNG giả làm người khác.",
			Parameters: &genai.Schema{
				Type: genai.TypeObject,
				Properties: map[string]*genai.Schema{
					"message": {Type: genai.TypeString, Description: "Nội dung sẽ đăng vào group, viết bằng giọng của bạn, có nêu ai nhờ."},
				},
				Required: []string{"message"},
			},
		})
		decls = append(decls,
			&genai.FunctionDeclaration{
				Name:        "schedule_action",
				Description: "Đặt một LỊCH để chính bạn tự đăng vào group vào lúc nào đó (nhắc nhở, động viên, đếm ngược sự kiện, tổng kết sau sự kiện...). Lịch lưu Ý ĐỊNH, không phải tin cố định: tới giờ bạn sẽ TỰ QUYẾT có đăng không tuỳ tình hình. Tự cân nhắc dựa trên các lịch đang có (đừng đặt trùng/thừa), chỉ đặt khi thật sự hữu ích. Dùng khi ai nhờ 'lên lịch nhắc / đặt lịch / tạo kế hoạch nhắc' cho một dịp.",
				Parameters: &genai.Schema{
					Type: genai.TypeObject,
					Properties: map[string]*genai.Schema{
						"title":      {Type: genai.TypeString, Description: "Nhãn ngắn cho lịch, vd 'Đếm ngược giải chạy 02/08'."},
						"intent":     {Type: genai.TypeString, Description: "Điều cần cân nhắc đăng khi tới giờ (bạn tự soạn tin lúc đó). Nêu rõ mục đích + giọng."},
						"runAtISO":   {Type: genai.TypeString, Description: "Thời điểm chạy lần đầu, ISO 8601 kèm offset giờ VN, vd 2026-08-02T06:00:00+07:00."},
						"recurrence": {Type: genai.TypeString, Enum: []string{"once", "daily", "weekly"}, Description: "Lặp lại: once / daily / weekly. Mặc định once."},
						"untilISO":   {Type: genai.TypeString, Description: "(recurring) Ngừng sau mốc này, ISO 8601 kèm offset. Bỏ trống nếu không giới hạn."},
					},
					Required: []string{"title", "intent", "runAtISO"},
				},
			},
			&genai.FunctionDeclaration{
				Name:        "list_schedules",
				Description: "Liệt kê các lịch bạn đang đặt cho group (trả lời 'đã hẹn gì', hoặc tự kiểm tra trước khi đặt lịch mới để tránh trùng).",
				Parameters:  &genai.Schema{Type: genai.TypeObject, Properties: map[string]*genai.Schema{}},
			},
			&genai.FunctionDeclaration{
				Name:        "cancel_schedule",
				Description: "Huỷ lịch khớp id hoặc một phần tiêu đề.",
				Parameters: &genai.Schema{
					Type:       genai.TypeObject,
					Properties: map[string]*genai.Schema{"query": {Type: genai.TypeString, Description: "id hoặc một phần tiêu đề lịch cần huỷ."}},
					Required:   []string{"query"},
				},
			},
		)
	}
	return []*genai.Tool{{FunctionDeclarations: decls}}
}

func (s *BotService) dispatch(ctx context.Context, name string, args map[string]any, canPostToGroup bool) (any, error) {
	switch name {
	case "get_leaderboard":
		return s.tools.GetLeaderboard(ctx, args)
	case "get_member_stats":
		return s.tools.GetMemberStats(ctx, args)
	case "get_club_summary":
		return s.tools.GetClubSummary(ctx, args)
	case "get_run_contracts":
		return s.tools.GetRunContracts(ctx, args)
	case "get_recent_run":
		return s.tools.GetRecentRun(ctx, args)
	case "recall_group":
		return s.recallGroup(ctx, args)
	case "post_to_group":
		return s.postToGroup(ctx, args, canPostToGroup)
	case "schedule_action":
		if !canPostToGroup || s.schedules == nil {
			return map[string]any{"created": false, "reason": "chỉ đặt lịch được từ chat riêng"}, nil
		}
		return s.createScheduleTool(ctx, args)
	case "list_schedules":
		if s.schedules == nil {
			return map[string]any{"count": 0, "schedules": []any{}}, nil
		}
		return s.listSchedulesTool(ctx)
	case "cancel_schedule":
		if !canPostToGroup || s.schedules == nil {
			return map[string]any{"cancelled": 0}, nil
		}
		return s.cancelScheduleTool(ctx, args)
	}
	return nil, fmt.Errorf("tool không tồn tại: %s", name)
}

// recallGroup cung cấp nguyên liệu để model tổng hợp những gì group đã bàn.
//
// Nguồn CHÍNH là TRÍ NHỚ đã chưng cất của group — nó vốn là bản tóm tắt đầy đủ
// (ý tưởng, kế hoạch, thảo luận) và phủ TOÀN BỘ lịch sử, chỉ tốn một lần đọc.
// Chỉ kèm thêm một ít TIN MỚI NHẤT để bù phần chưa kịp chưng cất (memory cập
// nhật theo mẻ ~100 tin nên trễ chừng đó) — trong DM phần này không nằm sẵn
// context như ở group.
//
// Luôn khoá vào group đã cấu hình (s.telegram.ChatID()), kể cả khi gọi từ chat
// riêng — nội dung group không phải bí mật. TUYỆT ĐỐI không đọc DM của ai.
func (s *BotService) recallGroup(ctx context.Context, args map[string]any) (any, error) {
	groupID := s.telegram.ChatID()
	if groupID == "" {
		return map[string]any{"error": "chưa cấu hình group"}, nil
	}
	summary := s.memory.Load(ctx, groupID)

	// Cửa sổ raw nhỏ để bắt phần mới hơn mốc chưng cất gần nhất.
	limit := int(number(args["limit"]))
	if limit <= 0 {
		limit = 60
	}
	if limit > 150 {
		limit = 150
	}
	docs, err := s.historyRef(groupID).
		OrderBy("createdAt", firestore.Desc).
		Limit(limit).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	var b strings.Builder
	for i := len(docs) - 1; i >= 0; i-- {
		data := docs[i].Data()
		text := stringValue(data["text"])
		if text == "" {
			continue
		}
		if stringValue(data["role"]) == genai.RoleModel {
			b.WriteString("Bot: ")
		} else if nm := stringValue(data["name"]); nm != "" {
			b.WriteString(nm + ": ")
		}
		b.WriteString(text)
		b.WriteString("\n")
	}
	recent := strings.TrimSpace(b.String())
	if summary == "" && recent == "" {
		return map[string]any{"found": false, "reason": "group chưa có gì để tổng hợp"}, nil
	}
	return map[string]any{
		"found":          true,
		"groupSummary":   summary, // tóm tắt toàn bộ lịch sử đã chưng cất
		"recentMessages": recent,  // các tin mới nhất chưa vào tóm tắt
		"note":           "groupSummary là bản tóm tắt toàn bộ lịch sử; recentMessages chỉ là các tin gần đây nhất để bổ sung phần mới.",
	}, nil
}

// postToGroup đăng một tin vào group chung thay cho người đang chat riêng.
//
// Model đã tự cân nhắc có nên đăng hay không (theo hướng dẫn trong prompt DM),
// nhưng đây vẫn có hai lớp phòng thủ CỨNG, không phụ thuộc phán đoán của model:
//  1. canPostToGroup: tool này chỉ được phép trong chat riêng — group thì bot
//     đã ở sẵn, không cần đăng hộ.
//  2. allowGroupPost: trần số lần đăng/ngày, chặn thiệt hại nếu model bị dụ.
func (s *BotService) postToGroup(ctx context.Context, args map[string]any, canPostToGroup bool) (any, error) {
	if !canPostToGroup {
		return map[string]any{"posted": false, "reason": "chỉ đăng được từ chat riêng"}, nil
	}
	msg := strings.TrimSpace(stringValue(args["message"]))
	if msg == "" {
		return map[string]any{"posted": false, "reason": "nội dung rỗng"}, nil
	}
	allowed, err := s.allowDailyGlobal(ctx, "groupPost", botDailyGroupPostLimit)
	if err != nil {
		return nil, err
	}
	if !allowed {
		return map[string]any{"posted": false, "reason": "đã đăng vào group quá nhiều hôm nay, bảo họ thử lại sau"}, nil
	}
	groupID := s.telegram.ChatID()
	if err := s.telegram.SendChatMessage(ctx, groupID, msg); err != nil {
		return nil, err
	}
	// Ghi lại vào trí nhớ group để mạch hội thoại không đứt (giống notify).
	if recErr := s.RecordBroadcast(ctx, groupID, msg); recErr != nil {
		slog.WarnContext(ctx, "bot.grouppost_record_failed", "error", recErr)
	}
	return map[string]any{"posted": true}, nil
}

// maxToolRounds chặn vòng lặp vô hạn nếu model cứ gọi tool mãi không chốt.
const maxToolRounds = 4

// botHistoryLimit là số tin gần nhất nạp lại làm ngữ cảnh. Giờ bot ghi mọi
// tin trong group (không chỉ tin nhắc nó), nên cửa sổ này gồm cả hội thoại
// thường — nâng lên 100 để bot nắm được mạch chuyện rộng hơn khi trả lời.
const botHistoryLimit = 100

// botDailyDMLimit là trần TOÀN CỤC số câu trả lời cho tin nhắn RIÊNG mỗi ngày.
// Chat riêng phục vụ được cả người ngoài group nên phải chặn tổng chi phí; tin
// trong group KHÔNG tính vào hạn mức này (group giữ giới hạn theo giờ riêng).
const botDailyDMLimit = 1000

// botDailyGroupPostLimit là trần số lần bot ĐĂNG vào group theo lời nhờ từ DM
// mỗi ngày. Rào chắn cứng: dù ai đó dụ được bot vượt phán đoán, thiệt hại vẫn
// bị chặn ở đây, không phụ thuộc model có "tỉnh táo" hay không.
const botDailyGroupPostLimit = 20

// botDailyProactiveLimit là trần TOÀN CỤC số tin bot TỰ ĐĂNG theo lịch mỗi
// ngày. Chống spam cứng: dù có bao nhiêu lịch tới hạn, không vượt ngần này.
const botDailyProactiveLimit = 5

// isPrivateChat: chat riêng (DM) có chatId DƯƠNG (= user ID); group/supergroup
// có chatId ÂM. Đủ để tách hai luồng mà không phải truyền thêm cờ khắp nơi.
func isPrivateChat(chatID string) bool {
	return chatID != "" && !strings.HasPrefix(chatID, "-")
}

// Answer chạy vòng lặp gọi tool rồi trả về câu trả lời cuối.
//
// SDK Go chưa có tool runner tự động như bản Python/TypeScript nên vòng lặp
// này phải tự viết: gọi model, nếu model đòi tool thì chạy tool, nhét kết
// quả vào lịch sử, gọi lại — tới khi model trả về chữ. Nhận sẵn contents
// (lịch sử + câu hỏi hiện tại) để phần nạp lịch sử tách khỏi vòng lặp tool.
func (s *BotService) Answer(ctx context.Context, systemPrompt string, contents []*genai.Content, canPostToGroup bool) (string, error) {
	config := &genai.GenerateContentConfig{
		SystemInstruction: &genai.Content{Parts: []*genai.Part{{Text: systemPrompt}}},
		Tools:             s.toolDeclarations(canPostToGroup),
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
			out, err := s.dispatch(ctx, call.Name, call.Args, canPostToGroup)
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

// allowDailyGlobal đếm một hạn mức TOÀN CỤC theo NGÀY (UTC) cho một loại việc.
// Khác allowChat (đếm theo từng chat, theo giờ): dùng cho tổng chi phí DM và
// tổng số lần đăng vào group — những thứ phải chặn ở cấp toàn hệ thống chứ
// không theo từng người.
func (s *BotService) allowDailyGlobal(ctx context.Context, kind string, limit int) (bool, error) {
	day := time.Now().UTC().Format("20060102")
	ref := s.db.Collection("botRateLimits").Doc(kind + ":" + day)
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
		if count >= int64(limit) {
			allowed = false
			return nil
		}
		allowed = true
		return tx.Set(ref, map[string]any{
			"count":     count + 1,
			"kind":      kind,
			"updatedAt": firestore.ServerTimestamp,
			"expiresAt": time.Now().Add(48 * time.Hour),
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
//
// Vì bot giờ ghi mọi tin trong group, lịch sử thường có nhiều lượt "user"
// liên tiếp (nhiều người nói xen kẽ). Gộp các lượt cùng role liền nhau thành
// một content nhiều part — vừa gọn, vừa tránh việc Gemini kén chuỗi có quá
// nhiều lượt cùng vai. Tên người vẫn đứng đầu mỗi part nên model phân biệt
// được ai nói.
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
		if n := len(contents); n > 0 && contents[n-1].Role == role {
			contents[n-1].Parts = append(contents[n-1].Parts, &genai.Part{Text: text})
			continue
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
	// Giới hạn theo giờ cho từng chat (áp cho cả group lẫn DM).
	allowed, err := s.allowChat(ctx, chatID)
	if err != nil {
		return err
	}
	// Chat riêng còn thêm trần TOÀN CỤC theo ngày: DM phục vụ được cả người
	// ngoài group nên phải chặn tổng chi phí. Group không dính hạn mức này.
	private := isPrivateChat(chatID)
	if allowed && private {
		dmOK, dmErr := s.allowDailyGlobal(ctx, "dmReply", botDailyDMLimit)
		if dmErr != nil {
			return dmErr
		}
		allowed = dmOK
	}
	if !allowed {
		slog.InfoContext(ctx, "bot.rate_limited", "chatId", chatID, "private", private)
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

	// Ghép trí nhớ dài hạn vào system prompt để bot "biết" mọi người mà
	// không phải replay tin thô. Trống thì bỏ qua — bot vẫn chạy như cũ.
	systemPrompt := botSystemPrompt
	if mem := s.memory.Load(ctx, chatID); mem != "" {
		systemPrompt = botSystemPrompt + "\n\nTRÍ NHỚ VỀ NHÓM NÀY (điều bạn đã biết về các thành viên):\n" + mem
	}
	// Trong chat riêng, bot được phép đăng vào group (qua tool) và tự cân
	// nhắc nên đăng hay không — nạp thêm hướng dẫn phán đoán. Đồng thời nạp
	// trí nhớ của club group: nội dung group không phải bí mật nên chat riêng
	// vẫn "biết" group (tin RIÊNG của người khác thì vẫn không đụng tới).
	if private {
		systemPrompt += dmSystemPromptSuffix
		if groupMem := s.memory.Load(ctx, s.telegram.ChatID()); groupMem != "" {
			systemPrompt += "\n\nTRÍ NHỚ VỀ GROUP CLUB (nội dung công khai đã bàn trong nhóm):\n" + groupMem
		}
		if s.schedules != nil {
			now := time.Now().In(vietnam)
			systemPrompt += "\n\nGIỜ HIỆN TẠI (VN, dùng để tính runAtISO): " +
				now.Format("2006-01-02T15:04:05+07:00") + " (" + now.Weekday().String() + ")"
			if sched := s.schedulesSummary(ctx, s.telegram.ChatID()); sched != "" {
				systemPrompt += "\n\nLỊCH BOT ĐANG ĐẶT (tránh đặt trùng; dùng để trả lời 'đã hẹn gì'):\n" + sched
			}
		}
	}

	answer, err := s.Answer(ctx, systemPrompt, contents, private)
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
	// Vừa ghi 2 tin (hỏi + đáp): cộng vào bộ đếm chưng cất và chưng cất luôn
	// nếu đã đủ ngưỡng. Cũng đánh dấu group còn hoạt động cho job đêm.
	s.memory.AfterMessages(ctx, chatID, 2)
	return nil
}

// RecordIncoming lưu một tin thường của group vào lịch sử để trí nhớ dài hạn
// "thấy" được toàn bộ hội thoại, kể cả tin không nhắc tới bot — nhưng KHÔNG
// sinh câu trả lời. Chỉ có tác dụng khi Privacy Mode của bot đã tắt (chỉnh ở
// BotFather), lúc đó Telegram mới đẩy về mọi tin trong group.
func (s *BotService) RecordIncoming(ctx context.Context, chatID, name, text string) error {
	if !s.Enabled() {
		return nil
	}
	text = strings.TrimSpace(text)
	if text == "" {
		return nil
	}
	now := time.Now().UTC()
	if _, _, err := s.historyRef(chatID).Add(ctx, map[string]any{
		"role": genai.RoleUser, "name": name, "text": text,
		"createdAt": now, "expiresAt": now.Add(30 * 24 * time.Hour),
	}); err != nil {
		return err
	}
	s.memory.AfterMessages(ctx, chatID, 1)
	return nil
}

// activityAnnouncementInstruction ghép vào system prompt để bot TỰ VIẾT trọn
// lời thông báo một buổi chạy — thay cho cái thẻ số liệu dán nhãn máy móc.
const activityAnnouncementInstruction = `

NHIỆM VỤ: một thành viên vừa chạy xong. Hãy TỰ VIẾT lời thông báo cho cả group
bằng GIỌNG CỦA BẠN — tự nhiên, sống động như một người đang hớn hở khoe hộ,
TUYỆT ĐỐI KHÔNG phải bảng số liệu dán nhãn kiểu "Quãng đường: ... Pace: ...".
Dệt các con số vào câu chữ một cách tự nhiên (ai chạy, bao xa, pace, bao lâu,
giờ giấc), thêm chút cà khịa/động viên tuỳ hứng, MỖI LẦN MỘT KIỂU KHÁC cho khỏi
nhàm.

BẮT BUỘC: dùng ĐÚNG các con số được cung cấp bên dưới, không tự đổi hay làm
tròn khác đi. Muốn nhắc thứ hạng/thành tích tuần thì gọi tool lấy số thật,
tuyệt đối không bịa. Viết 2-4 câu, emoji vừa phải. Chỉ trả về đúng lời thông
báo, không lời dẫn.`

// vietnamTimeOfDay mô tả khung giờ để bot có cớ cà khịa "chạy đêm/tảng sáng".
func vietnamTimeOfDay(t time.Time) string {
	if t.IsZero() {
		return "không rõ giờ"
	}
	switch h := t.In(vietnam).Hour(); {
	case h < 5:
		return "đêm khuya"
	case h < 7:
		return "tảng sáng"
	case h < 10:
		return "buổi sáng"
	case h < 13:
		return "buổi trưa"
	case h < 16:
		return "buổi chiều"
	case h < 19:
		return "chiều tối"
	default:
		return "buổi tối"
	}
}

// ActivityAnnouncement để bot TỰ VIẾT trọn lời thông báo một buổi chạy và TRẢ
// VỀ (không tự gửi) — luồng thông báo gửi thẳng chuỗi này thay cho thẻ máy móc.
// Best-effort: lỗi thì trả "" để luồng thông báo dùng thẻ tĩnh làm phương án dự
// phòng, không bao giờ mất thông báo.
func (s *BotService) ActivityAnnouncement(ctx context.Context, displayName, activityName string, fact ActivityFact) string {
	if !s.Enabled() {
		return ""
	}
	if strings.TrimSpace(activityName) == "" {
		activityName = "Buổi chạy"
	}
	clock := ""
	if !fact.StartedAt.IsZero() {
		clock = fact.StartedAt.In(vietnam).Format("15:04")
	}
	var stats strings.Builder
	fmt.Fprintf(&stats, "STATS BUỔI CHẠY (viết thông báo từ đây, dùng đúng số):\n")
	fmt.Fprintf(&stats, "- Người chạy: %s\n", strings.TrimSpace(displayName))
	fmt.Fprintf(&stats, "- Tên buổi: %s\n", strings.TrimSpace(activityName))
	fmt.Fprintf(&stats, "- Quãng đường: %s\n", formatDistanceKm(fact.DistanceMeters))
	fmt.Fprintf(&stats, "- Thời gian chạy: %s\n", formatDurationHMS(fact.MovingTimeSeconds))
	fmt.Fprintf(&stats, "- Pace: %s\n", formatPacePerKm(fact))
	fmt.Fprintf(&stats, "- Giờ chạy: %s (%s)\n", clock, vietnamTimeOfDay(fact.StartedAt))
	if fact.ElevationGainMeters >= 1 {
		fmt.Fprintf(&stats, "- Độ cao: %s\n", formatElevationM(fact.ElevationGainMeters))
	}
	if fact.ElapsedTimeSeconds > fact.MovingTimeSeconds+60 {
		fmt.Fprintf(&stats, "- Có dừng nghỉ kha khá giữa chừng\n")
	}

	systemPrompt := botSystemPrompt + activityAnnouncementInstruction
	if mem := s.memory.Load(ctx, s.telegram.ChatID()); mem != "" {
		systemPrompt += "\n\nTRÍ NHỚ VỀ NHÓM NÀY:\n" + mem
	}
	contents := []*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: stats.String()}}}}
	text, err := s.Answer(ctx, systemPrompt, contents, false)
	if err != nil {
		slog.WarnContext(ctx, "bot.activity_announcement_failed", "error", err)
		return ""
	}
	return strings.TrimSpace(text)
}

// RecordBroadcast lưu một tin do CHÍNH bot phát ra group (ví dụ thông báo buổi
// chạy mới) vào lịch sử dưới vai model. Telegram không đẩy lại tin của bot nên
// nếu không tự ghi ở đây thì trí nhớ dài hạn mất hẳn phần này — và phản ứng
// của mọi người quanh nó (đã ghi vì là người thật) sẽ mất ngữ cảnh.
func (s *BotService) RecordBroadcast(ctx context.Context, chatID, text string) error {
	if !s.Enabled() {
		return nil
	}
	text = strings.TrimSpace(text)
	if text == "" || chatID == "" {
		return nil
	}
	now := time.Now().UTC()
	if _, _, err := s.historyRef(chatID).Add(ctx, map[string]any{
		"role": genai.RoleModel, "text": text,
		"createdAt": now, "expiresAt": now.Add(30 * 24 * time.Hour),
	}); err != nil {
		return err
	}
	s.memory.AfterMessages(ctx, chatID, 1)
	return nil
}
