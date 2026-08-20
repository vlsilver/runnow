package backend

import (
	"context"
	"regexp"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// healthStepDay là số bước + quãng đường (đi bộ+chạy) của MỘT ngày (lịch VN)
// client đọc từ Apple Health. HealthKit đã tự dedup giữa iPhone + Apple Watch
// khi lấy tổng theo khoảng (HKStatisticsCollectionQuery cumulativeSum).
// DistanceMeters là chỉ số "Walking + Running Distance" — CHỈ để hiển thị kèm
// bước, KHÔNG tính vào km chạy / kèo.
type healthStepDay struct {
	Date           string  `json:"date"` // YYYY-MM-DD
	Steps          int64   `json:"steps"`
	DistanceMeters float64 `json:"distanceMeters"`
}

var stepDateRe = regexp.MustCompile(`^\d{4}-\d{2}-\d{2}$`)

func minStr(a, b string) string {
	if a < b {
		return a
	}
	return b
}

// ImportHealthSteps upsert số bước theo NGÀY (users/{uid}/stepDays/{date}) rồi
// dựng lại entry bảng xếp hạng BƯỚC (riêng, không dính km chạy / kèo). Ghi đè
// theo ngày nên đồng bộ lại chỉ cập nhật, không nhân bản.
func (s *ActivityService) ImportHealthSteps(ctx context.Context, uid string, days []healthStepDay) error {
	wrote := false
	for _, d := range days {
		if !stepDateRe.MatchString(d.Date) || d.Steps < 0 || d.Steps > 500000 {
			continue
		}
		// Chặn số vô lý: 200km/ngày là quá dư cho đi bộ+chạy. Âm → 0.
		dist := d.DistanceMeters
		if dist < 0 || dist > 200000 {
			dist = 0
		}
		ref := s.db.Collection("users").Doc(uid).Collection("stepDays").Doc(d.Date)
		if _, err := ref.Set(ctx, map[string]any{
			"date":           d.Date,
			"steps":          d.Steps,
			"distanceMeters": dist,
			"updatedAt":      firestore.ServerTimestamp,
		}, firestore.MergeAll); err != nil {
			return err
		}
		wrote = true
	}
	if !wrote {
		return nil
	}
	return s.rebuildStepLeaderboard(ctx, uid, time.Now())
}

// rebuildStepLeaderboard tổng BƯỚC theo 7 ngày / tuần / tháng (lịch VN, khớp
// leaderboard km) rồi ghi stepLeaderboardEntries/{uid}. Query 1 field `date`
// (range) — không cần composite index. Chỉ xếp hạng theo SỐ BƯỚC; quãng đường
// đi bộ (Apple) KHÔNG vào leaderboard (nó gộp cả đi-lại-thường-ngày + trùng km
// chạy) — chỉ hiển thị theo ngày ở card, còn km là leaderboardEntries (activity).
func (s *ActivityService) rebuildStepLeaderboard(ctx context.Context, uid string, now time.Time) error {
	periods := PeriodsAt(now)
	rollingKey := dateKey(periods.Rolling.Start)
	weekKey := dateKey(periods.Week.Start)
	monthKey := dateKey(periods.Month.Start)
	earliestKey := minStr(minStr(rollingKey, weekKey), monthKey)

	iter := s.db.Collection("users").Doc(uid).Collection("stepDays").
		Where("date", ">=", earliestKey).Documents(ctx)
	defer iter.Stop()
	var rolling, week, month int64
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		data := doc.Data()
		date := stringValue(data["date"])
		steps := int64(number(data["steps"]))
		if date >= rollingKey {
			rolling += steps
		}
		if date >= weekKey {
			week += steps
		}
		if date >= monthKey {
			month += steps
		}
	}

	profile, err := resolveProfile(ctx, s.db, uid)
	if err != nil {
		return err
	}
	_, err = s.db.Collection("stepLeaderboardEntries").Doc(uid).Set(ctx, map[string]any{
		"uid":                   uid,
		"displayName":           preferredName(profile),
		"avatarUrl":             nullableString(profile["avatarUrl"]),
		"profileVisibility":     defaultString(profile["profileVisibility"], "private"),
		"rollingSevenDaysSteps": rolling,
		"currentWeekSteps":      week,
		"currentMonthSteps":     month,
		"currentWeekStart":      weekKey,
		"currentMonthStart":     monthKey,
		"updatedAt":             firestore.ServerTimestamp,
		// Ghi đè km-đi-bộ CŨ (từ lần thử "Tổng km") về 0 — để app còn chạy code
		// merge cũ cũng cộng "running + 0 = running", km về chạy-thuần mà KHÔNG
		// cần build lại mobile. Khi mọi bản đã bỏ merge, có thể gỡ 3 dòng này.
		"rollingSevenDaysDistance": 0,
		"currentWeekDistance":      0,
		"currentMonthDistance":     0,
	}, firestore.MergeAll)
	return err
}
