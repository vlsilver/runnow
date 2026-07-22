package backend

import (
	"context"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/google/uuid"
	"google.golang.org/api/iterator"
)

type ReconciliationService struct {
	db    *firestore.Client
	tasks *TaskPublisher
}

func NewReconciliationService(db *firestore.Client, t *TaskPublisher) *ReconciliationService {
	return &ReconciliationService{db: db, tasks: t}
}
func (s *ReconciliationService) ReconcileConnections(ctx context.Context, cursor string) error {
	query := s.db.Collection("stravaConnections").OrderBy(firestore.DocumentID, firestore.Asc).Limit(100)
	if cursor != "" {
		query = query.StartAfter(cursor)
	}
	iter := query.Documents(ctx)
	defer iter.Stop()
	docs := []*firestore.DocumentSnapshot{}
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		docs = append(docs, doc)
	}
	after := time.Now().Unix() - 10*24*60*60
	for _, doc := range docs {
		statusValue := stringValue(doc.Data()["status"])
		if statusValue != "active" && statusValue != "backfilling" {
			continue
		}
		runID := uuid.NewString()
		if _, err := s.tasks.Publish(ctx, PublishTask{Queue: QueueBackfill, HandlerPath: "/tasks/backfill-page", Payload: map[string]any{"uid": doc.Ref.ID, "page": 1, "runId": runID, "after": after}, TaskID: "reconcile-" + doc.Ref.ID + "-" + runID + "-1"}); err != nil {
			return err
		}
	}
	if len(docs) == 100 {
		last := docs[len(docs)-1].Ref.ID
		_, err := s.tasks.Publish(ctx, PublishTask{Queue: QueueBackfill, HandlerPath: "/tasks/reconcile-connections", Payload: map[string]any{"cursor": last}, TaskID: "reconcile-page-" + last + "-" + itoa64(time.Now().UnixMilli())})
		return err
	}
	return nil
}
