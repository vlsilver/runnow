package backend

import (
	"context"
	"net/http"
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

// Share khoe thẻ của buổi activityID với club.
func (s *RunCardStore) Share(ctx context.Context, uid, activityID string) (map[string]any, error) {
	doc, err := s.share(ctx, s.cardRef(uid, activityID), s.clubCardRef(uid, activityID), errRunCardNoCard,
		func(card map[string]any, sharedAt time.Time) (map[string]any, error) {
			return clubCardDoc(uid, activityID, card, sharedAt), nil
		})
	if err != nil {
		return nil, err
	}
	out := runCardJSON(activityID, doc)
	out["sharedAt"] = doc["sharedAt"].(time.Time).UTC().Format(time.RFC3339Nano)
	return out, nil
}

// share chép thẻ ở source sang thẻ khoe ref, trả doc đã ghi; chưa có thẻ thì
// trả notFound. Khoe lại thì chép lại mặt thẻ nhưng giữ giờ khoe đầu, để app
// gửi lại không đẩy thẻ lên đầu mục.
func (s *RunCardStore) share(ctx context.Context, source, ref *firestore.DocumentRef, notFound error, build func(card map[string]any, sharedAt time.Time) (map[string]any, error)) (map[string]any, error) {
	var doc map[string]any
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		card, err := getOptional(tx, source)
		if err != nil {
			return err
		}
		if !card.Exists() {
			return notFound
		}
		shared, err := getOptional(tx, ref)
		if err != nil {
			return err
		}
		sharedAt := s.now()
		if t, ok := shared.Data()["sharedAt"].(time.Time); ok {
			sharedAt = t
		}
		doc, err = build(card.Data(), sharedAt)
		if err != nil {
			return err
		}
		return tx.Set(ref, doc)
	})
	return doc, err
}

// Thẻ Ma Sói và Hành trình khoe chung clubCards, id {uid}_{kind}_{id} và có
// field kind; thẻ buổi chạy không có kind vì app 1.7.0 chỉ biết loại đó. Id
// buổi chạy không bắt đầu bằng game_ hay journey_, mà có trùng thì cũng chỉ
// đụng thẻ của chính chủ vì id bắt đầu bằng uid. Hai loại này không có gì
// riêng tư nhưng vẫn chép theo danh sách field như thẻ buổi chạy.
var keptCardKinds = map[string]struct {
	collection string
	keys       []string
}{
	"game":    {"gameCards", []string{"gameId", "tier", "role", "team", "winner", "alive", "rounds", "playerCount", "endedAt", "deathRound", "variant"}},
	"journey": {"journeyCards", []string{"campaign", "routeId", "level", "tier", "distanceMeters", "runCount", "finishedAt"}},
}

var (
	errKeptCardNotFound = &HTTPError{Status: http.StatusNotFound, Code: "card_not_found", Message: "Bạn chưa có thẻ này."}
	errKeptCardTestMode = &HTTPError{Status: http.StatusConflict, Code: "card_test_mode", Message: "Thẻ của ván thử không khoe được."}
)

func (s *RunCardStore) keptClubCardRef(uid, kind, id string) *firestore.DocumentRef {
	return s.db.Collection("clubCards").Doc(uid + "_" + kind + "_" + id)
}

// ShareKept khoe thẻ Ma Sói (kind game) hay Hành trình (kind journey) với
// club. Thẻ của ván thử thì không.
func (s *RunCardStore) ShareKept(ctx context.Context, uid, kind, id string) error {
	spec, ok := keptCardKinds[kind]
	if !ok {
		return invalidRequest()
	}
	source := s.db.Collection("users").Doc(uid).Collection(spec.collection).Doc(id)
	_, err := s.share(ctx, source, s.keptClubCardRef(uid, kind, id), errKeptCardNotFound,
		func(card map[string]any, sharedAt time.Time) (map[string]any, error) {
			if card["testMode"] == true {
				return nil, errKeptCardTestMode
			}
			doc := map[string]any{"kind": kind, "ownerUid": uid, "sharedAt": sharedAt}
			for _, k := range spec.keys {
				if v, ok := card[k]; ok {
					doc[k] = v
				}
			}
			return doc, nil
		})
	return err
}

// UnshareKept thôi khoe thẻ Ma Sói hay Hành trình; gọi lại vẫn trả nil.
func (s *RunCardStore) UnshareKept(ctx context.Context, uid, kind, id string) error {
	if _, ok := keptCardKinds[kind]; !ok {
		return invalidRequest()
	}
	_, err := s.keptClubCardRef(uid, kind, id).Delete(ctx)
	return err
}

// Unshare thôi khoe thẻ. Firestore xoá doc không có vẫn thành công, nên gọi
// lại hay chưa khoe đều trả nil.
func (s *RunCardStore) Unshare(ctx context.Context, uid, activityID string) error {
	_, err := s.clubCardRef(uid, activityID).Delete(ctx)
	return err
}
