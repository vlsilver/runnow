// Command link-activities-to-contracts TỰ GÁN các buổi chạy CHƯA gán vào kèo
// đang active mà user tham gia — one-off, thay cho việc chờ từng người mở app
// (nơi client tự auto-link). Khớp logic client autoLinkUnassignedActivities:
// mỗi buổi → kèo SẮP HẾT HẠN nhất mà nó hợp lệ, 1-buổi-1-kèo, dedup Strava/3i
// (dùng backend.SelectOfficialActivities).
//
// PHẠM VI (an toàn): chỉ metric "distance", bỏ qua Hành trình (có route) +
// metric khác (route_completion/longest_run/activity_count/active_days) — in ra
// để xử riêng. Buổi đã claim ở kèo nào rồi thì bỏ qua (idempotent).
//
// MẶC ĐỊNH -dry-run=true: chỉ in dự định, KHÔNG ghi. Chạy lại với -dry-run=false
// để ghi thật.
//
//	gcloud auth application-default login
//	go run ./migrations/link-activities-to-contracts                 # dry-run
//	go run ./migrations/link-activities-to-contracts -dry-run=false  # ghi thật
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"
	"sort"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

var runSports = map[string]bool{"Run": true, "TrailRun": true, "VirtualRun": true}

type contractInfo struct {
	id          string
	metric      string
	start, end  time.Time
	participant map[string]any // participants[uid] hiện tại (giữ joinedAt…)
	counted     map[string]bool
}

// Metric cộng-dồn migration hỗ trợ (đơn giản, an toàn). longest_run/route_completion
// + Hành trình → bỏ qua, in ra để xử riêng.
var supportedMetric = map[string]bool{"distance": true, "activity_count": true, "active_days": true}

// Ngưỡng tối thiểu/buổi theo metric (khớp meetsMetricDistanceThreshold ở client).
func meetsThreshold(distMeters float64, metric string) bool {
	if metric == "activity_count" || metric == "active_days" {
		return distMeters > 1000
	}
	return distMeters > 0
}

var vnZone = time.FixedZone("VN", 7*3600)

func main() {
	project := flag.String("project", "run-now-79767", "GCP project ID")
	dryRun := flag.Bool("dry-run", true, "chỉ in, không ghi (an toàn)")
	flag.Parse()

	ctx := context.Background()
	client, err := firestore.NewClient(ctx, *project)
	if err != nil {
		slog.Error("connect Firestore failed — `gcloud auth application-default login` trước", "error", err)
		os.Exit(1)
	}
	defer client.Close()

	// 1) Kèo active hợp lệ (distance, không journey) → gom theo user tham gia.
	byUser := map[string][]*contractInfo{}
	iter := client.Collection("runContracts").Where("status", "==", "active").Documents(ctx)
	defer iter.Stop()
	skipped := 0
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			slog.Error("list runContracts failed", "error", err)
			os.Exit(1)
		}
		d := doc.Data()
		metric, _ := d["metric"].(string)
		_, hasRoute := d["route"].(map[string]any)
		if !supportedMetric[metric] || hasRoute { // journey (distance+route) hoặc metric phức tạp
			slog.Info("BỎ QUA kèo (metric không hỗ trợ / hành trình)", "id", doc.Ref.ID, "metric", metric, "journey", hasRoute)
			skipped++
			continue
		}
		start, _ := d["startAt"].(time.Time)
		end, _ := d["endAtExclusive"].(time.Time)
		if start.IsZero() || end.IsZero() {
			continue
		}
		participants, _ := d["participants"].(map[string]any)
		for uid, raw := range participants {
			p, _ := raw.(map[string]any)
			counted := map[string]bool{}
			if ids, ok := p["countedActivityIds"].([]any); ok {
				for _, v := range ids {
					if s, ok := v.(string); ok {
						counted[s] = true
					}
				}
			}
			byUser[uid] = append(byUser[uid], &contractInfo{
				id: doc.Ref.ID, metric: metric, start: start, end: end, participant: p, counted: counted,
			})
		}
	}
	slog.Info("kèo distance active", "users", len(byUser), "skipped_khác", skipped)

	linkedTotal := 0
	for uid, contracts := range byUser {
		linked := processUser(ctx, client, uid, contracts, *dryRun)
		linkedTotal += linked
	}
	slog.Info("HOÀN TẤT", "dry_run", *dryRun, "tổng_buổi_link", linkedTotal)
	if *dryRun {
		slog.Info(">>> Đây là DRY-RUN. Chạy lại với -dry-run=false để GHI thật.")
	}
}

// computeProgress: distance = tổng km; activity_count = số buổi; active_days =
// số ngày (lịch VN) khác nhau. Khớp calculateRunContractProgress ở client.
func computeProgress(metric string, ids []string, dist map[string]float64, start map[string]time.Time) float64 {
	switch metric {
	case "activity_count":
		return float64(len(ids))
	case "active_days":
		days := map[string]bool{}
		for _, id := range ids {
			if t, ok := start[id]; ok {
				days[t.In(vnZone).Format("2006-01-02")] = true
			}
		}
		return float64(len(days))
	default: // distance
		var m float64
		for _, id := range ids {
			m += dist[id]
		}
		return m / 1000
	}
}

func processUser(ctx context.Context, client *firestore.Client, uid string, contracts []*contractInfo, dryRun bool) int {
	// Cửa sổ bao toàn bộ kèo của user.
	minStart, maxEnd := contracts[0].start, contracts[0].end
	for _, c := range contracts {
		if c.start.Before(minStart) {
			minStart = c.start
		}
		if c.end.After(maxEnd) {
			maxEnd = c.end
		}
	}

	// Đọc activity trong cửa sổ → ActivityFact → dedup official.
	actIter := client.Collection("users").Doc(uid).Collection("activities").
		Where("startedAt", ">=", minStart.UTC().Format(time.RFC3339Nano)).
		Where("startedAt", "<", maxEnd.UTC().Format(time.RFC3339Nano)).Documents(ctx)
	defer actIter.Stop()
	facts := []backend.ActivityFact{}
	manual := map[string]bool{}
	for {
		doc, err := actIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			slog.Error("đọc activities lỗi", "uid", uid, "error", err)
			return 0
		}
		data := doc.Data()
		if m, _ := data["manual"].(bool); m {
			manual[doc.Ref.ID] = true
		}
		facts = append(facts, backend.NewActivityFact(doc.Ref.ID, data))
	}
	official := backend.SelectOfficialActivities(facts)
	distByID := map[string]float64{}
	startByID := map[string]time.Time{}
	for _, f := range official {
		distByID[f.ID] = f.DistanceMeters
		startByID[f.ID] = f.StartedAt
	}

	// Đọc claim hiện có của user.
	claimed := map[string]bool{}
	cIter := client.Collection("users").Doc(uid).Collection("runContractActivityClaims").Documents(ctx)
	defer cIter.Stop()
	for {
		doc, err := cIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			break
		}
		claimed[doc.Ref.ID] = true
	}

	// Gán mỗi buổi chưa claim vào kèo sắp hết hạn nhất mà nó hợp lệ (distance:
	// trong cửa sổ + distance>0 + là buổi CHẠY).
	newByContract := map[string][]string{}
	for _, f := range official {
		if claimed[f.ID] || manual[f.ID] || !runSports[f.SportType] {
			continue
		}
		var target *contractInfo
		for _, c := range contracts {
			inWindow := !f.StartedAt.Before(c.start) && f.StartedAt.Before(c.end)
			if inWindow && meetsThreshold(f.DistanceMeters, c.metric) {
				if target == nil || c.end.Before(target.end) {
					target = c
				}
			}
		}
		if target == nil {
			continue
		}
		newByContract[target.id] = append(newByContract[target.id], f.ID)
	}

	linked := 0
	for _, c := range contracts {
		newIDs := newByContract[c.id]
		if len(newIDs) == 0 {
			continue
		}
		// countedActivityIds = cũ + mới; progress theo metric của kèo.
		all := map[string]bool{}
		for id := range c.counted {
			all[id] = true
		}
		for _, id := range newIDs {
			all[id] = true
		}
		ids := make([]string, 0, len(all))
		for id := range all {
			ids = append(ids, id)
		}
		sort.Strings(ids)
		progress := computeProgress(c.metric, ids, distByID, startByID)

		slog.Info("LINK", "uid", uid, "contract", c.id, "metric", c.metric,
			"buổi_mới", len(newIDs), "tổng_buổi", len(ids), "progress", progress)
		linked += len(newIDs)
		if dryRun {
			continue
		}

		// Ghi claim cho từng buổi mới.
		for _, id := range newIDs {
			_, err := client.Collection("users").Doc(uid).Collection("runContractActivityClaims").Doc(id).Set(ctx, map[string]any{
				"activityId": id, "contractId": c.id, "uid": uid, "assignedAt": firestore.ServerTimestamp,
			})
			if err != nil {
				slog.Error("ghi claim lỗi", "uid", uid, "activity", id, "error", err)
			}
		}
		// Cập nhật participants[uid]: giữ joinedAt, đặt countedActivityIds + progressValue.
		p := map[string]any{
			"uid":                uid,
			"progressValue":      progress,
			"countedActivityIds": ids,
			"joinedAt":           c.participant["joinedAt"],
			"updatedAt":          firestore.ServerTimestamp,
		}
		_, err := client.Collection("runContracts").Doc(c.id).Update(ctx, []firestore.Update{
			{FieldPath: firestore.FieldPath{"participants", uid}, Value: p},
		})
		if err != nil {
			slog.Error("cập nhật participant lỗi", "contract", c.id, "uid", uid, "error", err)
		}
	}
	return linked
}
