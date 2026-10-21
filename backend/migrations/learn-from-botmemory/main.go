// Command learn-from-botmemory chuyển tóm tắt cũ của 3i về group PSC
// (botMemory/{chatID}) sang ký ức tự học (agentRooms/main/learned/*), xem
// backend.LearnService.PlanMigration. Chạy một lần, trước khi 3i chuyển sang
// đọc ký ức mới.
//
// Cần Application Default Credentials có quyền Firestore và Vertex AI:
//
//	gcloud auth application-default login
//
// Hai bước:
//
//	go run ./migrations/learn-from-botmemory -plan=plan.json   # gọi model, ghi file, KHÔNG ghi Firestore
//	go run ./migrations/learn-from-botmemory -apply=plan.json  # ghi ký ức trong file, không gọi model
//
// Đọc plan.json trước khi apply: target rỗng là ký ức không gắn được người, sẽ
// không ghi; sửa tay target (uid hoặc tg-{id}) nếu biết đó là ai. Mặc định đọc
// cả tóm tắt của group PSC hiện tại lẫn group cũ trước khi lên supergroup.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

func main() {
	project := flag.String("project", "run-now-79767", "GCP project ID")
	location := flag.String("location", "global", "Vertex location của model")
	model := flag.String("model", "gemini-3.8-flash", "model tách tóm tắt")
	chat := flag.String("chat", "-1004439220437", "group Telegram hiện tại, để tra tên người")
	sources := flag.String("sources", "-1004439220437,-5173585455", "các botMemory cần chuyển, cách nhau dấu phẩy")
	planPath := flag.String("plan", "", "ghi plan ra file này")
	applyPath := flag.String("apply", "", "ghi ký ức theo plan trong file này")
	flag.Parse()
	if (*planPath == "") == (*applyPath == "") {
		fail("cần đúng một trong -plan hoặc -apply", nil)
	}

	ctx := context.Background()
	db, err := firestore.NewClient(ctx, *project)
	if err != nil {
		fail("kết nối Firestore lỗi, chạy `gcloud auth application-default login` trước", err)
	}
	defer db.Close()
	client, err := genai.NewClient(ctx, &genai.ClientConfig{Project: *project, Location: *location, Backend: genai.BackendVertexAI})
	if err != nil {
		fail("tạo client Vertex lỗi", err)
	}
	svc := backend.NewGenaiLearnService(db, client, *model, *chat)

	if *planPath != "" {
		plan, err := svc.PlanMigration(ctx, strings.Split(*sources, ","))
		if err != nil {
			fail("plan lỗi", err)
		}
		raw, err := json.MarshalIndent(plan, "", "  ")
		if err != nil {
			fail("ghi JSON lỗi", err)
		}
		if err := os.WriteFile(*planPath, raw, 0o600); err != nil {
			fail("ghi file lỗi", err)
		}
		printPlan(plan)
		fmt.Printf("\nĐã ghi %s. Đọc xong thì chạy lại với -apply=%s\n", *planPath, *planPath)
		return
	}

	raw, err := os.ReadFile(*applyPath)
	if err != nil {
		fail("đọc file lỗi", err)
	}
	var plan backend.LearnMigration
	if err := json.Unmarshal(raw, &plan); err != nil {
		fail("file plan hỏng", err)
	}
	res, err := svc.ApplyMigration(ctx, &plan, time.Now())
	if err != nil {
		fail("apply lỗi", err)
	}
	fmt.Printf("ghi mới %d, đã có từ lần trước %d, doc đầy nên bỏ %d %v, không gắn được người %d %v\n",
		len(res.Added), len(res.Existing), len(res.Full), res.Full, len(res.Unmatched), res.Unmatched)
}

func printPlan(plan *backend.LearnMigration) {
	byTarget := map[string]int{}
	for _, it := range plan.Items {
		byTarget[it.Target]++
	}
	fmt.Printf("%d dòng tóm tắt → %d ký ức\n", len(plan.Lines), len(plan.Items))
	for target, n := range byTarget {
		if target != "" {
			fmt.Printf("  %-30s %d\n", target, n)
		}
	}
	fmt.Println("\nKhông gắn được người (apply sẽ bỏ qua):")
	for _, it := range plan.Items {
		if it.Target == "" {
			fmt.Printf("  %s [%s] %s: %s\n", it.ID, it.Person, it.Note, it.Text)
		}
	}
	text := map[string]string{}
	for _, ln := range plan.Lines {
		text[ln.ID] = ln.Text
	}
	fmt.Println("\nDòng model bỏ:")
	for _, d := range plan.Dropped {
		fmt.Printf("  %s (%s): %s\n", d.Line, d.Reason, text[d.Line])
	}
	fmt.Println("\nDòng KHÔNG nằm trong ký ức nào và cũng không được bỏ có lý do, tự xét:")
	for _, id := range plan.Uncovered {
		fmt.Printf("  %s: %s\n", id, text[id])
	}
}

func fail(msg string, err error) {
	slog.Error(msg, "error", err)
	os.Exit(1)
}
