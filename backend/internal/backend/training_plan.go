package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"math"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/genai"
)

// AI Coach: sinh GIÁO ÁN chạy cá nhân theo mục tiêu + lịch sử chạy thật của
// user. Gemini trả JSON đúng schema (structured output) → backend gắn ngày/nhãn
// + ghi users/{uid}/coach/current. Mỗi user chỉ 1 giáo án active (kiểm ở
// endpoint); "đổi" = ghi đè (replace), "xoá" = app tự xoá doc.

type runnerHistory struct {
	weekKm     float64 // km/tuần gần đây (rolling 7 ngày)
	monthKm    float64
	longestKm  float64
	avgPaceSec int // giây/km trung bình gần đây; 0 nếu chưa có
	activeDays int // số ngày có chạy trong tháng
}

// gatherRunnerHistory đọc leaderboardEntries/{uid} (đã tính sẵn) để tóm tắt
// phong độ. Rỗng (người mới) → trả zero, prompt sẽ coi là nền cơ bản.
func (s *BotService) gatherRunnerHistory(ctx context.Context, uid string) runnerHistory {
	snap, err := s.db.Collection("leaderboardEntries").Doc(uid).Get(ctx)
	if err != nil || !snap.Exists() {
		return runnerHistory{}
	}
	data := snap.Data()
	roll, _ := data["rollingSevenDays"].(map[string]any)
	month, _ := data["currentMonth"].(map[string]any)
	h := runnerHistory{}
	if roll != nil {
		h.weekKm = round1(number(roll["distanceMeters"]) / 1000)
		h.longestKm = round1(number(roll["longestDistanceMeters"]) / 1000)
		dist := number(roll["distanceMeters"])
		mov := number(roll["movingTimeSeconds"])
		if dist > 500 && mov > 0 {
			h.avgPaceSec = int(mov / (dist / 1000))
		}
	}
	if month != nil {
		h.monthKm = round1(number(month["distanceMeters"]) / 1000)
		h.activeDays = int(number(month["activeDays"]))
		if lk := round1(number(month["longestDistanceMeters"]) / 1000); lk > h.longestKm {
			h.longestKm = lk
		}
	}
	return h
}

type genPlanDay struct {
	Week       int      `json:"week"`
	Type       string   `json:"type"`
	Title      string   `json:"title"`
	DistanceKm *float64 `json:"distanceKm"`
	Detail     string   `json:"detail"`
	PaceHint   string   `json:"paceHint"`
	Note       string   `json:"note"`
}

type genPlan struct {
	GoalDistanceKm float64      `json:"goalDistanceKm"`
	Weeks          int          `json:"weeks"`
	Summary        string       `json:"summary"`
	Days           []genPlanDay `json:"days"`
}

var validWorkoutTypes = map[string]bool{
	"easy": true, "long": true, "tempo": true, "interval": true, "rest": true, "race": true,
}

func trainingPlanSchema() *genai.Schema {
	str := func() *genai.Schema { return &genai.Schema{Type: genai.TypeString} }
	return &genai.Schema{
		Type: genai.TypeObject,
		Properties: map[string]*genai.Schema{
			"goalDistanceKm": {Type: genai.TypeNumber},
			"weeks":          {Type: genai.TypeInteger},
			"summary":        str(),
			"days": {
				Type: genai.TypeArray,
				Items: &genai.Schema{
					Type: genai.TypeObject,
					Properties: map[string]*genai.Schema{
						"week": {Type: genai.TypeInteger},
						"type": {
							Type: genai.TypeString,
							Enum: []string{"easy", "long", "tempo", "interval", "rest", "race"},
						},
						"title":      str(),
						"distanceKm": {Type: genai.TypeNumber},
						"detail":     str(),
						"paceHint":   str(),
						"note":       str(),
					},
					Required: []string{"week", "type", "title"},
				},
			},
		},
		Required: []string{"goalDistanceKm", "weeks", "summary", "days"},
	}
}

const trainingPlanPrompt = `Bạn là một HUẤN LUYỆN VIÊN CHẠY BỘ CHUYÊN NGHIỆP, nắm vững khoa học thể thao và
đã dựng giáo án cho nhiều trình độ. Hãy thiết kế MỘT giáo án cá nhân hoá, AN TOÀN
và có cơ sở, dựa trên MỤC TIÊU và LỊCH SỬ TẬP THẬT của runner dưới đây.

MỤC TIÊU: %s
LỊCH SỬ TẬP (dữ liệu thật — CĂN độ khó theo đây, tuyệt đối không nhồi quá sức):
- Km trung bình 7 ngày gần đây: %s
- Km tháng này: %s
- Buổi dài nhất gần đây: %s
- Pace trung bình gần đây: %s
- Số ngày có chạy trong tháng: %d

HIỂU MỤC TIÊU (mục tiêu có thể là CÂU TỰ DO — tự trích và TÔN TRỌNG mọi ràng buộc):
- Thời gian / số tuần user nêu → dùng ĐÚNG số tuần đó.
- Pace mong muốn → căn paceHint quanh đó (easy chậm hơn, tempo/interval nhanh hơn).
- NGÀY RẢNH trong tuần (vd "rảnh Thứ 3, Thứ 5, Thứ 7") → xếp các buổi CHẠY vào đúng
  những ngày đó; ngày KHÔNG rảnh để "rest". Vẫn giữ nguyên tắc không 2 buổi nặng liền.
- Số buổi/tuần, hay ràng buộc khác user nêu → tuân theo hợp lý.
- User KHÔNG nêu cái gì thì bạn tự quyết theo nguyên tắc huấn luyện bên dưới.

NGUYÊN TẮC HUẤN LUYỆN (bám sát, đây là phần quan trọng nhất):
- CÁ NHÂN HOÁ theo nền hiện tại: khối lượng tuần đầu xấp xỉ km/tuần gần đây, KHÔNG
  nhảy vọt. Nếu chưa có dữ liệu (người mới) → khởi điểm nhẹ, thận trọng.
- TĂNG TẢI TỪ TỪ: tổng km mỗi tuần tăng không quá ~10%% so với tuần trước (quy tắc 10%%).
- PHÂN BỔ 80/20: phần lớn là chạy nhẹ (easy, đủ chậm để nói chuyện được); chỉ khoảng
  20%% khối lượng là cường độ cao (tempo/interval). Đừng lạm dụng buổi nặng.
- HỒI PHỤC: mỗi tuần có 2–3 ngày nghỉ/hồi phục xen kẽ; KHÔNG xếp 2 buổi nặng
  (interval/tempo/long) liền nhau.
- CHẠY DÀI tăng dần theo tuần để xây nền bền cho cự ly mục tiêu.
- TAPER: tuần CUỐI giảm tải rõ (~40–50%%) để chân tươi trước ngày về đích.
- Buổi CUỐI CÙNG là type "race" đúng bằng cự ly mục tiêu (nếu mục tiêu là cự ly).
- PACE MỤC TIÊU phải suy ra từ pace hiện tại của runner — thực tế, không viển vông.
  Buổi easy chậm hơn pace mục tiêu; interval/tempo nhanh hơn.
- Nếu mục tiêu quá sức so với nền trong thời gian ngắn → ưu tiên AN TOÀN, đặt cột
  mốc vừa sức thay vì ép.

RÀNG BUỘC ĐẦU RA:
- Tự chọn số TUẦN hợp lý (thường 2–8). Mục tiêu ghi rõ số tuần thì theo đúng.
- days có ĐÚNG weeks×7 phần tử, thứ tự Thứ 2 → Chủ nhật; field week = 1..weeks.
- type ∈ easy|long|tempo|interval|rest|race. Ngày rest: title "Nghỉ", bỏ distanceKm/pace.
- distanceKm: km buổi (số thực). paceHint dạng "6:15" (phút:giây/km). detail chỉ cho
  interval (vd "5×400m nghỉ 90s"). note: lời khuyên NGẮN, chuyên môn mà dễ hiểu
  (kỹ thuật/cảm giác/nhắc nhở cho ĐÚNG buổi đó) — không sáo rỗng, không cần mọi buổi.
- summary: 1 câu nêu định hướng giáo án.
Trả về DUY NHẤT JSON theo schema, không kèm giải thích.`

// GenerateTrainingPlan sinh giáo án cho user rồi ghi users/{uid}/coach/current
// (status active). Ghi đè giáo án cũ nếu có (endpoint đã kiểm luật "1 active").
func (s *BotService) GenerateTrainingPlan(ctx context.Context, uid, goal string) error {
	if !s.Enabled() {
		return fmt.Errorf("bot chưa bật")
	}
	goal = strings.TrimSpace(goal)
	if goal == "" {
		goal = "Chạy 10km"
	}
	h := s.gatherRunnerHistory(ctx, uid)
	pace := "chưa rõ"
	if h.avgPaceSec > 0 {
		pace = fmt.Sprintf("%d:%02d/km", h.avgPaceSec/60, h.avgPaceSec%60)
	}
	prompt := fmt.Sprintf(trainingPlanPrompt, goal,
		kmLabel(h.weekKm), kmLabel(h.monthKm), kmLabel(h.longestKm), pace, h.activeDays)

	resp, err := s.genai.Models.GenerateContent(ctx, s.model,
		[]*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: prompt}}}},
		&genai.GenerateContentConfig{
			ResponseMIMEType: "application/json",
			ResponseSchema:   trainingPlanSchema(),
		})
	if err != nil {
		return fmt.Errorf("gemini: %w", err)
	}
	var plan genPlan
	if err := json.Unmarshal([]byte(resp.Text()), &plan); err != nil {
		return fmt.Errorf("parse plan: %w", err)
	}
	if len(plan.Days) == 0 {
		return fmt.Errorf("plan rỗng")
	}

	doc := buildTrainingPlanDoc(uid, goal, plan, time.Now(), h.longestKm)
	_, err = s.db.Collection("users").Doc(uid).Collection("coach").Doc("current").
		Set(ctx, doc)
	return err
}

// buildTrainingPlanDoc gắn ngày lịch + nhãn thứ (backend tính, không để AI làm
// toán ngày) và chuẩn hoá thành doc Firestore khớp model client.
func buildTrainingPlanDoc(uid, goal string, plan genPlan, now time.Time, baselineKm float64) map[string]any {
	vn := time.FixedZone("Asia/Ho_Chi_Minh", 7*60*60)
	// Bắt đầu từ NGÀY MAI (giờ VN) để user có ngày chuẩn bị.
	t := now.In(vn)
	start := time.Date(t.Year(), t.Month(), t.Day(), 0, 0, 0, 0, vn).AddDate(0, 0, 1)

	days := make([]map[string]any, 0, len(plan.Days))
	for i, d := range plan.Days {
		date := start.AddDate(0, 0, i)
		typ := strings.ToLower(strings.TrimSpace(d.Type))
		if !validWorkoutTypes[typ] {
			typ = "easy"
		}
		entry := map[string]any{
			"week":  (i / 7) + 1, // ép theo vị trí cho chắc
			"label": weekdayLabelVN(date),
			"type":  typ,
			"title": strings.TrimSpace(d.Title),
			"done":  false,
		}
		if typ != "rest" && d.DistanceKm != nil && *d.DistanceKm > 0 {
			entry["distanceKm"] = round1(*d.DistanceKm)
		}
		if s := strings.TrimSpace(d.Detail); s != "" {
			entry["detail"] = s
		}
		if s := strings.TrimSpace(d.PaceHint); s != "" {
			entry["paceHint"] = s
		}
		if s := strings.TrimSpace(d.Note); s != "" {
			entry["note"] = s
		}
		days = append(days, entry)
	}
	target := start.AddDate(0, 0, len(days)-1)
	weeks := (len(days) + 6) / 7

	goalKm := plan.GoalDistanceKm
	if goalKm <= 0 {
		goalKm = parseGoalKm(goal)
	}
	return map[string]any{
		"goal":           goal,
		"goalDistanceKm": goalKm,
		"weeks":          weeks,
		"startDate":      dateKey(start),
		"targetDate":     dateKey(target),
		"summary":        strings.TrimSpace(plan.Summary),
		"baselineKm":     round1(baselineKm),
		"days":           days,
		"status":         "active",
		"createdAt":      firestore.ServerTimestamp,
		"updatedAt":      firestore.ServerTimestamp,
	}
}

func weekdayLabelVN(d time.Time) string {
	switch d.Weekday() {
	case time.Monday:
		return "Thứ 2"
	case time.Tuesday:
		return "Thứ 3"
	case time.Wednesday:
		return "Thứ 4"
	case time.Thursday:
		return "Thứ 5"
	case time.Friday:
		return "Thứ 6"
	case time.Saturday:
		return "Thứ 7"
	default:
		return "CN"
	}
}

func kmLabel(v float64) string {
	if v <= 0 {
		return "chưa có dữ liệu"
	}
	return fmt.Sprintf("%s km", trimFloat(v))
}

func parseGoalKm(goal string) float64 {
	g := strings.ToLower(goal)
	if strings.Contains(g, "half") || strings.Contains(g, "21") {
		return 21.1
	}
	if strings.Contains(g, "full") || strings.Contains(g, "42") || strings.Contains(g, "marathon") {
		return 42.2
	}
	// tìm số đầu tiên
	var num strings.Builder
	for _, r := range g {
		if r >= '0' && r <= '9' || r == '.' {
			num.WriteRune(r)
		} else if num.Len() > 0 {
			break
		}
	}
	if num.Len() > 0 {
		var f float64
		fmt.Sscanf(num.String(), "%f", &f)
		return f
	}
	return 0
}

func round1(v float64) float64 { return math.Round(v*10) / 10 }

func trimFloat(v float64) string {
	if v == math.Trunc(v) {
		return fmt.Sprintf("%d", int64(v))
	}
	return fmt.Sprintf("%.1f", v)
}
