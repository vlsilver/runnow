package backend

import (
	"context"
	"errors"
	"fmt"
	"html"
	"log/slog"
	"net/url"
	"regexp"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Thẻ Live trên Telegram: mỗi buổi live một tin duy nhất (trong topic Live
// Track nếu đã đặt). Sự kiện đầu tiên gửi thẻ, các mốc km và về đích chỉ sửa
// thẻ, nên group không bị một chuỗi tin dài. Người trong group bấm emoji cổ
// vũ ngay trên thẻ; lượt bấm ghi vào liveCheers như cổ vũ trong app, nên người
// chạy nhận toast trên màn chạy.
//
//	liveAnnounceState/{activityId}.card
//	  name, meters, seconds, line, finished   nội dung đang hiện
//	  version                                 tăng mỗi lần nội dung đổi
//	  messageId, chatId                       tin thẻ, 0 là chưa gửi
//	  sendingAt                               một task đang gửi thẻ
//
// Nội dung nằm trong Firestore, thẻ trên Telegram chỉ là bản vẽ của nó. Task
// nào đổi nội dung thì tự sửa thẻ, rồi đọc lại version: đổi trong lúc sửa thì
// sửa lần nữa, để hai task chạy song song không để lại thẻ cũ hơn dữ liệu.

// liveCheerEmojis khớp liveCheerEmojis của app và validCheer trong
// firestore.rules; thêm emoji thì sửa cả ba nơi.
var liveCheerEmojis = []string{"👏", "🔥", "💪", "🐢", "🏁"}

const (
	// liveCardSendLease: quá lâu mà task gửi thẻ chưa ghi được messageId thì
	// coi như nó đã chết, task sau được gửi lại.
	liveCardSendLease = 30 * time.Second
	// liveCardRefreshEvery gom các lượt bấm cổ vũ thành tối đa một lần sửa thẻ,
	// để cả group bấm dồn không làm Telegram trả 429.
	liveCardRefreshEvery = 10 * time.Second
	// liveStale khớp LiveSession.isExpired của app: quá 3 phút không cập nhật
	// là mất tín hiệu.
	liveStale = 3 * time.Minute
	// liveCardSyncRounds chặn vòng sửa lại khi nội dung đổi liên tục.
	liveCardSyncRounds = 3
)

type liveCardContent struct {
	name     string
	meters   float64
	seconds  float64
	line     string
	finished bool
}

// liveCardTakesOver: nội dung mới có thay nội dung đang hiện không. Task tới
// không theo thứ tự, nên mốc nhỏ hơn tới sau không được kéo thẻ lùi, và đã về
// đích thì giữ nguyên.
func liveCardTakesOver(card map[string]any, c liveCardContent) bool {
	if card["name"] == nil {
		return true
	}
	if finished, _ := card["finished"].(bool); finished {
		return false
	}
	return c.finished || c.meters >= number(card["meters"])
}

// claimLiveCardEvent đánh dấu sự kiện marker đã báo và ghi nội dung thẻ trong
// một transaction. claimed false là sự kiện đã báo rồi. send true là task này
// giữ quyền gửi thẻ (chưa có thẻ và không ai đang gửi).
func claimLiveCardEvent(ctx context.Context, db *firestore.Client, ref *firestore.DocumentRef, marker string, update map[string]any, c liveCardContent, now time.Time) (claimed, send bool, err error) {
	err = db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		claimed, send = false, false
		snap, err := tx.Get(ref)
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		var data map[string]any
		if err == nil {
			data = snap.Data()
		}
		if data[marker] != nil {
			return nil
		}
		claimed = true
		card := map[string]any{}
		if old, ok := data["card"].(map[string]any); ok {
			for k, v := range old {
				card[k] = v
			}
		}
		if liveCardTakesOver(card, c) {
			card["name"], card["meters"], card["seconds"], card["line"], card["finished"] = c.name, c.meters, c.seconds, c.line, c.finished
			card["version"] = int64(number(card["version"])) + 1
		}
		if int64(number(card["messageId"])) == 0 {
			at, _ := card["sendingAt"].(time.Time)
			if at.IsZero() || now.Sub(at) > liveCardSendLease {
				card["sendingAt"] = now
				send = true
			}
		}
		fields := map[string]any{"card": card}
		for k, v := range update {
			fields[k] = v
		}
		return tx.Set(ref, fields, firestore.MergeAll)
	})
	return claimed, send, err
}

// sendLiveCard gửi thẻ lần đầu rồi ghi messageId. Gửi lỗi thì nhả quyền gửi để
// sự kiện sau gửi lại.
func (s *ActivityService) sendLiveCard(ctx context.Context, activityID string, thread int64) error {
	ref := s.db.Collection("liveAnnounceState").Doc(activityID)
	text, markup, _, err := s.renderLiveCard(ctx, activityID)
	if err != nil {
		return err
	}
	chatID := s.telegram.ChatID()
	id, err := s.telegram.SendText(ctx, TelegramText{ChatID: chatID, ThreadID: thread, Text: text, HTML: true, Markup: markup})
	var apiErr *TelegramAPIError
	if thread != 0 && errors.As(err, &apiErr) && strings.Contains(apiErr.Description, "message thread not found") {
		slog.WarnContext(ctx, "telegram.thread_missing", "method", "sendMessage", "threadId", thread)
		id, err = s.telegram.SendText(ctx, TelegramText{ChatID: chatID, Text: text, HTML: true, Markup: markup})
	}
	if err != nil {
		if _, uerr := ref.Update(ctx, []firestore.Update{{Path: "card.sendingAt", Value: firestore.Delete}}); uerr != nil {
			slog.WarnContext(ctx, "live.card_release_failed", "error", uerr)
		}
		return err
	}
	if _, err := ref.Update(ctx, []firestore.Update{
		{Path: "card.messageId", Value: id},
		{Path: "card.chatId", Value: chatID},
		{Path: "card.sendingAt", Value: firestore.Delete},
	}); err != nil {
		return err
	}
	// Sự kiện tới trong lúc đang gửi chỉ ghi nội dung, nên vẽ lại một lần.
	return s.SyncLiveCard(ctx, activityID)
}

// SyncLiveCard vẽ lại thẻ theo nội dung, số cổ vũ và trạng thái buổi live hiện
// tại. Chưa có thẻ thì thôi: task đang gửi sẽ tự vẽ lại sau khi gửi xong.
func (s *ActivityService) SyncLiveCard(ctx context.Context, activityID string) error {
	ref := s.db.Collection("liveAnnounceState").Doc(activityID)
	for range liveCardSyncRounds {
		text, markup, card, err := s.renderLiveCard(ctx, activityID)
		if err != nil {
			return err
		}
		messageID := int64(number(card["messageId"]))
		if messageID == 0 {
			return nil
		}
		err = s.telegram.EditText(ctx, stringValue(card["chatId"]), messageID, text, true, markup)
		var apiErr *TelegramAPIError
		switch {
		case errors.As(err, &apiErr) && strings.Contains(apiErr.Description, "message is not modified"):
		case errors.As(err, &apiErr) && apiErr.Status == 400:
			// Thẻ bị xoá hay hỏng: gửi lại cũng hỏng y vậy.
			slog.WarnContext(ctx, "live.card_edit_rejected", "activityId", activityID, "error", err)
			return nil
		case err != nil:
			return err
		}
		after, err := getData(ctx, ref)
		if err != nil {
			return err
		}
		next, _ := after["card"].(map[string]any)
		if number(next["version"]) == number(card["version"]) {
			return nil
		}
	}
	return nil
}

// renderLiveCard đọc state, số cổ vũ và buổi live rồi vẽ thẻ. card là state
// thẻ đã dùng để vẽ (rỗng khi chưa có).
func (s *ActivityService) renderLiveCard(ctx context.Context, activityID string) (string, map[string]any, map[string]any, error) {
	state, err := getData(ctx, s.db.Collection("liveAnnounceState").Doc(activityID))
	if err != nil {
		return "", nil, nil, err
	}
	card, _ := state["card"].(map[string]any)
	counts, err := liveCheerCounts(ctx, s.db, activityID)
	if err != nil {
		return "", nil, nil, err
	}
	session, err := getData(ctx, s.db.Collection("liveSessions").Doc(activityID))
	if err != nil {
		return "", nil, nil, err
	}
	now := time.Now()
	return liveCardText(card, session, now), liveCardMarkup(activityID, counts, s.webBaseURL), card, nil
}

// liveCardStatus: về đích thì chốt; còn lại theo buổi live app đang ghi.
func liveCardStatus(card, session map[string]any, now time.Time) string {
	if finished, _ := card["finished"].(bool); finished {
		return "🏁 Về đích"
	}
	switch stringValue(session["status"]) {
	case "paused":
		return "⏸ Tạm dừng"
	case "finished", "expired":
		return "⚪ Đã dừng live"
	}
	if at, ok := session["updatedAt"].(time.Time); ok && now.Sub(at) > liveStale {
		return "⚪ Mất tín hiệu"
	}
	return "🟢 Đang chạy"
}

func liveCardText(card, session map[string]any, now time.Time) string {
	var b strings.Builder
	fmt.Fprintf(&b, "<b>%s</b> · %s\n", html.EscapeString(strings.TrimSpace(stringValue(card["name"]))), liveCardStatus(card, session, now))
	meters, seconds := number(card["meters"]), number(card["seconds"])
	fmt.Fprintf(&b, "📏 %s · ⏱ %s", formatDistanceKm(meters), formatDurationHMS(int64(seconds)))
	if meters >= 100 && seconds >= 1 {
		pace := int64(seconds / (meters / 1000))
		fmt.Fprintf(&b, " · ⚡ %d:%02d/km", pace/60, pace%60)
	}
	b.WriteString("\n")
	if line := strings.TrimSpace(stringValue(card["line"])); line != "" {
		fmt.Fprintf(&b, "💬 %s\n", html.EscapeString(truncateRunes(line, 300)))
	}
	fmt.Fprintf(&b, "🕒 Cập nhật %s", now.In(vietnam).Format("15:04"))
	return b.String()
}

// liveCardMarkup: hàng nút cổ vũ (kèm số đã bấm) và nút mở buổi live trên web.
func liveCardMarkup(activityID string, counts map[string]int, webBaseURL string) map[string]any {
	var rows [][]map[string]any
	if liveCheerIDPattern.MatchString(activityID) {
		row := make([]map[string]any, 0, len(liveCheerEmojis))
		for i, emoji := range liveCheerEmojis {
			label := emoji
			if n := counts[emoji]; n > 0 {
				label = emoji + " " + strconv.Itoa(n)
			}
			row = append(row, map[string]any{"text": label, "callback_data": liveCheerData(activityID, i)})
		}
		rows = append(rows, row)
	}
	if webBaseURL != "" {
		rows = append(rows, []map[string]any{{"text": "Xem trên 3i Run", "url": webBaseURL + "/live/" + url.PathEscape(activityID)}})
	}
	if len(rows) == 0 {
		return nil
	}
	return inlineKeyboard(rows)
}

// liveCheerCounts cộng số lần bấm từng emoji của mọi người xem. Mỗi người một
// document nên đọc hết không vượt số người xem.
func liveCheerCounts(ctx context.Context, db *firestore.Client, activityID string) (map[string]int, error) {
	docs, err := db.Collection("liveCheers").Doc(activityID).Collection("by").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	counts := map[string]int{}
	for _, d := range docs {
		n, _ := d.Data()["n"].(map[string]any)
		for emoji, v := range n {
			counts[emoji] += int(number(v))
		}
	}
	return counts, nil
}

// Nút cổ vũ: l1|<activityId>|<vị trí emoji>. callback_data tối đa 64 byte nên
// id buổi giới hạn 58 ký tự; id của app là "runnow-<ms>".
var liveCheerIDPattern = regexp.MustCompile(`^[A-Za-z0-9_-]{1,58}$`)

func liveCheerData(activityID string, i int) string {
	return "l1|" + activityID + "|" + strconv.Itoa(i)
}

// parseLiveCheer: false là không phải nút cổ vũ, hoặc data bị sửa.
func parseLiveCheer(data string) (activityID, emoji string, ok bool) {
	parts := strings.Split(data, "|")
	if len(parts) != 3 || parts[0] != "l1" || !liveCheerIDPattern.MatchString(parts[1]) {
		return "", "", false
	}
	i, err := strconv.Atoi(parts[2])
	if err != nil || i < 0 || i >= len(liveCheerEmojis) {
		return "", "", false
	}
	return parts[1], liveCheerEmojis[i], true
}

// liveCheerText ghi một lượt bấm cổ vũ từ Telegram và trả câu toast cho người
// bấm. Chỉ tài khoản đã liên kết mới cổ vũ được: lượt bấm mang uid như cổ vũ
// trong app, và không phải lưu Telegram id của người lạ. Thẻ sửa sau tối đa
// liveCardRefreshEvery; hẹn task lỗi thì chỉ log, vì lượt bấm đã ghi và lần
// sửa thẻ sau vẫn cộng nó.
func (s *Server) liveCheerText(ctx context.Context, tgUserID int64, activityID, emoji string, received time.Time) (string, error) {
	if s.deps == nil || s.deps.Firestore == nil || s.deps.TelegramLinks == nil {
		return "Nút này chưa dùng được.", nil
	}
	uid, err := s.deps.TelegramLinks.UIDForTelegram(ctx, tgUserID)
	if err != nil {
		return adminFailedText, err
	}
	if uid == "" {
		return "Liên kết Telegram trong app 3i Run để cổ vũ nhé.", nil
	}
	db := s.deps.Firestore
	state, err := getData(ctx, db.Collection("liveAnnounceState").Doc(activityID))
	if err != nil {
		return adminFailedText, err
	}
	card, _ := state["card"].(map[string]any)
	if card == nil {
		return "Buổi live này không còn nhận cổ vũ.", nil
	}
	if _, err := db.Collection("liveCheers").Doc(activityID).Collection("by").Doc(uid).Set(ctx, map[string]any{
		"uid": uid, "emoji": emoji, "n": map[string]any{emoji: firestore.Increment(1)}, "at": firestore.ServerTimestamp,
	}, firestore.MergeAll); err != nil {
		return adminFailedText, err
	}
	if publish := s.enqueueTask(); publish != nil {
		at := received.Truncate(liveCardRefreshEvery).Add(liveCardRefreshEvery)
		task := PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/live-card", Payload: map[string]any{"activityId": activityID},
			TaskID: StableTaskID("livecard", map[string]any{"activityId": activityID, "at": at.Unix()}), ScheduleTime: &at}
		if _, err := publish(ctx, task); err != nil {
			slog.WarnContext(ctx, "live.card_refresh_enqueue_failed", "activityId", activityID, "error", err)
		}
	}
	return fmt.Sprintf("Đã gửi %s cho %s", emoji, strings.TrimSpace(stringValue(card["name"]))), nil
}
