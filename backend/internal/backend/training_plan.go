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
// user. Gemini trả JSON đúng schema (structured output) → backend gắn ngày/nhãn.
//
// Hai bước, không phải một:
//
//	coach/draft    bản đề xuất, kèm rationale/feasibility/warnings. User đọc
//	               rồi mới quyết. Giáo án đang chạy KHÔNG bị đụng tới.
//	coach/current  giáo án đang chạy, chỉ tới đây qua ConfirmTrainingPlan.
//
// Tách hai bước vì trước đây lịch ghi thẳng vào current: user không biết vì sao
// ra lịch đó, và một lần bấm nhầm là mất giáo án đang tập.

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
	Rationale      string       `json:"rationale"`
	TargetPaceSec  int          `json:"targetPaceSec"`
	Feasibility    string       `json:"feasibility"`
	Warnings       []string     `json:"warnings"`
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
			// rationale là thứ user đọc TRƯỚC KHI xác nhận giáo án. Không có nó
			// thì lịch hiện ra mà không ai biết vì sao lại thế.
			"rationale":     str(),
			"targetPaceSec": {Type: genai.TypeInteger},
			"feasibility": {
				Type: genai.TypeString,
				Enum: []string{"vừa sức", "thử thách", "quá sức"},
			},
			"warnings": {Type: genai.TypeArray, Items: str()},
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
		Required: []string{"goalDistanceKm", "weeks", "summary", "rationale", "feasibility", "days"},
	}
}

const trainingPlanPrompt = `Bạn là một HUẤN LUYỆN VIÊN CHẠY BỘ CHUYÊN NGHIỆP, nắm vững khoa học thể thao và
đã dựng giáo án cho nhiều trình độ. Hãy thiết kế MỘT giáo án cá nhân hoá, AN TOÀN
và có cơ sở, dựa trên MỤC TIÊU và LỊCH SỬ TẬP THẬT của runner dưới đây.

MỤC TIÊU (nguyên văn): %s

RÀNG BUỘC ĐÃ TRÍCH SẴN (backend phân tích câu trên — TÔN TRỌNG, đừng trích lại):
%s

LỊCH SỬ TẬP (dữ liệu thật — CĂN độ khó theo đây, tuyệt đối không nhồi quá sức):
- Km trung bình 7 ngày gần đây: %s
- Km tháng này: %s
- Buổi dài nhất gần đây: %s
- Pace trung bình gần đây: %s
- Số ngày có chạy trong tháng: %d

HIỂU MỤC TIÊU (phần backend chưa trích được thì tự đọc từ câu nguyên văn):
- NGÀY RẢNH trong tuần (vd "rảnh Thứ 3, Thứ 5, Thứ 7") → xếp các buổi CHẠY vào đúng
  những ngày đó; ngày KHÔNG rảnh để "rest". Vẫn giữ nguyên tắc không 2 buổi nặng liền.
- Số buổi/tuần, hay ràng buộc khác user nêu → tuân theo hợp lý.
- User KHÔNG nêu cái gì thì bạn tự quyết theo nguyên tắc huấn luyện bên dưới.

MỤC TIÊU THỜI GIAN (khi phần trích ở trên có pace đích):
- Toàn bộ giáo án phải hướng về pace đích đó: buổi tempo/interval chạy quanh hoặc
  nhanh hơn pace đích, buổi easy chậm hơn rõ rệt.
- SO pace đích với pace hiện tại của runner và NÓI THẬT. Rút quá 15 giây/km trong
  vài tuần là phi thực tế với người đã tập đều — đặt feasibility "quá sức", nêu rõ
  trong warnings, và dựng giáo án hướng tới mốc VỪA SỨC thay vì ép theo con số.
- targetPaceSec: pace đích mà giáo án này thật sự nhắm tới (giây/km). Nếu bạn hạ
  mục tiêu vì quá sức thì ghi pace đã hạ, ĐỪNG ghi pace user đòi.

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

GIẢI THÍCH CHO USER (user đọc phần này rồi mới bấm xác nhận — viết cho người tập,
không phải cho đồng nghiệp HLV):
- rationale: 2–4 câu trả lời đúng câu hỏi "vì sao lịch lại ra như thế này". Nêu cụ
  thể: vì sao chừng đó tuần, vì sao khối lượng tuần đầu ở mức đó, vì sao bố trí buổi
  nặng vào những ngày đó. Bám vào SỐ LIỆU lịch sử ở trên, đừng nói chung chung.
- feasibility: "vừa sức" khi mục tiêu nằm trong tầm với; "thử thách" khi phải cố
  nhưng vẫn an toàn; "quá sức" khi nền hiện tại không cho phép trong khoảng thời
  gian đó.
- warnings: những điều user cần biết trước khi bắt đầu — mục tiêu đã bị hạ, khối
  lượng nhảy hơn mức an toàn, dữ liệu lịch sử quá ít để căn. Không có thì để mảng
  rỗng, đừng bịa cho đủ.
Trả về DUY NHẤT JSON theo schema, không kèm giải thích.`

// goalConstraintLines dựng khối "ràng buộc đã trích sẵn" cho prompt. Trích ở
// Go thay vì để model tự đọc câu: mục tiêu THỜI GIAN trước đây không có chỗ nào
// chứa nên pace đích không bao giờ tới được model — "10km dưới 1h" ra giáo án
// không nhắm tới 6:00/km.
func goalConstraintLines(spec goalSpec) string {
	var b strings.Builder
	if spec.DistanceKm > 0 {
		fmt.Fprintf(&b, "- Cự ly đích: %s\n", kmLabel(spec.DistanceKm))
	} else {
		b.WriteString("- Cự ly đích: user chưa nêu, bạn tự chọn mốc hợp lý\n")
	}
	if spec.TargetSec > 0 {
		fmt.Fprintf(&b, "- Thời gian đích: %s\n", fmtDuration(spec.TargetSec))
	}
	if p := spec.TargetPaceSec(); p > 0 {
		fmt.Fprintf(&b, "- Pace đích suy ra: %s — ĐÂY LÀ RÀNG BUỘC CHÍNH của giáo án\n", fmtGoalPace(p))
	}
	if spec.PlanWeeks > 0 {
		fmt.Fprintf(&b, "- Số tuần user muốn: %d — dùng đúng số này\n", spec.PlanWeeks)
	}
	if b.Len() == 0 {
		return "- (không trích được ràng buộc nào — tự quyết theo nguyên tắc bên dưới)"
	}
	return strings.TrimRight(b.String(), "\n")
}

// GenerateTrainingPlan sinh giáo án cho user rồi ghi users/{uid}/coach/draft
// (status draft). User xem tóm tắt + lý do rồi mới xác nhận sang current —
// xem ConfirmTrainingPlan. Giáo án đang chạy ở coach/current không bị đụng tới.
func (s *BotService) GenerateTrainingPlan(ctx context.Context, uid, goal string) error {
	if !s.Enabled() {
		return fmt.Errorf("bot chưa bật")
	}
	goal = strings.TrimSpace(goal)
	if goal == "" {
		goal = "Chạy 10km"
	}
	spec := parseGoal(goal)
	h := s.gatherRunnerHistory(ctx, uid)
	pace := "chưa rõ"
	if h.avgPaceSec > 0 {
		pace = fmt.Sprintf("%d:%02d/km", h.avgPaceSec/60, h.avgPaceSec%60)
	}
	prompt := fmt.Sprintf(trainingPlanPrompt, goal, goalConstraintLines(spec),
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

	doc := buildTrainingPlanDoc(uid, goal, spec, plan, time.Now(), h.longestKm)
	_, err = s.db.Collection("users").Doc(uid).Collection("coach").Doc("draft").
		Set(ctx, doc)
	return err
}

// ConfirmTrainingPlan chuyển bản nháp thành giáo án đang chạy: copy
// coach/draft → coach/current với status active, rồi xoá nháp. Chạy trong một
// transaction để không có lúc nào cả hai cùng tồn tại ở trạng thái nửa vời.
func (s *BotService) ConfirmTrainingPlan(ctx context.Context, uid string) error {
	coach := s.db.Collection("users").Doc(uid).Collection("coach")
	draftRef, curRef := coach.Doc("draft"), coach.Doc("current")

	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(draftRef)
		if err != nil || !snap.Exists() {
			return fmt.Errorf("chưa có bản nháp nào để xác nhận")
		}
		doc := snap.Data()
		doc["status"] = "active"
		doc["confirmedAt"] = firestore.ServerTimestamp
		if err := tx.Set(curRef, doc); err != nil {
			return err
		}
		return tx.Delete(draftRef)
	})
}

// DiscardTrainingPlanDraft bỏ bản nháp mà không đụng tới giáo án đang chạy.
func (s *BotService) DiscardTrainingPlanDraft(ctx context.Context, uid string) error {
	_, err := s.db.Collection("users").Doc(uid).Collection("coach").Doc("draft").Delete(ctx)
	return err
}

// buildTrainingPlanDoc gắn ngày lịch + nhãn thứ (backend tính, không để AI làm
// toán ngày) và chuẩn hoá thành doc Firestore khớp model client.
func buildTrainingPlanDoc(uid, goal string, spec goalSpec, plan genPlan, now time.Time, baselineKm float64) map[string]any {
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

	// Cự ly: ưu tiên con số model trả về, rồi tới câu user viết. Cả hai đều
	// không có mới chịu thua — không đoán bừa.
	goalKm := plan.GoalDistanceKm
	if goalKm <= 0 {
		goalKm = spec.DistanceKm
	}
	// Pace đích: model có quyền HẠ so với con số user đòi (khi quá sức), nên
	// lấy của model trước; chỉ khi model bỏ trống mới dùng con số suy từ câu.
	targetPace := plan.TargetPaceSec
	if targetPace <= 0 {
		targetPace = spec.TargetPaceSec()
	}

	doc := map[string]any{
		"goal":           goal,
		"goalDistanceKm": goalKm,
		"weeks":          weeks,
		"startDate":      dateKey(start),
		"targetDate":     dateKey(target),
		"summary":        strings.TrimSpace(plan.Summary),
		"rationale":      strings.TrimSpace(plan.Rationale),
		"feasibility":    strings.TrimSpace(plan.Feasibility),
		"baselineKm":     round1(baselineKm),
		"totalKm":        round1(totalKm(days)),
		"days":           days,
		"status":         "draft",
		"createdAt":      firestore.ServerTimestamp,
		"updatedAt":      firestore.ServerTimestamp,
	}
	if spec.TargetSec > 0 {
		doc["goalTimeSec"] = spec.TargetSec
	}
	if targetPace > 0 {
		doc["targetPaceSec"] = targetPace
	}
	// Cảnh báo chỉ ghi khi thật sự có — mảng rỗng trong Firestore làm client
	// phải phân biệt "chưa sinh" với "không có cảnh báo nào".
	warnings := make([]string, 0, len(plan.Warnings))
	for _, w := range plan.Warnings {
		if w = strings.TrimSpace(w); w != "" {
			warnings = append(warnings, w)
		}
	}
	if len(warnings) > 0 {
		doc["warnings"] = warnings
	}
	return doc
}

// totalKm cộng km của cả giáo án — hiện ở màn xác nhận để user thấy khối lượng
// mình sắp cam kết, trước khi bấm đồng ý.
func totalKm(days []map[string]any) float64 {
	var sum float64
	for _, d := range days {
		if v, ok := d["distanceKm"].(float64); ok {
			sum += v
		}
	}
	return sum
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
func round1(v float64) float64 { return math.Round(v*10) / 10 }

func trimFloat(v float64) string {
	if v == math.Trunc(v) {
		return fmt.Sprintf("%d", int64(v))
	}
	return fmt.Sprintf("%.1f", v)
}
