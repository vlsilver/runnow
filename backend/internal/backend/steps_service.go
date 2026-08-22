package backend

import (
	"context"
	"regexp"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// NewActivityFact dựng ActivityFact từ doc Firestore — wrapper EXPORT cho
// migration (activityFact nội bộ không export). Đúng cùng parse với leaderboard.
func NewActivityFact(id string, data map[string]any) ActivityFact {
	return activityFact(id, data)
}

// RebuildStepLeaderboardFor dựng lại stepLeaderboardEntries/{uid} — wrapper
// EXPORT cho migration one-off (chỉ cần firestore client, không cần deps khác).
// Dùng đúng logic rebuildStepLeaderboard hiện tại (đi-bộ-thuần = Apple − chạy).
func RebuildStepLeaderboardFor(ctx context.Context, db *firestore.Client, uid string, now time.Time) error {
	s := &ActivityService{db: db}
	return s.rebuildStepLeaderboard(ctx, uid, now)
}

// healthStepDay là số bước + quãng đường (đi bộ+chạy) của MỘT ngày (lịch VN)
// client đọc từ Apple Health. HealthKit đã tự dedup giữa iPhone + Apple Watch
// khi lấy tổng theo khoảng (HKStatisticsCollectionQuery cumulativeSum).
// DistanceMeters là chỉ số "Walking + Running Distance" — CHỈ để hiển thị kèm
// bước, KHÔNG tính vào km chạy / kèo.
type healthStepDay struct {
	Date           string  `json:"date"` // YYYY-MM-DD
	Steps          int64   `json:"steps"`
	DistanceMeters float64 `json:"distanceMeters"`
	// Chi tiết THEO GIỜ (24 phần tử 0h→23h) — client đọc từ Apple Health rồi lưu để
	// màn detail đọc từ Firestore (xem được simulator/offline/user khác). Có thể rỗng.
	HourlySteps    []int64   `json:"hourlySteps"`
	HourlyDistance []float64 `json:"hourlyDistance"`
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
		doc := map[string]any{
			"date":           d.Date,
			"steps":          d.Steps,
			"distanceMeters": dist,
			"updatedAt":      firestore.ServerTimestamp,
		}
		// Chi tiết theo giờ (24 phần tử) — chỉ ghi khi client gửi (ngày cũ / client
		// cũ không gửi thì giữ nguyên field cũ nhờ MergeAll, không xoá).
		if len(d.HourlySteps) == 24 {
			doc["hourlySteps"] = d.HourlySteps
		}
		if len(d.HourlyDistance) == 24 {
			doc["hourlyDistance"] = d.HourlyDistance
		}
		ref := s.db.Collection("users").Doc(uid).Collection("stepDays").Doc(d.Date)
		if _, err := ref.Set(ctx, doc, firestore.MergeAll); err != nil {
			return err
		}
		wrote = true
	}
	if !wrote {
		return nil
	}
	return s.rebuildStepLeaderboard(ctx, uid, time.Now())
}

// officialRunMetersByDay tổng quãng đường các buổi CHÍNH THỨC (đã khử trùng
// Strava/3i qua SelectOfficialActivities — đúng bộ đang tính ở km leaderboard)
// theo NGÀY (dateKey VN) trong khoảng các kỳ hiện tại. Dùng để trừ khỏi chỉ số
// đi-bộ-chạy của Apple, tránh đếm đôi phần chạy trong "Tổng km".
func (s *ActivityService) officialRunMetersByDay(ctx context.Context, uid string, periods CurrentPeriods) (map[string]float64, error) {
	start := earliest(periods.Rolling.Start, periods.Week.Start, periods.Month.Start).Add(-24 * time.Hour)
	end := latest(periods.Rolling.End, periods.Week.End, periods.Month.End)
	iter := s.db.Collection("users").Doc(uid).Collection("activities").
		Where("startedAt", ">=", start.UTC().Format(time.RFC3339Nano)).
		Where("startedAt", "<", end.UTC().Format(time.RFC3339Nano)).Documents(ctx)
	defer iter.Stop()
	facts := []ActivityFact{}
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return nil, err
		}
		facts = append(facts, activityFact(doc.Ref.ID, doc.Data()))
	}
	byDay := map[string]float64{}
	for _, a := range SelectOfficialActivities(facts) {
		byDay[dateKey(a.StartedAt)] += a.DistanceMeters
	}
	return byDay, nil
}

// rebuildStepLeaderboard tổng bước theo 7 ngày / tuần / tháng (lịch VN, khớp
// leaderboard km) rồi ghi stepLeaderboardEntries/{uid}. Query 1 field `date`
// (range) — không cần composite index.
func (s *ActivityService) rebuildStepLeaderboard(ctx context.Context, uid string, now time.Time) error {
	periods := PeriodsAt(now)
	rollingKey := dateKey(periods.Rolling.Start)
	weekKey := dateKey(periods.Week.Start)
	monthKey := dateKey(periods.Month.Start)
	earliestKey := minStr(minStr(rollingKey, weekKey), monthKey)

	// Km CHẠY chính thức (đã khử trùng Strava/3i) theo NGÀY — để TRỪ khỏi chỉ số
	// Apple "Walking + RUNNING Distance" (vốn đã gồm cả chạy). Còn lại là đi bộ
	// THUẦN → cộng vào "Tổng km" mà không đếm đôi phần chạy (đã có ở km leaderboard).
	runByDay, err := s.officialRunMetersByDay(ctx, uid, periods)
	if err != nil {
		return err
	}

	iter := s.db.Collection("users").Doc(uid).Collection("stepDays").
		Where("date", ">=", earliestKey).Documents(ctx)
	defer iter.Stop()
	var rolling, week, month int64
	// Quãng đường ĐI BỘ THUẦN (mét) theo kỳ — client cộng vào BXH "Tổng km".
	var rollingDist, weekDist, monthDist float64
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
		// Apple(đi+chạy) trừ km chạy chính thức ngày đó = đi bộ thuần (không âm).
		walk := number(data["distanceMeters"]) - runByDay[date]
		if walk < 0 {
			walk = 0
		}
		if date >= rollingKey {
			rolling += steps
			rollingDist += walk
		}
		if date >= weekKey {
			week += steps
			weekDist += walk
		}
		if date >= monthKey {
			month += steps
			monthDist += walk
		}
	}

	// Km CHẠY chính thức theo kỳ (từ runByDay) — để BACKEND tự tính TỔNG = chạy +
	// đi-bộ (client KHÔNG phải cộng 2 nguồn nữa). Cộng theo ngày để phủ cả ngày có
	// chạy nhưng không có stepDay. dateKey (YYYY-MM-DD) so chuỗi = so thời gian.
	var rollingRun, weekRun, monthRun float64
	for date, m := range runByDay {
		if date >= rollingKey {
			rollingRun += m
		}
		if date >= weekKey {
			weekRun += m
		}
		if date >= monthKey {
			monthRun += m
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
		"rollingSevenDaysSteps":    rolling,
		"currentWeekSteps":         week,
		"currentMonthSteps":        month,
		"rollingSevenDaysDistance": rollingDist,
		"currentWeekDistance":      weekDist,
		"currentMonthDistance":     monthDist,
		// Km CHẠY chính thức theo kỳ (để minh bạch/đối chiếu).
		"rollingSevenDaysRunDistance": rollingRun,
		"currentWeekRunDistance":      weekRun,
		"currentMonthRunDistance":     monthRun,
		// TỔNG km = chạy + đi-bộ-thuần — BACKEND tính sẵn, client đọc thẳng số này
		// cho BXH "Tổng km" (khỏi tự cộng 2 nguồn → hết lệch/đếm đôi).
		"rollingSevenDaysTotalDistance": rollingRun + rollingDist,
		"currentWeekTotalDistance":      weekRun + weekDist,
		"currentMonthTotalDistance":     monthRun + monthDist,
		"currentWeekStart":              weekKey,
		"currentMonthStart":             monthKey,
		"updatedAt":                     firestore.ServerTimestamp,
	}, firestore.MergeAll)
	return err
}
