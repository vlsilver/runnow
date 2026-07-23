package backend

import (
	"context"
	"errors"
	"fmt"
	"log/slog"

	"cloud.google.com/go/firestore"
	gcs "cloud.google.com/go/storage"
	"firebase.google.com/go/v4/auth"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// AccountService xoá vĩnh viễn một tài khoản cùng toàn bộ dữ liệu của nó.
//
// Google Play và App Store đều bắt buộc app cho tạo tài khoản phải cho xoá
// tài khoản, và phải xoá thật chứ không chỉ đánh dấu. Client không tự làm
// được: Firestore không xoá subcollection theo document cha, và app không có
// quyền gỡ chính user khỏi Firebase Auth sau khi vừa xoá dữ liệu.
type AccountService struct {
	db      *firestore.Client
	auth    *auth.Client
	oauth   *OAuthService
	storage *gcs.BucketHandle
}

func NewAccountService(db *firestore.Client, authClient *auth.Client, oauth *OAuthService, bucket *gcs.BucketHandle) *AccountService {
	return &AccountService{db: db, auth: authClient, oauth: oauth, storage: bucket}
}

// Delete gỡ sạch dấu vết của uid.
//
// Thứ tự có chủ đích: thu hồi Strava trước (cần access token, mà token nằm
// trong dữ liệu sắp xoá), rồi tới dữ liệu, và Firebase Auth user sau cùng.
// Nếu đứt giữa chừng, tài khoản vẫn đăng nhập được để bấm xoá lại — mọi
// bước đều idempotent. Làm ngược lại sẽ để user mồ côi dữ liệu không ai
// dọn được.
func (s *AccountService) Delete(ctx context.Context, uid string) error {
	if uid == "" {
		return invalidRequest()
	}
	athleteID := s.stravaAthleteID(ctx, uid)

	// Lỗi phía Strava không được chặn việc xoá: user đã yêu cầu xoá thì phải
	// xoá được, kể cả khi Strava đang sập. Token vẫn bị xoá cùng Firestore
	// ngay bên dưới, và user có thể tự gỡ quyền tại strava.com/settings/apps.
	if err := s.oauth.Disconnect(ctx, uid); err != nil {
		slog.WarnContext(ctx, "account.delete.strava_revoke_failed", "uid", uid, "error", err)
	}

	if err := s.deleteStorage(ctx, uid); err != nil {
		return fmt.Errorf("delete storage: %w", err)
	}
	if err := s.leaveRunContracts(ctx, uid); err != nil {
		return fmt.Errorf("leave run contracts: %w", err)
	}
	if err := s.deleteOwnedDocuments(ctx, uid, athleteID); err != nil {
		return fmt.Errorf("delete documents: %w", err)
	}
	// Dọn cả users/{uid} lẫn mọi subcollection bên dưới (activities, stats,
	// periodStats, trainingGoalHistory, runContractActivityClaims) —
	// subcollection không tự mất khi xoá document cha.
	if err := s.deleteDocumentTree(ctx, s.db.Collection("users").Doc(uid)); err != nil {
		return fmt.Errorf("delete user tree: %w", err)
	}

	if err := s.auth.DeleteUser(ctx, uid); err != nil && !auth.IsUserNotFound(err) {
		return fmt.Errorf("delete auth user: %w", err)
	}
	slog.InfoContext(ctx, "account.delete.completed", "uid", uid)
	return nil
}

func (s *AccountService) stravaAthleteID(ctx context.Context, uid string) string {
	snap, err := s.db.Collection("stravaConnections").Doc(uid).Get(ctx)
	if err != nil {
		return ""
	}
	return stringValue(snap.Data()["athleteId"])
}

// deleteStorage xoá ảnh buổi chạy và ảnh đại diện. Tất cả nằm dưới cùng một
// prefix users/{uid}/ (xem storage.rules), nên một vòng quét prefix là đủ.
func (s *AccountService) deleteStorage(ctx context.Context, uid string) error {
	if s.storage == nil {
		return nil
	}
	it := s.storage.Objects(ctx, &gcs.Query{Prefix: "users/" + uid + "/"})
	for {
		attrs, err := it.Next()
		if errors.Is(err, iterator.Done) {
			return nil
		}
		if err != nil {
			return err
		}
		if err := s.storage.Object(attrs.Name).Delete(ctx); err != nil && !errors.Is(err, gcs.ErrObjectNotExist) {
			return err
		}
	}
}

// leaveRunContracts gỡ user khỏi các kèo đã tham gia.
//
// Kèo là dữ liệu chung: xoá thẳng một kèo còn người khác đang chạy sẽ phá
// dữ liệu của họ. Nên chỉ rút user ra, và chỉ xoá hẳn khi kèo không còn ai.
func (s *AccountService) leaveRunContracts(ctx context.Context, uid string) error {
	docs, err := s.db.Collection("runContracts").Where("participantUids", "array-contains", uid).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	for _, doc := range docs {
		if remainingParticipants(doc.Data(), uid) == 0 {
			if err := s.deleteDocumentTree(ctx, doc.Ref); err != nil {
				return err
			}
			continue
		}
		_, err := doc.Ref.Update(ctx, []firestore.Update{
			{Path: "participantUids", Value: firestore.ArrayRemove(uid)},
			{FieldPath: firestore.FieldPath{"participants", uid}, Value: firestore.Delete},
			{Path: "updatedAt", Value: firestore.ServerTimestamp},
		})
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
	}
	return nil
}

// remainingParticipants đếm số người còn lại trong kèo sau khi gỡ uid ra.
//
// Đọc từ participantUids vì đó là field các truy vấn kèo đang dùng
// (array-contains). Trả về 0 nghĩa là kèo không còn ai và xoá được.
func remainingParticipants(contract map[string]any, uid string) int {
	uids, ok := contract["participantUids"].([]any)
	if !ok {
		return 0
	}
	remaining := 0
	for _, value := range uids {
		if stringValue(value) != uid {
			remaining++
		}
	}
	return remaining
}

func (s *AccountService) deleteOwnedDocuments(ctx context.Context, uid, athleteID string) error {
	refs := []*firestore.DocumentRef{
		s.db.Collection("publicProfiles").Doc(uid),
		s.db.Collection("leaderboardEntries").Doc(uid),
		s.db.Collection("stravaConnections").Doc(uid),
	}
	if athleteID != "" {
		refs = append(refs, s.db.Collection("stravaAthleteLinks").Doc(athleteID))
	}
	for _, ref := range refs {
		if _, err := ref.Delete(ctx); err != nil && status.Code(err) != codes.NotFound {
			return err
		}
	}

	queries := []firestore.Query{
		s.db.Collection("feedPosts").Where("authorUid", "==", uid),
		s.db.Collection("liveSessions").Where("ownerUid", "==", uid),
		s.db.Collection("activityTombstones").Where("uid", "==", uid),
	}
	if athleteID != "" {
		queries = append(queries, s.db.Collection("integrationEvents").Where("ownerId", "==", athleteID))
	}
	for _, query := range queries {
		if err := s.deleteQuery(ctx, query); err != nil {
			return err
		}
	}
	return nil
}

// deleteDocumentTree xoá một document cùng toàn bộ subcollection bên dưới.
//
// SDK Go không có RecursiveDelete (chỉ Node và Python có), nên phải tự đi
// xuống từng nhánh. Bỏ qua bước này thì subcollection thành dữ liệu mồ côi:
// không còn document cha nên không ai truy ra, nhưng vẫn nằm nguyên trong
// Firestore — tức là chưa xoá thật.
func (s *AccountService) deleteDocumentTree(ctx context.Context, ref *firestore.DocumentRef) error {
	it := ref.Collections(ctx)
	for {
		collection, err := it.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return err
		}
		docs, err := collection.Documents(ctx).GetAll()
		if err != nil {
			return err
		}
		for _, doc := range docs {
			if err := s.deleteDocumentTree(ctx, doc.Ref); err != nil {
				return err
			}
		}
	}
	if _, err := ref.Delete(ctx); err != nil && status.Code(err) != codes.NotFound {
		return err
	}
	return nil
}

// deleteQuery xoá theo lô. Firestore giới hạn 500 thao tác mỗi batch, và
// BulkWriter lo phần chia lô lẫn retry.
func (s *AccountService) deleteQuery(ctx context.Context, query firestore.Query) error {
	docs, err := query.Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	if len(docs) == 0 {
		return nil
	}
	writer := s.db.BulkWriter(ctx)
	for _, doc := range docs {
		if _, err := writer.Delete(doc.Ref); err != nil {
			return err
		}
	}
	writer.End()
	return nil
}
