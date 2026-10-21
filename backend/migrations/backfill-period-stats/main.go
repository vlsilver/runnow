// Command backfill-period-stats populates users/{uid}/periodStats/{type}:{key}
// for existing activities — a one-time run needed because that collection is
// new; going forward it's kept up to date incrementally by the API/worker
// (see ActivityService.enqueuePeriodStats). One-off data migration, not a
// deployed service — lives under migrations/, not cmd/.
//
// Only needs Firestore access (no Strava secrets, no task queues), so it
// talks to Firestore directly instead of going through the full
// backend.LoadConfig/NewDependencies used by the api/worker services.
//
// Requires Application Default Credentials for a principal with Firestore
// access to the target project:
//
//	gcloud auth application-default login
//
// Usage:
//
//	go run ./migrations/backfill-period-stats                              # all users
//	go run ./migrations/backfill-period-stats -uid=abc123                  # just one user
//	go run ./migrations/backfill-period-stats -project=run-now-79767       # override project
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

func main() {
	project := flag.String("project", "run-now-79767", "GCP project ID")
	onlyUID := flag.String("uid", "", "backfill only this uid (default: all users)")
	flag.Parse()

	ctx := context.Background()
	client, err := firestore.NewClient(ctx, *project)
	if err != nil {
		slog.Error("connect to Firestore failed — run `gcloud auth application-default login` first", "error", err)
		os.Exit(1)
	}
	defer client.Close()
	periodStats := backend.NewPeriodStatsService(client)

	if *onlyUID != "" {
		count, err := periodStats.BackfillUser(ctx, *onlyUID)
		if err != nil {
			slog.Error("backfill user failed", "uid", *onlyUID, "error", err)
			os.Exit(1)
		}
		slog.Info("backfilled user", "uid", *onlyUID, "periods", count)
		return
	}

	iter := client.Collection("users").Documents(ctx)
	defer iter.Stop()
	users, totalPeriods := 0, 0
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			slog.Error("list users failed", "error", err)
			os.Exit(1)
		}
		count, err := periodStats.BackfillUser(ctx, doc.Ref.ID)
		if err != nil {
			slog.Error("backfill user failed", "uid", doc.Ref.ID, "error", err)
			continue
		}
		users++
		totalPeriods += count
		if count > 0 {
			slog.Info("backfilled user", "uid", doc.Ref.ID, "periods", count)
		}
	}
	slog.Info("backfill complete", "users", users, "totalPeriods", totalPeriods)
}
