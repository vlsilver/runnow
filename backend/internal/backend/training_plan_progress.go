package backend

import (
	"context"
	"log/slog"
	"sort"
	"strconv"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// planSessionMinRatio: tổng km chạy trong ngày đạt 80% quãng của buổi thì buổi
// đó tính là xong. Chạy tách khởi động và bài chính thành hai activity vẫn đủ.
const planSessionMinRatio = 0.8

// planMarkLookbackDays: chỉ xét buổi trong 7 ngày gần nhất, đủ cho đồng hồ
// đồng bộ trễ mà mỗi lượt không phải đọc activity của cả giáo án.
const planMarkLookbackDays = 7

// PlanSessionMark là một buổi vừa được đánh dấu xong cho một người.
type PlanSessionMark struct {
	PlanID, UID string
	DayIndex    int
	ActivityID  string
}

type planSession struct {
	index  int
	day    string // dateKey giờ VN
	meters float64
}

// duePlanSessions là các buổi chạy của uid tới hạn xét: có quãng đường, ngày
// nằm trong planMarkLookbackDays tính tới hôm nay và không trước ngày uid tham
// gia, chưa xong, chưa từng được tự đánh dấu. Buổi đã tự đánh dấu mà người
// dùng bỏ tick thì không đánh dấu lại.
func duePlanSessions(plan map[string]any, uid string, now time.Time) []planSession {
	parts, _ := plan["participants"].(map[string]any)
	part, ok := parts[uid].(map[string]any)
	if !ok {
		return nil
	}
	start, err := time.ParseInLocation("2006-01-02", stringValue(plan["startDate"]), vietnam)
	if err != nil {
		return nil
	}
	done := map[int]bool{}
	for _, v := range toAnySlice(part["doneIndices"]) {
		done[int(number(v))] = true
	}
	matched, _ := part["matched"].(map[string]any)
	today := dateKey(now)
	from := dateKey(now.AddDate(0, 0, -planMarkLookbackDays))
	if joined, ok := part["joinedAt"].(time.Time); ok && dateKey(joined) > from {
		from = dateKey(joined)
	}
	var out []planSession
	for i, raw := range toAnySlice(plan["days"]) {
		day, _ := raw.(map[string]any)
		km := number(day["distanceKm"])
		if stringValue(day["type"]) == "rest" || km <= 0 || done[i] {
			continue
		}
		if _, seen := matched[strconv.Itoa(i)]; seen {
			continue
		}
		key := dateKey(start.AddDate(0, 0, i))
		if key < from || key > today {
			continue
		}
		out = append(out, planSession{index: i, day: key, meters: km * 1000})
	}
	return out
}

// matchPlanSessions trả về buổi nào đã chạy đủ, kèm activity dài nhất của ngày
// đó. Chỉ tính buổi chạy chính thức (đã bỏ bản trùng nguồn), không tính đi bộ.
func matchPlanSessions(sessions []planSession, facts []ActivityFact) map[int]string {
	metersByDay := map[string]float64{}
	longest := map[string]ActivityFact{}
	for _, a := range SelectOfficialActivities(facts) {
		if !runSportTypes[a.SportType] {
			continue
		}
		day := dateKey(a.StartedAt)
		metersByDay[day] += a.DistanceMeters
		if best, ok := longest[day]; !ok || a.DistanceMeters > best.DistanceMeters {
			longest[day] = a
		}
	}
	out := map[int]string{}
	for _, s := range sessions {
		if metersByDay[s.day] >= s.meters*planSessionMinRatio {
			out[s.index] = longest[s.day].ID
		}
	}
	return out
}

// MarkPlanSessions đánh dấu xong buổi chạy cho mọi người đang theo một giáo án
// đang chạy. dryRun chỉ tính, không ghi.
func MarkPlanSessions(ctx context.Context, db *firestore.Client, now time.Time, dryRun bool) ([]PlanSessionMark, error) {
	docs, err := db.Collection("coachPlans").Where("status", "==", "active").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	var marks []PlanSessionMark
	for _, doc := range docs {
		parts, _ := doc.Data()["participants"].(map[string]any)
		uids := make([]string, 0, len(parts))
		for uid := range parts {
			uids = append(uids, uid)
		}
		sort.Strings(uids)
		got, err := markPlanDoc(ctx, db, doc, uids, now, dryRun)
		if err != nil {
			return marks, err
		}
		marks = append(marks, got...)
	}
	return marks, nil
}

// MarkPlanSessionsForUser làm việc đó cho riêng uid, gọi khi activity của uid
// vừa đổi để buổi hôm nay được tick ngay.
func MarkPlanSessionsForUser(ctx context.Context, db *firestore.Client, uid string, now time.Time) ([]PlanSessionMark, error) {
	docs, err := db.Collection("coachPlans").Where("participantUids", "array-contains", uid).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	var marks []PlanSessionMark
	for _, doc := range docs {
		if stringValue(doc.Data()["status"]) != "active" {
			continue
		}
		got, err := markPlanDoc(ctx, db, doc, []string{uid}, now, false)
		if err != nil {
			return marks, err
		}
		marks = append(marks, got...)
	}
	return marks, nil
}

// markPlanDoc ghi mọi buổi vừa khớp của uids trong một giáo án bằng một lần
// update, để điều kiện "giáo án chưa đổi" đúng cho cả lượt.
func markPlanDoc(ctx context.Context, db *firestore.Client, doc *firestore.DocumentSnapshot, uids []string, now time.Time, dryRun bool) ([]PlanSessionMark, error) {
	plan := doc.Data()
	if plan["endedAt"] != nil {
		return nil, nil
	}
	var marks []PlanSessionMark
	updates := []firestore.Update{{Path: "updatedAt", Value: firestore.ServerTimestamp}}
	for _, uid := range uids {
		sessions := duePlanSessions(plan, uid, now)
		if len(sessions) == 0 {
			continue
		}
		first, last := sessions[0].day, sessions[0].day
		for _, s := range sessions {
			first, last = min(first, s.day), max(last, s.day)
		}
		from, _ := time.ParseInLocation("2006-01-02", first, vietnam)
		to, _ := time.ParseInLocation("2006-01-02", last, vietnam)
		facts, err := activityFactsBetween(ctx, db, uid, from, to.AddDate(0, 0, 1))
		if err != nil {
			return nil, err
		}
		matches := matchPlanSessions(sessions, facts)
		var indices []any
		for _, s := range sessions {
			id, ok := matches[s.index]
			if !ok {
				continue
			}
			marks = append(marks, PlanSessionMark{PlanID: doc.Ref.ID, UID: uid, DayIndex: s.index, ActivityID: id})
			indices = append(indices, s.index)
			updates = append(updates, firestore.Update{
				FieldPath: firestore.FieldPath{"participants", uid, "matched", strconv.Itoa(s.index)},
				Value:     id,
			})
		}
		if len(indices) > 0 {
			updates = append(updates, firestore.Update{
				FieldPath: firestore.FieldPath{"participants", uid, "doneIndices"},
				Value:     firestore.ArrayUnion(indices...),
			})
		}
	}
	if dryRun || len(marks) == 0 {
		return marks, nil
	}
	// Giáo án vừa bị sửa (đổi lịch, rời giáo án, tick tay) thì bỏ lượt này:
	// kết quả tính trên bản cũ, lượt sau tính lại trên bản mới.
	if _, err := doc.Ref.Update(ctx, updates, firestore.LastUpdateTime(doc.UpdateTime)); err != nil {
		if status.Code(err) == codes.FailedPrecondition {
			slog.Info("giáo án đổi giữa chừng, để lượt sau đánh dấu", "plan", doc.Ref.ID)
			return nil, nil
		}
		return nil, err
	}
	return marks, nil
}
