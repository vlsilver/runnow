package backend

import (
	"context"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// agentRoomRefs là mọi phòng bot đang có trong Firestore, kể cả phòng chỉ còn
// subcollection mà không có doc phòng (DocumentRefs đọc cả doc "missing").
// Liệt kê agentRooms thay vì query CollectionGroup("messages"): tên messages
// còn dùng ở coach chat, query theo uid trên cả nhóm thì có thể xoá nhầm tin
// không thuộc phòng bot, và phải thêm index phạm vi collection group mới chạy.
// Số phòng chỉ vài cái nên một lượt ListDocuments là đủ. Không dựa vào
// agentRoomChannels, để phòng đã bỏ khỏi code mà còn dữ liệu vẫn được dọn.
func (s *AccountService) agentRoomRefs(ctx context.Context) ([]*firestore.DocumentRef, error) {
	return s.db.Collection("agentRooms").DocumentRefs(ctx).GetAll()
}

// deleteAgentReports gỡ báo cáo và danh sách chặn của uid trong phòng bot:
// báo cáo họ gửi hay bị gửi ở mọi phòng, agentBlocks/{uid}, và uid trong danh
// sách chặn của người khác. Cùng cách B7 làm với chatReports và gameBlocks của
// Ma Sói. Chạy lại bao nhiêu lần cũng ra cùng kết quả.
func (s *AccountService) deleteAgentReports(ctx context.Context, uid string) error {
	rooms, err := s.agentRoomRefs(ctx)
	if err != nil {
		return err
	}
	for _, room := range rooms {
		reports := room.Collection("reports")
		for _, query := range []firestore.Query{reports.Where("author", "==", uid), reports.Where("reporter", "==", uid)} {
			if err := s.deleteQuery(ctx, query); err != nil {
				return err
			}
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
