// Command rebuild-step-leaderboards dựng lại stepLeaderboardEntries/{uid} cho
// MỌI user đã có bước — one-off sau khi đổi logic "Tổng km" (đi-bộ-thuần =
// Apple − km chạy chính thức). Bình thường tự cập nhật ở mỗi lần sync; migration
// này áp ngay cho toàn bộ, không đợi từng người mở app.
//
// Chỉ cần Firestore (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/rebuild-step-leaderboards                 # tất cả user có bước
//	go run ./migrations/rebuild-step-leaderboards -uid=abc123     # chỉ 1 user
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

func main() {
	project := flag.String("project", "run-now-79767", "GCP project ID")
	onlyUID := flag.String("uid", "", "rebuild only this uid (default: all users with steps)")
	flag.Parse()

	ctx := context.Background()
	client, err := firestore.NewClient(ctx, *project)
	if err != nil {
		slog.Error("connect to Firestore failed — chạy `gcloud auth application-default login` trước", "error", err)
		os.Exit(1)
	}
	defer client.Close()
	now := time.Now()

	if *onlyUID != "" {
		if err := backend.RebuildStepLeaderboardFor(ctx, client, *onlyUID, now); err != nil {
			slog.Error("rebuild failed", "uid", *onlyUID, "error", err)
			os.Exit(1)
		}
		slog.Info("rebuilt", "uid", *onlyUID)
		return
	}

	// Chỉ user đã có stepLeaderboardEntries (tức có dữ liệu bước) — không tạo
	// entry rỗng cho người chưa từng đồng bộ Apple Health.
	iter := client.Collection("stepLeaderboardEntries").Documents(ctx)
	defer iter.Stop()
	n := 0
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			slog.Error("list stepLeaderboardEntries failed", "error", err)
			os.Exit(1)
		}
		if err := backend.RebuildStepLeaderboardFor(ctx, client, doc.Ref.ID, now); err != nil {
			slog.Error("rebuild user failed", "uid", doc.Ref.ID, "error", err)
			continue
		}
		n++
		slog.Info("rebuilt", "uid", doc.Ref.ID)
	}
	slog.Info("rebuild-step-leaderboards complete", "users", n)
}
