package backend

import (
	"math"
	"regexp"
	"strconv"
	"strings"
)

// goalSpec là những ràng buộc trích được từ câu mục tiêu tự do của user.
// Trường nào không nêu thì để 0 — người gọi tự quyết mặc định.
type goalSpec struct {
	DistanceKm float64 // cự ly đích
	TargetSec  int     // thời gian đích cho cả cự ly, vd "10km dưới 1h" → 3600
	PlanWeeks  int     // độ dài giáo án user muốn, vd "trong 8 tuần" → 8
}

// TargetPaceSec là pace đích suy ra từ cự ly + thời gian đích, giây/km.
// 0 khi thiếu một trong hai.
func (g goalSpec) TargetPaceSec() int {
	if g.DistanceKm <= 0 || g.TargetSec <= 0 {
		return 0
	}
	return int(math.Round(float64(g.TargetSec) / g.DistanceKm))
}

var (
	// "10km", "10 km", "10k", "5,5km"
	reDistance = regexp.MustCompile(`(\d+(?:[.,]\d+)?)\s*k(?:m\b|\b)`)
	// "1h", "1 giờ", "1h30", "1 giờ 30"
	reHour = regexp.MustCompile(`(\d+)\s*(?:h|giờ|gio)\s*(\d+)?`)
	// "60 phút", "60p", "60 min"
	reMinute = regexp.MustCompile(`(\d+)\s*(?:phút|phut|min\b|p\b)`)
	// "sub 60", "dưới 55", "under 50" — số trần, không đơn vị
	reBareTarget = regexp.MustCompile(`(?:sub|dưới|duoi|under|<)\s*(\d+(?:[.,]\d+)?)`)

	reWeeks  = regexp.MustCompile(`(\d+)\s*(?:tuần|tuan|week)`)
	reMonths = regexp.MustCompile(`(\d+)\s*(?:tháng|thang|month)`)
	reDays   = regexp.MustCompile(`(\d+)\s*(?:ngày|ngay|day)`)
)

// parseGoal trích cự ly, thời gian đích và độ dài giáo án từ câu tự do.
//
// Bản trước chỉ tìm "số đầu tiên" và bắt chuỗi "21"/"42" ở bất cứ đâu, nên
// "chạy 5km trong 42 ngày" ra 42.2km và "sub 60 10k" ra 60km. Ở đây mỗi đại
// lượng phải đi kèm ĐƠN VỊ của nó mới được nhận, và đơn vị cũng là thứ phân
// biệt "trong 55 phút" (thời gian đích) với "trong 8 tuần" (độ dài giáo án).
func parseGoal(goal string) goalSpec {
	g := strings.ToLower(strings.TrimSpace(goal))
	var spec goalSpec

	// ── cự ly ────────────────────────────────────────────────────────────
	// Tên cự ly chuẩn xét trước, vì "half marathon" không mang số nào.
	switch {
	case strings.Contains(g, "half marathon"), strings.Contains(g, "bán marathon"),
		strings.Contains(g, "ban marathon"), regexp.MustCompile(`\bhm\b`).MatchString(g):
		spec.DistanceKm = 21.1
	case strings.Contains(g, "full marathon"), regexp.MustCompile(`\bfm\b`).MatchString(g):
		spec.DistanceKm = 42.2
	}
	if m := reDistance.FindStringSubmatch(g); m != nil {
		if v := parseNum(m[1]); v > 0 {
			spec.DistanceKm = v
		}
	}
	// "marathon" trần chỉ tính khi chưa có cự ly nào khác — tránh nuốt
	// "chuẩn bị marathon sang năm, giờ chạy 10km".
	if spec.DistanceKm == 0 && strings.Contains(g, "marathon") {
		spec.DistanceKm = 42.2
	}

	// ── độ dài giáo án ───────────────────────────────────────────────────
	if m := reWeeks.FindStringSubmatch(g); m != nil {
		spec.PlanWeeks = atoi(m[1])
	} else if m := reMonths.FindStringSubmatch(g); m != nil {
		spec.PlanWeeks = atoi(m[1]) * 4
	} else if m := reDays.FindStringSubmatch(g); m != nil {
		if d := atoi(m[1]); d > 0 {
			spec.PlanWeeks = (d + 6) / 7
		}
	}

	// ── thời gian đích ───────────────────────────────────────────────────
	// Chỉ nhận khi có đơn vị thời gian rõ ràng. "trong 8 tuần" không lọt
	// vào đây vì "tuần" không phải đơn vị thời gian đích.
	if m := reHour.FindStringSubmatch(g); m != nil {
		spec.TargetSec = atoi(m[1]) * 3600
		if len(m) > 2 && m[2] != "" {
			spec.TargetSec += atoi(m[2]) * 60
		}
	} else if m := reMinute.FindStringSubmatch(g); m != nil {
		spec.TargetSec = atoi(m[1]) * 60
	} else if m := reBareTarget.FindStringSubmatch(g); m != nil {
		// Số trần sau "sub"/"dưới": quy ước chạy bộ là ≤10 thì tính giờ
		// ("sub 4" cho marathon), lớn hơn thì tính phút ("sub 60" cho 10k).
		if v := parseNum(m[1]); v > 0 {
			if v <= 10 {
				spec.TargetSec = int(v * 3600)
			} else {
				spec.TargetSec = int(v * 60)
			}
		}
	}

	return spec
}

func parseNum(s string) float64 {
	v, err := strconv.ParseFloat(strings.Replace(s, ",", ".", 1), 64)
	if err != nil {
		return 0
	}
	return v
}

func atoi(s string) int {
	v, _ := strconv.Atoi(s)
	return v
}

// fmtDuration in thời gian đích cho prompt và cho phần tóm tắt: "1h00", "55 phút".
func fmtDuration(sec int) string {
	if sec <= 0 {
		return ""
	}
	h, m := sec/3600, (sec%3600)/60
	if h > 0 {
		return strconv.Itoa(h) + "h" + pad2(m)
	}
	return strconv.Itoa(m) + " phút"
}

// fmtGoalPace in pace đích dạng "6:00/km". Khác fmtPace ở bot_tools.go:
// rỗng khi chưa có mục tiêu, và có hậu tố đơn vị.
func fmtGoalPace(secPerKm int) string {
	if secPerKm <= 0 {
		return ""
	}
	return strconv.Itoa(secPerKm/60) + ":" + pad2(secPerKm%60) + "/km"
}

func pad2(v int) string {
	if v < 10 {
		return "0" + strconv.Itoa(v)
	}
	return strconv.Itoa(v)
}
