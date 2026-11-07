// Command agent-ai-consent ghi đồng ý AI bản hiện hành (agents/{uid}/consent/ai,
// source backfill) cho allowlist hiện tại (gameState/config.adminUids cộng
// agentState/config.memberUids), xem backend.AgentStore.BackfillAIConsent.
//
// Người trong allowlist vốn không bị đòi đồng ý, nên app 1.5.0 của tester
// không phụ thuộc migration này và chạy trước hay sau deploy đều được. Nó chỉ
// để tester đã dùng bot từ trước có sẵn bản ghi đồng ý, phòng khi sau này bỏ
// ngoại lệ allowlist. Chạy lại không đổi gì: ai đã có bản ghi thì để nguyên.
//
// Chỉ cần Firestore (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/agent-ai-consent
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
	project := flag.String("project", "run-now-79767", "GCP project ID")
	flag.Parse()

	ctx := context.Background()
	db, err := firestore.NewClient(ctx, *project)
	if err != nil {
		slog.Error("kết nối Firestore lỗi, chạy `gcloud auth application-default login` trước", "error", err)
		os.Exit(1)
	}
	defer db.Close()

	set, err := backend.NewAgentStore(db).BackfillAIConsent(ctx, time.Now())
	if err != nil {
		slog.Error("backfill lỗi, chạy lại được", "done", set, "error", err)
		os.Exit(1)
	}
	slog.Info("agent-ai-consent xong", "set", len(set), "uids", set)
}
