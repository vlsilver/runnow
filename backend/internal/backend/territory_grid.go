package backend

import (
	"fmt"
	"math"
	"strconv"
	"strings"
)

// Lãnh địa chia mặt đất theo lưới tile slippy map (Web Mercator, cách OSM,
// Google Maps và Protomaps cắt tile). Lưới chỉ là công thức nên không lưu ở
// đâu, và app vẽ ô bằng đúng bốn góc tile. Cỡ ô không được đổi sau khi ra mắt:
// đổi zoom là mọi id ô đã lưu mất nghĩa. Thiết kế: docs/territory_design.md.
const (
	// territoryCellZoom cho ô cạnh khoảng 150 m ở TP.HCM, 143 m ở Hà Nội.
	territoryCellZoom = 18
	// territoryChunkZoom gom 32×32 ô thành một doc territoryChunks.
	territoryChunkZoom = 13
)

// tileXY là toạ độ một tile ở zoom ngầm định theo ngữ cảnh (ô hay chunk).
type tileXY struct{ X, Y int }

// id là khoá của ô hay chunk trong Firestore: "x_y".
func (t tileXY) id() string { return strconv.Itoa(t.X) + "_" + strconv.Itoa(t.Y) }

// cellAt trả ô z18 chứa điểm, theo công thức "Slippy map tilenames" của OSM.
// Toạ độ không hợp lệ (NaN, vĩ độ ngoài ±90, kinh độ ngoài ±180) trả false.
// Vĩ độ ngoài biên Mercator (±85,05°) và kinh độ đúng 180 rơi ra ngoài lưới,
// nên chỉ số được kẹp về hàng, cột biên.
func cellAt(lat, lng float64) (tileXY, bool) {
	if math.IsNaN(lat) || math.IsNaN(lng) || math.Abs(lat) > 90 || math.Abs(lng) > 180 {
		return tileXY{}, false
	}
	n := float64(int(1) << territoryCellZoom)
	x := int(math.Floor((lng + 180) / 360 * n))
	rad := lat * math.Pi / 180
	y := int(math.Floor((1 - math.Log(math.Tan(rad)+1/math.Cos(rad))/math.Pi) / 2 * n))
	last := int(n) - 1
	return tileXY{min(max(x, 0), last), min(max(y, 0), last)}, true
}

// chunkOf trả chunk z13 chứa ô z18.
func chunkOf(cell tileXY) tileXY {
	shift := territoryCellZoom - territoryChunkZoom
	return tileXY{cell.X >> shift, cell.Y >> shift}
}

// parseTileID đọc lại khoá "x_y".
func parseTileID(id string) (tileXY, error) {
	xs, ys, ok := strings.Cut(id, "_")
	if !ok {
		return tileXY{}, fmt.Errorf("id ô %q thiếu dấu _", id)
	}
	x, err := strconv.Atoi(xs)
	if err != nil {
		return tileXY{}, fmt.Errorf("id ô %q: %w", id, err)
	}
	y, err := strconv.Atoi(ys)
	if err != nil {
		return tileXY{}, fmt.Errorf("id ô %q: %w", id, err)
	}
	return tileXY{x, y}, nil
}
