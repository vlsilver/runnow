package backend

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// FrameKm là km của một người trong một khung chốt Ma Sói (R26–R29), kèm nguồn
// của số để soát lại sau. Đơn vị mét, không làm tròn: phiếu tính bằng
// floor(tổng/X) nên làm tròn sớm có thể lệch đúng ở ngưỡng.
type FrameKm struct {
	FrameStart     time.Time `json:"frameStart"`
	FrameEnd       time.Time `json:"frameEnd"`
	OfficialMeters float64   `json:"officialMeters"`
	HealthMeters   float64   `json:"healthMeters"`
	Meters         float64   `json:"meters"`
	Source         string    `json:"source"` // official | health | none
	// Có hourly hay phải lấy tổng cả ngày, và hệ số scale đã dùng (R28).
	HourlyYesterday bool    `json:"hourlyYesterday"`
	HourlyToday     bool    `json:"hourlyToday"`
	ScaleYesterday  float64 `json:"scaleYesterday"`
	ScaleToday      float64 `json:"scaleToday"`
}

// stepDayKm là phần của users/{uid}/stepDays/{date} mà khung km cần.
type stepDayKm struct {
	DistanceMeters float64
	HourlyDistance []float64 // 24 phần tử 0h→23h giờ VN; rỗng nếu client không gửi
}

// maxHourlyMeters kẹp một giờ vô lý trước khi tính scale: 30 km/giờ là trên mức
// chạy bộ nhanh nhất, nên giá trị lớn hơn là lỗi dữ liệu.
const maxHourlyMeters = 30000

// frameLookback: nạp thêm các buổi bắt đầu trước khung để SelectOfficialActivities
// khử trùng được buổi vắt qua mốc (bản Strava 21:59 và bản Health 22:00 của cùng
// một lần chạy), rồi mới lọc theo khung.
const frameLookback = 12 * time.Hour

// checkKmFrame: số Health chỉ có theo giờ, nên khung phải tròn giờ VN và không
// dài quá một ngày (không chạm quá hai ngày dương lịch).
func checkKmFrame(start, end time.Time) error {
	if whole := time.Hour; !start.Truncate(whole).Equal(start) || !end.Truncate(whole).Equal(end) || !end.After(start) || end.Sub(start) > 24*time.Hour {
		return fmt.Errorf("khung km phải tròn giờ, dài tối đa 24 tiếng, nhận %s tới %s", start.In(vietnam).Format(time.RFC3339), end.In(vietnam).Format(time.RFC3339))
	}
	return nil
}

// computeFrameKm tính km khung [start, end) (R26–R28):
//   - official: buổi chính thức (SelectOfficialActivities) có startedAt trong khung;
//   - health: tổng các giờ thuộc khung của từng ngày × scale ngày đó, scale =
//     distanceMeters / Σhourly (frameDayMeters);
//   - km = max(official, health), không cộng: cùng một buổi chạy có mặt ở cả hai.
//
// yesterday là ngày của start, today là ngày của end; khung nằm gọn một ngày thì
// chỉ dùng today. activities phải gồm cả các buổi bắt đầu trong frameLookback
// trước khung.
func computeFrameKm(start, end time.Time, activities []ActivityFact, yesterday, today *stepDayKm) (FrameKm, error) {
	if err := checkKmFrame(start, end); err != nil {
		return FrameKm{}, err
	}
	out := FrameKm{FrameStart: start.In(vietnam), FrameEnd: end.In(vietnam)}
	for _, a := range SelectOfficialActivities(activities) {
		if !a.StartedAt.Before(start) && a.StartedAt.Before(end) {
			out.OfficialMeters += a.DistanceMeters
		}
	}
	from, to := out.FrameStart.Hour(), out.FrameEnd.Hour()
	if sameDate(start, end) {
		out.HealthMeters, out.HourlyToday, out.ScaleToday = frameDayMeters(today, from, to)
	} else {
		var early, late float64
		early, out.HourlyYesterday, out.ScaleYesterday = frameDayMeters(yesterday, from, 24)
		late, out.HourlyToday, out.ScaleToday = frameDayMeters(today, 0, to)
		out.HealthMeters = early + late
	}
	switch {
	case out.OfficialMeters == 0 && out.HealthMeters == 0:
		out.Source = "none"
	case out.OfficialMeters >= out.HealthMeters:
		out.Meters, out.Source = out.OfficialMeters, "official"
	default:
		out.Meters, out.Source = out.HealthMeters, "health"
	}
	return out, nil
}

// dayTotalHour: ngày thiếu hourly thì tổng cả ngày thuộc về khung chứa giờ này,
// nếu không hai vòng trong ngày cùng tính một số. Giờ cuối của khung 22h gốc.
const dayTotalHour = 21

// frameDayMeters là km của các giờ [from, to) trong ngày d.
func frameDayMeters(d *stepDayKm, from, to int) (meters float64, hourly bool, scale float64) {
	if d == nil {
		return 0, false, 0
	}
	scale, hourly = hourlyScale(d)
	if !hourly {
		if from <= dayTotalHour && dayTotalHour < to {
			meters = d.DistanceMeters
		}
		return meters, false, 0
	}
	var sum float64
	for h := from; h < to; h++ {
		sum += clampHourly(d.HourlyDistance[h])
	}
	return sum * scale, true, scale
}

// hourlyScale = distanceMeters / Σhourly đã kẹp. ok=false khi thiếu hourly hoặc Σ = 0.
func hourlyScale(d *stepDayKm) (float64, bool) {
	if len(d.HourlyDistance) != 24 {
		return 0, false
	}
	var sum float64
	for _, v := range d.HourlyDistance {
		sum += clampHourly(v)
	}
	if sum <= 0 {
		return 0, false
	}
	return d.DistanceMeters / sum, true
}

func clampHourly(v float64) float64 {
	if v < 0 {
		return 0
	}
	return min(v, maxHourlyMeters)
}

// LoadFrameKm đọc dữ liệu đã có mặt lúc gọi và tính km khung [start, end)
// (R29: chỉ đọc một lần, không chốt lại). Lỗi Firestore thì trả lỗi, không coi
// là 0 km: thiếu km là mất phiếu của người ta.
func LoadFrameKm(ctx context.Context, db *firestore.Client, uid string, start, end time.Time) (FrameKm, error) {
	if err := checkKmFrame(start, end); err != nil {
		return FrameKm{}, err
	}
	user := db.Collection("users").Doc(uid)
	iter := user.Collection("activities").
		Where("startedAt", ">=", start.Add(-frameLookback).UTC().Format(time.RFC3339Nano)).
		Where("startedAt", "<", end.UTC().Format(time.RFC3339Nano)).Documents(ctx)
	defer iter.Stop()
	var facts []ActivityFact
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return FrameKm{}, err
		}
		facts = append(facts, activityFact(doc.Ref.ID, doc.Data()))
	}
	var yesterday *stepDayKm
	if !sameDate(start, end) {
		var err error
		if yesterday, err = loadStepDayKm(ctx, user, dateKey(start)); err != nil {
			return FrameKm{}, err
		}
	}
	today, err := loadStepDayKm(ctx, user, dateKey(end.In(vietnam)))
	if err != nil {
		return FrameKm{}, err
	}
	return computeFrameKm(start, end, facts, yesterday, today)
}

// loadStepDayKm trả nil khi ngày đó chưa có doc (chưa sync), lỗi khác thì trả lỗi.
func loadStepDayKm(ctx context.Context, user *firestore.DocumentRef, date string) (*stepDayKm, error) {
	snap, err := user.Collection("stepDays").Doc(date).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	data := snap.Data()
	d := &stepDayKm{DistanceMeters: number(data["distanceMeters"])}
	if raw, ok := data["hourlyDistance"].([]any); ok && len(raw) == 24 {
		d.HourlyDistance = make([]float64, 24)
		for i, v := range raw {
			d.HourlyDistance[i] = number(v)
		}
	}
	return d, nil
}
