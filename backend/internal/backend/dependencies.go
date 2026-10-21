package backend

import (
	"context"
	"log/slog"
	"time"

	"cloud.google.com/go/cloudtasks/apiv2"
	"cloud.google.com/go/firestore"
	gcs "cloud.google.com/go/storage"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/genai"
)

type Dependencies struct {
	Firestore      *firestore.Client
	Auth           *auth.Client
	Tasks          *TaskPublisher
	OAuth          *OAuthService
	Webhook        *WebhookService
	Activities     *ActivityService
	Derived        *DerivedDataService
	PeriodStats    *PeriodStatsService
	Profiles       *ProfileService
	Reconciliation *ReconciliationService
	Telegram       *TelegramService
	Accounts       *AccountService
	Bot            *BotService
	Gemini         *genai.Client
	Memory         *MemoryService
	TelegramLinks  *TelegramLinkService
	Games          *GameStore
	Agents         *AgentStore
	// AgentBrain chạy LLM của bot cá nhân; chỉ có trên service có Gemini (bot).
	AgentBrain *AgentService
	// ManagedBots là MyBot trên Telegram; nil khi chưa cấu hình bot quản lý
	// (Config.MybotEnabled).
	ManagedBots *ManagedBotService
	// Learn là task bot tự học ký ức; nil khi AGENT_LEARN chưa bật.
	Learn *LearnService
	// EnqueueTask thay Tasks.Publish khi khác nil; test gài để bắt task mà
	// không cần Cloud Tasks.
	EnqueueTask taskPublishFunc
	// Now thay time.Now ở game-advance và schedule-tick khi khác nil; test gài
	// đồng hồ giả để chạy task hẹn giờ mà không phải chờ.
	Now func() time.Time
}

func NewDependencies(ctx context.Context, config Config) (*Dependencies, error) {
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: config.ProjectID, StorageBucket: config.StorageBucket})
	if err != nil {
		return nil, err
	}
	db, err := app.Firestore(ctx)
	if err != nil {
		return nil, err
	}
	authClient, err := app.Auth(ctx)
	if err != nil {
		db.Close()
		return nil, err
	}
	tasksClient, err := cloudtasks.NewClient(ctx)
	if err != nil {
		db.Close()
		return nil, err
	}
	gateway := NewStravaGateway(config.StravaClientID, config.StravaClientSecret)
	tasks := NewTaskPublisher(tasksClient, config)
	tokens := NewTokenStore(db, gateway)
	telegram := NewTelegramService(config.TelegramBotToken, config.TelegramChatID)
	d := &Dependencies{Firestore: db, Auth: authClient, Tasks: tasks, Telegram: telegram}
	d.TelegramLinks = NewTelegramLinkService(db, config.TelegramBotUsername)
	d.Games = NewGameStore(db, config.TelegramChatID)
	d.Agents = NewAgentStore(db)
	d.OAuth = NewOAuthService(db, gateway, tasks, config)
	d.Webhook = NewWebhookService(db, tasks, config.WebhookVerifyToken, config.StravaSubscriptionID)
	d.Activities = NewActivityService(db, gateway, tokens, tasks, telegram, config.PublicBaseURL, config.WebBaseURL)
	d.Derived = NewDerivedDataService(db)
	d.PeriodStats = NewPeriodStatsService(db)
	d.Profiles = NewProfileService(db, tasks)
	d.Reconciliation = NewReconciliationService(db, tasks)
	// Không có bucket thì xoá tài khoản vẫn chạy, chỉ bỏ qua phần ảnh —
	// thà xoá được dữ liệu còn hơn chặn cả luồng vì cấu hình Storage.
	var bucket *gcs.BucketHandle
	if storageClient, storageErr := app.Storage(ctx); storageErr == nil {
		if handle, bucketErr := storageClient.DefaultBucket(); bucketErr == nil {
			bucket = handle
		} else {
			slog.WarnContext(ctx, "dependencies.storage_bucket_unavailable", "error", bucketErr)
		}
	} else {
		slog.WarnContext(ctx, "dependencies.storage_unavailable", "error", storageErr)
	}
	d.Accounts = NewAccountService(db, authClient, d.OAuth, bucket)
	// 3i là bot quản lý của mọi MyBot trên Telegram. Trên api telegram không
	// có token: api chỉ ghi Firestore và hẹn task, task chạy trên bot.
	if config.MybotEnabled() {
		d.ManagedBots = NewManagedBotService(db, telegram, config.TelegramBotUsername, config.TelegramWebhookSecret, config.PublicBaseURL, tasks.Publish)
		d.Accounts.managed = d.ManagedBots
	} else if config.AgentTelegramBots {
		slog.WarnContext(ctx, "dependencies.mybot_partial_config", "hasUsername", config.TelegramBotUsername != "", "hasWebhookSecret", config.TelegramWebhookSecret != "")
	}
	// Bot chỉ bật khi có đủ Telegram lẫn Vertex AI. Thiếu một trong hai thì
	// mọi luồng cũ vẫn chạy y như trước, chỉ không có bot.
	//
	// genai client tách khỏi Bot và giữ ở cấp Dependencies: bot Q&A chạy trên
	// API, còn chưng cất trí nhớ hàng ngày và nhận xét buổi chạy chạy trên
	// worker — cả ba dùng chung một client.
	if telegram.Enabled() {
		genaiClient, genErr := genai.NewClient(ctx, &genai.ClientConfig{
			Project:  config.ProjectID,
			Location: config.GeminiLocation,
			Backend:  genai.BackendVertexAI,
		})
		if genErr != nil {
			slog.WarnContext(ctx, "dependencies.genai_unavailable", "error", genErr)
		} else {
			d.Gemini = genaiClient
			d.Memory = NewMemoryService(genaiClient, db, config.GeminiModel)
			// Mọi lượt gọi model của bot cá nhân đi qua trần chi phí ngày; chưa đặt
			// agentState/config.dailyBudgetUsd thì chỉ cộng số, không chặn gì.
			budget := NewAgentBudget(db, adminNotifier(d.Games, telegram))
			d.AgentBrain = NewAgentService(d.Agents, budgetAgentLLM{inner: genaiAgentLLM{client: genaiClient, model: config.AgentModel, thinking: config.GeminiThinkingLevel}, model: config.AgentModel, budget: budget}, tasks.Publish)
			d.AgentBrain.chatID = config.TelegramChatID
			if d.ManagedBots != nil {
				d.AgentBrain.SetChannelReply(d.ManagedBots.channelReply)
			}
			if config.AgentLearn {
				d.Learn = NewLearnService(d.Agents, budgetLearnLLM{inner: genaiLearnLLM{client: genaiClient, model: config.AgentLearnModel}, model: config.AgentLearnModel, budget: budget}, config.TelegramChatID)
			}
			// Client RIÊNG cho sinh ảnh: model ảnh nằm cố định ở location "global",
			// không theo GEMINI_LOCATION. Hỏng thì chỉ tắt tính năng vẽ, không
			// ảnh hưởng chat.
			imageClient, imgErr := genai.NewClient(ctx, &genai.ClientConfig{
				Project:  config.ProjectID,
				Location: "global",
				Backend:  genai.BackendVertexAI,
			})
			if imgErr != nil {
				slog.WarnContext(ctx, "dependencies.image_genai_unavailable", "error", imgErr)
				imageClient = nil
			}
			d.Bot = NewBotService(genaiClient, telegram, NewBotTools(db), db, config.GeminiModel, config.BotHourlyLimit, d.Memory, NewScheduleStore(db), imageClient, geminiImageModel, bucket)
			d.Bot.thinking = config.GeminiThinkingLevel
			if config.BotGroupFacts {
				d.Bot.learned = d.Agents
			}
			// Cho ActivityService ghi lại chính thông báo buổi chạy vào trí
			// nhớ (Telegram không đẩy lại tin của bot).
			d.Activities.SetBroadcastRecorder(d.Bot)
		}
	}
	return d, nil
}

func (d *Dependencies) Close() error { d.Tasks.Close(); return d.Firestore.Close() }
