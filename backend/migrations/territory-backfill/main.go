// Command territory-backfill tính ô lãnh địa cho buổi trong cửa sổ 30 ngày của
// mọi user và dựng territoryChunks, territoryOwners. Chạy sau khi deploy
// worker và index. Không ghi kết quả "+N ô" hay push: buổi kết thúc trước
// config/territory.enabledAt có kết quả rỗng. Chạy lại không đổi gì.
//
// Chỉ cần Firestore (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/territory-backfill -project run-now-79767
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"
	"time"

	"cloud.google.com/go/firestore"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

func main() {
	project := flag.String("project", "", "GCP project ID (bắt buộc, để không chạy nhầm prod)")
	flag.Parse()
	if *project == "" {
		slog.Error("thiếu -project")
		os.Exit(2)
	}
	ctx := context.Background()
	db, err := firestore.NewClient(ctx, *project)
	if err != nil {
		slog.Error("kết nối Firestore lỗi, chạy `gcloud auth application-default login` trước", "error", err)
		os.Exit(1)
	}
	defer db.Close()
	n, err := backend.SyncAllTerritory(ctx, db, time.Now())
	if err != nil {
		slog.Error("backfill lỗi, chạy lại được", "synced", n, "error", err)
		os.Exit(1)
	}
	slog.Info("territory-backfill xong", "users", n)
}
