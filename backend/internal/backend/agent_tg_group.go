package backend

import (
	"context"
	"errors"
	"log/slog"
	"slices"
	"strconv"
	"strings"
)

// MyBot ở group chính PSC (phòng tg-group): General và mọi topic trừ topic
// Phòng bot. Khác Phòng bot, ở đây bot chỉ nói khi được gọi, để không chen vào
// chuyện thường ngày của group:
//   - tin reply tin của bot, hay @username của bot: bot đó trả lời;
//   - tin reply tin của chủ bot (người khác gửi, không hỏi 3i): bot của chủ
//     được đỡ lời, model tự nhường lượt khi tin không cần đáp;
//   - tin bot: bot khác chỉ nói tiếp khi bị gọi tên, tối đa agentGroupChainMax.
//
// Chỉ tin gọi bot mới vào phòng, nên transcript là chuỗi các lần gọi chứ không
// phải cả group. Bot con để privacy mode nên 3i (admin, thấy mọi tin) đưa tin
// vào phòng; tin của bot đi ra bằng chính bot con của chủ (roomOut), reply tin
// đã gọi nó.

const (
	agentGroupChainMax = 3
	// agentGroupQuoteRunes là phần đầu tin được reply mà bot đọc kèm.
	agentGroupQuoteRunes = 300
)

const agentGroupRule = `

NƠI BẠN ĐANG NÓI: group Telegram chung của club, nơi mọi người chat chuyện thường ngày, không phải phòng bot. Bạn chỉ được gọi ra khi có người reply hay nhắc tên bạn, hoặc khi có người trả lời tin của chủ bạn.
- Người ta trả lời tin của chủ bạn mà trêu, hỏi, khen hay chê chủ thì đỡ lời cho chủ một câu vui, có duyên, không gắt. Tin bình thường không cần bạn chen vào (chào hỏi, "ok", hẹn giờ, việc công ty) thì trả đúng ` + agentPass + `.
- Ngắn hơn phòng bot: 1 đến 2 câu.`

// telegramGroupMessage đưa tin ở PSC ngoài topic Phòng bot vào phòng tg-group
// khi tin đó gọi một MyBot đang ở PSC. askedThreeI: tin đang hỏi 3i, khi đó
// reply tin của chủ bot không gọi bot của chủ, để không hai bot cùng đáp.
// Không gọi bot nào thì không làm gì.
func (s *Server) telegramGroupMessage(ctx context.Context, update TelegramUpdate, askedThreeI bool) error {
	msg := update.Message
	if s.deps == nil || s.deps.ManagedBots == nil || s.deps.Agents == nil || s.deps.TelegramLinks == nil ||
		msg == nil || msg.From == nil || msg.From.IsBot || strconv.FormatInt(msg.Chat.ID, 10) != s.config.TelegramChatID {
		return nil
	}
	text := strings.TrimSpace(msg.Text)
	if text == "" {
		text = strings.TrimSpace(msg.Caption)
	}
	reply := msg.ReplyToMessage
	if reply != nil && (reply.From == nil || msg.IsTopicMessage && reply.MessageID == msg.MessageThreadID) {
		reply = nil // reply ngầm vào tin tạo topic, Telegram gắn cho mọi tin trong topic
	}
	// Phần lớn tin group không reply, không @ ai: khỏi đọc Firestore.
	if text == "" || reply == nil && !strings.Contains(text, "@") {
		return nil
	}
	acc, err := s.deps.Agents.access(ctx)
	if err != nil {
		return err
	}
	agents, err := s.deps.Agents.telegramRoomAgents(ctx, acc)
	if err != nil || len(agents) == 0 {
		return err
	}
	src := roomSource{
		key: strconv.FormatInt(update.UpdateID, 10), photo: photoFileID(update),
		tgUserID: msg.From.ID, tgThread: messageThreadID(update), tgMessageID: msg.MessageID,
	}
	if reply != nil {
		src.replyText = truncateRunes(strings.TrimSpace(reply.Text), agentGroupQuoteRunes)
		if reply.From.IsBot {
			id := strconv.FormatInt(reply.From.ID, 10)
			if slices.ContainsFunc(agents, func(ag roomAgent) bool { return ag.botID == id }) {
				src.replyToBot = id
			}
		}
	}
	lower := strings.ToLower(text)
	mentioned := slices.ContainsFunc(agents, func(ag roomAgent) bool {
		return ag.username != "" && mentions(lower, strings.ToLower(ag.username))
	})
	if src.replyToBot == "" && !mentioned {
		if askedThreeI || reply == nil || reply.From.IsBot || reply.From.ID == msg.From.ID {
			return nil
		}
		owner, err := s.deps.TelegramLinks.UIDForTelegram(ctx, reply.From.ID)
		if err != nil {
			return err
		}
		if owner == "" || !slices.ContainsFunc(agents, func(ag roomAgent) bool { return ag.uid == owner }) {
			return nil
		}
		src.target = owner
	}
	uid, err := s.deps.TelegramLinks.UIDForTelegram(ctx, msg.From.ID)
	if err != nil {
		return err
	}
	if uid == "" {
		src.name = senderName(update)
	}
	_, err = s.postRoomMessage(ctx, agentTelegramGroupRoom, uid, text, src)
	if errors.Is(err, errAgentText) || errors.Is(err, errAgentTooFast) {
		slog.InfoContext(ctx, "agent.tg_group_skip", "uid", uid, "reason", err.Error())
		return nil
	}
	return err
}

// pickGroupSpeaker chọn bot nói ở phòng tg-group: chỉ bot được gọi. Tin người
// gọi bot bằng reply hay @username (addressedBot), hay reply tin của chủ bot
// (targetUid); tin bot thì bot khác chỉ nói tiếp khi bị gọi tên hay @username.
// Không ai được gọi thì thôi, khác phòng bot nơi bot lâu chưa nói được nói tiếp.
func pickGroupSpeaker(agents []roomAgent, _ map[string]any, last map[string]any) (roomAgent, bool) {
	if ag, ok := addressedBot(agents, last); ok {
		return ag, true
	}
	if stringValue(last["kind"]) == agentKindHuman {
		target := stringValue(last["targetUid"])
		for _, ag := range agents {
			if target != "" && ag.uid == target {
				return ag, true
			}
		}
		return roomAgent{}, false
	}
	text := strings.ToLower(stringValue(last["text"]))
	for _, ag := range agents {
		if ag.uid == stringValue(last["uid"]) {
			continue
		}
		name := strings.ToLower(strings.TrimSpace(ag.name))
		if name != "" && strings.Contains(text, name) || ag.username != "" && mentions(text, strings.ToLower(ag.username)) {
			return ag, true
		}
	}
	return roomAgent{}, false
}

// repliedTo là phần ghi chú tin người m đang trả lời ai, để bot biết người ta
// đáp câu nào: ", trả lời tin của X: "..."". Rỗng khi tin không reply bot hay
// chủ bot (phòng main, Phòng bot không có replyText).
func repliedTo(m map[string]any, names map[string]string, agents []roomAgent) string {
	who := ""
	if bot := stringValue(m["replyToBot"]); bot != "" {
		for _, ag := range agents {
			if ag.botID == bot {
				who = ag.name
			}
		}
	}
	if target := stringValue(m["targetUid"]); who == "" && target != "" {
		who = names[target]
	}
	if who == "" {
		return ""
	}
	if quote := stringValue(m["replyText"]); quote != "" {
		return ", trả lời tin của " + who + ": \"" + quote + "\""
	}
	return ", trả lời tin của " + who
}
