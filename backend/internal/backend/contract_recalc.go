package backend

import (
	"context"
	"log/slog"
	"sort"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// contractNonRunSports: sportType KHÔNG tính là buổi CHẠY khi link vào kèo (khớp
// client: chỉ kind==run mới đếm). Đi bộ/leo núi/đạp xe đóng góp qua LUẬT BƯỚC
// (>=2500/ngày) + km đi-bộ-thuần, KHÔNG qua linking activity.
var contractNonRunSports = map[string]bool{
	"TrailRun": true, "VirtualRun": true, "Walk": true, "Hike": true, "Ride": true,
}

// stepDaySessionThreshold: >= 2500 bước trong 1 ngày (lịch VN) = 1 buổi thành công.
const stepDaySessionThreshold = 2500

type contractTarget struct {
	id, metric, creator string
	isJourney           bool
	start, end          time.Time
	participant         map[string]any
	counted             map[string]bool
}

// ContractRecalcResult: 1 dòng tiến độ đã tính (để log/kiểm tra dry-run).
type ContractRecalcResult struct {
	UID, ContractID, Metric  string
	OldProgress, NewProgress float64
	NewLinked                int
}

// RecalcActiveContracts link buổi chạy chưa gán + tính lại tiến độ (GỒM đi bộ:
// km đi-bộ-thuần cho distance/journey, và luật >=2500 bước/ngày = 1 buổi cho
// activity_count/active_days) cho MỌI kèo active. Chạy từ scheduler 2 lần/ngày
// để kèo luôn tươi mà user khỏi phải mở app. routeCompletion BỎ QUA (cần khớp
// tuyến — để client lo, không ghi đè). dryRun=true chỉ TÍNH + trả kết quả, KHÔNG
// ghi (để đối chiếu an toàn trước khi bật thật).
func RecalcActiveContracts(ctx context.Context, db *firestore.Client, dryRun bool) ([]ContractRecalcResult, error) {
	byUser := map[string][]*contractTarget{}
	it := db.Collection("runContracts").Where("status", "==", "active").Documents(ctx)
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			it.Stop()
			return nil, err
		}
		d := doc.Data()
		metric, _ := d["metric"].(string)
		if metric == "route_completion" {
			continue // client lo (khớp tuyến)
		}
		_, hasRoute := d["route"].(map[string]any)
		start, _ := d["startAt"].(time.Time)
		end, _ := d["endAtExclusive"].(time.Time)
		if start.IsZero() || end.IsZero() {
			continue
		}
		creator, _ := d["creatorUid"].(string)
		parts, _ := d["participants"].(map[string]any)
		for uid, pv := range parts {
			pm, _ := pv.(map[string]any)
			counted := map[string]bool{}
			if cids, ok := pm["countedActivityIds"].([]any); ok {
				for _, c := range cids {
					if s, ok := c.(string); ok {
						counted[s] = true
					}
				}
			}
			byUser[uid] = append(byUser[uid], &contractTarget{
				id: doc.Ref.ID, metric: metric, creator: creator,
				isJourney: hasRoute && metric == "distance",
				start:     start, end: end, participant: pm, counted: counted,
			})
		}
	}
	it.Stop()

	var results []ContractRecalcResult
	for uid := range byUser {
		rs, err := recalcUserContracts(ctx, db, uid, byUser[uid], dryRun)
		if err != nil {
			slog.Error("recalc contracts cho user lỗi", "uid", uid, "error", err)
			continue
		}
		results = append(results, rs...)
	}
	return results, nil
}

func recalcUserContracts(ctx context.Context, db *firestore.Client, uid string, targets []*contractTarget, dryRun bool) ([]ContractRecalcResult, error) {
	// Cửa sổ bao toàn bộ kèo của user.
	minStart, maxEnd := targets[0].start, targets[0].end
	for _, t := range targets {
		if t.start.Before(minStart) {
			minStart = t.start
		}
		if t.end.After(maxEnd) {
			maxEnd = t.end
		}
	}

	// 1) Buổi chạy trong cửa sổ → ActivityFact → dedup official (khớp client).
	facts := []ActivityFact{}
	manual := map[string]bool{}
	dupOf := map[string]string{}
	aIter := db.Collection("users").Doc(uid).Collection("activities").
		Where("startedAt", ">=", minStart.UTC().Format(time.RFC3339Nano)).
		Where("startedAt", "<", maxEnd.UTC().Format(time.RFC3339Nano)).Documents(ctx)
	for {
		doc, err := aIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			aIter.Stop()
			return nil, err
		}
		data := doc.Data()
		if m, _ := data["manual"].(bool); m {
			manual[doc.Ref.ID] = true
		}
		if dup, _ := data["duplicateOfActivityId"].(string); dup != "" {
			dupOf[doc.Ref.ID] = dup
		}
		facts = append(facts, NewActivityFact(doc.Ref.ID, data))
	}
	aIter.Stop()
	official := SelectOfficialActivities(facts)

	distByID := map[string]float64{}
	startByID := map[string]time.Time{}
	sportByID := map[string]string{}
	officialMetersByDay := map[string]float64{} // ALL official (khớp walk-only ở rebuildStepLeaderboard)
	for _, f := range official {
		distByID[f.ID] = f.DistanceMeters
		startByID[f.ID] = f.StartedAt
		sportByID[f.ID] = f.SportType
		officialMetersByDay[dateKey(f.StartedAt)] += f.DistanceMeters
	}

	// 2) stepDays trong cửa sổ: số bước + quãng đường (đi bộ+chạy) theo NGÀY.
	stepMetersByDay := map[string]float64{}
	stepCountByDay := map[string]int64{}
	sIter := db.Collection("users").Doc(uid).Collection("stepDays").
		Where("date", ">=", dateKey(minStart)).
		Where("date", "<=", dateKey(maxEnd)).Documents(ctx)
	for {
		doc, err := sIter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			sIter.Stop()
			return nil, err
		}
		data := doc.Data()
		day := stringValue(data["date"])
		stepMetersByDay[day] = number(data["distanceMeters"])
		stepCountByDay[day] = int64(number(data["steps"]))
	}
	sIter.Stop()

	// Buổi chạy hiện có claim (để không claim đôi + biết buổi nào đã chiếm chỗ).
	claimed := map[string]bool{}
	cIter := db.Collection("users").Doc(uid).Collection("runContractActivityClaims").Documents(ctx)
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
	cIter.Stop()
	blocked := map[string]bool{}
	for id := range claimed {
		blocked[id] = true
		if d := dupOf[id]; d != "" {
			blocked[d] = true
		}
	}

	// 3) LINK buổi chạy chưa gán vào kèo (KHÔNG-journey) sắp hết hạn nhất mà hợp lệ.
	// Journey KHÔNG chiếm buổi (chỉ TÍNH), nên loại khỏi bước gán claim.
	newByContract := map[string][]string{}
	for _, f := range official {
		if manual[f.ID] || contractNonRunSports[sportByID[f.ID]] {
			continue // chỉ buổi CHẠY thuần được gán
		}
		if blocked[f.ID] || (dupOf[f.ID] != "" && blocked[dupOf[f.ID]]) {
			continue // 1-buổi-1-claim (kể cả bản trùng-nguồn)
		}
		var target *contractTarget
		for _, c := range targets {
			if c.isJourney {
				continue
			}
			inWindow := !f.StartedAt.Before(c.start) && f.StartedAt.Before(c.end)
			if inWindow && contractMeetsThreshold(f.DistanceMeters, c.metric) {
				if target == nil || c.end.Before(target.end) {
					target = c
				}
			}
		}
		if target != nil {
			newByContract[target.id] = append(newByContract[target.id], f.ID)
		}
	}

	var results []ContractRecalcResult
	for _, c := range targets {
		var countedIDs []string
		if c.isJourney {
			// Hành trình TÍNH mọi buổi chạy trong kỳ (không chiếm claim).
			for _, f := range official {
				if contractNonRunSports[sportByID[f.ID]] {
					continue
				}
				if !f.StartedAt.Before(c.start) && f.StartedAt.Before(c.end) {
					countedIDs = append(countedIDs, f.ID)
				}
			}
		} else {
			all := map[string]bool{}
			for id := range c.counted {
				all[id] = true
			}
			for _, id := range newByContract[c.id] {
				all[id] = true
			}
			for id := range all {
				countedIDs = append(countedIDs, id)
			}
		}
		sort.Strings(countedIDs)

		progress := contractProgressWithWalk(
			c.metric, countedIDs, c.start, c.end,
			distByID, startByID, officialMetersByDay, stepMetersByDay, stepCountByDay,
		)
		newIDs := newByContract[c.id]
		results = append(results, ContractRecalcResult{
			UID: uid, ContractID: c.id, Metric: c.metric,
			OldProgress: number(c.participant["progressValue"]),
			NewProgress: progress, NewLinked: len(newIDs),
		})
		if dryRun {
			continue // chỉ tính, không ghi
		}

		// Ghi claim buổi mới (journey không có buổi mới).
		for _, id := range newIDs {
			if _, err := db.Collection("users").Doc(uid).Collection("runContractActivityClaims").Doc(id).Set(ctx, map[string]any{
				"activityId": id, "contractId": c.id, "uid": uid, "assignedAt": firestore.ServerTimestamp,
			}); err != nil {
				slog.Error("ghi claim lỗi", "uid", uid, "activity", id, "error", err)
			}
		}

		p := map[string]any{
			"uid":                uid,
			"progressValue":      progress,
			"countedActivityIds": ternStrings(c.isJourney, nil, countedIDs),
			"joinedAt":           c.participant["joinedAt"],
			"updatedAt":          firestore.ServerTimestamp,
		}
		updates := []firestore.Update{
			{FieldPath: firestore.FieldPath{"participants", uid}, Value: p},
		}
		if c.creator == uid {
			updates = append(updates, firestore.Update{Path: "progressValue", Value: progress})
		}
		if _, err := db.Collection("runContracts").Doc(c.id).Update(ctx, updates); err != nil {
			slog.Error("cập nhật participant lỗi", "contract", c.id, "uid", uid, "error", err)
		}
	}
	return results, nil
}

// contractMeetsThreshold: ngưỡng tối thiểu/buổi (khớp meetsMetricDistanceThreshold client).
func contractMeetsThreshold(distMeters float64, metric string) bool {
	if metric == "activity_count" || metric == "active_days" {
		return distMeters > 1000
	}
	return distMeters > 0
}

// contractProgressWithWalk tính tiến độ GỒM đi bộ:
//   - distance/journey: km chạy đã tính + km ĐI-BỘ-THUẦN (Apple ngày − official chạy).
//   - activity_count: số buổi chạy + số NGÀY >= 2500 bước.
//   - active_days: số ngày có (buổi chạy HOẶC >= 2500 bước).
//   - longest_run: buổi CHẠY dài nhất (đi bộ KHÔNG tính).
func contractProgressWithWalk(
	metric string, countedIDs []string, start, end time.Time,
	distByID map[string]float64, startByID map[string]time.Time,
	officialMetersByDay, stepMetersByDay map[string]float64, stepCountByDay map[string]int64,
) float64 {
	switch metric {
	case "longest_run":
		var m float64
		for _, id := range countedIDs {
			if distByID[id] > m {
				m = distByID[id]
			}
		}
		return m / 1000
	case "activity_count":
		n := float64(len(countedIDs))
		for day, steps := range stepCountByDay {
			if steps >= stepDaySessionThreshold && dayInWindow(day, start, end) {
				n++
			}
		}
		return n
	case "active_days":
		days := map[string]bool{}
		for _, id := range countedIDs {
			days[dateKey(startByID[id])] = true
		}
		for day, steps := range stepCountByDay {
			if steps >= stepDaySessionThreshold && dayInWindow(day, start, end) {
				days[day] = true
			}
		}
		return float64(len(days))
	default: // distance + journey
		var m float64
		for _, id := range countedIDs {
			m += distByID[id]
		}
		// Cộng km ĐI-BỘ-THUẦN theo ngày (không đếm đôi phần chạy đã có ở trên).
		for day, dist := range stepMetersByDay {
			if !dayInWindow(day, start, end) {
				continue
			}
			walk := dist - officialMetersByDay[day]
			if walk > 0 {
				m += walk
			}
		}
		return m / 1000
	}
}

// dayInWindow: ngày (YYYY-MM-DD lịch VN) có nằm trong [start,end) không.
func dayInWindow(day string, start, end time.Time) bool {
	return day >= dateKey(start) && day <= dateKey(end.Add(-time.Second))
}

func ternStrings(cond bool, a, b []string) []string {
	if cond {
		return a
	}
	return b
}
