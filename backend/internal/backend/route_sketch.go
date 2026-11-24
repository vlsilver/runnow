package backend

import (
	"errors"
	"math"
)

var errBadPolyline = errors.New("polyline hỏng")

// routeSketchScale là cạnh khung toạ độ của routeSketch.
const routeSketchScale = 1000

// routeSketchMaxPoints đủ cho một đường cỡ 240px trên thẻ; buổi 10km ghi từ
// app có vài nghìn điểm, giữ hết thì mỗi dòng danh sách nặng thêm vài trăm KB.
const routeSketchMaxPoints = 64

// routeSketch thu tuyến về dáng để vẽ nền thẻ trong danh sách buổi chạy:
// mảng phẳng [x0, y0, x1, y1, ...] số nguyên, chiều dài hơn của tuyến là
// 0..1000, giữ đúng tỉ lệ ngang dọc, bắc ở trên (y nhỏ). Không còn toạ độ thật
// nên danh sách không lộ vị trí. Tuyến dài được lấy mẫu lại còn
// routeSketchMaxPoints điểm cách đều theo quãng đường. Ít hơn 2 điểm hoặc
// tuyến đứng yên một chỗ thì trả nil.
func routeSketch(points [][2]float64) []int {
	if len(points) < 2 {
		return nil
	}
	meanLat := 0.0
	for _, p := range points {
		meanLat += p[0]
	}
	// Kinh độ co lại theo cos(vĩ độ), nếu không thì tuyến ở Hà Nội bị kéo ngang.
	k := math.Cos(meanLat / float64(len(points)) * math.Pi / 180)
	xy := make([][2]float64, len(points))
	for i, p := range points {
		xy[i] = [2]float64{p[1] * k, -p[0]}
	}
	if len(xy) > routeSketchMaxPoints {
		xy = resampleByDistance(xy, routeSketchMaxPoints)
	}
	minX, minY := math.Inf(1), math.Inf(1)
	maxX, maxY := math.Inf(-1), math.Inf(-1)
	for _, p := range xy {
		minX, maxX = math.Min(minX, p[0]), math.Max(maxX, p[0])
		minY, maxY = math.Min(minY, p[1]), math.Max(maxY, p[1])
	}
	span := math.Max(maxX-minX, maxY-minY)
	if span <= 0 {
		return nil
	}
	out := make([]int, 0, 2*len(xy))
	for _, p := range xy {
		out = append(out,
			int(math.Round((p[0]-minX)/span*routeSketchScale)),
			int(math.Round((p[1]-minY)/span*routeSketchScale)))
	}
	return out
}

// activityRouteSketch tính routeSketch cho một doc buổi chạy: ưu tiên
// routePoints (buổi ghi bằng app, đủ điểm), không có thì giải polyline (buổi
// Strava). Polyline hỏng thì coi như không có tuyến: dáng tuyến chỉ để trang
// trí, không đáng chặn việc lưu buổi chạy.
func activityRouteSketch(doc map[string]any) []int {
	if raw, ok := doc["routePoints"].([]any); ok && len(raw) > 0 {
		points := make([][2]float64, 0, len(raw))
		for _, item := range raw {
			p, ok := item.(map[string]any)
			if !ok || p["latitude"] == nil || p["longitude"] == nil {
				continue
			}
			points = append(points, [2]float64{number(p["latitude"]), number(p["longitude"])})
		}
		return routeSketch(points)
	}
	if encoded, ok := doc["polyline"].(string); ok && encoded != "" {
		points, err := decodePolyline(encoded)
		if err != nil {
			return nil
		}
		return routeSketch(points)
	}
	return nil
}

// resampleByDistance trả n điểm cách đều nhau theo quãng đường dọc tuyến,
// giữ điểm đầu và điểm cuối. Lấy theo chỉ số thì đoạn GPS dày (chạy chậm, đứng
// chờ đèn) chiếm hết điểm còn đoạn thưa bị cắt góc.
func resampleByDistance(xy [][2]float64, n int) [][2]float64 {
	cum := make([]float64, len(xy))
	for i := 1; i < len(xy); i++ {
		cum[i] = cum[i-1] + math.Hypot(xy[i][0]-xy[i-1][0], xy[i][1]-xy[i-1][1])
	}
	total := cum[len(cum)-1]
	if total == 0 {
		return xy[:1]
	}
	out := make([][2]float64, 0, n)
	j := 0
	for i := 0; i < n; i++ {
		d := total * float64(i) / float64(n-1)
		for j < len(xy)-2 && cum[j+1] < d {
			j++
		}
		seg := cum[j+1] - cum[j]
		t := 0.0
		if seg > 0 {
			t = math.Min(1, (d-cum[j])/seg)
		}
		out = append(out, [2]float64{
			xy[j][0] + (xy[j+1][0]-xy[j][0])*t,
			xy[j][1] + (xy[j+1][1]-xy[j][1])*t,
		})
	}
	return out
}

// decodePolyline giải mã chuỗi theo Encoded Polyline Algorithm Format của
// Google (Strava dùng định dạng này cho map.polyline), trả các cặp
// [vĩ độ, kinh độ].
func decodePolyline(encoded string) ([][2]float64, error) {
	var points [][2]float64
	var lat, lng int
	for i := 0; i < len(encoded); {
		var delta [2]int
		for k := range delta {
			shift, result := 0, 0
			for {
				if i >= len(encoded) || shift > 30 {
					return nil, errBadPolyline
				}
				b := int(encoded[i]) - 63
				i++
				if b < 0 || b > 63 {
					return nil, errBadPolyline
				}
				result |= (b & 0x1f) << shift
				shift += 5
				if b < 0x20 {
					break
				}
			}
			if result&1 != 0 {
				delta[k] = ^(result >> 1)
			} else {
				delta[k] = result >> 1
			}
		}
		lat += delta[0]
		lng += delta[1]
		points = append(points, [2]float64{float64(lat) / 1e5, float64(lng) / 1e5})
	}
	return points, nil
}
