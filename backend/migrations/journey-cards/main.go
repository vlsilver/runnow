// Command journey-cards phát thẻ Hành trình cho người đã về đích trước khi có
// thẻ. Sau lần chạy này worker tự trao thẻ mỗi khi dựng lại periodStats (xem
// JourneyCardService.AwardFinished). Chạy lại không sao: thẻ đã có thì bỏ qua.
//
// Cần Application Default Credentials có quyền Firestore:
//
//	gcloud auth application-default login
//
// Usage:
//
//	go run ./migrations/journey-cards                 # mọi user
//	go run ./migrations/journey-cards -uid=abc123     # một user
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
	onlyUID := flag.String("uid", "", "chỉ chạy cho uid này (mặc định: mọi user)")
	flag.Parse()

	ctx := context.Background()
	client, err := firestore.NewClient(ctx, *project)
	if err != nil {
		slog.Error("connect to Firestore failed — run `gcloud auth application-default login` first", "error", err)
		os.Exit(1)
	}
	defer client.Close()
	cards := backend.NewJourneyCardService(client)

	if *onlyUID != "" {
		count, err := cards.AwardFinished(ctx, *onlyUID)
		if err != nil {
			slog.Error("award journey cards failed", "uid", *onlyUID, "error", err)
			os.Exit(1)
		}
		slog.Info("awarded journey cards", "uid", *onlyUID, "cards", count)
		return
	}

	iter := client.Collection("users").Documents(ctx)
	defer iter.Stop()
	users, total, failed := 0, 0, 0
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			slog.Error("list users failed", "error", err)
			os.Exit(1)
		}
		count, err := cards.AwardFinished(ctx, doc.Ref.ID)
		if err != nil {
			slog.Error("award journey cards failed", "uid", doc.Ref.ID, "error", err)
			failed++
			continue
		}
		users++
		total += count
	}
	slog.Info("journey cards complete", "users", users, "cards", total, "failed", failed)
	if failed > 0 {
		os.Exit(1)
	}
}
