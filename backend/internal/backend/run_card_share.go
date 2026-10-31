package backend

import (
	"context"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Thẻ khoe với club nằm ở clubCards/{uid}_{activityId}, cùng dạng doc thẻ để
// app vẽ được bằng một khuôn. Ai đăng nhập cũng đọc được nên chỉ chép mặt thẻ:
// không có đường chạy (lộ chỗ ở) và nhịp tim. Tranh không chép: storage rule
// mở art-*.png của thẻ khi doc khoe còn.
//
// Thẻ tự lên club khi chủ để hồ sơ công khai, giống feed buổi chạy của club:
// lật thẻ và ván Ma Sói kết thúc thì ghi thẻ khoe trong cùng transaction,
// SyncClub khoe bù thẻ còn thiếu và gỡ thẻ của người chuyển sang riêng tư.

// publicProfile là hồ sơ (publicProfiles/{uid}) để công khai; thiếu field thì
// là riêng tư.
func publicProfile(data map[string]any) bool {
	return stringValue(data["profileVisibility"]) == "public"
}

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
	// at là field giờ có thẻ, theo thứ tự ưu tiên; khoe bù lấy giờ đó làm giờ
	// khoe để thẻ cũ không nhảy lên đầu mục.
	at []string
}{
	"game":    {"gameCards", []string{"gameId", "tier", "role", "team", "winner", "alive", "rounds", "playerCount", "endedAt", "deathRound", "variant"}, []string{"endedAt"}},
	"journey": {"journeyCards", []string{"campaign", "routeId", "level", "tier", "distanceMeters", "runCount", "finishedAt"}, []string{"awardedAt", "finishedAt"}},
}

var (
	errKeptCardNotFound = &HTTPError{Status: http.StatusNotFound, Code: "card_not_found", Message: "Bạn chưa có thẻ này."}
	errKeptCardTestMode = &HTTPError{Status: http.StatusConflict, Code: "card_test_mode", Message: "Thẻ của ván thử không khoe được."}
)

func keptClubCardID(uid, kind, id string) string { return uid + "_" + kind + "_" + id }

func (s *RunCardStore) keptClubCardRef(uid, kind, id string) *firestore.DocumentRef {
	return s.db.Collection("clubCards").Doc(keptClubCardID(uid, kind, id))
}

// keptClubCardDoc là thẻ khoe của thẻ Ma Sói hay Hành trình: chỉ chép
// các field trong danh sách của kind.
func keptClubCardDoc(kind, uid string, card map[string]any, sharedAt time.Time) map[string]any {
	doc := map[string]any{"kind": kind, "ownerUid": uid, "sharedAt": sharedAt}
	for _, k := range keptCardKinds[kind].keys {
		if v, ok := card[k]; ok {
			doc[k] = v
		}
	}
	return doc
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
			return keptClubCardDoc(kind, uid, card, sharedAt), nil
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

// SyncClub cho thẻ khoe của uid khớp chế độ hồ sơ. Công khai thì khoe mọi thẻ
// chưa khoe (trừ thẻ ván thử), giờ khoe là giờ có thẻ; riêng tư thì gỡ hết.
// Thẻ đã khoe giữ nguyên. Chạy lại bao nhiêu lần cũng được.
func (s *RunCardStore) SyncClub(ctx context.Context, uid string) error {
	profile, err := s.db.Collection("publicProfiles").Doc(uid).Get(ctx)
	if err != nil && status.Code(err) != codes.NotFound {
		return err
	}
	shared, err := s.db.Collection("clubCards").Where("ownerUid", "==", uid).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	if !profile.Exists() || !publicProfile(profile.Data()) {
		for _, doc := range shared {
			if _, err := doc.Ref.Delete(ctx); err != nil {
				return err
			}
		}
		return nil
	}
	have := map[string]bool{}
	for _, doc := range shared {
		have[doc.Ref.ID] = true
	}
	// Create chứ không Set: thẻ vừa khoe lúc lật trong lúc này thì giữ bản đó.
	create := func(ref *firestore.DocumentRef, doc map[string]any) error {
		if have[ref.ID] {
			return nil
		}
		if _, err := ref.Create(ctx, doc); err != nil && status.Code(err) != codes.AlreadyExists {
			return err
		}
		return nil
	}
	user := s.db.Collection("users").Doc(uid)
	runs, err := user.Collection("runCards").Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	for _, doc := range runs {
		card := doc.Data()
		at, _ := card["rolledAt"].(time.Time)
		if err := create(s.clubCardRef(uid, doc.Ref.ID), clubCardDoc(uid, doc.Ref.ID, card, at)); err != nil {
			return err
		}
	}
	for kind, spec := range keptCardKinds {
		docs, err := user.Collection(spec.collection).Documents(ctx).GetAll()
		if err != nil {
			return err
		}
		for _, doc := range docs {
			card := doc.Data()
			if card["testMode"] == true {
				continue
			}
			at := s.now()
			for _, k := range spec.at {
				if t, ok := card[k].(time.Time); ok {
					at = t
					break
				}
			}
			if err := create(s.keptClubCardRef(uid, kind, doc.Ref.ID), keptClubCardDoc(kind, uid, card, at)); err != nil {
				return err
			}
		}
	}
	return nil
}

// Unshare thôi khoe thẻ. Firestore xoá doc không có vẫn thành công, nên gọi
// lại hay chưa khoe đều trả nil.
func (s *RunCardStore) Unshare(ctx context.Context, uid, activityID string) error {
	_, err := s.clubCardRef(uid, activityID).Delete(ctx)
	return err
}
