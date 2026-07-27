package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"html"
	"io"
	"net/http"
	"strings"
	"time"
)

// TelegramService pushes an activity alert to a single configured chat via the
// Telegram Bot API whenever a new Strava run activity syncs in. Purely
// outbound: no bot commands, no webhook receiver needed on our side.
type TelegramService struct {
	botToken, chatID string
	client           *http.Client
	apiBaseURL       string
}

func NewTelegramService(botToken, chatID string) *TelegramService {
	return &TelegramService{
		botToken:   botToken,
		chatID:     chatID,
		client:     &http.Client{Timeout: 10 * time.Second},
		apiBaseURL: "https://api.telegram.org",
	}
}

// Enabled reports whether both the bot token and target chat are configured.
// Callers should skip all Telegram work entirely when this is false, so
// deployments that never set up Telegram behave exactly as before.
func (s *TelegramService) Enabled() bool {
	return s.botToken != "" && s.chatID != ""
}

// ChatID là group đích của các thông báo — cũng là khoá lịch sử/trí nhớ để
// ghi lại chính những thông báo đó.
func (s *TelegramService) ChatID() string { return s.chatID }

// SendActivityAlert posts the alert as an HTML text message.
//
// An earlier version rendered a PNG card server-side, but Go's standard
// bitmap face (basicfont) covers ASCII only, so every Vietnamese diacritic
// was stripped ("hoàn thành" came out "hoan thanh") and the text was
// aliased. Telegram renders HTML natively with the reader's own font and
// theme, which handles Unicode correctly and stays sharp at any zoom.
func (s *TelegramService) SendActivityAlert(ctx context.Context, displayName, activityName string, fact ActivityFact, detailURL, comment string) error {
	if !s.Enabled() {
		return nil
	}
	replyMarkup, err := json.Marshal(map[string]any{
		"inline_keyboard": [][]map[string]any{{{"text": "Xem chi tiết", "url": detailURL}}},
	})
	if err != nil {
		return err
	}
	payload, err := json.Marshal(map[string]any{
		"chat_id":    s.chatID,
		"text":       telegramActivityMessage(displayName, activityName, fact, comment),
		"parse_mode": "HTML",
		// Link trỏ về app; Telegram xem trước sẽ chỉ lôi về được màn hình
		// đăng nhập, vừa xấu vừa vô nghĩa.
		"link_preview_options": map[string]any{"is_disabled": true},
		"reply_markup":         json.RawMessage(replyMarkup),
	})
	if err != nil {
		return err
	}
	url := s.apiBaseURL + "/bot" + s.botToken + "/sendMessage"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("telegram sendMessage failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}
	return nil
}

// SendActivityAnnouncement gửi lời thông báo buổi chạy do BOT tự viết — text
// thô (KHÔNG parse_mode vì model sinh, tránh vỡ HTML), kèm nút "Xem chi tiết".
func (s *TelegramService) SendActivityAnnouncement(ctx context.Context, text, detailURL string) error {
	if !s.Enabled() {
		return nil
	}
	replyMarkup, err := json.Marshal(map[string]any{
		"inline_keyboard": [][]map[string]any{{{"text": "Xem chi tiết", "url": detailURL}}},
	})
	if err != nil {
		return err
	}
	payload, err := json.Marshal(map[string]any{
		"chat_id":              s.chatID,
		"text":                 text,
		"link_preview_options": map[string]any{"is_disabled": true},
		"reply_markup":         json.RawMessage(replyMarkup),
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.apiBaseURL+"/bot"+s.botToken+"/sendMessage", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("telegram sendMessage failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}

// SendChatMessage gửi một tin nhắn thuần văn bản tới một chat bất kỳ.
//
// Cố tình KHÔNG đặt parse_mode: nội dung do model sinh ra, chứa một dấu `<`
// hay `&` lạc là Telegram từ chối cả tin nhắn. Bot im lặng vì lỗi cú pháp
// khó lần ra hơn nhiều so với việc mất mấy chữ in đậm.
func (s *TelegramService) SendChatMessage(ctx context.Context, chatID, text string) error {
	if !s.Enabled() {
		return nil
	}
	payload, err := json.Marshal(map[string]any{
		"chat_id":              chatID,
		"text":                 text,
		"link_preview_options": map[string]any{"is_disabled": true},
	})
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.apiBaseURL+"/bot"+s.botToken+"/sendMessage", bytes.NewReader(payload))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		body, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("telegram sendMessage failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	return nil
}

// telegramActivityMessage builds the HTML body.
//
// Telegram only supports a small tag set (b, i, u, s, code, pre, a,
// blockquote) — no tables, no <br>, no CSS — so layout is done with newlines
// and emoji labels. Every interpolated value is user-controlled and escaped.
func telegramActivityMessage(displayName, activityName string, fact ActivityFact, comment string) string {
	disp := sportDisplayFor(fact.SportType)
	if strings.TrimSpace(activityName) == "" {
		activityName = disp.defaultName
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%s <b>%s</b> vừa hoàn thành\n", disp.emoji, html.EscapeString(strings.TrimSpace(displayName)))
	fmt.Fprintf(&b, "<b>%s</b>\n\n", html.EscapeString(strings.TrimSpace(activityName)))
	// Nhãn dùng dấu hai chấm chứ không căn cột bằng dấu cách: Telegram
	// render bằng font tỉ lệ nên khoảng trắng không bao giờ thẳng hàng.
	fmt.Fprintf(&b, "📏 Quãng đường: <b>%s</b>\n", formatDistanceKm(fact.DistanceMeters))
	fmt.Fprintf(&b, "⏱ Thời gian: <b>%s</b>\n", formatDurationHMS(fact.MovingTimeSeconds))
	paceLabel, paceVal := paceOrSpeed(fact)
	fmt.Fprintf(&b, "⚡ %s: <b>%s</b>\n", paceLabel, paceVal)
	if fact.ElevationGainMeters >= 1 {
		fmt.Fprintf(&b, "⛰ Độ cao: <b>%s</b>\n", formatElevationM(fact.ElevationGainMeters))
	}
	if !fact.StartedAt.IsZero() {
		fmt.Fprintf(&b, "\n<i>%s</i>", telegramActivityTime(fact.StartedAt))
	}
	// Câu bình luận tuỳ hứng của bot, đính ngay dưới thẻ. Model sinh ra text
	// thô nên PHẢI escape trước khi nhét vào body parse_mode=HTML.
	if c := strings.TrimSpace(comment); c != "" {
		fmt.Fprintf(&b, "\n\n💬 <i>%s</i>", html.EscapeString(c))
	}
	return b.String()
}

// telegramActivityPlain dựng bản một dòng, không HTML, của thông báo buổi
// chạy — để LƯU vào trí nhớ (transcript cần chữ đọc được, không phải thẻ
// HTML). Giữ tên, cự ly, thời gian, pace: đủ để bot nắm ai chạy và thói quen;
// con số nhất thời thì bước chưng cất sẽ tự loại.
func telegramActivityPlain(displayName, activityName string, fact ActivityFact) string {
	disp := sportDisplayFor(fact.SportType)
	if strings.TrimSpace(activityName) == "" {
		activityName = disp.defaultName
	}
	paceLabel, paceVal := paceOrSpeed(fact)
	s := fmt.Sprintf("%s %s vừa hoàn thành %s — %s, %s, %s %s",
		disp.emoji, strings.TrimSpace(displayName), strings.TrimSpace(activityName),
		formatDistanceKm(fact.DistanceMeters), formatDurationHMS(fact.MovingTimeSeconds),
		strings.ToLower(paceLabel), paceVal)
	if !fact.StartedAt.IsZero() {
		s += " (" + telegramActivityTime(fact.StartedAt) + ")"
	}
	return s
}

// telegramActivityTime renders the start time in Vietnam local time — the
// Firestore value is UTC, and every reader of the chat runs in Vietnam.
func telegramActivityTime(startedAt time.Time) string {
	return startedAt.In(vietnam).Format("15:04 · 02/01/2006")
}

// formatDistanceKm/formatDurationHMS/formatPacePerKm mirror the exact display
// conventions in lib/src/formatters.dart so the Telegram message reads
// identically to the app.
func formatDistanceKm(meters float64) string {
	return fmt.Sprintf("%.2f km", meters/1000)
}

func formatDurationHMS(totalSeconds int64) string {
	if totalSeconds < 0 {
		totalSeconds = 0
	}
	hours := totalSeconds / 3600
	minutes := (totalSeconds % 3600) / 60
	seconds := totalSeconds % 60
	if hours > 0 {
		return fmt.Sprintf("%d:%02d:%02d", hours, minutes, seconds)
	}
	return fmt.Sprintf("%02d:%02d", minutes, seconds)
}

func formatElevationM(meters float64) string {
	return fmt.Sprintf("%.0f m", meters)
}

func formatPacePerKm(fact ActivityFact) string {
	if fact.DistanceMeters <= 0 || fact.MovingTimeSeconds <= 0 {
		return "--"
	}
	secondsPerKm := int64(float64(fact.MovingTimeSeconds) / (fact.DistanceMeters / 1000))
	return fmt.Sprintf("%d:%02d /km", secondsPerKm/60, secondsPerKm%60)
}

// formatSpeedKmh dùng cho đạp xe — km/h là quy ước tự nhiên, không phải pace /km.
func formatSpeedKmh(fact ActivityFact) string {
	if fact.DistanceMeters <= 0 || fact.MovingTimeSeconds <= 0 {
		return "--"
	}
	kmh := (fact.DistanceMeters / 1000) / (float64(fact.MovingTimeSeconds) / 3600)
	return fmt.Sprintf("%.1f km/h", kmh)
}

// paceOrSpeed trả (nhãn, giá trị): pace /km cho chạy & đi bộ, tốc độ km/h cho xe đạp.
func paceOrSpeed(fact ActivityFact) (string, string) {
	if sportDisplayFor(fact.SportType).usesSpeed {
		return "Tốc độ", formatSpeedKmh(fact)
	}
	return "Pace", formatPacePerKm(fact)
}

// notifySportTypes là các loại hoạt động được THÔNG BÁO vào group. Cố ý RỘNG
// hơn runSportTypes (thứ định nghĩa cái gì tính vào leaderboard chạy bộ): đi bộ
// và đạp xe được khoe lên group nhưng KHÔNG được cộng vào leaderboard — nên hai
// tập này tách riêng, sửa cái này không đụng cái kia.
var notifySportTypes = map[string]bool{
	"Run": true, "TrailRun": true, "VirtualRun": true, // chạy bộ
	"Walk": true, "Hike": true, // đi bộ
	"Ride": true, "VirtualRide": true, "MountainBikeRide": true, "GravelRide": true, "EBikeRide": true, // đạp xe
}

// sportDisplay gom cách hiển thị một loại hoạt động để thông báo mô tả ĐÚNG:
// không gọi buổi đạp xe là "chạy", không hiện pace phút/km cho xe đạp.
type sportDisplay struct {
	emoji       string
	verb        string // "chạy bộ" | "đi bộ" | "đạp xe"
	defaultName string
	usesSpeed   bool // true → km/h thay vì pace /km
}

func sportDisplayFor(sportType string) sportDisplay {
	switch sportType {
	case "Walk", "Hike":
		return sportDisplay{"🚶", "đi bộ", "Buổi đi bộ", false}
	case "Ride", "VirtualRide", "MountainBikeRide", "GravelRide", "EBikeRide":
		return sportDisplay{"🚴", "đạp xe", "Buổi đạp xe", true}
	default:
		return sportDisplay{"🏃", "chạy bộ", "Buổi chạy", false}
	}
}
