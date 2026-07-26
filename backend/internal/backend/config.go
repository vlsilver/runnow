package backend

import (
	"fmt"
	"net/mail"
	"net/url"
	"os"
	"strconv"
	"strings"
)

type Config struct {
	Environment           string
	Port                  int
	ProjectID             string
	Region                string
	PublicBaseURL         string
	WorkerBaseURL         string
	BotBaseURL            string
	MobileReturnURI       string
	WebReturnURI          string
	AllowedWebOrigins     map[string]struct{}
	StravaClientID        string
	StravaClientSecret    string
	WebhookVerifyToken    string
	StravaSubscriptionID  string
	TaskInvokerAccount    string
	EventsQueue           string
	BackfillQueue         string
	DerivedQueue          string
	NotifyQueue           string
	BotInboundQueue       string
	TelegramBotToken      string
	TelegramChatID        string
	StorageBucket         string
	TelegramBotUsername   string
	TelegramWebhookSecret string
	GeminiLocation        string
	GeminiModel           string
	BotHourlyLimit        int
	// WebBaseURL là domain của app 3i Run bản web, không phải của API. Link
	// chia sẻ trỏ về đây để mở đúng màn hình chi tiết trong app (hoặc bản
	// web nếu chưa cài app), thay vì một trang HTML do backend tự dựng.
	WebBaseURL string
}

func LoadConfig() (Config, error) {
	port, err := strconv.Atoi(env("PORT", "8080"))
	if err != nil || port <= 0 {
		return Config{}, fmt.Errorf("PORT must be a positive integer")
	}
	c := Config{
		Environment: env("NODE_ENV", "development"), Port: port,
		ProjectID: required("GOOGLE_CLOUD_PROJECT"), Region: env("GOOGLE_CLOUD_REGION", "asia-southeast1"),
		PublicBaseURL: trimURL(required("PUBLIC_BASE_URL")), WorkerBaseURL: trimURL(required("WORKER_BASE_URL")),
		MobileReturnURI: required("MOBILE_RETURN_URI"), WebReturnURI: required("WEB_RETURN_URI"),
		StravaClientID: required("STRAVA_CLIENT_ID"), StravaClientSecret: required("STRAVA_CLIENT_SECRET"),
		WebhookVerifyToken: required("STRAVA_WEBHOOK_VERIFY_TOKEN"), StravaSubscriptionID: strings.TrimSpace(os.Getenv("STRAVA_SUBSCRIPTION_ID")),
		TaskInvokerAccount: required("TASK_INVOKER_SERVICE_ACCOUNT"),
		EventsQueue:        env("STRAVA_EVENTS_QUEUE", "strava-events"), BackfillQueue: env("STRAVA_BACKFILL_QUEUE", "strava-backfill"), DerivedQueue: env("DERIVED_DATA_QUEUE", "derived-data"),
		NotifyQueue:      env("NOTIFY_QUEUE", "notifications"),
		BotInboundQueue:  env("BOT_INBOUND_QUEUE", "bot-inbound"),
		TelegramBotToken: env("TELEGRAM_BOT_TOKEN", ""), TelegramChatID: env("TELEGRAM_CHAT_ID", ""),
		AllowedWebOrigins: map[string]struct{}{},
	}
	// Bucket mặc định của Firebase Storage theo project. Đặt riêng biến môi
	// trường để chuyển được sang bucket khác mà không phải sửa code.
	c.StorageBucket = env("STORAGE_BUCKET", c.ProjectID+".firebasestorage.app")
	c.WebBaseURL = trimURL(env("WEB_BASE_URL", "https://threei.run"))
	// BotBaseURL rỗng thì task bot-inbound rơi về worker (hành vi cũ). Set nó
	// = URL runnow-bot để dời phần xử lý AI sang service riêng.
	c.BotBaseURL = trimURL(env("BOT_BASE_URL", ""))
	c.TelegramBotUsername = strings.TrimPrefix(env("TELEGRAM_BOT_USERNAME", ""), "@")
	c.TelegramWebhookSecret = env("TELEGRAM_WEBHOOK_SECRET", "")
	// Gemini chạy ở region riêng: model chưa mở ở asia-southeast1 nơi
	// backend đang chạy, nên không dùng chung GOOGLE_CLOUD_REGION.
	c.GeminiLocation = env("GEMINI_LOCATION", "us-central1")
	c.GeminiModel = env("GEMINI_MODEL", "gemini-2.5-pro")
	if n, convErr := strconv.Atoi(env("BOT_HOURLY_LIMIT", "100")); convErr == nil && n > 0 {
		c.BotHourlyLimit = n
	} else {
		c.BotHourlyLimit = 100
	}
	missing := []string{}
	for name, value := range map[string]string{
		"GOOGLE_CLOUD_PROJECT": c.ProjectID, "PUBLIC_BASE_URL": c.PublicBaseURL, "WORKER_BASE_URL": c.WorkerBaseURL,
		"MOBILE_RETURN_URI": c.MobileReturnURI, "WEB_RETURN_URI": c.WebReturnURI, "STRAVA_CLIENT_ID": c.StravaClientID,
		"STRAVA_CLIENT_SECRET": c.StravaClientSecret, "STRAVA_WEBHOOK_VERIFY_TOKEN": c.WebhookVerifyToken,
		"TASK_INVOKER_SERVICE_ACCOUNT": c.TaskInvokerAccount,
	} {
		if value == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) > 0 {
		return Config{}, fmt.Errorf("missing required configuration: %s", strings.Join(missing, ", "))
	}
	for _, raw := range []string{c.PublicBaseURL, c.WorkerBaseURL, c.WebReturnURI} {
		if parsed, parseErr := url.ParseRequestURI(raw); parseErr != nil || parsed.Scheme == "" || parsed.Host == "" {
			return Config{}, fmt.Errorf("invalid URL: %s", raw)
		}
	}
	if _, err = mail.ParseAddress(c.TaskInvokerAccount); err != nil {
		return Config{}, fmt.Errorf("invalid TASK_INVOKER_SERVICE_ACCOUNT: %w", err)
	}
	for _, origin := range strings.Split(os.Getenv("ALLOWED_WEB_ORIGINS"), ",") {
		if origin = strings.TrimSpace(origin); origin != "" {
			c.AllowedWebOrigins[origin] = struct{}{}
		}
	}
	return c, nil
}

func env(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}
func required(name string) string { return strings.TrimSpace(os.Getenv(name)) }
func trimURL(value string) string { return strings.TrimRight(value, "/") }
