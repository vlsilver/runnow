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

// kmFrameStart trả đầu khung của khung kết thúc lúc end; end phải đúng 22:00 VN.
func kmFrameStart(end time.Time) (time.Time, error) {
	local := end.In(vietnam)
	if local.Hour() != 22 || local.Minute() != 0 || local.Second() != 0 || local.Nanosecond() != 0 {
		return time.Time{}, fmt.Errorf("khung km phải kết thúc đúng 22:00 VN, nhận %s", local.Format(time.RFC3339))
	}
	return local.AddDate(0, 0, -1), nil
}

// computeFrameKm tính km khung [22:00 hôm qua, 22:00 hôm nay) (R26–R28):
//   - official: buổi chính thức (SelectOfficialActivities) có startedAt trong khung;
//   - health: hourly[22..23] hôm qua × scale hôm qua + hourly[0..21] hôm nay × scale
//     hôm nay, scale = distanceMeters / Σhourly. Thiếu hourly hoặc Σ = 0 thì phần
//     hôm qua tính 0, phần hôm nay lấy distanceMeters cả ngày;
//   - km = max(official, health), không cộng: cùng một buổi chạy có mặt ở cả hai.
//
// activities phải gồm cả các buổi bắt đầu trong frameLookback trước khung.
func computeFrameKm(frameEnd time.Time, activities []ActivityFact, yesterday, today *stepDayKm) (FrameKm, error) {
	start, err := kmFrameStart(frameEnd)
	if err != nil {
		return FrameKm{}, err
	}
	out := FrameKm{FrameStart: start, FrameEnd: frameEnd.In(vietnam)}
	for _, a := range SelectOfficialActivities(activities) {
		if !a.StartedAt.Before(start) && a.StartedAt.Before(out.FrameEnd) {
			out.OfficialMeters += a.DistanceMeters
		}
	}
	if yesterday != nil {
		if scale, ok := hourlyScale(yesterday); ok {
			out.HourlyYesterday, out.ScaleYesterday = true, scale
			out.HealthMeters += (clampHourly(yesterday.HourlyDistance[22]) + clampHourly(yesterday.HourlyDistance[23])) * scale
		}
	}
	if today != nil {
		if scale, ok := hourlyScale(today); ok {
			out.HourlyToday, out.ScaleToday = true, scale
			var sum float64
			for h := 0; h < 22; h++ {
				sum += clampHourly(today.HourlyDistance[h])
			}
			out.HealthMeters += sum * scale
		} else {
			out.HealthMeters += today.DistanceMeters
		}
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

// LoadFrameKm đọc dữ liệu đã có mặt lúc gọi và tính km khung kết thúc frameEnd
// (R29: chỉ đọc một lần, không chốt lại). Lỗi Firestore thì trả lỗi, không coi
// là 0 km: thiếu km là mất phiếu của người ta.
func LoadFrameKm(ctx context.Context, db *firestore.Client, uid string, frameEnd time.Time) (FrameKm, error) {
	start, err := kmFrameStart(frameEnd)
	if err != nil {
		return FrameKm{}, err
	}
	user := db.Collection("users").Doc(uid)
	iter := user.Collection("activities").
		Where("startedAt", ">=", start.Add(-frameLookback).UTC().Format(time.RFC3339Nano)).
		Where("startedAt", "<", frameEnd.UTC().Format(time.RFC3339Nano)).Documents(ctx)
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
	yesterday, err := loadStepDayKm(ctx, user, dateKey(start))
	if err != nil {
		return FrameKm{}, err
	}
	today, err := loadStepDayKm(ctx, user, dateKey(frameEnd.In(vietnam)))
	if err != nil {
		return FrameKm{}, err
	}
	return computeFrameKm(frameEnd, facts, yesterday, today)
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
