package backend

import (
	"context"
	"fmt"
	"math"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
)

// BotTools là tập truy vấn Firestore mà model được phép gọi.
//
// Cố tình KHÔNG cho model tự viết query. Firestore không aggregate tuỳ ý,
// mỗi truy vấn nhiều điều kiện cần composite index khai báo trước, và tính
// tiền theo số document đọc — thả cho model tự sinh query nghĩa là nhận lấy
// lỗi thiếu index, quét nhầm cả collection, và không kiểm soát được nó đọc
// dữ liệu của ai. Mỗi tool dưới đây là một truy vấn đã tối ưu sẵn, chỉ chạm
// vào dữ liệu thành viên đã đặt hồ sơ ở chế độ công khai.
type BotTools struct {
	db *firestore.Client
}

func NewBotTools(db *firestore.Client) *BotTools { return &BotTools{db: db} }

// periodField ánh xạ tên kỳ mà model dùng sang đúng field trong
// leaderboardEntries (xem StatsFor trong derived_data_service.go).
func periodField(period string) (string, string, error) {
	switch strings.ToLower(strings.TrimSpace(period)) {
	case "week", "":
		return "currentWeek", "tuần này", nil
	case "month":
		return "currentMonth", "tháng này", nil
	case "rolling7":
		return "rollingSevenDays", "7 ngày qua", nil
	}
	return "", "", fmt.Errorf("period không hợp lệ: %q (chỉ nhận week, month, rolling7)", period)
}

// memberRow là một dòng đã phẳng hoá, sẵn sàng đưa cho model.
//
// Đơn vị đổi sang km/phút ngay tại đây thay vì để model tự chia: model tính
// nhẩm sai là chuyện thường, mà sai số quãng đường thì người đọc tin ngay.
type memberRow struct {
	Name          string  `json:"name"`
	DistanceKm    float64 `json:"distanceKm"`
	Sessions      int64   `json:"sessions"`
	ActiveDays    int64   `json:"activeDays"`
	LongestKm     float64 `json:"longestKm"`
	MovingMinutes int64   `json:"movingMinutes"`
	PacePerKm     string  `json:"pacePerKm,omitempty"`
	paceSeconds   float64
	// uid không serialize ra cho model — chỉ để lần tới activities của người
	// này khi cần chi tiết một buổi chạy.
	uid string
}

// loadMembers đọc toàn bộ bảng xếp hạng cho một kỳ.
//
// Chỉ lấy thành viên để hồ sơ công khai — giống hệt điều kiện bản app dùng
// khi dựng danh sách club. Người đặt hồ sơ riêng tư không được bot nhắc tới.
func (t *BotTools) loadMembers(ctx context.Context, period string) ([]memberRow, string, error) {
	field, label, err := periodField(period)
	if err != nil {
		return nil, "", err
	}
	docs, err := t.db.Collection("leaderboardEntries").Documents(ctx).GetAll()
	if err != nil {
		return nil, "", err
	}
	rows := make([]memberRow, 0, len(docs))
	for _, doc := range docs {
		data := doc.Data()
		if stringValue(data["profileVisibility"]) != "public" {
			continue
		}
		stats, _ := data[field].(map[string]any)
		if stats == nil {
			continue
		}
		row := memberRow{
			Name:          preferredName(data),
			DistanceKm:    round2(number(stats["distanceMeters"]) / 1000),
			Sessions:      int64(number(stats["activityCount"])),
			ActiveDays:    int64(number(stats["activeDays"])),
			LongestKm:     round2(number(stats["longestDistanceMeters"]) / 1000),
			MovingMinutes: int64(number(stats["movingTimeSeconds"]) / 60),
			paceSeconds:   number(stats["fastestPaceSecondsPerKm"]),
		}
		if row.paceSeconds > 0 {
			row.PacePerKm = fmt.Sprintf("%d:%02d", int64(row.paceSeconds)/60, int64(row.paceSeconds)%60)
		}
		row.uid = doc.Ref.ID
		rows = append(rows, row)
	}
	return rows, label, nil
}

// sortMembers sắp xếp theo tiêu chí. Pace là trường hợp ngược: nhỏ hơn là
// nhanh hơn, và ai chưa có pace phải bị đẩy xuống cuối chứ không được coi
// như nhanh vô hạn.
func sortMembers(rows []memberRow, metric string) error {
	switch strings.ToLower(strings.TrimSpace(metric)) {
	case "distance", "":
		sort.SliceStable(rows, func(i, j int) bool { return rows[i].DistanceKm > rows[j].DistanceKm })
	case "sessions":
		sort.SliceStable(rows, func(i, j int) bool { return rows[i].Sessions > rows[j].Sessions })
	case "activedays":
		sort.SliceStable(rows, func(i, j int) bool { return rows[i].ActiveDays > rows[j].ActiveDays })
	case "longest":
		sort.SliceStable(rows, func(i, j int) bool { return rows[i].LongestKm > rows[j].LongestKm })
	case "pace":
		sort.SliceStable(rows, func(i, j int) bool {
			a, b := rows[i].paceSeconds, rows[j].paceSeconds
			if a <= 0 {
				return false
			}
			if b <= 0 {
				return true
			}
			return a < b
		})
	default:
		return fmt.Errorf("metric không hợp lệ: %q", metric)
	}
	return nil
}

// GetLeaderboard trả về bảng xếp hạng đã sắp sẵn.
func (t *BotTools) GetLeaderboard(ctx context.Context, args map[string]any) (any, error) {
	period := stringValue(args["period"])
	metric := stringValue(args["metric"])
	rows, label, err := t.loadMembers(ctx, period)
	if err != nil {
		return nil, err
	}
	if err := sortMembers(rows, metric); err != nil {
		return nil, err
	}
	limit := int(number(args["limit"]))
	if limit <= 0 {
		limit = 5
	}
	if limit > 20 {
		limit = 20
	}
	// Người chưa chạy buổi nào không nên chiếm chỗ trong bảng xếp hạng.
	active := rows[:0]
	for _, r := range rows {
		if r.Sessions > 0 {
			active = append(active, r)
		}
	}
	if len(active) > limit {
		active = active[:limit]
	}
	return map[string]any{"period": label, "metric": metric, "entries": active}, nil
}

// GetMemberStats tra chỉ số của một người theo tên.
//
// Model nhận được tên do người dùng gõ trong chat, thường thiếu dấu hoặc chỉ
// là một phần tên, nên phải so khớp lỏng. Trả về danh sách ứng viên khi mơ
// hồ để model tự hỏi lại, thay vì đoán bừa một người.
func (t *BotTools) GetMemberStats(ctx context.Context, args map[string]any) (any, error) {
	query := strings.ToLower(strings.TrimSpace(stringValue(args["name"])))
	if query == "" {
		return nil, fmt.Errorf("thiếu tên thành viên")
	}
	period := stringValue(args["period"])
	rows, label, err := t.loadMembers(ctx, period)
	if err != nil {
		return nil, err
	}
	matches := []memberRow{}
	for _, r := range rows {
		if strings.Contains(strings.ToLower(r.Name), query) {
			matches = append(matches, r)
		}
	}
	switch {
	case len(matches) == 0:
		return map[string]any{"found": false, "reason": "không có thành viên công khai nào tên như vậy"}, nil
	case len(matches) > 1:
		names := make([]string, 0, len(matches))
		for _, m := range matches {
			names = append(names, m.Name)
		}
		return map[string]any{"found": false, "reason": "tên trùng nhiều người", "candidates": names}, nil
	}
	return map[string]any{"found": true, "period": label, "member": matches[0]}, nil
}

// GetClubSummary tổng hợp cả club trong một kỳ.
func (t *BotTools) GetClubSummary(ctx context.Context, args map[string]any) (any, error) {
	rows, label, err := t.loadMembers(ctx, stringValue(args["period"]))
	if err != nil {
		return nil, err
	}
	totalKm, totalSessions, runners := float64(0), int64(0), 0
	var top memberRow
	for _, r := range rows {
		totalKm += r.DistanceKm
		totalSessions += r.Sessions
		if r.Sessions > 0 {
			runners++
		}
		if r.DistanceKm > top.DistanceKm {
			top = r
		}
	}
	out := map[string]any{
		"period":         label,
		"totalKm":        round2(totalKm),
		"totalSessions":  totalSessions,
		"runnersActive":  runners,
		"membersVisible": len(rows),
	}
	if top.Sessions > 0 {
		out["topRunner"] = map[string]any{"name": top.Name, "distanceKm": top.DistanceKm}
	}
	return out, nil
}

// GetRunContracts liệt kê các kèo đang chạy.
func (t *BotTools) GetRunContracts(ctx context.Context, _ map[string]any) (any, error) {
	docs, err := t.db.Collection("runContracts").
		Where("status", "==", "active").
		Where("visibility", "==", "club").
		Limit(10).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]map[string]any, 0, len(docs))
	for _, doc := range docs {
		data := doc.Data()
		target := number(data["targetValue"])
		progress := number(data["progressValue"])
		entry := map[string]any{
			"title":        stringValue(data["title"]),
			"metric":       stringValue(data["metric"]),
			"targetValue":  target,
			"currentValue": round2(progress),
			"participants": len(toAnySlice(data["participantUids"])),
		}
		if target > 0 {
			entry["percentDone"] = round2(math.Min(progress/target*100, 999))
		}
		if end, ok := data["endAtExclusive"].(time.Time); ok {
			entry["endsAt"] = end.In(vietnam).Format("02/01/2006")
		}
		out = append(out, entry)
	}
	return map[string]any{"contracts": out}, nil
}

// GetRecentRun trả chi tiết một buổi chạy của một thành viên (mặc định buổi
// gần nhất). Chỉ đọc được của thành viên đặt hồ sơ công khai — cùng ràng buộc
// với các tool khác. Model nhận facts rồi tự viết nhận xét.
func (t *BotTools) GetRecentRun(ctx context.Context, args map[string]any) (any, error) {
	query := strings.ToLower(strings.TrimSpace(stringValue(args["name"])))
	if query == "" {
		return nil, fmt.Errorf("thiếu tên thành viên")
	}
	// Dùng lại loadMembers để (a) lọc đúng người công khai, (b) lấy uid. Kỳ
	// truyền vào không ảnh hưởng việc tra uid.
	rows, _, err := t.loadMembers(ctx, "month")
	if err != nil {
		return nil, err
	}
	matches := make([]memberRow, 0)
	for _, r := range rows {
		if strings.Contains(strings.ToLower(r.Name), query) {
			matches = append(matches, r)
		}
	}
	switch {
	case len(matches) == 0:
		return map[string]any{"found": false, "reason": "không có thành viên công khai nào tên như vậy"}, nil
	case len(matches) > 1:
		names := make([]string, 0, len(matches))
		for _, m := range matches {
			names = append(names, m.Name)
		}
		return map[string]any{"found": false, "reason": "tên trùng nhiều người", "candidates": names}, nil
	}
	member := matches[0]

	// startedAt lưu dạng chuỗi RFC3339; OrderBy chuỗi ~ theo thời gian, nhưng
	// vẫn sort lại trong Go phòng lệch timezone. Lấy dư một ít rồi cắt.
	docs, err := t.db.Collection("users").Doc(member.uid).Collection("activities").
		OrderBy("startedAt", firestore.Desc).Limit(50).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	runs := make([]ActivityFact, 0, len(docs))
	for _, d := range docs {
		f := activityFact(d.Ref.ID, d.Data())
		// Bỏ hoạt động từ Strava không phải chạy; hoạt động ghi trong app thì giữ.
		if f.Source == "strava" && !runSportTypes[f.SportType] {
			continue
		}
		runs = append(runs, f)
	}
	sort.SliceStable(runs, func(i, j int) bool { return runs[i].StartedAt.After(runs[j].StartedAt) })
	if len(runs) == 0 {
		return map[string]any{"found": false, "member": member.Name, "reason": "chưa có buổi chạy nào"}, nil
	}
	offset := int(number(args["offset"]))
	if offset < 0 {
		offset = 0
	}
	if offset >= len(runs) {
		return map[string]any{"found": false, "member": member.Name,
			"reason": fmt.Sprintf("chỉ có %d buổi gần đây, không có buổi thứ %d", len(runs), offset+1)}, nil
	}
	run := runs[offset]
	out := map[string]any{
		"found":              true,
		"member":             member.Name,
		"runIndexFromLatest": offset,
		"date":               run.StartedAt.In(vietnam).Format("15:04 · 02/01/2006"),
		"sportType":          run.SportType,
		"distanceKm":         round2(run.DistanceMeters / 1000),
		"movingTime":         formatDurationHMS(run.MovingTimeSeconds),
		"pacePerKm":          formatPacePerKm(run),
		"elevationM":         int64(math.Round(run.ElevationGainMeters)),
	}
	// Nghỉ nhiều (elapsed > moving) là tín hiệu đáng nhận xét (đi bộ, dừng đèn...).
	if run.ElapsedTimeSeconds > run.MovingTimeSeconds+30 {
		out["elapsedTime"] = formatDurationHMS(run.ElapsedTimeSeconds)
		out["stoppedMinutes"] = (run.ElapsedTimeSeconds - run.MovingTimeSeconds) / 60
	}
	return out, nil
}

func round2(v float64) float64 { return math.Round(v*100) / 100 }

func toAnySlice(v any) []any {
	s, _ := v.([]any)
	return s
}
