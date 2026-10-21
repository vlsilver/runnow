package backend

import (
	"context"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// deleteAgentReports gỡ báo cáo và danh sách chặn của uid trong phòng bot:
// báo cáo họ gửi hay bị gửi, agentBlocks/{uid}, và uid trong danh sách chặn
// của người khác. Cùng cách B7 làm với chatReports và gameBlocks của Ma Sói.
// Chạy lại bao nhiêu lần cũng ra cùng kết quả.
func (s *AccountService) deleteAgentReports(ctx context.Context, uid string) error {
	reports := s.db.Collection("agentRooms").Doc(agentMainRoom).Collection("reports")
	for _, query := range []firestore.Query{reports.Where("author", "==", uid), reports.Where("reporter", "==", uid)} {
		if err := s.deleteQuery(ctx, query); err != nil {
			return err
		}
	}
	if _, err := s.db.Collection("agentBlocks").Doc(uid).Delete(ctx); err != nil && status.Code(err) != codes.NotFound {
		return err
	}
	docs, err := s.db.Collection("agentBlocks").Where("uids", "array-contains", uid).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	for _, doc := range docs {
		if _, err := doc.Ref.Update(ctx, []firestore.Update{{Path: "uids", Value: firestore.ArrayRemove(uid)}}); err != nil && status.Code(err) != codes.NotFound {
			return err
		}
	}
	return nil
}
