package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"runtime/debug"
	"strings"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type taskPublishFunc func(context.Context, PublishTask) (string, error)

// serveTelegramUpdate định tuyến một update và trả lời Telegram theo quy tắc:
//   - 5xx chỉ khi enqueue lỗi tạm thời, để Telegram gửi lại. TaskID theo
//     update_id nên lần gửi lại không tạo task trùng.
//   - Lỗi khác, kể cả panic, thì 200 kèm log error. Bug lặp lại được mà trả 5xx
//     thì Telegram gửi lại mãi, kẹt cả các update sau của bot.
func (s *Server) serveTelegramUpdate(ctx context.Context, w http.ResponseWriter, body []byte, publish taskPublishFunc) {
	defer func() {
		if p := recover(); p != nil {
			slog.ErrorContext(ctx, "telegram.webhook_panic", "panic", fmt.Sprint(p), "stack", string(debug.Stack()))
			w.WriteHeader(http.StatusOK)
		}
	}()
	var update TelegramUpdate
	if json.Unmarshal(body, &update) != nil {
		w.WriteHeader(http.StatusOK)
		return
	}
	reply, err := s.routeTelegramUpdate(ctx, update, body, publish)
	if err != nil {
		if transientEnqueueErr(err) {
			slog.WarnContext(ctx, "telegram.enqueue_retry", "updateId", update.UpdateID, "error", err)
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		slog.ErrorContext(ctx, "telegram.enqueue_failed", "updateId", update.UpdateID, "error", err)
	}
	if reply != nil {
		_ = writeJSON(w, http.StatusOK, reply)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// transientEnqueueErr: lỗi mà gửi lại sau ít giây có thể qua. Publish đã tự thử
// lại vài lần; tới đây vẫn hỏng thì nhờ Telegram gửi lại.
func transientEnqueueErr(err error) bool {
	if errors.Is(err, context.DeadlineExceeded) {
		return true
	}
	st, ok := status.FromError(err)
	if !ok {
		return false
	}
	switch st.Code() {
	case codes.Unavailable, codes.DeadlineExceeded, codes.Aborted, codes.ResourceExhausted:
		return true
	}
	return false
}

// routeTelegramUpdate trả body để Telegram thực hiện ngay (answerCallbackQuery,
// sendMessage), hoặc nil nếu chỉ enqueue. Body trả trong response webhook không
// cần token bot, và không biết được là gửi thành công hay không.
func (s *Server) routeTelegramUpdate(ctx context.Context, update TelegramUpdate, raw []byte, publish taskPublishFunc) (map[string]any, error) {
	if cq := update.CallbackQuery; cq != nil {
		// Chưa có ván nào dùng nút (W0 mới ghi hành động). Vẫn phải trả lời,
		// không thì nút cứ quay vòng trên máy người bấm.
		return map[string]any{"method": "answerCallbackQuery", "callback_query_id": cq.ID, "text": "Nút này chưa dùng được."}, nil
	}
	if reply, ok, err := s.linkReply(ctx, update, raw, publish); ok {
		return reply, err
	}
	if reply, ok := s.commandReply(update); ok {
		return reply, nil
	}
	if isMembershipUpdate(update) {
		if m := update.Message; m != nil && (m.MigrateToChatID != 0 || m.MigrateFromChatID != 0) {
			slog.WarnContext(ctx, "telegram.chat_migrated", "chatId", m.Chat.ID, "to", m.MigrateToChatID, "from", m.MigrateFromChatID)
		}
		if publish == nil || s.config.GameInboundQueue == "" {
			return nil, nil
		}
		_, err := publish(ctx, PublishTask{
			Queue:       QueueGameInbound,
			HandlerPath: "/tasks/game-update",
			Payload:     gameUpdateTask{UpdateID: update.UpdateID, Raw: raw},
			TaskID:      StableTaskID("gameupd", update.UpdateID),
		})
		return nil, err
	}
	if publish == nil {
		return nil, nil
	}
	name := senderName(update)
	chatID, question, isQuestion := botQuestion(update, s.config.TelegramBotUsername)
	recordChatID, _, rawText, hasText := incomingMessage(update)
	if !isQuestion && !hasText {
		return nil, nil
	}
	task := botMessageTask{IsQuestion: isQuestion, Name: name, SenderID: senderID(update), PhotoFileID: photoFileID(update), ThreadID: messageThreadID(update)}
	if isQuestion {
		task.ChatID, task.Question = chatID, question
	} else {
		task.ChatID, task.RawText = recordChatID, rawText
	}
	_, err := publish(ctx, PublishTask{
		Queue:       QueueBotInbound,
		HandlerPath: "/tasks/bot-message",
		Payload:     task,
		TaskID:      StableTaskID("botmsg", update.UpdateID),
	})
	return nil, err
}

// gameUpdateTask chở nguyên update sang bot. Bot decode lỏng, nên thêm field
// không bị ràng buộc thứ tự deploy như botMessageTask.
type gameUpdateTask struct {
	UpdateID int64           `json:"updateId"`
	Raw      json.RawMessage `json:"raw"`
}

func isMembershipUpdate(u TelegramUpdate) bool {
	if len(u.ChatMember) > 0 || len(u.MyChatMember) > 0 || len(u.ChatJoinRequest) > 0 {
		return true
	}
	m := u.Message
	return m != nil && (len(m.NewChatMembers) > 0 || len(m.LeftChatMember) > 0 || m.MigrateToChatID != 0 || m.MigrateFromChatID != 0)
}

// commandReply trả lời ngay các lệnh không cần LLM (/vai). Không enqueue,
// không ghi history.
func (s *Server) commandReply(update TelegramUpdate) (map[string]any, bool) {
	msg := update.Message
	if msg == nil || msg.From == nil {
		return nil, false
	}
	cmd, _ := parseBotCommand(msg.Text, s.config.TelegramBotUsername)
	private := msg.Chat.Type == "private"
	var text string
	switch {
	case cmd == "/vai" && private:
		text = "Bạn chưa ở trong ván Ma Sói nào."
	case cmd == "/vai":
		// Lá bài không bao giờ hiện trong group.
		text = "Nhắn /vai riêng cho 3i để xem lá bài của bạn."
	default:
		return nil, false
	}
	reply := map[string]any{"method": "sendMessage", "chat_id": msg.Chat.ID, "text": text}
	if id := messageThreadID(update); id != 0 {
		reply["message_thread_id"] = id
	}
	return reply, true
}

// linkReply tiêu mã của "/start <mã>" trong DM (L1) và trả lời ngay trong
// response webhook. Liên kết xong thì enqueue game-update để bot ghi inPsc.
// /start không kèm mã không phải việc của hàm này: vẫn đi LLM như trước.
//
// Telegram gửi lại update (do 5xx hay mất response) thì mã đã dùng bởi chính tg
// đó vẫn ra "đã liên kết", và TaskID theo update_id nên không enqueue đôi.
func (s *Server) linkReply(ctx context.Context, update TelegramUpdate, raw []byte, publish taskPublishFunc) (map[string]any, bool, error) {
	msg := update.Message
	if msg == nil || msg.From == nil || msg.Chat.Type != "private" {
		return nil, false, nil
	}
	cmd, code := parseBotCommand(msg.Text, s.config.TelegramBotUsername)
	if cmd != "/start" || code == "" {
		return nil, false, nil
	}
	reply := func(text string) map[string]any {
		return map[string]any{"method": "sendMessage", "chat_id": msg.Chat.ID, "text": text}
	}
	if s.deps == nil || s.deps.TelegramLinks == nil {
		slog.ErrorContext(ctx, "telegram.link_unconfigured", "updateId", update.UpdateID)
		return reply("Chưa liên kết được lúc này, bạn thử lại sau nhé."), true, nil
	}
	tg := TelegramUser{ID: msg.From.ID, Username: msg.From.Username, FirstName: msg.From.FirstName}
	name, err := s.deps.TelegramLinks.ConsumeLinkCode(ctx, code, tg, time.Now())
	switch {
	case errors.Is(err, errLinkCodeInvalid), errors.Is(err, errLinkCodeExpired):
		return reply("Mã liên kết không đúng hoặc đã hết hạn. Mở app 3i Run để lấy mã mới."), true, nil
	case errors.Is(err, errLinkCodeUsed):
		return reply("Mã này đã được dùng rồi. Mở app 3i Run để lấy mã mới."), true, nil
	case errors.Is(err, errLinkInGame):
		return reply(errLinkInGame.Message), true, nil
	case err != nil:
		if transientEnqueueErr(err) {
			// Không trả lời: trả 5xx để Telegram gửi lại, lần sau có thể qua.
			return nil, true, err
		}
		return reply("Chưa liên kết được lúc này, bạn thử lại sau nhé."), true, err
	}
	if name == "" {
		name = "tài khoản 3i Run của bạn"
	}
	out := reply("Đã liên kết Telegram với " + name + ".")
	if publish == nil || s.config.GameInboundQueue == "" {
		return out, true, nil
	}
	_, err = publish(ctx, PublishTask{
		Queue:       QueueGameInbound,
		HandlerPath: "/tasks/game-update",
		Payload:     gameUpdateTask{UpdateID: update.UpdateID, Raw: raw},
		TaskID:      StableTaskID("gameupd", update.UpdateID),
	})
	if err != nil && transientEnqueueErr(err) {
		return nil, true, err
	}
	return out, true, err
}

// parseBotCommand tách "/lenh@TenBot tham số". Lệnh gắn tên bot khác thì trả
// rỗng: trong group, /vai@BotKhac không phải gọi mình.
func parseBotCommand(text, botUsername string) (cmd, arg string) {
	text = strings.TrimSpace(text)
	if !strings.HasPrefix(text, "/") {
		return "", ""
	}
	head, rest, _ := strings.Cut(text, " ")
	if name, at, ok := strings.Cut(head, "@"); ok {
		if !strings.EqualFold(at, botUsername) {
			return "", ""
		}
		head = name
	}
	return strings.ToLower(head), strings.TrimSpace(rest)
}
