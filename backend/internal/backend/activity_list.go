package backend

import (
	"context"
	"strings"

	"cloud.google.com/go/firestore"
)

// activityListFields là các field app cần để vẽ một dòng trong danh sách buổi
// chạy. Doc activity còn routePoints, streams và trackingDebug chiếm gần hết
// dung lượng; SDK Firestore trên điện thoại không chọn field được nên app đọc
// trực tiếp là tải nguyên doc. Danh sách đi qua đây để chỉ tải phần cần.
var activityListFields = []string{
	"id", "name", "sportType", "startedAt", "distanceMeters", "movingTimeSeconds",
	"elapsedTimeSeconds", "source", "sourceActivityId", "manual", "recordingDevice",
	"averageHeartRate", "averageCadence", "elevationGainMeters", "hydrated",
	"schemaVersion", "duplicateOfActivityId",
}

const activityPageMax = 50

// ActivityPage là một trang buổi chạy, mới trước. Cursor rỗng là hết trang.
type ActivityPage struct {
	Activities []map[string]any `json:"activities"`
	Cursor     string           `json:"cursor,omitempty"`
}

// List trả các buổi của uid, mới trước, theo trang. Hai buổi trùng giờ bắt
// đầu (buổi 3i trùng buổi Strava) xếp tiếp theo id doc, nên cursor gồm cả
// startedAt lẫn id để sang trang không mất hay lặp buổi nào.
func (s *ActivityService) List(ctx context.Context, uid, cursor string, limit int) (ActivityPage, error) {
	if limit < 1 || limit > activityPageMax {
		return ActivityPage{}, invalidRequest()
	}
	col := s.db.Collection("users").Doc(uid).Collection("activities")
	q := col.Select(activityListFields...).
		OrderBy("startedAt", firestore.Desc).
		OrderBy(firestore.DocumentID, firestore.Desc).
		Limit(limit)
	if cursor != "" {
		startedAt, id, ok := strings.Cut(cursor, "|")
		if !ok || startedAt == "" || id == "" {
			return ActivityPage{}, invalidRequest()
		}
		q = q.StartAfter(startedAt, id)
	}
	docs, err := q.Documents(ctx).GetAll()
	if err != nil {
		return ActivityPage{}, err
	}
	out := ActivityPage{Activities: make([]map[string]any, 0, len(docs))}
	for _, d := range docs {
		out.Activities = append(out.Activities, d.Data())
	}
	if len(docs) == limit {
		last := docs[len(docs)-1]
		out.Cursor = stringValue(last.Data()["startedAt"]) + "|" + last.Ref.ID
	}
	return out, nil
}
