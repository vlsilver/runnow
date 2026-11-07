// Command health-hydrated ghi hydrated=true cho các buổi Apple Health / Health
// Connect đã nhập trước bản backend ghi cờ này, xem
// backend.BackfillHealthHydrated.
//
// Thiếu cờ thì app coi buổi là chưa có chi tiết, gọi hydrate (chỉ chạy qua
// Strava, trả 409) và màn chi tiết không mở được. Chạy sau khi deploy api để
// buổi nhập trong lúc chạy cũng đã có cờ; chạy trước cũng không hại gì, chỉ sót
// những buổi nhập xen giữa. Chạy lại không đổi gì.
//
// Chỉ cần Firestore (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/health-hydrated
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"

	"cloud.google.com/go/firestore"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

func main() {
	project := flag.String("project", "run-now-79767", "GCP project ID")
	flag.Parse()

	ctx := context.Background()
	db, err := firestore.NewClient(ctx, *project)
	if err != nil {
		slog.Error("kết nối Firestore lỗi, chạy `gcloud auth application-default login` trước", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	n, err := backend.BackfillHealthHydrated(ctx, db)
	if err != nil {
		slog.Error("backfill lỗi, chạy lại được", "updated", n, "error", err)
		os.Exit(1)
	}
	slog.Info("health-hydrated xong", "updated", n)
}
