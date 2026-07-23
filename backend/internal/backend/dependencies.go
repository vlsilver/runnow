package backend

import (
	"context"
	"log/slog"

	"cloud.google.com/go/cloudtasks/apiv2"
	"cloud.google.com/go/firestore"
	gcs "cloud.google.com/go/storage"
	firebase "firebase.google.com/go/v4"
	"firebase.google.com/go/v4/auth"
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
	return d, nil
}

func (d *Dependencies) Close() error { d.Tasks.Close(); return d.Firestore.Close() }
