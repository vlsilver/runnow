package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"html"
	"image"
	"image/color"
	"image/draw"
	"image/png"
	"io"
	"mime/multipart"
	"net/http"
	"strings"
	"time"

	"golang.org/x/image/font"
	"golang.org/x/image/font/basicfont"
	"golang.org/x/image/math/fixed"
)

// TelegramService pushes a visual activity card to a single configured chat via
// the Telegram Bot API whenever a new Strava run activity syncs in. Purely
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

func (s *TelegramService) SendActivityAlert(ctx context.Context, displayName, activityName string, fact ActivityFact, detailURL string) error {
	if !s.Enabled() {
		return nil
	}
	card, err := renderTelegramActivityCard(displayName, activityName, fact)
	if err != nil {
		return err
	}
	body := &bytes.Buffer{}
	writer := multipart.NewWriter(body)
	if err := writer.WriteField("chat_id", s.chatID); err != nil {
		return err
	}
	if err := writer.WriteField("caption", telegramActivityCaption(displayName, activityName)); err != nil {
		return err
	}
	if err := writer.WriteField("parse_mode", "HTML"); err != nil {
		return err
	}
	replyMarkup, err := json.Marshal(map[string]any{
		"inline_keyboard": [][]map[string]any{{{"text": "Xem chi tiết", "url": detailURL}}},
	})
	if err != nil {
		return err
	}
	if err := writer.WriteField("reply_markup", string(replyMarkup)); err != nil {
		return err
	}
	part, err := writer.CreateFormFile("photo", "runnow-activity.png")
	if err != nil {
		return err
	}
	if _, err := part.Write(card); err != nil {
		return err
	}
	if err := writer.Close(); err != nil {
		return err
	}
	url := s.apiBaseURL + "/bot" + s.botToken + "/sendPhoto"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", writer.FormDataContentType())
	resp, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		respBody, _ := io.ReadAll(io.LimitReader(resp.Body, 1024))
		return fmt.Errorf("telegram sendPhoto failed: status=%d body=%s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}
	return nil
}

func telegramActivityCaption(displayName, activityName string) string {
	return fmt.Sprintf("🏃 <b>%s</b> hoàn thành <b>%s</b>", html.EscapeString(displayName), html.EscapeString(activityName))
}

func renderTelegramActivityCard(displayName, activityName string, fact ActivityFact) ([]byte, error) {
	const width, height = 900, 470
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	fill(img, img.Bounds(), hexColor(0x0B1420))
	drawRoundedRect(img, image.Rect(36, 36, width-36, height-36), 34, hexColor(0x182838))
	drawRoundedRect(img, image.Rect(70, 88, 148, 166), 18, hexColor(0xE4B640))
	drawText(img, 72, 75, "3I", hexColor(0x63C6F3))
	drawText(img, 176, 126, truncateText(displayName+" hoan thanh", 34), color.White)
	drawText(img, 176, 154, truncateText(activityName+" "+telegramActivityTime(fact.StartedAt), 48), hexColor(0xAEB8C4))

	drawRoundedRect(img, image.Rect(70, 212, width-70, 304), 16, hexColor(0x263746))
	statX := []int{160, 410, 660}
	statValueY := 252
	statLabelY := 280
	drawDivider(img, 320, 228, 288, hexColor(0x445462))
	drawDivider(img, 570, 228, 288, hexColor(0x445462))
	drawCenteredText(img, statX[0], statValueY, strings.TrimSuffix(formatDistanceKm(fact.DistanceMeters), " km"), color.White)
	drawCenteredText(img, statX[0], statLabelY, "km", hexColor(0x9AA7B3))
	drawCenteredText(img, statX[1], statValueY, formatDurationHMS(fact.MovingTimeSeconds), color.White)
	drawCenteredText(img, statX[1], statLabelY, "thoi gian", hexColor(0x9AA7B3))
	drawCenteredText(img, statX[2], statValueY, strings.TrimSuffix(formatPacePerKm(fact), " /km"), hexColor(0x63C6F3))
	drawCenteredText(img, statX[2], statLabelY, "/km pace", hexColor(0x9AA7B3))

	drawRoundedRect(img, image.Rect(70, 334, width-70, 404), 16, hexColor(0x1D2D3D))
	drawText(img, 106, 378, "Xem chi tiet buoi chay", color.White)
	drawText(img, width-124, 378, "->", hexColor(0x63C6F3))

	var out bytes.Buffer
	if err := png.Encode(&out, img); err != nil {
		return nil, err
	}
	return out.Bytes(), nil
}

func telegramActivityTime(startedAt time.Time) string {
	if startedAt.IsZero() {
		return ""
	}
	return "- " + startedAt.Format("15:04")
}

func fill(img *image.RGBA, rect image.Rectangle, c color.Color) {
	draw.Draw(img, rect, &image.Uniform{C: c}, image.Point{}, draw.Src)
}

func drawRoundedRect(img *image.RGBA, rect image.Rectangle, radius int, c color.Color) {
	r2 := radius * radius
	for y := rect.Min.Y; y < rect.Max.Y; y++ {
		for x := rect.Min.X; x < rect.Max.X; x++ {
			dx, dy := 0, 0
			if x < rect.Min.X+radius {
				dx = rect.Min.X + radius - x
			} else if x >= rect.Max.X-radius {
				dx = x - (rect.Max.X - radius - 1)
			}
			if y < rect.Min.Y+radius {
				dy = rect.Min.Y + radius - y
			} else if y >= rect.Max.Y-radius {
				dy = y - (rect.Max.Y - radius - 1)
			}
			if dx == 0 || dy == 0 || dx*dx+dy*dy <= r2 {
				img.Set(x, y, c)
			}
		}
	}
}

func drawDivider(img *image.RGBA, x, y1, y2 int, c color.Color) {
	for y := y1; y <= y2; y++ {
		img.Set(x, y, c)
	}
}

func drawText(img *image.RGBA, x, baseline int, text string, c color.Color) {
	d := font.Drawer{
		Dst:  img,
		Src:  &image.Uniform{C: c},
		Face: basicfont.Face7x13,
		Dot:  fixed.P(x, baseline),
	}
	d.DrawString(text)
}

func drawCenteredText(img *image.RGBA, centerX, baseline int, text string, c color.Color) {
	drawText(img, centerX-(len([]rune(text))*7)/2, baseline, text, c)
}

func truncateText(text string, maxRunes int) string {
	runes := []rune(strings.TrimSpace(text))
	if len(runes) <= maxRunes {
		return string(runes)
	}
	return string(runes[:maxRunes-3]) + "..."
}

func hexColor(rgb uint32) color.RGBA {
	return color.RGBA{R: uint8(rgb >> 16), G: uint8(rgb >> 8), B: uint8(rgb), A: 255}
}

// formatDistanceKm/formatDurationHMS/formatPacePerKm mirror the exact display
// conventions in lib/src/formatters.dart so the Telegram message and the
// public HTML page read identically to the app.
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
