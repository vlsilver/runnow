package backend

import (
	"context"
	"errors"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Phòng bot trên Telegram (T4): một topic của PSC là phòng tg-psc, độc lập với
// phòng main trong app. Bot con để privacy mode nên không thấy tin thường
// trong group; 3i là admin nên thấy hết, vì vậy 3i ghi tin của người trong
// topic vào phòng, còn tin của từng MyBot do chính bot con của chủ gửi ra topic
// (ManagedBotService.roomOut). 3i không nói trong topic này.
//
// Trí nhớ vẫn chung giữa hai phòng: bot nào cũng đọc điều chủ dạy và ký ức tự
// học (agentRooms/main/learned). Tin trong topic vẫn được 3i ghi vào
// botMessages như mọi tin PSC, nên việc tự học học được từ đây mà không cần
// thêm nguồn.
//
//	agentState/config.tgRoomThreadId    message_thread_id của topic; admin đặt bằng /phongbot
//	agentRooms/tg-psc/tgUpdates/{key}   update_id đã ghi vào phòng, và câu nhắc đã gửi trong ngày

const telegramRoomCommand = "/phongbot"

const (
	tgRoomNoLinkHint   = "Các bot chưa đọc được tin của bạn: liên kết Telegram trong app 3i Run trước nhé."
	tgRoomDisabledHint = "Các bot chưa đọc được tin của bạn: MyBot chưa mở cho tài khoản này."
	tgRoomConsentHint  = "Các bot chưa đọc được tin của bạn: mở MyBot trong app 3i Run và đồng ý cho bot gửi dữ liệu tới AI trước nhé."
)

// telegramRoomThread là topic Phòng bot đã đặt trong cfg (agentState/config);
// 0 là chưa đặt hoặc đã tắt.
func telegramRoomThread(cfg map[string]any) int64 {
	return int64(number(cfg["tgRoomThreadId"]))
}

func (s *AgentStore) TelegramRoomThread(ctx context.Context) (int64, error) {
	cfg, err := getData(ctx, s.configRef())
	if err != nil {
		return 0, err
	}
	return telegramRoomThread(cfg), nil
}

// SetTelegramRoomThread đặt topic Phòng bot; thread 0 là tắt. Không đụng
// adminUpdatedAt: trang admin không sửa field này nên không cần báo trang đang
// mở tải lại.
func (s *AgentStore) SetTelegramRoomThread(ctx context.Context, thread int64, by string, wall time.Time) error {
	var v any = thread
	if thread == 0 {
		v = firestore.Delete
	}
	_, err := s.configRef().Set(ctx, map[string]any{"tgRoomThreadId": v, "tgRoomSetBy": by, "tgRoomSetAt": wall}, firestore.MergeAll)
	return err
}

// claimRoomHint ghi key câu nhắc; false là đã nhắc rồi.
func (s *AgentStore) claimRoomHint(ctx context.Context, key string, wall time.Time) (bool, error) {
	_, err := s.roomRef(agentTelegramRoom).Collection("tgUpdates").Doc(key).Create(ctx, map[string]any{"at": wall, "expiresAt": wall.Add(managedUpdateTTL)})
	if status.Code(err) == codes.AlreadyExists {
		return false, nil
	}
	return err == nil, err
}

// telegramRoomOn: Phòng bot đang bật trên PSC, nên đáng mời chủ đưa bot vào.
func (s *Server) telegramRoomOn(ctx context.Context) (bool, error) {
	if s.deps == nil || s.deps.Agents == nil || s.config.TelegramChatID == "" {
		return false, nil
	}
	thread, err := s.deps.Agents.TelegramRoomThread(ctx)
	return thread != 0, err
}

// telegramRoomMessage đưa tin của người trong topic Phòng bot vào phòng tg-psc.
// inRoom true là tin nằm trong topic đó, kể cả khi không vào phòng được, để 3i
// không tự trả lời ở đây. reply là câu 3i nhắc người chưa đủ điều kiện (chưa
// liên kết, chưa được dùng MyBot, chưa đồng ý dùng AI), mỗi người một lần mỗi
// ngày, để người đó biết vì sao các bot im mà topic không ngập câu nhắc.
func (s *Server) telegramRoomMessage(ctx context.Context, update TelegramUpdate) (map[string]any, bool, error) {
	msg := update.Message
	thread := messageThreadID(update)
	if s.deps == nil || s.deps.ManagedBots == nil || s.deps.Agents == nil || s.deps.TelegramLinks == nil ||
		msg == nil || msg.From == nil || thread == 0 || strconv.FormatInt(msg.Chat.ID, 10) != s.config.TelegramChatID {
		return nil, false, nil
	}
	room, err := s.deps.Agents.TelegramRoomThread(ctx)
	if err != nil {
		return nil, false, err
	}
	if room != thread {
		return nil, false, nil
	}
	// Ảnh kèm chữ thì chữ nằm ở caption; bot nhìn ảnh lúc tới lượt nói.
	text := strings.TrimSpace(msg.Text)
	if text == "" {
		text = strings.TrimSpace(msg.Caption)
	}
	if msg.From.IsBot || text == "" {
		return nil, true, nil // sticker, ảnh không chú thích: không có gì để đáp
	}
	uid, err := s.deps.TelegramLinks.UIDForTelegram(ctx, msg.From.ID)
	if err != nil {
		return nil, true, err
	}
	hint := tgRoomNoLinkHint
	if uid != "" {
		src := roomSource{key: strconv.FormatInt(update.UpdateID, 10), photo: photoFileID(update)}
		if r := msg.ReplyToMessage; r != nil && r.From != nil && r.From.IsBot {
			src.replyToBot = strconv.FormatInt(r.From.ID, 10)
		}
		_, err := s.postRoomMessage(ctx, agentTelegramRoom, uid, text, src)
		switch {
		case err == nil:
			return nil, true, nil
		case errors.Is(err, errAgentDisabled):
			hint = tgRoomDisabledHint
		case errors.Is(err, errAgentConsentRequired):
			hint = tgRoomConsentHint
		case errors.Is(err, errAgentText), errors.Is(err, errAgentTooFast):
			slog.InfoContext(ctx, "agent.tg_room_skip", "uid", uid, "reason", err.Error())
			return nil, true, nil
		default:
			return nil, true, err
		}
	}
	wall := s.now()
	first, err := s.deps.Agents.claimRoomHint(ctx, "hint-"+strconv.FormatInt(msg.From.ID, 10)+"-"+vnDay(wall), wall)
	if err != nil || !first {
		return nil, true, err
	}
	slog.InfoContext(ctx, "agent.tg_room_hint", "uid", uid, "hint", hint)
	return map[string]any{
		"method": "sendMessage", "chat_id": msg.Chat.ID, "message_thread_id": thread, "text": hint,
		"reply_parameters": map[string]any{"message_id": msg.MessageID},
	}, true, nil
}

// telegramRoomCommandText chạy /phongbot: admin gõ trong một topic của PSC thì
// topic đó thành Phòng bot; "/phongbot tat" thì tắt. Bot API không có hàm liệt
// kê topic, nên lấy message_thread_id từ chính tin gõ lệnh.
func (s *Server) telegramRoomCommandText(ctx context.Context, update TelegramUpdate, arg string) (string, error) {
	msg := update.Message
	if s.deps == nil || s.deps.ManagedBots == nil || s.deps.Agents == nil || s.deps.TelegramLinks == nil || s.deps.Games == nil {
		return "MyBot trên Telegram đang tắt.", nil
	}
	if strconv.FormatInt(msg.Chat.ID, 10) != s.config.TelegramChatID {
		return "Lệnh này chỉ dùng trong group PSC.", nil
	}
	uid, err := s.deps.TelegramLinks.UIDForTelegram(ctx, msg.From.ID)
	if err != nil {
		return adminFailedText, err
	}
	if uid == "" {
		return "Tài khoản Telegram này chưa liên kết với 3i Run.", nil
	}
	if err := s.deps.Games.RequireAdmin(ctx, uid); errors.Is(err, errNotAdmin) {
		return "Lệnh này chỉ dành cho admin.", nil
	} else if err != nil {
		return adminFailedText, err
	}
	thread := messageThreadID(update)
	off := map[string]bool{"tat": true, "tắt": true, "off": true}[strings.ToLower(strings.TrimSpace(arg))]
	if off {
		thread = 0
	} else if thread == 0 {
		return "Gõ lệnh này trong topic muốn dùng làm Phòng bot, không phải General.", nil
	}
	if err := s.deps.Agents.SetTelegramRoomThread(ctx, thread, uid, s.now()); err != nil {
		return adminFailedText, err
	}
	slog.InfoContext(ctx, "agent.tg_room_set", "uid", uid, "thread", thread)
	if off {
		return "Đã tắt Phòng bot: các MyBot thôi nói trong topic.", nil
	}
	return "Topic này giờ là Phòng bot. MyBot nào đã được thêm vào PSC sẽ trò chuyện ở đây, còn 3i không trả lời trong topic này.", nil
}
