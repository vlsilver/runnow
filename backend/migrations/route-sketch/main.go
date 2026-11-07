// Command route-sketch ghi routeSketch (dáng tuyến đã chuẩn hoá, không còn toạ
// độ thật) cho các buổi lưu trước bản backend tự tính field này, xem
// backend.BackfillRouteSketch.
//
// Thiếu field thì thẻ trong danh sách Buổi chạy không có nền tuyến, còn lại vẫn
// hiện bình thường. Chạy sau khi deploy api để buổi lưu trong lúc chạy cũng đã
// có field; chạy trước cũng không hại gì, chỉ sót những buổi lưu xen giữa.
// Chạy lại không đổi gì.
//
// Chỉ cần Firestore (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/route-sketch
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

	n, err := backend.BackfillRouteSketch(ctx, db)
	if err != nil {
		slog.Error("backfill lỗi, chạy lại được", "updated", n, "error", err)
		os.Exit(1)
	}
	slog.Info("route-sketch xong", "updated", n)
}
