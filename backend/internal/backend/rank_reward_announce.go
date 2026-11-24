package backend

import (
	"context"
	"fmt"
	"html"
	"log/slog"
	"net/http"
	"net/url"
	"regexp"
	"strings"

	"cloud.google.com/go/firestore"
)

// Bài báo quà BXH trong group: sau khi bảng có người trúng quà, bot đăng một
// tin liệt kê ai trúng món gì, món bốc thăm ghi số người trong lượt bốc, kèm
// nút mở bảng trên 3i Run. Chạy ở runnow-bot vì cần Telegram, qua queue
// notifications như push quà.
const rankRewardAnnouncePath = "/tasks/rank-reward-announce"

// rankRewardAnnouncer đăng bài báo quà. telegram nil hoặc tắt thì bỏ qua.
// broadcast ghi bài vào trí nhớ bot, để bot trả lời lời chúc mừng có ngữ
// cảnh; nil hay tắt thì chỉ đăng.
type rankRewardAnnouncer struct {
	db         *firestore.Client
	telegram   *TelegramService
	links      *TelegramLinkService
	broadcast  rankRewardBroadcast
	webBaseURL string
}

type rankRewardBroadcast interface {
	Enabled() bool
	RecordBroadcast(ctx context.Context, chatID, text string) error
}

// rankRewardTags là thẻ HTML trong bài báo quà, bỏ đi trước khi ghi vào trí
// nhớ bot: <b> và tag người trúng.
var rankRewardTags = regexp.MustCompile(`</?b>|<a href="[^"]*">|</a>`)

// Announce đăng bài báo quà của boardID một lần. Đăng xong thì ghi
// announcedAt lên bảng; task chạy lại sau đó thấy announcedAt thì thôi. Chọn
// thà đăng trùng còn hơn lỡ bài, như báo kèo mới: Telegram nhận tin mà trả lời
// quá hạn, hay ghi announcedAt hỏng, thì lần thử lại đăng thêm một bài. Ghi
// announcedAt không theo ctx request, để request bị huỷ sau khi đăng không mở
// thêm cửa đăng trùng.
func (a rankRewardAnnouncer) Announce(ctx context.Context, boardID string) error {
	if a.telegram == nil || !a.telegram.Enabled() {
		return nil
	}
	key, ok := parseRankBoardID(boardID)
	if !ok {
		return nil
	}
	ref := a.db.Collection("rankBoards").Doc(boardID)
	board, err := getData(ctx, ref)
	if err != nil || board == nil {
		return err
	}
	if board["announcedAt"] != nil {
		return nil
	}
	entries := anyList(board["entries"])
	tgIDs, err := a.winnerTelegramIDs(ctx, entries)
	if err != nil {
		return err
	}
	text := rankRewardAnnounceText(key, entries, tgIDs)
	if text == "" {
		return nil
	}
	var markup any
	if a.webBaseURL != "" {
		markup = map[string]any{"inline_keyboard": [][]map[string]any{{{"text": "Xem thẻ quà trên 3i Run", "url": rankBoardLink(a.webBaseURL, boardID)}}}}
	}
	msgID, err := a.telegram.SendText(ctx, TelegramText{ChatID: a.telegram.ChatID(), Text: text, HTML: true, Markup: markup})
	if err != nil {
		return err
	}
	slog.InfoContext(ctx, "rank_reward.announced", "board", boardID, "message_id", msgID)
	if _, err := ref.Update(context.WithoutCancel(ctx), []firestore.Update{{Path: "announcedAt", Value: firestore.ServerTimestamp}}); err != nil {
		return err
	}
	if a.broadcast != nil && a.broadcast.Enabled() {
		plain := html.UnescapeString(rankRewardTags.ReplaceAllString(text, ""))
		if err := a.broadcast.RecordBroadcast(ctx, a.telegram.ChatID(), plain); err != nil {
			slog.WarnContext(ctx, "rank_reward.announce_record_failed", "board", boardID, "error", err)
		}
	}
	return nil
}

// winnerTelegramIDs là Telegram id của người trúng đã liên kết Telegram, theo
// uid, để bài báo quà tag họ. Người chưa liên kết thì không có trong map.
func (a rankRewardAnnouncer) winnerTelegramIDs(ctx context.Context, entries []any) (map[string]string, error) {
	out := map[string]string{}
	if a.links == nil {
		return out, nil
	}
	for _, raw := range entries {
		e, _ := raw.(map[string]any)
		uid := stringValue(e["uid"])
		if e["reward"] == nil || uid == "" {
			continue
		}
		tg, err := a.links.TelegramIDForUID(ctx, uid)
		if err != nil {
			return nil, fmt.Errorf("telegramLinks/%s: %w", uid, err)
		}
		if tg != "" {
			out[uid] = tg
		}
	}
	return out, nil
}

// rankBoardLink mở bảng đã chốt trong app (universal link /bxh/*), máy chưa
// cài app thì mở trang web.
func rankBoardLink(webBaseURL, boardID string) string {
	return webBaseURL + "/bxh/" + url.PathEscape(boardID)
}

// rankRewardAnnounceText là nội dung HTML của bài báo quà; rỗng khi bảng không
// có ai trúng. Tên người và tên quà do người dùng đặt nên được escape. Người
// trúng có trong tgIDs (uid → Telegram id) thì tên thành tag tới họ.
func rankRewardAnnounceText(key rankBoardKey, entries []any, tgIDs map[string]string) string {
	var lines []string
	for _, raw := range entries {
		e, _ := raw.(map[string]any)
		reward, _ := e["reward"].(map[string]any)
		if reward == nil {
			continue
		}
		name := html.EscapeString(strings.TrimSpace(stringValue(e["displayName"])))
		if tg := tgIDs[stringValue(e["uid"])]; tg != "" {
			name = fmt.Sprintf(`<a href="tg://user?id=%s">%s</a>`, url.QueryEscape(tg), name)
		}
		gift := html.EscapeString(stringValue(reward["name"]))
		how := fmt.Sprintf("hạng %d", int(number(e["rank"])))
		if stringValue(reward["kind"]) == rankRewardDraw {
			how = fmt.Sprintf("bốc thăm trong %d người", int(number(reward["pool"])))
		}
		lines = append(lines, fmt.Sprintf("🎁 <b>%s</b> → %s (%s)", gift, name, how))
	}
	if len(lines) == 0 {
		return ""
	}
	head := fmt.Sprintf("🏆 Quà BXH %s %s–%s đã có chủ!", rankPeriodWord(key.r),
		key.period.Start.In(vietnam).Format("02/01"), key.period.End.Add(-1).In(vietnam).Format("02/01"))
	return head + "\n" + strings.Join(lines, "\n") + "\nMở thẻ quà để nhận quà và khoe với mọi người."
}

func (s *Server) rankRewardAnnounce(w http.ResponseWriter, r *http.Request) error {
	var task rankRewardPushTask
	if decodeJSON(r, &task) != nil || task.BoardID == "" {
		w.WriteHeader(204)
		return nil
	}
	a := rankRewardAnnouncer{db: s.deps.Firestore, telegram: s.deps.Telegram, links: s.deps.TelegramLinks, webBaseURL: s.config.WebBaseURL}
	if s.deps.Bot != nil {
		a.broadcast = s.deps.Bot
	}
	if err := a.Announce(r.Context(), task.BoardID); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
