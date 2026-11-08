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
	if update.CallbackQuery != nil {
		return s.callbackReply(ctx, update)
	}
	if reply, ok, err := s.managedBotUpdate(ctx, raw); ok {
		return reply, err
	}
	if reply, ok, err := s.linkReply(ctx, update, raw, publish); ok {
		return reply, err
	}
	if reply, ok, err := s.commandReply(ctx, update); ok {
		return reply, err
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
	roomReply, inRoom, err := s.telegramRoomMessage(ctx, update)
	if err != nil {
		return nil, err
	}
	name := senderName(update)
	chatID, question, isQuestion := botQuestion(update, s.config.TelegramBotUsername)
	if inRoom {
		// Topic Phòng bot là của MyBot: 3i không trả lời, chỉ ghi tin như mọi
		// tin PSC khác, để việc tự học (nguồn botMessages) vẫn học tin ở đây.
		isQuestion = false
	}
	recordChatID, _, rawText, hasText := incomingMessage(update)
	if isQuestion || hasText {
		task := botMessageTask{IsQuestion: isQuestion, Name: name, SenderID: senderID(update), PhotoFileID: photoFileID(update), ThreadID: messageThreadID(update)}
		if isQuestion {
			task.ChatID, task.Question = chatID, question
		} else {
			task.ChatID, task.RawText = recordChatID, rawText
		}
		if _, err := publish(ctx, PublishTask{
			Queue:       QueueBotInbound,
			HandlerPath: "/tasks/bot-message",
			Payload:     task,
			TaskID:      StableTaskID("botmsg", update.UpdateID),
		}); err != nil {
			return roomReply, err
		}
	}
	if inRoom {
		return roomReply, nil
	}
	// Sau task của 3i: lỗi ở đây thì Telegram gửi lại update, task của 3i khử
	// trùng theo update_id nên không ghi đôi.
	return roomReply, s.telegramGroupMessage(ctx, update, isQuestion)
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

// commandReply trả lời ngay các lệnh không cần LLM (/vai, lệnh admin Ma Sói).
// Không enqueue, không ghi history. Firestore lỗi tạm thời thì trả lỗi không
// kèm câu trả lời, để webhook trả 5xx và Telegram gửi lại.
func (s *Server) commandReply(ctx context.Context, update TelegramUpdate) (map[string]any, bool, error) {
	msg := update.Message
	if msg == nil || msg.From == nil {
		return nil, false, nil
	}
	cmd, arg := parseBotCommand(msg.Text, s.config.TelegramBotUsername)
	if cmd != "/vai" && cmd != telegramRoomCommand && cmd != liveTrackCommand && !adminCommands[cmd] {
		return nil, false, nil
	}
	reply := func(text string, html bool) map[string]any {
		r := map[string]any{"method": "sendMessage", "chat_id": msg.Chat.ID, "text": text}
		if html {
			r["parse_mode"] = "HTML"
		}
		if id := messageThreadID(update); id != 0 {
			r["message_thread_id"] = id
		}
		return r
	}
	if cmd == telegramRoomCommand {
		text, err := s.telegramRoomCommandText(ctx, update, arg)
		return reply(text, false), true, err
	}
	if cmd == liveTrackCommand {
		text, err := s.liveTrackCommandText(ctx, update, arg)
		return reply(text, false), true, err
	}
	if adminCommands[cmd] {
		text, markup, err := s.adminReply(ctx, update, cmd, arg)
		r := reply(text, false)
		if markup != nil {
			r["reply_markup"] = markup
		}
		return r, true, err
	}
	if msg.Chat.Type != "private" {
		// Lá bài không bao giờ hiện trong group.
		return reply("Nhắn /vai riêng cho 3i để xem lá bài của bạn.", false), true, nil
	}
	text, html, err := s.cardReply(ctx, msg.From.ID, "")
	if text == "" {
		return nil, true, err
	}
	return reply(text, html), true, err
}

// cardReply là câu trả lời /vai nhắn riêng bot host (botId của bot ván, rỗng
// là 3i): lá bài trong ván của bot đó. text rỗng kèm lỗi là lỗi tạm thời, không
// trả lời để webhook trả 5xx và Telegram gửi lại.
func (s *Server) cardReply(ctx context.Context, tgID int64, host string) (text string, html bool, err error) {
	const failed = "Chưa xem được lá bài lúc này, bạn thử lại sau nhé."
	if s.deps == nil || s.deps.Games == nil || s.deps.TelegramLinks == nil {
		slog.ErrorContext(ctx, "telegram.card_unconfigured", "host", host)
		return failed, false, nil
	}
	uid, err := s.deps.TelegramLinks.UIDForTelegram(ctx, tgID)
	if err == nil && uid == "" {
		return "Tài khoản Telegram này chưa liên kết với RunNow. Mở app RunNow để lấy mã liên kết.", false, nil
	}
	var card string
	if err == nil {
		card, err = s.deps.Games.CardText(ctx, uid, host)
	}
	switch {
	case err != nil && transientEnqueueErr(err):
		return "", false, err
	case err != nil:
		return failed, false, err
	case card == "":
		return "Bạn chưa ở trong ván Ma Sói nào của quản trò này.", false, nil
	}
	return card, true, nil
}

// callbackReply trả answerCallbackQuery cho mọi nút: không trả lời thì nút cứ
// quay vòng trên máy người bấm. Firestore lỗi tạm thời thì trả lỗi để webhook
// trả 5xx; Telegram gửi lại cùng update_id nên SubmitAction không ghi đôi.
func (s *Server) callbackReply(ctx context.Context, update TelegramUpdate) (map[string]any, error) {
	received := time.Now()
	cq := update.CallbackQuery
	answer := func(text string, alert bool) map[string]any {
		r := map[string]any{"method": "answerCallbackQuery", "callback_query_id": cq.ID, "text": truncateUTF16(text, answerTextSize)}
		if alert {
			r["show_alert"] = true
		}
		return r
	}
	if activityID, emoji, ok := parseLiveCheer(cq.Data); ok {
		text, err := s.liveCheerText(ctx, cq.From.ID, activityID, emoji, received)
		if err != nil && transientEnqueueErr(err) {
			return nil, err
		}
		return answer(text, false), err
	}
	b, ok := parseGameButton(cq.Data)
	if !ok {
		return answer("Nút này chưa dùng được.", false), nil
	}
	reply, err := s.pressGameButton(ctx, b, cq.From.ID, "", update.UpdateID, received)
	return gameButtonAnswer(answer, reply, err)
}

// pressGameButton xử lý nút Ma Sói bấm ở bot host (botId của bot ván, rỗng là
// 3i). Nút huỷ ván của admin chỉ có ở 3i.
func (s *Server) pressGameButton(ctx context.Context, b gameButton, tgID int64, host string, updateID int64, received time.Time) (ButtonReply, error) {
	if s.deps == nil || s.deps.Games == nil || s.deps.TelegramLinks == nil || (b.Op == opCancel && host != "") {
		return ButtonReply{Text: "Nút này chưa dùng được."}, nil
	}
	uid, err := s.deps.TelegramLinks.UIDForTelegram(ctx, tgID)
	if err != nil {
		return ButtonReply{}, err
	}
	if uid == "" {
		return ButtonReply{Text: "Tài khoản Telegram này chưa liên kết với RunNow."}, nil
	}
	if b.Op == opCancel {
		// Admin có thể không chơi ván, nên không đi qua PressButton.
		text, err := s.cancelButtonReply(ctx, b.GameID, uid)
		return ButtonReply{Text: text, Alert: true}, err
	}
	reply, err := s.deps.Games.PressButton(ctx, b, uid, host, updateID, received)
	if err == nil && reply.Wrote {
		s.kickGameFlush(ctx, b.GameID)
	}
	return reply, err
}

// gameButtonAnswer đổi kết quả bấm nút thành answerCallbackQuery. Lỗi tạm thời
// thì không trả lời, để webhook trả 5xx và Telegram gửi lại cùng update_id.
func gameButtonAnswer(answer func(string, bool) map[string]any, reply ButtonReply, err error) (map[string]any, error) {
	switch {
	case err != nil && transientEnqueueErr(err):
		return nil, err
	case err != nil:
		return answer("Chưa làm được lúc này, bạn thử lại sau nhé.", false), err
	}
	return answer(reply.Text, reply.Alert), nil
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
