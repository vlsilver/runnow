package backend

import (
	"bytes"
	"encoding/json"
	"math"
	"sort"
	"strings"
	"time"
)

const (
	garminRoutePointsMax = 500 // cùng mức buổi Strava (normalizeStreams), đủ vẽ map mà doc vẫn nhẹ
	garminStreamMax      = 300
	// garminSpeedWindowSeconds: GPS từng giây rất nhiễu, tính tốc độ trên một đoạn
	// ngắn thì đồ thị pace mới đọc được.
	garminSpeedWindowSeconds = 15
	garminSplitMeters        = 1000
	// garminSplitMinMeters: đoạn dư ngắn hơn mức này là sai số GPS cuối buổi, không phải một km lẻ.
	garminSplitMinMeters = 10
)

// garminDetail là một phần tử activityDetails: summary của buổi kèm các mẫu.
// Tên trường đọc từ code mã nguồn mở đang nhận dữ liệu Garmin thật, chưa đối
// chiếu spec, nên mẫu giữ dạng map và log garmin.details ghi tên trường thật.
type garminDetail struct {
	UserID     string           `json:"userId"`
	SummaryID  string           `json:"summaryId"`
	ActivityID any              `json:"activityId"`
	Summary    garminActivity   `json:"summary"`
	Samples    []map[string]any `json:"samples"`
}

// decodeGarminDetail đọc một phần tử và trả thêm tên các trường cấp ngoài.
func decodeGarminDetail(raw json.RawMessage) (garminDetail, []string, error) {
	var detail garminDetail
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.UseNumber()
	if err := decoder.Decode(&detail); err != nil {
		return garminDetail{}, nil, err
	}
	var top map[string]json.RawMessage
	if err := json.Unmarshal(raw, &top); err != nil {
		return garminDetail{}, nil, err
	}
	keys := make([]string, 0, len(top))
	for k := range top {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return detail, keys, nil
}

// activity trả summary mang id của phần tử, để ghi vào đúng doc của buổi đó:
// summaryId bản chi tiết có đuôi "-detail" còn bản số tổng thì không.
func (d garminDetail) activity() garminActivity {
	a := d.Summary
	a.UserID = d.UserID
	if a.ActivityID == nil {
		a.ActivityID = d.ActivityID
	}
	a.SummaryID = strings.TrimSuffix(d.SummaryID, "-detail")
	return a
}

// garminSampleKeys gom tên các trường xuất hiện trong mẫu, chỉ tên chứ không có giá trị.
func garminSampleKeys(samples []map[string]any) []string {
	seen := map[string]bool{}
	for _, s := range samples {
		for k := range s {
			seen[k] = true
		}
	}
	keys := make([]string, 0, len(seen))
	for k := range seen {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func garminSampleNumber(s map[string]any, key string) (float64, bool) {
	v, ok := s[key].(json.Number)
	if !ok {
		return 0, false
	}
	f, err := v.Float64()
	if err != nil || math.IsNaN(f) || math.IsInf(f, 0) {
		return 0, false
	}
	return f, true
}

// garminTrackPoint là một mẫu đã có đủ thời điểm và quãng đường.
type garminTrackPoint struct {
	elapsed, moving, timer, distance float64
	heartRate, altitude              float64
}

// garminDetailFields đổi các mẫu thành các trường doc mà app đang đọc cho buổi
// Strava và buổi 3i. Thiếu loại dữ liệu nào thì không có trường đó, để lần ghi
// merge không xoá thứ đã có.
func garminDetailFields(samples []map[string]any, startSeconds int64) map[string]any {
	out := map[string]any{}
	route := make([]map[string]any, 0, len(samples))
	points := make([][2]float64, 0, len(samples))
	track := make([]garminTrackPoint, 0, len(samples))
	allMoving, allTimer := true, true
	for _, s := range samples {
		at, ok := garminSampleNumber(s, "startTimeInSeconds")
		if !ok {
			continue
		}
		lat, hasLat := garminSampleNumber(s, "latitudeInDegree")
		lng, hasLng := garminSampleNumber(s, "longitudeInDegree")
		if hasLat && hasLng && math.Abs(lat) <= 90 && math.Abs(lng) <= 180 && (lat != 0 || lng != 0) {
			points = append(points, [2]float64{lat, lng})
			route = append(route, map[string]any{
				"latitude": lat, "longitude": lng,
				"timestamp": time.Unix(int64(at), 0).UTC().Format(time.RFC3339Nano),
			})
		}
		distance, ok := garminSampleNumber(s, "totalDistanceInMeters")
		// Quãng đường là cộng dồn, mẫu tụt lại thì không dùng cho đồ thị và từng km.
		if !ok || distance < 0 || (len(track) > 0 && distance < track[len(track)-1].distance) {
			continue
		}
		p := garminTrackPoint{elapsed: at - float64(startSeconds), distance: distance}
		if v, ok := garminSampleNumber(s, "movingDurationInSeconds"); ok {
			p.moving = v
		} else {
			allMoving = false
		}
		if v, ok := garminSampleNumber(s, "timerDurationInSeconds"); ok {
			p.timer = v
		} else {
			allTimer = false
		}
		p.heartRate, _ = garminSampleNumber(s, "heartRate")
		p.altitude = math.NaN()
		if v, ok := garminSampleNumber(s, "elevationInMeters"); ok {
			p.altitude = v
		}
		track = append(track, p)
	}
	// Một nguồn thời gian cho cả buổi: trộn đồng hồ giữa các mẫu thì hiệu giữa hai
	// mẫu vô nghĩa, có thể ra số âm.
	for i := range track {
		switch {
		case allMoving:
		case allTimer:
			track[i].moving = track[i].timer
		default:
			track[i].moving = track[i].elapsed
		}
	}
	if sketch := routeSketch(points); sketch != nil {
		out["routeSketch"] = sketch
	}
	if len(route) > 0 {
		sampled := make([]any, 0, garminRoutePointsMax)
		for _, i := range sampleIndexes(len(route), garminRoutePointsMax) {
			sampled = append(sampled, route[i])
		}
		out["routePoints"] = sampled
	}
	if len(track) < 2 {
		return out
	}
	if splits := garminSplits(track); len(splits) > 0 {
		out["splits"] = splits
	}
	out["streams"] = garminStreams(track)
	out["streamsHydrated"] = true
	out["streamsVersion"] = 4
	return out
}

// garminSplits cắt buổi theo từng km. Điểm cắt nằm giữa hai mẫu nên thời gian
// nội suy theo quãng đường; nhịp tim lấy trung bình các mẫu trong km đó.
func garminSplits(track []garminTrackPoint) []any {
	out := []any{}
	from := track[0]
	var hrSum, hrCount float64
	emit := func(to garminTrackPoint) {
		distance := to.distance - from.distance
		moving := to.moving - from.moving
		row := map[string]any{
			"split":              len(out) + 1,
			"distanceMeters":     distance,
			"movingTimeSeconds":  int64(math.Round(moving)),
			"elapsedTimeSeconds": int64(math.Round(to.elapsed - from.elapsed)),
		}
		if moving > 0 {
			row["averageSpeedMetersPerSecond"] = distance / moving
		}
		if hrCount > 0 {
			row["averageHeartRate"] = hrSum / hrCount
		}
		out = append(out, row)
		from = to
		hrSum, hrCount = 0, 0
	}
	for i := 1; i < len(track); i++ {
		prev, cur := track[i-1], track[i]
		for next := from.distance + garminSplitMeters; cur.distance >= next; next = from.distance + garminSplitMeters {
			t := (next - prev.distance) / (cur.distance - prev.distance)
			emit(garminTrackPoint{
				elapsed:  prev.elapsed + (cur.elapsed-prev.elapsed)*t,
				moving:   prev.moving + (cur.moving-prev.moving)*t,
				distance: next,
			})
		}
		if cur.heartRate > 0 {
			hrSum += cur.heartRate
			hrCount++
		}
	}
	end := track[len(track)-1]
	if end.distance-from.distance >= garminSplitMinMeters {
		emit(end)
	}
	return out
}

// garminStreams dựng các dãy đồ thị cùng độ dài, vì app ghép chúng theo chỉ số.
func garminStreams(track []garminTrackPoint) map[string]any {
	indexes := sampleIndexes(len(track), garminStreamMax)
	times := make([]float64, len(indexes))
	distances := make([]float64, len(indexes))
	speeds := make([]float64, len(indexes))
	hearts := make([]float64, len(indexes))
	altitudes := make([]float64, len(indexes))
	hasHeart, hasAltitude := false, false
	lastHeart, lastAltitude := 0.0, math.NaN()
	back := 0
	for n, i := range indexes {
		p := track[i]
		times[n], distances[n] = p.elapsed, p.distance
		for back < i-1 && p.elapsed-track[back+1].elapsed >= garminSpeedWindowSeconds {
			back++
		}
		if span := p.elapsed - track[back].elapsed; span > 0 {
			speeds[n] = (p.distance - track[back].distance) / span
		}
		if p.heartRate > 0 {
			lastHeart, hasHeart = p.heartRate, true
		}
		hearts[n] = lastHeart
		if !math.IsNaN(p.altitude) {
			lastAltitude, hasAltitude = p.altitude, true
		}
		altitudes[n] = lastAltitude
	}
	out := map[string]any{"time": times, "distance": distances, "velocity_smooth": speeds}
	if hasHeart {
		out["heartrate"] = hearts
	}
	if hasAltitude {
		// Đoạn đầu chưa có độ cao thì lấy giá trị đầu tiên đo được: Firestore không nhận NaN.
		first := 0.0
		for _, v := range altitudes {
			if !math.IsNaN(v) {
				first = v
				break
			}
		}
		for i, v := range altitudes {
			if math.IsNaN(v) {
				altitudes[i] = first
			}
		}
		out["altitude"] = altitudes
	}
	return out
}
