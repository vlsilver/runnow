package backend

import (
	"math"
	"testing"
	"time"
)

// Giá trị mong đợi tính tay:
//   - z18 có n = 2^18 = 262144 ô mỗi chiều; (0, 0) rơi vào ô (n/2, n/2).
//   - Ô Bến Thành (10.772, 106.698) tính bằng dạng asinh của công thức OSM
//     (y = ⌊(1 − asinh(tan φ)/π)/2 · n⌋), khác dạng log mà code dùng.
//   - Một ô dọc xích đạo dài 2π·6 371 000 / 2^18 = 152,703 m theo haversine.
const equatorCellMeters = 152.70299374405343

var cellLngDeg = 360.0 / float64(1<<18)

func TestCellAtKnownTiles(t *testing.T) {
	cases := []struct {
		name     string
		lat, lng float64
		want     tileXY
	}{
		{"gốc toạ độ", 0, 0, tileXY{131072, 131072}},
		{"kinh độ -180", 0, -180, tileXY{0, 131072}},
		{"kinh độ 180 kẹp vào ô cuối", 0, 180, tileXY{262143, 131072}},
		{"cực bắc kẹp vào hàng đầu", 90, 0, tileXY{131072, 0}},
		{"cực nam kẹp vào hàng cuối", -90, 0, tileXY{131072, 262143}},
		{"chợ Bến Thành", 10.772, 106.698, tileXY{208767, 123181}},
	}
	for _, c := range cases {
		got, ok := cellAt(c.lat, c.lng)
		if !ok || got != c.want {
			t.Errorf("%s: cellAt(%v, %v) = %v, %v; muốn %v", c.name, c.lat, c.lng, got, ok, c.want)
		}
	}
	for _, bad := range [][2]float64{{math.NaN(), 0}, {0, math.NaN()}, {91, 0}, {0, 181}, {-90.5, 0}} {
		if _, ok := cellAt(bad[0], bad[1]); ok {
			t.Errorf("cellAt(%v, %v) nhận toạ độ hỏng", bad[0], bad[1])
		}
	}
}

func TestChunkAndID(t *testing.T) {
	cell := tileXY{208767, 123181}
	if got := chunkOf(cell); got != (tileXY{6523, 3849}) {
		t.Fatalf("chunkOf = %v; muốn 6523_3849 (chia 32)", got)
	}
	if cell.id() != "208767_123181" {
		t.Fatalf("id = %q", cell.id())
	}
	back, err := parseTileID(cell.id())
	if err != nil || back != cell {
		t.Fatalf("parseTileID(%q) = %v, %v", cell.id(), back, err)
	}
	for _, bad := range []string{"", "12", "a_1", "1_b"} {
		if _, err := parseTileID(bad); err == nil {
			t.Errorf("parseTileID(%q) không báo lỗi", bad)
		}
	}
}

// equatorRoute dựng tuyến dọc xích đạo (vĩ độ 0,0003 để nằm gọn trong một
// hàng ô) từ mép trái ô x=131072 + startCells, mỗi điểm cách nhau stepCells ô.
func equatorRoute(startCells, endCells, stepCells float64, secondsPerPoint float64) []routeSample {
	terrT0 := time.Date(2026, 11, 25, 6, 0, 0, 0, time.UTC)
	var out []routeSample
	i := 0
	for c := startCells; c <= endCells+1e-9; c += stepCells {
		s := routeSample{Lat: 0.0003, Lng: c * cellLngDeg}
		if secondsPerPoint > 0 {
			s.At = terrT0.Add(time.Duration(float64(i)*secondsPerPoint*1e9) * time.Nanosecond)
		}
		out = append(out, s)
		i++
	}
	return out
}

func noTrim() territoryRules {
	r := defaultTerritoryRules()
	r.TrimMeters = 0
	return r
}

func assertMeters(t *testing.T, got map[string]int, want map[string]float64) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("số ô = %d (%v); muốn %d (%v)", len(got), got, len(want), want)
	}
	for id, w := range want {
		g, ok := got[id]
		if !ok {
			t.Fatalf("thiếu ô %s trong %v", id, got)
		}
		// Mỗi mép ô sai tối đa nửa bước nội suy, cộng 1 m làm tròn.
		if math.Abs(float64(g)-w) > territoryStepMeters+1 {
			t.Errorf("ô %s = %d m; muốn khoảng %.1f m", id, g, w)
		}
	}
}

func TestTerritoryCellsMetersPerCell(t *testing.T) {
	// Từ giữa ô 131072 tới giữa ô 131075, hai điểm thưa: nội suy phải phủ đủ
	// hai ô ở giữa.
	got := territoryCells(equatorRoute(0.5, 3.5, 3, 0), noTrim())
	half := equatorCellMeters / 2
	assertMeters(t, got, map[string]float64{
		"131072_131071": half,
		"131073_131071": equatorCellMeters,
		"131074_131071": equatorCellMeters,
		"131075_131071": half,
	})
}

func TestTerritoryCellsTrimsBothEnds(t *testing.T) {
	// 1000 m từ mép ô 131072, cắt 200 m mỗi đầu: còn 200..800 m.
	end := 1000 / equatorCellMeters
	got := territoryCells(equatorRoute(0, end, end/50, 0), defaultTerritoryRules())
	c := equatorCellMeters
	assertMeters(t, got, map[string]float64{
		"131073_131071": 2*c - 200, // 152,7..305,4 tính từ 200
		"131074_131071": c,
		"131075_131071": c,
		"131076_131071": c,
		"131077_131071": 800 - 5*c, // 763,5..800
	})
}

func TestTerritoryCellsTooShortAfterTrim(t *testing.T) {
	end := 390 / equatorCellMeters
	if got := territoryCells(equatorRoute(0, end, end/10, 0), defaultTerritoryRules()); len(got) != 0 {
		t.Fatalf("tuyến 390 m với cắt 2×200 m phải rỗng, ra %v", got)
	}
}

func TestTerritoryCellsFilters(t *testing.T) {
	step := 100 / equatorCellMeters // điểm cách nhau ~100 m
	route := func(seconds float64) []routeSample { return equatorRoute(0.5, 0.5+3*step, step, seconds) }

	// 6:00/km → 36 s mỗi 100 m: giữ đủ ~300 m.
	if total := sumMeters(territoryCells(route(36), noTrim())); math.Abs(float64(total)-300) > 3 {
		t.Fatalf("chạy 6:00/km mất mét: %d", total)
	}
	// 1:40/km (10 s mỗi 100 m) là đi xe: bỏ hết.
	if got := territoryCells(route(10), noTrim()); len(got) != 0 {
		t.Fatalf("đi xe vẫn có ô: %v", got)
	}
	// 100 m trong 30 phút là đứng yên: bỏ hết.
	if got := territoryCells(route(1800), noTrim()); len(got) != 0 {
		t.Fatalf("đứng yên vẫn có ô: %v", got)
	}
	// Giờ đứng yên giữa hai điểm (dt = 0) là giờ hỏng: bỏ.
	bad := route(36)
	bad[2].At = bad[1].At
	if total := sumMeters(territoryCells(bad, noTrim())); math.Abs(float64(total)-200) > 3 {
		t.Fatalf("đoạn dt=0 phải bị bỏ, còn %d m", total)
	}
	// Điểm sai số 50 m lệch 60 m về phía bắc bị bỏ, nên quãng vẫn 300 m. Giữ
	// điểm đó thì quãng dài thêm khoảng 2×(√(100²+60²) − 100) ≈ 33 m.
	acc := route(0)
	acc[1].Lat += 60.0 / 111195
	acc[1].Accuracy, acc[1].HasAccuracy = 50, true
	acc[2].Accuracy, acc[2].HasAccuracy = 5, true
	if total := sumMeters(territoryCells(acc, noTrim())); math.Abs(float64(total)-300) > 3 {
		t.Fatalf("bỏ điểm kém phải giữ quãng 300 m, ra %d", total)
	}
	// Đoạn nhảy 3 km bị bỏ.
	jump := []routeSample{{Lat: 0.0003, Lng: 0}, {Lat: 0.0003, Lng: 3000 / equatorCellMeters * cellLngDeg}}
	if got := territoryCells(jump, noTrim()); len(got) != 0 {
		t.Fatalf("đoạn nhảy 3 km vẫn có ô: %v", got)
	}
}

// Lọc trước rồi mới cắt: 3 phút đứng ở cửa nhà, GPS nhảy qua lại 30 m mỗi 10 s
// (nhanh hơn ngưỡng đứng yên thì không bị lọc, nên dùng 10 m mỗi 10 s = 16:40
// sẽ bị giữ; ở đây dùng 3 m mỗi 10 s = 55:33/km, đúng kiểu đứng yên). Nếu cắt
// trước, 200 m bị "ăn" bởi quãng nhảy và ô nhà lộ ra.
func TestTerritoryCellsFilterBeforeTrim(t *testing.T) {
	terrT0 := time.Date(2026, 11, 25, 6, 0, 0, 0, time.UTC)
	var route []routeSample
	jitter := 3 / equatorCellMeters * cellLngDeg
	at := terrT0
	for i := 0; i < 200; i++ { // ~600 m nhảy tại chỗ ở ô 131072
		lng := 0.5 * cellLngDeg
		if i%2 == 1 {
			lng += jitter
		}
		route = append(route, routeSample{Lat: 0.0003, Lng: lng, At: at})
		at = at.Add(10 * time.Second)
	}
	// Rồi chạy 1000 m về phía đông ở 6:00/km.
	step := 50 / equatorCellMeters
	for c := 0.5 + step; c <= 0.5+1000/equatorCellMeters+1e-9; c += step {
		at = at.Add(18 * time.Second)
		route = append(route, routeSample{Lat: 0.0003, Lng: c * cellLngDeg, At: at})
	}
	got := territoryCells(route, defaultTerritoryRules())
	if _, ok := got["131072_131071"]; ok {
		t.Fatalf("ô nhà vẫn lộ ra sau khi cắt: %v", got)
	}
	if total := sumMeters(got); math.Abs(float64(total)-600) > 5 {
		t.Fatalf("phải còn ~600 m sau cắt, ra %d", total)
	}
}

func TestTerritoryCellsDropsZeroMeterCells(t *testing.T) {
	// Đoạn 0,3 m làm tròn thành 0 m: không được ghi ô 0 m.
	route := []routeSample{{Lat: 0.0003, Lng: 0.5 * cellLngDeg}, {Lat: 0.0003, Lng: 0.5*cellLngDeg + 0.3/equatorCellMeters*cellLngDeg}}
	if got := territoryCells(route, noTrim()); len(got) != 0 {
		t.Fatalf("ô 0 m vẫn có trong map: %v", got)
	}
}

func sumMeters(m map[string]int) int {
	total := 0
	for _, v := range m {
		total += v
	}
	return total
}

func TestRouteSamplesFromDoc(t *testing.T) {
	doc := map[string]any{"routePoints": []any{
		map[string]any{"latitude": 10.0, "longitude": 106.0, "timestamp": "2026-11-25T01:02:03.456789Z", "accuracyMeters": 4.5},
		map[string]any{"latitude": 10.001, "longitude": 106.001},
		map[string]any{"longitude": 106.0},
		"không phải map",
	}}
	got := routeSamplesFromDoc(doc)
	if len(got) != 2 {
		t.Fatalf("muốn 2 điểm hợp lệ, ra %d", len(got))
	}
	if got[0].At.IsZero() || !got[0].HasAccuracy || got[0].Accuracy != 4.5 {
		t.Fatalf("điểm đầu thiếu giờ hay độ chính xác: %+v", got[0])
	}
	if !got[1].At.IsZero() || got[1].HasAccuracy {
		t.Fatalf("điểm thứ hai không có giờ, độ chính xác: %+v", got[1])
	}
	// Vector chuẩn của Encoded Polyline Algorithm Format (tài liệu Google).
	poly := routeSamplesFromDoc(map[string]any{"polyline": "_p~iF~ps|U_ulLnnqC_mqNvxq`@"})
	if len(poly) != 3 || poly[0].Lat != 38.5 || poly[0].Lng != -120.2 || poly[2].Lat != 43.252 || poly[2].Lng != -126.453 {
		t.Fatalf("giải polyline sai: %+v", poly)
	}
	if routeSamplesFromDoc(map[string]any{"polyline": "@@@@~"}) != nil {
		t.Fatal("polyline hỏng phải coi như không có tuyến")
	}
}

var terrT0 = time.Date(2026, 11, 1, 6, 0, 0, 0, time.UTC)

func terrPass(uid, id string, hours, meters int) territoryPass {
	return territoryPass{UID: uid, ActivityID: id, EndedAt: terrT0.Add(time.Duration(hours) * time.Hour), Meters: meters}
}

const terrMonth = 30 * 24 * time.Hour

func TestOwnerOf(t *testing.T) {
	at := terrT0.Add(100 * time.Hour)
	o, ok := ownerOf([]territoryPass{terrPass("A", "a1", 1, 300), terrPass("B", "b1", 2, 200), terrPass("A", "a2", 3, 50)}, at, terrMonth)
	if !ok || o != (cellOwner{UID: "A", Meters: 350, Second: 200}) {
		t.Fatalf("nhiều km nhất giữ: %+v %v", o, ok)
	}
	// Hoà 200–200: B có lượt sớm hơn (giờ 1) giữ.
	o, _ = ownerOf([]territoryPass{terrPass("A", "a1", 2, 200), terrPass("B", "b1", 1, 200)}, at, terrMonth)
	if o.UID != "B" {
		t.Fatalf("hoà phải cho người tới trước: %+v", o)
	}
	// Lượt sớm nhất của A nằm sau trong danh sách: vẫn phải lấy lượt sớm nhất.
	o, _ = ownerOf([]territoryPass{terrPass("A", "a2", 5, 100), terrPass("B", "b1", 3, 200), terrPass("A", "a1", 1, 100)}, at, terrMonth)
	if o.UID != "A" {
		t.Fatalf("hoà phải so lượt sớm nhất của mỗi người: %+v", o)
	}
	// Cửa sổ (at − 30 ngày, at]: đúng mốc at − 30 ngày bị loại, đúng at được tính,
	// sau at bị loại.
	edge := []territoryPass{
		{UID: "A", ActivityID: "old", EndedAt: at.Add(-terrMonth), Meters: 999},
		{UID: "B", ActivityID: "now", EndedAt: at, Meters: 10},
		{UID: "C", ActivityID: "future", EndedAt: at.Add(time.Second), Meters: 999},
	}
	o, _ = ownerOf(edge, at, terrMonth)
	if o != (cellOwner{UID: "B", Meters: 10}) {
		t.Fatalf("mép cửa sổ sai: %+v", o)
	}
	if _, ok := ownerOf(nil, at, terrMonth); ok {
		t.Fatal("không lượt nào thì ô trống")
	}
	if _, ok := ownerOf([]territoryPass{terrPass("A", "a", 1, 100)}, terrT0.Add(31*24*time.Hour+2*time.Hour), terrMonth); ok {
		t.Fatal("lượt đã trôi khỏi cửa sổ thì ô trống")
	}
}

func TestResultFor(t *testing.T) {
	cell := "1_1"
	run := func(x territoryPass, others ...territoryPass) territoryResult {
		return resultFor(x, map[string]int{cell: x.Meters}, map[string][]territoryPass{cell: others}, terrMonth)
	}
	if r := run(terrPass("B", "b1", 5, 100)); r.Gained != 1 || len(r.Taken) != 0 {
		t.Fatalf("ô trống phải là ô mới: %+v", r)
	}
	if r := run(terrPass("B", "b1", 5, 400), terrPass("A", "a1", 1, 300)); r.Gained != 0 || r.Taken["A"] != 1 {
		t.Fatalf("vượt A phải chiếm của A: %+v", r)
	}
	if r := run(terrPass("B", "b1", 5, 200), terrPass("A", "a1", 1, 300)); r.Gained != 0 || len(r.Taken) != 0 {
		t.Fatalf("chưa vượt thì không có gì: %+v", r)
	}
	if r := run(terrPass("B", "b2", 5, 100), terrPass("B", "b1", 1, 300)); r.Gained != 0 || len(r.Taken) != 0 {
		t.Fatalf("chủ chạy lại tuyến cũ không có ô mới: %+v", r)
	}
	// Hai buổi của B: buổi đầu chưa vượt, buổi sau vượt; chỉ buổi sau chiếm.
	a, b1, b2 := terrPass("A", "a1", 1, 300), terrPass("B", "b1", 2, 200), terrPass("B", "b2", 3, 200)
	if r := run(b1, a, b2); len(r.Taken) != 0 || r.Gained != 0 {
		t.Fatalf("buổi đầu của B chưa vượt A: %+v", r)
	}
	if r := run(b2, a, b1); r.Taken["A"] != 1 {
		t.Fatalf("buổi sau của B mới chiếm: %+v", r)
	}
	// Lượt sau x (C chạy sau) và bản ghi của chính x không đổi kết quả của x.
	if r := run(terrPass("B", "b1", 5, 400), terrPass("A", "a1", 1, 300), terrPass("C", "c1", 9, 900), terrPass("B", "b1", 5, 400)); r.Taken["A"] != 1 {
		t.Fatalf("lượt sau x hay bản sao của x làm đổi kết quả: %+v", r)
	}
	// C kết thúc cùng giờ với x nhưng đứng sau x theo khoá (uid C > B): không
	// được tính vào "trước", nên x chiếm của A chứ không của C.
	if r := run(terrPass("B", "b1", 5, 400), terrPass("A", "a1", 1, 300), terrPass("C", "c1", 5, 350)); r.Taken["A"] != 1 || r.Taken["C"] != 0 {
		t.Fatalf("lượt cùng giờ đứng sau x bị tính vào trước: %+v", r)
	}
	// Hoà với chủ cũ: chủ cũ tới trước nên giữ, B không chiếm.
	if r := run(terrPass("B", "b1", 5, 300), terrPass("A", "a1", 1, 300)); len(r.Taken) != 0 {
		t.Fatalf("hoà thì người tới trước giữ: %+v", r)
	}
}
