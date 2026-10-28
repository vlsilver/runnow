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
	Environment          string
	Port                 int
	ProjectID            string
	Region               string
	PublicBaseURL        string
	WorkerBaseURL        string
	BotBaseURL           string
	MobileReturnURI      string
	WebReturnURI         string
	AllowedWebOrigins    map[string]struct{}
	StravaClientID       string
	StravaClientSecret   string
	WebhookVerifyToken   string
	StravaSubscriptionID string
	// Garmin là nguồn tuỳ chọn: GarminClientID rỗng thì route Garmin trả
	// garmin_not_configured, mọi thứ khác chạy như cũ. GarminWebhookToken là
	// đoạn bí mật trong đường dẫn webhook, vì Garmin không ký các lần đẩy.
	GarminClientID        string
	GarminClientSecret    string
	GarminWebhookToken    string
	TaskInvokerAccount    string
	EventsQueue           string
	BackfillQueue         string
	DerivedQueue          string
	NotifyQueue           string
	BotInboundQueue       string
	GameInboundQueue      string
	TelegramBotToken      string
	TelegramChatID        string
	StorageBucket         string
	TelegramBotUsername   string
	TelegramWebhookSecret string
	GeminiLocation        string
	GeminiModel           string
	// GeminiFallbackModel ở GeminiFallbackLocation là model 3i và bot trong app
	// gọi khi model chính hết chỗ (generateWithFallback). Rỗng là không có dự
	// phòng; đặt GEMINI_FALLBACK_MODEL=off để tắt.
	GeminiFallbackModel    string
	GeminiFallbackLocation string
	// GeminiThinkingLevel là mức thinking của 3i và bot trong app. "default"
	// để model tự chọn, dùng khi đổi GEMINI_MODEL hay AGENT_MODEL sang model
	// không nhận thinkingLevel.
	GeminiThinkingLevel string
	// AgentModel là model của bot cá nhân. Mặc định Flash: phòng bot nói nhiều
	// tin ngắn, Pro đắt mà không cần.
	AgentModel string
	// RunCardArtModel là model ảnh vẽ tranh thẻ buổi chạy, gọi ở location
	// global. Tách khỏi model ảnh của 3i để đổi riêng khi model cũ nghỉ.
	RunCardArtModel string
	// AgentLearn bật task bot tự học ký ức từ tin trong phòng bot và group
	// Telegram (agent_learn.go). Chỉ "on" mới bật.
	AgentLearn      bool
	AgentLearnModel string
	// AgentTelegramBots bật MyBot trên Telegram (Pha T): 3i làm bot quản lý
	// Managed Bots, mỗi MyBot là một bot Telegram thật. Chỉ "on" mới bật.
	AgentTelegramBots bool
	// BotGroupFacts cho 3i đọc trí nhớ về group club từ ký ức tự học thay cho
	// tóm tắt botMemory. Chỉ "on" mới bật; tắt là quay về botMemory ngay.
	BotGroupFacts  bool
	BotHourlyLimit int
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
		GameInboundQueue: env("GAME_INBOUND_QUEUE", ""), // rỗng: webhook bỏ qua update thành viên của Ma Sói
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
	c.GarminClientID = env("GARMIN_CLIENT_ID", "")
	c.GarminClientSecret = env("GARMIN_CLIENT_SECRET", "")
	c.GarminWebhookToken = env("GARMIN_WEBHOOK_TOKEN", "")
	// Gemini chạy ở location riêng, không dùng chung GOOGLE_CLOUD_REGION:
	// gemini-3.8-flash chỉ mở ở global. Dòng 2.5 Vertex retire 20/10/2026, và
	// Google ghi 3.8-flash là model thay cho 2.5-pro.
	c.GeminiLocation = env("GEMINI_LOCATION", "global")
	c.GeminiModel = env("GEMINI_MODEL", "gemini-3.8-flash")
	// Dự phòng là 3.5-flash ở asia-southeast1: khác model và khác location nên
	// không chung pool capacity với 3.8-flash ở global.
	c.GeminiFallbackModel = env("GEMINI_FALLBACK_MODEL", "gemini-3.5-flash")
	if c.GeminiFallbackModel == "off" {
		c.GeminiFallbackModel = ""
	}
	c.GeminiFallbackLocation = env("GEMINI_FALLBACK_LOCATION", "asia-southeast1")
	c.GeminiThinkingLevel = env("GEMINI_THINKING_LEVEL", "LOW")
	c.AgentModel = env("AGENT_MODEL", "gemini-3.8-flash")
	c.RunCardArtModel = env("RUN_CARD_ART_MODEL", geminiImageModel)
	c.AgentLearn = env("AGENT_LEARN", "") == "on"
	c.AgentTelegramBots = env("AGENT_TELEGRAM_BOTS", "") == "on"
	// Task học không có model dự phòng, nên đi theo GEMINI_MODEL: đổi model của
	// 3i vì model cũ treo thì task học đổi theo, không bị bỏ lại trên model cũ.
	c.AgentLearnModel = env("AGENT_LEARN_MODEL", c.GeminiModel)
	c.BotGroupFacts = env("BOT_GROUP_FACTS", "") == "on"
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

// MybotEnabled: cờ bật và đủ cấu hình để chạy MyBot trên Telegram. Secret
// webhook của bot con là HMAC của TelegramWebhookSecret, link tạo bot cần
// username của 3i, nên thiếu một trong hai cũng tắt. Không đòi token 3i: api
// không có token, mọi lời gọi Telegram của bot con chạy trong task trên bot.
func (c Config) MybotEnabled() bool {
	return c.AgentTelegramBots && c.TelegramBotUsername != "" && c.TelegramWebhookSecret != ""
}

// GarminEnabled: đủ cả ba giá trị Garmin. File env dùng chung cho mọi service
// nhưng chỉ api nhận secret Garmin, nên bot và worker luôn thấy Garmin tắt.
func (c Config) GarminEnabled() bool {
	return c.GarminClientID != "" && c.GarminClientSecret != "" && c.GarminWebhookToken != ""
}

func env(name, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(name)); value != "" {
		return value
	}
	return fallback
}
func required(name string) string { return strings.TrimSpace(os.Getenv(name)) }
func trimURL(value string) string { return strings.TrimRight(value, "/") }
