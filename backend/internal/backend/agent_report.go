package backend

import (
	"context"
	"fmt"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Báo cáo và chặn trong phòng bot (App Store 1.2), cùng khuôn với chat phe Ma
// Sói (game_chat_report.go):
//
//	agentRooms/{room}/reports/{seq}_{reporter}  báo cáo, bấm lại thì ghi đè
//	agentBlocks/{uid}.uids                    những người uid đã chặn
//
// Danh sách chặn tách khỏi gameBlocks vì hai chỗ khác nhau về cách gỡ: phòng
// bot có màn bỏ chặn, Ma Sói thì không. Dùng chung thì bỏ chặn ở MyBot sẽ âm
// thầm bỏ luôn chặn trong Ma Sói. Thêm nữa, chặn có sẵn từ Ma Sói mà áp ngay
// vào phòng bot lúc deploy thì app 1.5.0, vốn chưa biết field hidden, sẽ vẽ
// bong bóng trống cho những tin đó.
//
// Chặn chỉ đổi những gì người chặn nhìn thấy. Bot của người bị chặn vẫn đọc
// đoạn chat và vẫn có thể được chọn nói, nhưng tin của nó bị ẩn với người chặn.
// Đổi cách chọn lượt theo từng cặp chặn thì phòng chung sẽ khác nhau với mỗi
// người, mà chưa có lý do cần tới mức đó.

var errAgentNoMessage = &HTTPError{Status: http.StatusNotFound, Code: "message_not_found", Message: "Không còn tin nhắn này."}

// AgentBlocked là một người trong danh sách chặn, để app vẽ màn bỏ chặn.
type AgentBlocked struct {
	UID  string `json:"uid"`
	Name string `json:"name"`
}

func (s *AgentStore) blocksRef(uid string) *firestore.DocumentRef {
	return s.db.Collection("agentBlocks").Doc(uid)
}

// blockedUIDs là những uid mà uid đã chặn, theo thứ tự chặn.
func (s *AgentStore) blockedUIDs(ctx context.Context, uid string) ([]string, error) {
	d, err := s.blocksRef(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var out []string
	for _, v := range anyList(d.Data()["uids"]) {
		if u := stringValue(v); u != "" {
			out = append(out, u)
		}
	}
	return out, nil
}

// ReportRoom ghi báo cáo tin seq trong phòng roomID và, nếu block, chặn người gửi.
// Tin của bot thì người bị báo cáo là chủ bot, vì uid trên tin là uid chủ; chặn
// thì ẩn cả người lẫn bot của họ. Trả chữ DM cho admin. Gọi lại với cùng tin
// thì ghi đè báo cáo cũ, nên bấm lại sau lỗi mạng không sinh báo cáo trùng.
func (s *AgentStore) ReportRoom(ctx context.Context, roomID, uid string, seq int64, block bool, wall time.Time) (string, error) {
	if seq < 1 {
		return "", invalidRequest()
	}
	if err := s.requireMember(ctx, uid); err != nil {
		return "", err
	}
	room := s.roomRef(roomID)
	d, err := room.Collection("messages").Doc(seqDocID(seq)).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", errAgentNoMessage
	}
	if err != nil {
		return "", err
	}
	m := d.Data()
	author, kind, text := stringValue(m["uid"]), stringValue(m["kind"]), stringValue(m["text"])
	// Tin của bot mình cũng là tin của mình: muốn bot nói khác thì sửa tính cách.
	if author == "" || author == uid {
		return "", invalidRequest()
	}
	report := map[string]any{"seq": seq, "kind": kind, "author": author, "reporter": uid, "text": text, "block": block, "at": wall}
	if kind == agentKindAgent {
		report["botName"] = stringValue(m["name"])
	}
	if _, err := room.Collection("reports").Doc(fmt.Sprintf("%s_%s", seqDocID(seq), uid)).Set(ctx, report); err != nil {
		return "", err
	}
	if block {
		if _, err := s.blocksRef(uid).Set(ctx, map[string]any{"uids": firestore.ArrayUnion(author), "updatedAt": wall}, firestore.MergeAll); err != nil {
			return "", err
		}
	}
	names, err := s.displayNames(ctx, []string{uid, author})
	if err != nil {
		return "", err
	}
	target := names[author]
	if kind == agentKindAgent {
		target = fmt.Sprintf("bot %s (của %s)", stringValue(m["name"]), names[author])
	}
	note := ""
	if block {
		note = fmt.Sprintf(" và chặn %s cùng bot của họ", names[author])
	}
	return fmt.Sprintf("Báo cáo phòng bot: %s báo cáo tin của %s%s.\nTin #%d (author %s, reporter %s):\n\n%s",
		names[uid], target, note, seq, author, uid, text), nil
}

// Blocks trả danh sách người uid đã chặn trong phòng bot, kèm tên hiện tại.
func (s *AgentStore) Blocks(ctx context.Context, uid string) ([]AgentBlocked, error) {
	if err := s.requireMember(ctx, uid); err != nil {
		return nil, err
	}
	uids, err := s.blockedUIDs(ctx, uid)
	if err != nil {
		return nil, err
	}
	names, err := s.displayNames(ctx, uids)
	if err != nil {
		return nil, err
	}
	out := make([]AgentBlocked, 0, len(uids))
	for _, u := range uids {
		out = append(out, AgentBlocked{UID: u, Name: names[u]})
	}
	return out, nil
}

// Unblock bỏ chặn other. Chưa từng chặn thì coi như xong, để bấm lại không báo lỗi.
func (s *AgentStore) Unblock(ctx context.Context, uid, other string, wall time.Time) error {
	if other == "" {
		return invalidRequest()
	}
	if err := s.requireMember(ctx, uid); err != nil {
		return err
	}
	_, err := s.blocksRef(uid).Update(ctx, []firestore.Update{{Path: "uids", Value: firestore.ArrayRemove(other)}, {Path: "updatedAt", Value: wall}})
	if status.Code(err) == codes.NotFound {
		return nil
	}
	return err
}
