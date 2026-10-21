// Command split-contract-routes tách polyline của kèo "Theo tuyến"
// (metric=routeCompletion) từ doc kèo `runContracts/{id}.route.points` ra doc
// riêng `runContractRoutes/{id}` — để DANH SÁCH kèo khỏi cõng cả polyline nặng.
//
// MẶC ĐỊNH KHÔNG PHÁ HUỶ (copy-only): chỉ TẠO doc route, GIỮ points inline ở doc
// kèo → app CŨ vẫn đọc được như thường. App MỚI đọc points inline (nếu còn) hoặc
// hydrate từ doc route. Danh sách chỉ thật sự nhẹ khi points inline bị bỏ — dùng
// `-strip` để làm bước đó, NHƯNG chỉ chạy khi phần lớn user đã lên bản app mới
// (app cũ sẽ mất bản đồ tuyến + có thể tính lại routeCompletion = 0).
//
// Chỉ cần Firestore (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/split-contract-routes            # copy-only, TẤT CẢ kèo route
//	go run ./migrations/split-contract-routes -id=abc123 # chỉ 1 kèo
//	go run ./migrations/split-contract-routes -dry       # chỉ đếm, không ghi
//	go run ./migrations/split-contract-routes -strip     # copy + BỎ points inline (Phase 2)
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

func main() {
	project := flag.String("project", "run-now-79767", "GCP project ID")
	onlyID := flag.String("id", "", "chỉ xử lý kèo này (default: mọi kèo routeCompletion)")
	strip := flag.Bool("strip", false, "BỎ points inline khỏi doc kèo sau khi copy (Phase 2, phá vỡ app cũ)")
	dry := flag.Bool("dry", false, "chỉ đếm, không ghi gì")
	flag.Parse()

	ctx := context.Background()
	client, err := firestore.NewClient(ctx, *project)
	if err != nil {
		slog.Error("connect to Firestore failed — chạy `gcloud auth application-default login` trước", "error", err)
		os.Exit(1)
	}
	defer client.Close()

	contracts := client.Collection("runContracts")
	var docs []*firestore.DocumentSnapshot
	if *onlyID != "" {
		snap, gerr := contracts.Doc(*onlyID).Get(ctx)
		if gerr != nil {
			slog.Error("get contract failed", "id", *onlyID, "error", gerr)
			os.Exit(1)
		}
		docs = append(docs, snap)
	} else {
		it := contracts.Where("metric", "==", "route_completion").Documents(ctx)
		for {
			d, nerr := it.Next()
			if nerr == iterator.Done {
				break
			}
			if nerr != nil {
				it.Stop()
				slog.Error("list contracts failed", "error", nerr)
				os.Exit(1)
			}
			docs = append(docs, d)
		}
		it.Stop()
	}

	copied, stripped, skipped := 0, 0, 0
	for _, d := range docs {
		data := d.Data()
		route, _ := data["route"].(map[string]any)
		if route == nil {
			skipped++
			continue
		}
		points, _ := route["points"].([]any)
		if len(points) == 0 {
			// Không có polyline inline (đã tách rồi, hoặc kèo không hợp lệ) → bỏ qua.
			skipped++
			continue
		}
		creatorUID, _ := data["creatorUid"].(string)
		distanceMeters := route["distanceMeters"]

		if *dry {
			slog.Info("would split", "id", d.Ref.ID, "points", len(points), "strip", *strip)
			copied++
			continue
		}

		// 1) Ghi doc route đầy đủ (idempotent — chạy lại chỉ ghi đè cùng nội dung).
		routeDoc := map[string]any{
			"points":         points,
			"distanceMeters": distanceMeters,
			"pointCount":     len(points),
			"creatorUid":     creatorUID,
			"updatedAt":      firestore.ServerTimestamp,
		}
		if _, werr := client.Collection("runContractRoutes").Doc(d.Ref.ID).Set(ctx, routeDoc); werr != nil {
			slog.Error("write route doc failed", "id", d.Ref.ID, "error", werr)
			os.Exit(1)
		}
		copied++

		// 2) (tuỳ chọn) BỎ points inline → doc kèo còn route NHẸ. Phá vỡ app cũ nên
		// chỉ làm khi đã chốt. Giữ distanceMeters + pointCount cho card/label.
		if *strip {
			lightRoute := map[string]any{
				"distanceMeters": distanceMeters,
				"pointCount":     len(points),
			}
			if _, uerr := d.Ref.Update(ctx, []firestore.Update{{Path: "route", Value: lightRoute}}); uerr != nil {
				slog.Error("strip inline points failed", "id", d.Ref.ID, "error", uerr)
				os.Exit(1)
			}
			stripped++
		}
	}

	slog.Info("done", "contracts", len(docs), "copied", copied, "stripped", stripped, "skipped", skipped, "dry", *dry, "strip", *strip)
}
