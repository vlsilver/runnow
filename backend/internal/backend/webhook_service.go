package backend

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"strconv"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type WebhookService struct {
	db                          *firestore.Client
	tasks                       *TaskPublisher
	verifyToken, subscriptionID string
}

func NewWebhookService(db *firestore.Client, t *TaskPublisher, verifyToken, subscriptionID string) *WebhookService {
	return &WebhookService{db: db, tasks: t, verifyToken: verifyToken, subscriptionID: subscriptionID}
}
func (s *WebhookService) Verification(mode, challenge, token string) (map[string]string, error) {
	if mode != "subscribe" || token != s.verifyToken || challenge == "" {
		return nil, &HTTPError{Status: 403, Code: "invalid_webhook_verification", Message: "Webhook verification failed"}
	}
	return map[string]string{"hub.challenge": challenge}, nil
}
func (s *WebhookService) Receive(ctx context.Context, event StravaWebhookEvent) (string, error) {
	if s.subscriptionID != "" && strconv.FormatInt(event.SubscriptionID, 10) != s.subscriptionID {
		return "", &HTTPError{Status: 403, Code: "invalid_subscription", Message: "Unexpected Strava subscription"}
	}
	key := EventIdentity(event)
	ref := s.db.Collection("integrationEvents").Doc(key)
	payloadBytes, _ := json.Marshal(event)
	payloadSum := sha256.Sum256(payloadBytes)
	_, err := ref.Create(ctx, map[string]any{"provider": "strava", "eventKey": key, "objectType": event.ObjectType, "objectId": itoa64(event.ObjectID), "ownerId": itoa64(event.OwnerID), "aspectType": event.AspectType, "eventTime": event.EventTime, "updates": event.Updates, "payloadHash": hex.EncodeToString(payloadSum[:]), "status": "received", "attempts": 0, "receivedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp, "expiresAt": time.Now().Add(30 * 24 * time.Hour)})
	if status.Code(err) == codes.AlreadyExists {
		return "duplicate", nil
	}
	if err != nil {
		return "", err
	}
	result, err := s.tasks.Publish(ctx, PublishTask{Queue: QueueEvents, HandlerPath: "/tasks/strava-event", Payload: map[string]any{"eventKey": key, "event": event}, TaskID: StableTaskID("strava-event", map[string]any{"eventKey": key})})
	if err != nil {
		_, _ = ref.Set(ctx, map[string]any{"status": "queue_failed", "lastErrorCode": "task_publish_failed", "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
		return "", err
	}
	_, err = ref.Set(ctx, map[string]any{"status": "queued", "queuedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	return result, err
}
func EventIdentity(event StravaWebhookEvent) string {
	raw, _ := canonicalJSON(event)
	sum := sha256.Sum256(raw)
	return hex.EncodeToString(sum[:])
}
