package backend

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"slices"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Ngưỡng của M1. Tick chạy mỗi 10 phút, nên admin nhận DM trong vòng 10 phút
// sau khi vượt ngưỡng.
const (
	alertStaleAfter   = 15 * time.Minute // tin chờ gửi lâu hơn thế là kẹt
	alertOverdueAfter = 25 * time.Minute // quá mốc chốt chừng này mà chưa chốt
	alertWebhookAfter = 10 * time.Minute // Telegram giữ update chưa giao lâu hơn thế
)

// gameIssues là các chuyện M1 báo admin. Chỉ có số đếm, không có tên hay lựa
// chọn, vì admin cũng có thể đang chơi (C5).
type gameIssues struct {
	TickFailed     bool
	Overdue        bool
	Failed         int // tin lỗi chưa xếp gửi lại
	Stale          int // tin chờ gửi quá alertStaleAfter
	WebhookPending int // update Telegram chưa giao, kéo dài quá alertWebhookAfter
	DMBlocked      int // người chơi có dmOk=false
}

// lines là từng dòng của tin báo, kèm khoá loại để chống gửi lặp.
func (a gameIssues) lines() (keys, lines []string) {
	add := func(ok bool, key, line string) {
		if ok {
			keys, lines = append(keys, key), append(lines, "- "+line)
		}
	}
	add(a.TickFailed, "tick", "Tick chạy ván bị lỗi, xem log tick.job_failed.")
	add(a.Overdue, "overdue", "Quá mốc chốt hơn 25 phút mà ván chưa chuyển lượt.")
	add(a.Failed > 0, "failed", fmt.Sprintf("%d tin gửi lỗi, gõ /retry để gửi lại.", a.Failed))
	add(a.Stale > 0, "stale", fmt.Sprintf("%d tin chờ gửi quá 15 phút.", a.Stale))
	add(a.WebhookPending > 0, "webhook", fmt.Sprintf("Telegram còn %d update chưa giao tới webhook, đã hơn 10 phút.", a.WebhookPending))
	add(a.DMBlocked > 0, "dm", fmt.Sprintf("%d người chơi chưa nhận được DM của bot.", a.DMBlocked))
	return keys, lines
}

// countIssues đếm vấn đề của ván lúc wall, chỉ đọc phần công khai, outbox và
// cờ dmOk.
func (s *GameStore) countIssues(ctx context.Context, gameID string, wall time.Time) (gameIssues, error) {
	var a gameIssues
	game := s.gameRef(gameID)
	g, err := game.Get(ctx)
	if err != nil {
		return a, err
	}
	d := g.Data()
	if next := timeValue(d["nextAt"]); stringValue(d["status"]) == gameRunning && d["paused"] != true && !next.IsZero() {
		a.Overdue = next.Add(-clockOffset(d)).Before(wall.Add(-alertOverdueAfter))
	}
	docs, err := game.Collection("outbox").Where("status", "in", []string{outboxPending, outboxSending, outboxFailed}).Documents(ctx).GetAll()
	if err != nil {
		return a, err
	}
	for _, doc := range docs {
		m := doc.Data()
		switch {
		case m["status"] == outboxFailed:
			if m["retriedAs"] == nil {
				a.Failed++
			}
		case timeValue(m["createdAt"]).Before(wall.Add(-alertStaleAfter)):
			a.Stale++
		}
	}
	blocked, err := game.Collection("players").Where("dmOk", "==", false).Documents(ctx).GetAll()
	if err != nil {
		return a, err
	}
	a.DMBlocked = len(blocked)
	return a, nil
}

// gameHealth là gameState/health: state của M1 giữa các tick.
type gameHealth struct {
	GameID       string    `firestore:"gameId"`
	AlertKey     string    `firestore:"alertKey"`     // các loại đã báo; rỗng khi hết chuyện
	WebhookSince time.Time `firestore:"webhookSince"` // lần đầu thấy pending_update_count > 0
	SummaryKey   string    `firestore:"summaryKey"`   // giờ VN của tin tóm tắt gần nhất
	UpdatedAt    time.Time `firestore:"updatedAt"`
}

func (s *GameStore) healthRef() *firestore.DocumentRef {
	return s.db.Collection("gameState").Doc("health")
}

func (s *GameStore) readHealth(ctx context.Context, gameID string) (gameHealth, error) {
	snap, err := s.healthRef().Get(ctx)
	if status.Code(err) == codes.NotFound {
		return gameHealth{GameID: gameID}, nil
	}
	if err != nil {
		return gameHealth{}, err
	}
	var h gameHealth
	if err := snap.DataTo(&h); err != nil {
		return gameHealth{}, err
	}
	if h.GameID != gameID {
		return gameHealth{GameID: gameID}, nil // ván mới: báo lại từ đầu
	}
	return h, nil
}

// adminChats là Telegram ID của admin đã liên kết, theo thứ tự uid.
func (s *GameStore) adminChats(ctx context.Context) ([]string, error) {
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return nil, err
	}
	uids := make([]string, 0, len(cfg.admins))
	for uid := range cfg.admins {
		uids = append(uids, uid)
	}
	sort.Strings(uids)
	var chats []string
	for _, uid := range uids {
		link, err := s.readLink(ctxGetter(ctx), uid)
		if err != nil {
			return nil, err
		}
		if !link.linked {
			slog.WarnContext(ctx, "game.alert_admin_unlinked", "uid", uid)
			continue
		}
		chats = append(chats, fmt.Sprint(link.tgUserID))
	}
	return chats, nil
}

// summaryKey: tick đầu tiên sau 10:30 và 22:30 giờ VN gửi tóm tắt; khoá theo giờ
// để mỗi mốc chỉ gửi một lần, kể cả khi tick lúc 10:30 lỡ.
func summaryKey(wall time.Time) (string, bool) {
	vn := wall.In(vietnam)
	if (vn.Hour() != 10 && vn.Hour() != 22) || vn.Minute() < 30 {
		return "", false
	}
	return vn.Format("2006-01-02T15"), true
}

// tickAlerts là M1, chạy trong tick sau phần game: DM admin khi có loại vấn đề
// mới, và gửi tóm tắt lúc 10:30, 22:30. DM gửi thẳng, không qua outbox, vì
// outbox có thể chính là chỗ đang hỏng. gameErr là lỗi phần game của tick này.
func (s *Server) tickAlerts(ctx context.Context, wall time.Time, gameErr error) error {
	games, tg := s.deps.Games, s.deps.Telegram
	if games == nil || tg == nil || !tg.Enabled() {
		return nil
	}
	id, st, err := games.CurrentGame(ctx)
	if err != nil || id == "" || st == gameRegistering || st == gameCancelled {
		return err
	}
	chats, err := games.adminChats(ctx)
	if err != nil || len(chats) == 0 {
		return err
	}
	h, err := games.readHealth(ctx, id)
	if err != nil {
		return err
	}
	a, err := games.countIssues(ctx, id, wall)
	if err != nil {
		return err
	}
	a.TickFailed = gameErr != nil
	pending, err := tg.WebhookPendingCount(ctx)
	if err != nil {
		return err
	}
	switch {
	case pending == 0:
		h.WebhookSince = time.Time{}
	case h.WebhookSince.IsZero():
		h.WebhookSince = wall
	}
	if pending > 0 && !wall.Before(h.WebhookSince.Add(alertWebhookAfter)) {
		a.WebhookPending = pending
	}

	// Chỉ báo khi có loại chưa báo; một loại hết thì thôi, không báo lại.
	var texts []string
	keys, lines := a.lines()
	if slices.ContainsFunc(keys, func(k string) bool { return !slices.Contains(strings.Split(h.AlertKey, ","), k) }) {
		texts = append(texts, "Ma Sói cần xem:\n"+strings.Join(lines, "\n"))
	}
	key := strings.Join(keys, ",")
	sk, due := summaryKey(wall)
	if due && st == gameRunning && sk != h.SummaryKey {
		summary, err := games.AdminSummary(ctx, id)
		if err != nil {
			return err
		}
		texts = append(texts, "Tóm tắt Ma Sói lúc "+wall.In(vietnam).Format("15")+":30\n"+summary)
		h.SummaryKey = sk
	}
	if err := sendToAny(ctx, tg, chats, texts); err != nil {
		return err
	}
	h.AlertKey, h.UpdatedAt = key, wall
	_, err = games.healthRef().Set(ctx, h)
	return err
}

// sendToAny gửi từng tin cho mọi admin. Một admin chặn bot thì chỉ log; không
// admin nào nhận được thì trả lỗi để tick sau gửi lại.
func sendToAny(ctx context.Context, tg *TelegramService, chats, texts []string) error {
	for _, text := range texts {
		var errs []error
		for _, chat := range chats {
			if _, err := tg.SendText(ctx, TelegramText{ChatID: chat, Text: text}); err != nil {
				slog.WarnContext(ctx, "game.alert_send_failed", "chat", chat, "error", err)
				errs = append(errs, err)
			}
		}
		if len(errs) == len(chats) {
			return errors.Join(errs...)
		}
	}
	return nil
}
