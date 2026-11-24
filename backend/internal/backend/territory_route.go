package backend

import (
	"math"
	"time"
)

// routeSample là một điểm tuyến đã đọc từ doc buổi chạy. Có hay không có giờ,
// có hay không có độ chính xác tuỳ nguồn: polyline Strava không có cả hai,
// Garmin và Strava hydrate có giờ, app 3i có cả hai.
type routeSample struct {
	Lat, Lng    float64
	At          time.Time // zero khi không có giờ
	Accuracy    float64
	HasAccuracy bool
}

// territoryRules là các ngưỡng lấy ô từ tuyến. BE2 đọc từ config/territory;
// thiếu field nào thì dùng giá trị mặc định ở defaultTerritoryRules.
type territoryRules struct {
	// TrimMeters cắt ở đầu và cuối tuyến đã lọc, vì điểm đầu và cuối hay là nhà.
	TrimMeters float64
	// Đoạn nhanh hơn FastestPace là đi xe; chậm hơn SlowestPace là đứng yên
	// mà GPS vẫn nhảy (chờ đèn, ngồi quán). Đơn vị giây mỗi km.
	FastestPaceSecPerKm float64
	SlowestPaceSecPerKm float64
	// MaxAccuracyMeters bỏ điểm GPS kém; điểm không có độ chính xác thì giữ.
	MaxAccuracyMeters float64
	// MaxSegmentMeters bỏ đoạn nhảy xa giữa hai điểm (mất tín hiệu).
	MaxSegmentMeters float64
}

func defaultTerritoryRules() territoryRules {
	return territoryRules{
		TrimMeters:          200,
		FastestPaceSecPerKm: 150,
		SlowestPaceSecPerKm: 1200,
		MaxAccuracyMeters:   30,
		MaxSegmentMeters:    2000,
	}
}

// territoryStepMeters là bước nội suy. Mỗi bước tính trọn cho ô chứa điểm giữa
// của bước, nên mét ở mép ô sai tối đa nửa bước. 2 m là đủ khít so với ô
// 150 m mà buổi 10 km mới có 5 000 bước.
const territoryStepMeters = 2.0

// routeSamplesFromDoc đọc tuyến của một doc buổi: routePoints nếu có, không thì
// giải polyline. Điểm thiếu toạ độ bị bỏ; polyline hỏng coi như không có tuyến.
func routeSamplesFromDoc(doc map[string]any) []routeSample {
	if raw, ok := doc["routePoints"].([]any); ok && len(raw) > 0 {
		out := make([]routeSample, 0, len(raw))
		for _, item := range raw {
			p, ok := item.(map[string]any)
			if !ok || p["latitude"] == nil || p["longitude"] == nil {
				continue
			}
			s := routeSample{Lat: number(p["latitude"]), Lng: number(p["longitude"])}
			if ts, ok := p["timestamp"].(string); ok {
				if at, err := time.Parse(time.RFC3339Nano, ts); err == nil {
					s.At = at
				}
			}
			if acc, ok := p["accuracyMeters"]; ok && acc != nil {
				s.Accuracy, s.HasAccuracy = number(acc), true
			}
			out = append(out, s)
		}
		return out
	}
	if encoded, ok := doc["polyline"].(string); ok && encoded != "" {
		points, err := decodePolyline(encoded)
		if err != nil {
			return nil
		}
		out := make([]routeSample, len(points))
		for i, p := range points {
			out[i] = routeSample{Lat: p[0], Lng: p[1]}
		}
		return out
	}
	return nil
}

type routeSegment struct {
	from, to routeSample
	meters   float64
}

// territoryCells biến tuyến thành map id ô z18 → số mét chạy trong ô, làm tròn
// tới mét; ô dưới nửa mét không có trong map. Thứ tự: bỏ điểm kém, bỏ đoạn
// nhảy xa, đi xe hay đứng yên, rồi mới cắt TrimMeters đầu và cuối trên quãng
// còn lại, để GPS nhảy lúc đứng ở cửa nhà không "ăn" hết phần cắt.
func territoryCells(samples []routeSample, rules territoryRules) map[string]int {
	kept := make([]routeSample, 0, len(samples))
	for _, s := range samples {
		if _, ok := cellAt(s.Lat, s.Lng); !ok {
			continue
		}
		if s.HasAccuracy && s.Accuracy > rules.MaxAccuracyMeters {
			continue
		}
		kept = append(kept, s)
	}
	segments := make([]routeSegment, 0, len(kept))
	total := 0.0
	for i := 1; i < len(kept); i++ {
		a, b := kept[i-1], kept[i]
		d := haversineMeters(a.Lat, a.Lng, b.Lat, b.Lng)
		if d <= 0 || d > rules.MaxSegmentMeters || !segmentPaceOK(a, b, d, rules) {
			continue
		}
		segments = append(segments, routeSegment{a, b, d})
		total += d
	}
	acc := map[string]float64{}
	walked := 0.0
	for _, seg := range segments {
		n := int(math.Ceil(seg.meters / territoryStepMeters))
		step := seg.meters / float64(n)
		for k := 0; k < n; k++ {
			mid := walked + (float64(k)+0.5)*step
			if mid < rules.TrimMeters || mid > total-rules.TrimMeters {
				continue
			}
			t := (float64(k) + 0.5) / float64(n)
			cell, _ := cellAt(seg.from.Lat+t*(seg.to.Lat-seg.from.Lat), seg.from.Lng+t*(seg.to.Lng-seg.from.Lng))
			acc[cell.id()] += step
		}
		walked += seg.meters
	}
	out := map[string]int{}
	for id, m := range acc {
		if r := int(math.Round(m)); r > 0 {
			out[id] = r
		}
	}
	return out
}

// segmentPaceOK: đoạn có giờ ở cả hai đầu thì pace phải nằm trong khoảng cho
// phép. Giờ đứng hay lùi (dt ≤ 0) cho pace ≤ 0, nhanh hơn mọi ngưỡng đi xe, nên
// cũng bị bỏ. Đoạn thiếu giờ thì giữ.
func segmentPaceOK(a, b routeSample, meters float64, rules territoryRules) bool {
	if a.At.IsZero() || b.At.IsZero() {
		return true
	}
	dt := b.At.Sub(a.At).Seconds()
	pace := dt / (meters / 1000)
	return pace >= rules.FastestPaceSecPerKm && pace <= rules.SlowestPaceSecPerKm
}

// haversineMeters là khoảng cách mặt cầu bán kính 6 371 km.
func haversineMeters(lat1, lng1, lat2, lng2 float64) float64 {
	const r = 6371000.0
	p1, p2 := lat1*math.Pi/180, lat2*math.Pi/180
	dp := p2 - p1
	dl := (lng2 - lng1) * math.Pi / 180
	h := math.Sin(dp/2)*math.Sin(dp/2) + math.Cos(p1)*math.Cos(p2)*math.Sin(dl/2)*math.Sin(dl/2)
	return 2 * r * math.Asin(math.Min(1, math.Sqrt(h)))
}
