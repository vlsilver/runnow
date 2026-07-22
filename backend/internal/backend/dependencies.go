package backend

import (
	"context"

	"cloud.google.com/go/cloudtasks/apiv2"
	"cloud.google.com/go/firestore"
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
}

func NewDependencies(ctx context.Context, config Config) (*Dependencies, error) {
	app, err := firebase.NewApp(ctx, &firebase.Config{ProjectID: config.ProjectID})
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
	d.Activities = NewActivityService(db, gateway, tokens, tasks, telegram, config.PublicBaseURL)
	d.Derived = NewDerivedDataService(db)
	d.PeriodStats = NewPeriodStatsService(db)
	d.Profiles = NewProfileService(db, tasks)
	d.Reconciliation = NewReconciliationService(db, tasks)
	return d, nil
}

func (d *Dependencies) Close() error { d.Tasks.Close(); return d.Firestore.Close() }
