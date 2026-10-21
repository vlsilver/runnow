package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"runtime/debug"
	"strconv"
)

// Route của MyBot trên Telegram. Tính năng tắt (AGENT_TELEGRAM_BOTS khác "on",
// hay thiếu TELEGRAM_BOT_USERNAME, TELEGRAM_WEBHOOK_SECRET) thì deps.ManagedBots
// là nil: webhook bot con trả 404, update managed_bot tới 3i chỉ log, task trả
// 204, GET /v1/agents/me không có mục telegram.

const (
	managedStrangerReply = "Đây là bot cá nhân trên 3i Run, chỉ chủ bot nhắn được."
	managedTooFastReply  = "Gửi chậm lại một chút nhé."
	managedTextReply     = "Mình chỉ đọc được tin chữ, dài tối đa 1000 ký tự."
	managedNoLinkReply   = "Bạn liên kết Telegram trong app 3i Run trước, rồi bấm Kết nối lại."
	managedNoAgentReply  = "Bạn tạo MyBot trong app 3i Run trước, rồi bấm Kết nối lại."
)

func (s *Server) mybotRoutes() {
	s.route("POST /v1/telegram/managed/{botId}/webhook", s.mybotChildWebhook)
}

var errMybotOff = &HTTPError{Status: http.StatusNotFound, Code: "not_found", Message: "Not found"}

// serveMybot trả lời Telegram theo cùng quy tắc với serveTelegramUpdate: 5xx
// khi lỗi tạm thời để Telegram gửi lại, còn lại 200 kèm log, kể cả panic.
func (s *Server) serveMybot(ctx context.Context, w http.ResponseWriter, run func(context.Context) (map[string]any, error)) {
	defer func() {
		if p := recover(); p != nil {
			slog.ErrorContext(ctx, "mybot.webhook_panic", "panic", fmt.Sprint(p), "stack", string(debug.Stack()))
			w.WriteHeader(http.StatusOK)
		}
	}()
	reply, err := run(ctx)
	if err != nil {
		var retry *mybotRetryErr
		if errors.As(err, &retry) || transientEnqueueErr(err) {
			slog.WarnContext(ctx, "mybot.webhook_retry", "error", err)
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		slog.ErrorContext(ctx, "mybot.webhook_failed", "error", err)
	}
	if reply != nil {
		_ = writeJSON(w, http.StatusOK, reply)
		return
	}
	w.WriteHeader(http.StatusOK)
}

// mybotRetryErr bọc lỗi mà webhook phải trả 5xx dù không phải lỗi tạm thời
// của gRPC (vd lỗi lạ khi ghi tin của chủ): Telegram gửi lại thì tin không mất.
type mybotRetryErr struct{ err error }

func (e *mybotRetryErr) Error() string { return e.err.Error() }
func (e *mybotRetryErr) Unwrap() error { return e.err }

type managedUser struct {
	ID        int64  `json:"id"`
	IsBot     bool   `json:"is_bot"`
	Username  string `json:"username"`
	FirstName string `json:"first_name"`
}

// managerUpdate là phần update của 3i dành cho Managed Bots: managed_bot khi
// bot con được tạo, đổi token hay đổi chủ; managed_bot_created là tin dịch vụ
// trong DM với 3i lúc người dùng vừa tạo xong bot.
type managerUpdate struct {
	UpdateID   int64 `json:"update_id"`
	ManagedBot *struct {
		User managedUser `json:"user"`
		Bot  managedUser `json:"bot"`
	} `json:"managed_bot"`
	Message *struct {
		Chat struct {
			ID int64 `json:"id"`
		} `json:"chat"`
		ManagedBotCreated json.RawMessage `json:"managed_bot_created"`
	} `json:"message"`
}

// managedBotUpdate xử lý update Managed Bots tới webhook 3i; ok false là update
// khác, để routeTelegramUpdate đi tiếp như cũ. Lỗi trả ra theo quy tắc của
// webhook 3i: chỉ lỗi tạm thời mới thành 5xx, vì 5xx làm kẹt mọi update của 3i.
func (s *Server) managedBotUpdate(ctx context.Context, raw []byte) (map[string]any, bool, error) {
	var u managerUpdate
	if json.Unmarshal(raw, &u) != nil {
		return nil, false, nil
	}
	if msg := u.Message; msg != nil && len(msg.ManagedBotCreated) > 0 {
		// Chỉ để tra log: việc nối bot đi theo update managed_bot.
		slog.InfoContext(ctx, "mybot.bot_created_message", "updateId", u.UpdateID, "chatId", msg.Chat.ID, "enabled", s.deps.ManagedBots != nil)
		return nil, true, nil
	}
	mb := u.ManagedBot
	if mb == nil {
		return nil, false, nil
	}
	m := s.deps.ManagedBots
	if m == nil {
		slog.WarnContext(ctx, "mybot.update_ignored", "updateId", u.UpdateID, "botId", mb.Bot.ID, "tgUserId", mb.User.ID)
		return nil, true, nil
	}
	if mb.Bot.ID == 0 || mb.User.ID == 0 {
		return nil, true, nil
	}
	res, err := m.Link(ctx, mb.User.ID, mb.Bot.ID, mb.Bot.Username, s.deps.TelegramLinks)
	var reply map[string]any
	switch {
	case errors.Is(err, errManagedNoLink), errors.Is(err, errManagedNoAgent):
		text := managedNoLinkReply
		if errors.Is(err, errManagedNoAgent) {
			text = managedNoAgentReply
		}
		// Người tạo bot qua link của 3i nên đã có DM với 3i; gửi qua response
		// webhook thì không biết tới nơi chưa, nên log để còn tra.
		slog.WarnContext(ctx, "mybot.link_rejected", "tgUserId", mb.User.ID, "botId", mb.Bot.ID, "reason", err.Error())
		reply = map[string]any{"method": "sendMessage", "chat_id": mb.User.ID, "text": text}
	case err != nil:
		return nil, true, err
	default:
		slog.InfoContext(ctx, "mybot.linked", "uid", res.UID, "botId", mb.Bot.ID, "changed", res.Changed, "retired", res.Retired)
	}
	// Bot cũ gỡ webhook trước: enqueue lỗi giữa chừng thì Telegram gửi lại,
	// mà lần đó Link không còn thấy bot cũ nữa. Bot cũ còn sót webhook thì
	// webhook bot con tự hẹn gỡ (xem routeChildUpdate).
	for _, old := range res.Retired {
		if _, err := m.publish(ctx, managedSyncTaskFor(old, "retired")); err != nil {
			return nil, true, err
		}
	}
	if err == nil {
		if _, err := m.publish(ctx, managedSyncTaskFor(strconv.FormatInt(mb.Bot.ID, 10), strconv.FormatInt(u.UpdateID, 10))); err != nil {
			return nil, true, err
		}
	}
	return reply, true, nil
}

type childUpdate struct {
	UpdateID int64 `json:"update_id"`
	Message  *struct {
		Text string `json:"text"`
		Chat struct {
			ID   int64  `json:"id"`
			Type string `json:"type"`
		} `json:"chat"`
		From *managedUser `json:"from"`
	} `json:"message"`
	MyChatMember *struct {
		Chat struct {
			ID    int64  `json:"id"`
			Type  string `json:"type"`
			Title string `json:"title"`
		} `json:"chat"`
		From          managedUser `json:"from"`
		NewChatMember struct {
			Status string `json:"status"`
		} `json:"new_chat_member"`
	} `json:"my_chat_member"`
}

// mybotChildWebhook nhận update của mọi bot con. Secret là HMAC theo botId,
// nên secret của bot này không mở được webhook của bot khác.
func (s *Server) mybotChildWebhook(w http.ResponseWriter, r *http.Request) error {
	m := s.deps.ManagedBots
	if m == nil {
		return errMybotOff
	}
	botID := r.PathValue("botId")
	if _, err := strconv.ParseInt(botID, 10, 64); err != nil || len(botID) > 20 {
		return errMybotOff
	}
	if !secretMatches(r.Header.Get("X-Telegram-Bot-Api-Secret-Token"), m.childSecret(botID)) {
		return &HTTPError{Status: 401, Code: "unauthenticated", Message: "Invalid webhook secret"}
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		w.WriteHeader(http.StatusOK)
		return nil
	}
	s.serveMybot(r.Context(), w, func(ctx context.Context) (map[string]any, error) {
		return nil, s.routeChildUpdate(ctx, m, botID, body)
	})
	return nil
}

func (s *Server) routeChildUpdate(ctx context.Context, m *ManagedBotService, botID string, body []byte) error {
	var u childUpdate
	if json.Unmarshal(body, &u) != nil {
		return nil
	}
	info, ok, err := m.bot(ctx, botID)
	if err != nil {
		return err
	}
	if !ok {
		// Secret đúng nghĩa là webhook này do mình đặt, mà bản ghi đã mất (chủ
		// xoá tài khoản): hẹn Sync để gỡ webhook.
		slog.WarnContext(ctx, "mybot.child_unknown", "botId", botID, "updateId", u.UpdateID)
		_, err := m.publish(ctx, managedSyncTaskFor(botID, "gone"))
		return err
	}
	if info.Retired {
		// Bot đã bị thay mà vẫn còn webhook về đây: hẹn gỡ lần nữa.
		slog.WarnContext(ctx, "mybot.child_retired", "botId", botID, "updateId", u.UpdateID)
		_, err := m.publish(ctx, managedSyncTaskFor(botID, "retired"))
		return err
	}
	if mc := u.MyChatMember; mc != nil {
		return s.childMembership(ctx, m, info, u.UpdateID, mc.Chat.ID, mc.Chat.Type, mc.Chat.Title, mc.From.ID, mc.NewChatMember.Status)
	}
	msg := u.Message
	if msg == nil || msg.From == nil || msg.From.IsBot || msg.Chat.Type != "private" {
		// Tin trong group (privacy mode chỉ đẩy tin nhắc bot) chưa xử lý ở bản
		// này; tin trong PSC thì bot quản lý đọc (T4).
		return nil
	}
	fresh, err := m.claimUpdate(ctx, botID, u.UpdateID)
	if err != nil || !fresh {
		if !fresh && err == nil {
			slog.InfoContext(ctx, "mybot.update_duplicate", "botId", botID, "updateId", u.UpdateID)
		}
		return err
	}
	chatID := strconv.FormatInt(msg.Chat.ID, 10)
	key := "upd-" + strconv.FormatInt(u.UpdateID, 10)
	if msg.From.ID != info.OwnerTgID {
		err = m.enqueueManagedSend(ctx, botID, chatID, managedStrangerReply, key)
	} else {
		err = s.agentTelegramDM(ctx, m, info.UID, botID, chatID, msg.Text, key)
	}
	if err != nil {
		m.releaseUpdate(ctx, botID, u.UpdateID)
		return &mybotRetryErr{err}
	}
	return nil
}

// agentTelegramDM đưa tin chủ nhắn bot con vào chat riêng kênh telegram, như
// chủ nhắn trong app. Lỗi đã biết của PostDM thì trả câu cố định, không gọi
// model; lỗi khác trả ra để webhook trả 5xx và Telegram gửi lại.
func (s *Server) agentTelegramDM(ctx context.Context, m *ManagedBotService, uid, botID, chatID, text, key string) error {
	_, err := s.PostChannelDM(ctx, uid, agentChannelTelegram, text)
	if err == nil {
		return nil
	}
	var reply string
	switch {
	case errors.Is(err, errAgentDisabled):
		reply = "Bạn chưa được mời dùng MyBot. Mở app 3i Run để xem: " + s.config.WebBaseURL
	case errors.Is(err, errAgentConsentRequired):
		reply = "Bạn cần đồng ý cho bot gửi dữ liệu tới AI trong app 3i Run trước: " + s.config.WebBaseURL
	case errors.Is(err, errAgentNotFound):
		reply = "Bạn chưa tạo MyBot trong app 3i Run: " + s.config.WebBaseURL
	case errors.Is(err, errAgentText):
		reply = managedTextReply
	case errors.Is(err, errAgentTooFast):
		reply = managedTooFastReply
	default:
		return err
	}
	slog.InfoContext(ctx, "mybot.dm_rejected", "uid", uid, "botId", botID, "reason", err.Error())
	return m.enqueueManagedSend(ctx, botID, chatID, reply, key)
}

// childMembership: bot con vào hay ra một group. PSC duyệt sẵn: vào thì được
// nói trong topic Phòng bot, ra (rời, bị kick) thì thôi. Group khác thì bản này
// chưa có bước chủ xác nhận (T7), nên bot không nói gì và rời ngay.
func (s *Server) childMembership(ctx context.Context, m *ManagedBotService, info managedBotInfo, updateID, chatID int64, chatType, title string, by int64, newStatus string) error {
	if chatType == "private" {
		return nil
	}
	botID := info.ID
	joined := newStatus == "member" || newStatus == "administrator"
	chat := strconv.FormatInt(chatID, 10)
	if chat == s.config.TelegramChatID {
		slog.InfoContext(ctx, "mybot.psc_membership", "botId", botID, "uid", info.UID, "status", newStatus, "addedBy", by)
		return m.setInPsc(ctx, info.UID, botID, joined)
	}
	if !joined {
		return nil
	}
	slog.WarnContext(ctx, "mybot.group_left_v1", "botId", botID, "chatId", chatID, "title", title, "addedBy", by)
	return m.enqueueManagedLeave(ctx, botID, chat, "leave-"+chat+"-"+strconv.FormatInt(updateID, 10))
}

// ---- Task trên bot service ----

func (s *Server) managedBotSync(w http.ResponseWriter, r *http.Request) error {
	var task managedSyncTask
	if decodeJSON(r, &task) != nil || task.BotID == "" || s.deps.ManagedBots == nil {
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if err := s.deps.ManagedBots.Sync(r.Context(), task.BotID); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

func (s *Server) managedSend(w http.ResponseWriter, r *http.Request) error {
	var task managedSendTask
	if decodeJSON(r, &task) != nil || task.BotID == "" || task.Key == "" || s.deps.ManagedBots == nil {
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if err := s.deps.ManagedBots.Deliver(r.Context(), task.BotID, task.Key); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
