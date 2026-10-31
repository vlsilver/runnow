package backend

import (
	"context"
	"strings"

	"cloud.google.com/go/firestore"
)

// clubRunsScanRounds giới hạn số lần đọc thêm cho một trang feed khi các buổi
// mới nhất toàn của người để hồ sơ riêng tư. Hết lượt thì trả phần đã có kèm
// cursor để app đọc tiếp.
const clubRunsScanRounds = 5

// ClubRun là một buổi trong feed club, kèm uid người tập vì collection group
// không cho biết doc thuộc ai nếu không nhìn đường dẫn.
type ClubRun struct {
	OwnerUID string         `json:"ownerUid"`
	Activity map[string]any `json:"activity"`
}

// ClubRunsPage là một trang feed, mới trước. Cursor rỗng là hết trang; trang
// có thể ít hơn limit (kể cả rỗng) mà vẫn có cursor.
type ClubRunsPage struct {
	Runs   []ClubRun `json:"runs"`
	Cursor string    `json:"cursor,omitempty"`
}

// ClubRuns trả buổi tập của những người để hồ sơ public, khớp với rules cho
// đọc activities của hồ sơ public. Buổi 3i trùng buổi Strava
// (duplicateOfActivityId) bị bỏ để một buổi không hiện hai lần. Đọc
// collection group activities theo startedAt rồi lọc, nên cursor gồm
// startedAt, uid và id buổi.
func (s *ActivityService) ClubRuns(ctx context.Context, cursor string, limit int) (ClubRunsPage, error) {
	if limit < 1 || limit > activityPageMax {
		return ClubRunsPage{}, invalidRequest()
	}
	var after *firestore.DocumentRef
	var afterStartedAt string
	if cursor != "" {
		parts := strings.SplitN(cursor, "|", 3)
		if len(parts) != 3 || parts[0] == "" || parts[1] == "" || parts[2] == "" {
			return ClubRunsPage{}, invalidRequest()
		}
		afterStartedAt = parts[0]
		after = s.db.Collection("users").Doc(parts[1]).Collection("activities").Doc(parts[2])
	}
	public, err := s.publicProfileUIDs(ctx)
	if err != nil {
		return ClubRunsPage{}, err
	}
	batch := min(max(limit*2, 20), 100)
	out := ClubRunsPage{Runs: make([]ClubRun, 0, limit)}
	for range clubRunsScanRounds {
		q := s.db.CollectionGroup("activities").Select(activityListFields...).
			OrderBy("startedAt", firestore.Desc).
			OrderBy(firestore.DocumentID, firestore.Desc).
			Limit(batch)
		if after != nil {
			q = q.StartAfter(afterStartedAt, after)
		}
		docs, err := q.Documents(ctx).GetAll()
		if err != nil {
			return ClubRunsPage{}, err
		}
		for _, d := range docs {
			data := d.Data()
			afterStartedAt, after = stringValue(data["startedAt"]), d.Ref
			owner := d.Ref.Parent.Parent
			if owner == nil || !public[owner.ID] || stringValue(data["duplicateOfActivityId"]) != "" {
				continue
			}
			out.Runs = append(out.Runs, ClubRun{OwnerUID: owner.ID, Activity: data})
			if len(out.Runs) == limit {
				out.Cursor = clubRunsCursor(afterStartedAt, after)
				return out, nil
			}
		}
		if len(docs) < batch {
			return out, nil
		}
	}
	out.Cursor = clubRunsCursor(afterStartedAt, after)
	return out, nil
}

func clubRunsCursor(startedAt string, ref *firestore.DocumentRef) string {
	return startedAt + "|" + ref.Parent.Parent.ID + "|" + ref.ID
}

func (s *ActivityService) publicProfileUIDs(ctx context.Context) (map[string]bool, error) {
	docs, err := s.db.Collection("publicProfiles").
		Where("profileVisibility", "==", "public").
		Select().
		Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	uids := make(map[string]bool, len(docs))
	for _, d := range docs {
		uids[d.Ref.ID] = true
	}
	return uids, nil
}
