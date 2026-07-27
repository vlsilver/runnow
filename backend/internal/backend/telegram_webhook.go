package backend

import (
	"strconv"
	"strings"
)

// telegramEntity là một entity trong text hoặc caption (mention, command, ...).
// Dùng chung cho cả entities (của text) lẫn caption_entities (của ảnh có chữ).
type telegramEntity struct {
	Type   string `json:"type"`
	Offset int    `json:"offset"`
	Length int    `json:"length"`
	// User có mặt khi entity là text_mention — Telegram chèn tên hiển thị của
	// bot ("3i") thay vì chuỗi @username, nên phải khớp qua đây.
	User *struct {
		Username string `json:"username"`
		IsBot    bool   `json:"is_bot"`
	} `json:"user"`
}

// TelegramUpdate là phần tối thiểu của update mà bot cần.
//
// Telegram gửi rất nhiều loại update; khai đúng thứ dùng tới thay vì map
// toàn bộ schema để không phải chạy theo mỗi lần họ thêm field.
type TelegramUpdate struct {
	// UpdateID là số tăng dần, duy nhất mỗi update — dùng làm khoá dedup khi
	// đẩy vào queue để Cloud Tasks không tạo task trùng.
	UpdateID int64 `json:"update_id"`
	Message  *struct {
		MessageID int64  `json:"message_id"`
		Text      string `json:"text"`
		// Caption + Photo: khi người dùng gửi ẢNH kèm chữ, Telegram để chữ ở
		// caption (không phải text) và ảnh ở photo (mảng nhiều cỡ, phần tử cuối
		// là lớn nhất). Bot dùng để "vẽ lại" từ ảnh tham chiếu gửi kèm.
		Caption string `json:"caption"`
		Photo   []struct {
			FileID   string `json:"file_id"`
			FileSize int64  `json:"file_size"`
		} `json:"photo"`
		Chat struct {
			ID   int64  `json:"id"`
			Type string `json:"type"`
		} `json:"chat"`
		From *struct {
			ID        int64  `json:"id"`
			Username  string `json:"username"`
			FirstName string `json:"first_name"`
		} `json:"from"`
		Entities        []telegramEntity `json:"entities"`
		CaptionEntities []telegramEntity `json:"caption_entities"`
		ReplyToMessage *struct {
			From *struct {
				IsBot    bool   `json:"is_bot"`
				Username string `json:"username"`
			} `json:"from"`
		} `json:"reply_to_message"`
	} `json:"message"`
}

// botQuestion quyết định update này có phải câu hỏi dành cho bot không, và
// trả về phần nội dung đã bỏ tên bot.
//
// Privacy mode đang bật nên Telegram chỉ đẩy về những tin có nhắc bot hoặc
// reply vào bot — nhưng vẫn phải tự kiểm tra: cấu hình phía BotFather có thể
// bị đổi bất cứ lúc nào, và lúc đó bot sẽ trả lời mọi câu trong group.
func botQuestion(update TelegramUpdate, botUsername string) (chatID string, question string, ok bool) {
	msg := update.Message
	if msg == nil {
		return "", "", false
	}
	// Ảnh kèm chữ: chữ + entity nằm ở caption chứ không phải text. Lấy caption
	// làm nội dung khi text rỗng, để tag bot trong caption vẫn nhận ra.
	text := msg.Text
	entities := msg.Entities
	if strings.TrimSpace(text) == "" && strings.TrimSpace(msg.Caption) != "" {
		text = msg.Caption
		entities = msg.CaptionEntities
	}
	if strings.TrimSpace(text) == "" {
		return "", "", false
	}
	chatID = strconv.FormatInt(msg.Chat.ID, 10)

	// Chat riêng với bot thì mọi tin đều là hỏi bot.
	if msg.Chat.Type == "private" {
		return chatID, strings.TrimSpace(stripCommandSuffix(text, botUsername)), true
	}

	// Reply vào chính tin nhắn của bot.
	if r := msg.ReplyToMessage; r != nil && r.From != nil && r.From.IsBot &&
		strings.EqualFold(r.From.Username, botUsername) {
		return chatID, strings.TrimSpace(stripCommandSuffix(text, botUsername)), true
	}

	// text_mention: Telegram hiển thị tên bot ("3i") và gắn username vào
	// entity.user thay vì để "@Run3IBot" trong text. Bắt trường hợp này
	// trước khi tìm chuỗi, nếu không sẽ trượt.
	mentionedViaEntity := false
	for _, e := range entities {
		if e.Type == "text_mention" && e.User != nil && strings.EqualFold(e.User.Username, botUsername) {
			mentionedViaEntity = true
			// Bỏ đúng đoạn tên bot khỏi text theo offset/length.
			if e.Offset >= 0 && e.Offset+e.Length <= len(text) {
				text = text[:e.Offset] + " " + text[e.Offset+e.Length:]
			}
		}
	}

	// Nhắc tên bot bằng @username thường.
	mention := "@" + botUsername
	if !mentionedViaEntity && !strings.Contains(strings.ToLower(text), strings.ToLower(mention)) {
		return "", "", false
	}
	cleaned := stripCommandSuffix(replaceFold(text, mention, " "), botUsername)
	cleaned = strings.Join(strings.Fields(cleaned), " ")
	if cleaned == "" {
		return "", "", false
	}
	return chatID, cleaned, true
}

// botMessageTask là payload đẩy vào queue bot-inbound: webhook chỉ tách sẵn
// phần cần rồi enqueue, còn việc gọi Gemini (nặng) để worker xử lý trong một
// request thật — full CPU, timeout dài, tự retry — thay cho goroutine sau-200
// vốn bị Cloud Run bóp CPU tới mức timeout.
type botMessageTask struct {
	IsQuestion  bool   `json:"isQuestion"`
	ChatID      string `json:"chatId"`
	SenderID    string `json:"senderId,omitempty"`
	Name        string `json:"name"`
	Question    string `json:"question,omitempty"`
	RawText     string `json:"rawText,omitempty"`
	PhotoFileID string `json:"photoFileId,omitempty"`
}

// photoFileID trả file_id của ảnh CỠ LỚN NHẤT trong tin (nếu có). Telegram xếp
// message.photo từ nhỏ → lớn, nên phần tử cuối là bản gốc/nét nhất. Rỗng nếu
// tin không kèm ảnh.
func photoFileID(update TelegramUpdate) string {
	if update.Message == nil || len(update.Message.Photo) == 0 {
		return ""
	}
	return update.Message.Photo[len(update.Message.Photo)-1].FileID
}

// senderID lấy Telegram user id (chuỗi) của người gửi — khoá ổn định cho hạn
// mức theo NGƯỜI (vd trần số ảnh AI mỗi người/ngày). Rỗng nếu không xác định.
func senderID(update TelegramUpdate) string {
	if update.Message == nil || update.Message.From == nil {
		return ""
	}
	return strconv.FormatInt(update.Message.From.ID, 10)
}

// incomingMessage trả về chatID, tên người gửi và text thô của một tin bất kỳ
// có nội dung — để bot GHI NHỚ mọi tin trong group, không chỉ tin nhắc tới nó.
// ok=false nếu update không phải tin văn bản từ một người thật (bỏ tin dịch
// vụ, bài đăng kênh, tin rỗng).
func incomingMessage(update TelegramUpdate) (chatID, name, text string, ok bool) {
	msg := update.Message
	if msg == nil || msg.From == nil {
		return "", "", "", false
	}
	text = strings.TrimSpace(msg.Text)
	if text == "" {
		return "", "", "", false
	}
	return strconv.FormatInt(msg.Chat.ID, 10), senderName(update), text, true
}

// senderName lấy tên người gửi để gắn vào lịch sử — nhờ đó bot phân biệt
// được ai hỏi khi nhiều người xen kẽ trong group.
func senderName(update TelegramUpdate) string {
	if update.Message == nil || update.Message.From == nil {
		return "ai đó"
	}
	f := update.Message.From
	if name := strings.TrimSpace(f.FirstName); name != "" {
		return name
	}
	if f.Username != "" {
		return f.Username
	}
	return "ai đó"
}

// stripCommandSuffix bỏ phần "@TenBot" dính sau lệnh, ví dụ "/top@RunBot".
func stripCommandSuffix(text, botUsername string) string {
	return replaceFold(text, "@"+botUsername, " ")
}

// replaceFold thay thế không phân biệt hoa thường — người ta gõ tên bot với
// đủ kiểu viết hoa.
func replaceFold(text, old, new string) string {
	if old == "" {
		return text
	}
	lowerText, lowerOld := strings.ToLower(text), strings.ToLower(old)
	var b strings.Builder
	for {
		i := strings.Index(lowerText, lowerOld)
		if i < 0 {
			b.WriteString(text)
			return b.String()
		}
		b.WriteString(text[:i])
		b.WriteString(new)
		text, lowerText = text[i+len(old):], lowerText[i+len(lowerOld):]
	}
}
