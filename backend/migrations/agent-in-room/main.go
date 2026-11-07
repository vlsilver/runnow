// Command agent-in-room ghi agents/{uid}.inRoom = true cho bot đã tạo của
// allowlist hiện tại (gameState/config.adminUids cộng
// agentState/config.memberUids), xem backend.AgentStore.BackfillInRoom.
//
// Cờ open bật thì phòng bot chỉ lấy bot có inRoom == true. Bot tạo trước khi có
// field này chưa có nó, nên phải chạy migration này trước khi bật cờ, không thì
// các bot đó im. Cờ còn tắt thì bot thiếu field vẫn được nói, nên deploy không
// cần chờ migration. Chạy lại bao nhiêu lần cũng vậy: bot đã có inRoom thì để
// nguyên.
//
// Chỉ cần Firestore (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/agent-in-room
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

	set, err := backend.NewAgentStore(db).BackfillInRoom(ctx)
	if err != nil {
		slog.Error("backfill lỗi, chạy lại được", "done", set, "error", err)
		os.Exit(1)
	}
	slog.Info("agent-in-room xong", "set", len(set), "uids", set)
}
