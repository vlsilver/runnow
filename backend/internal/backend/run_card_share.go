package backend

import (
	"context"
	"time"

	"cloud.google.com/go/firestore"
)

// Thẻ khoe với club nằm ở clubCards/{uid}_{activityId}, cùng dạng doc thẻ để
// app vẽ được bằng một khuôn. Ai đăng nhập cũng đọc được nên chỉ chép mặt thẻ:
// không có đường chạy (lộ chỗ ở) và nhịp tim. Tranh không chép: storage rule
// mở art-*.png của thẻ khi doc khoe còn.

// clubCardSnapshotKeys là những field snapshot được khoe. Liệt kê field được
// phép chứ không liệt kê field cấm, để field mới thêm vào snapshot không tự lộ.
var clubCardSnapshotKeys = []string{"name", "sportType", "source", "startedAt", "distanceMeters", "movingTimeSeconds", "elapsedTimeSeconds", "elevationGainMeters", "splits"}

func (s *RunCardStore) clubCardRef(uid, activityID string) *firestore.DocumentRef {
	return s.db.Collection("clubCards").Doc(uid + "_" + activityID)
}

// clubCardArt là phần tranh được khoe: chỉ tranh đã vẽ xong.
func clubCardArt(art map[string]any) map[string]any {
	if stringValue(art["status"]) != "done" {
		return nil
	}
	return map[string]any{"status": "done", "path": art["path"]}
}

func clubCardDoc(uid, activityID string, card map[string]any, sharedAt time.Time) map[string]any {
	doc := map[string]any{"ownerUid": uid, "activityId": activityID, "sharedAt": sharedAt}
	for _, k := range []string{"tier", "km", "odds", "startedAt", "rolledAt", "variant"} {
		if v, ok := card[k]; ok {
			doc[k] = v
		}
	}
	snapshot, _ := card["snapshot"].(map[string]any)
	shown := map[string]any{}
	for _, k := range clubCardSnapshotKeys {
		if v, ok := snapshot[k]; ok {
			shown[k] = v
		}
	}
	doc["snapshot"] = shown
	if art, _ := card["art"].(map[string]any); clubCardArt(art) != nil {
		doc["art"] = clubCardArt(art)
	}
	return doc
}

// Share khoe thẻ của buổi activityID với club. Khoe lại thì chép lại mặt thẻ
// nhưng giữ giờ khoe đầu, để app gửi lại không đẩy thẻ lên đầu mục.
func (s *RunCardStore) Share(ctx context.Context, uid, activityID string) (map[string]any, error) {
	ref := s.clubCardRef(uid, activityID)
	var doc map[string]any
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		card, err := getOptional(tx, s.cardRef(uid, activityID))
		if err != nil {
			return err
		}
		if !card.Exists() {
			return errRunCardNoCard
		}
		shared, err := getOptional(tx, ref)
		if err != nil {
			return err
		}
		sharedAt := s.now()
		if t, ok := shared.Data()["sharedAt"].(time.Time); ok {
			sharedAt = t
		}
		doc = clubCardDoc(uid, activityID, card.Data(), sharedAt)
		return tx.Set(ref, doc)
	})
	if err != nil {
		return nil, err
	}
	out := runCardJSON(activityID, doc)
	out["sharedAt"] = doc["sharedAt"].(time.Time).UTC().Format(time.RFC3339Nano)
	return out, nil
}

// Unshare thôi khoe thẻ. Firestore xoá doc không có vẫn thành công, nên gọi
// lại hay chưa khoe đều trả nil.
func (s *RunCardStore) Unshare(ctx context.Context, uid, activityID string) error {
	_, err := s.clubCardRef(uid, activityID).Delete(ctx)
	return err
}
