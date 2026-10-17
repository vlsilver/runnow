package backend

import (
	"context"
	"fmt"
	"log/slog"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Báo cáo và chặn trong chat phe (App Store 1.2). Báo cáo ghi vào
// games/{id}/chatReports để admin tra lại, và DM admin ngay để xử lý trong ngày.
// Chặn giữ ở gameBlocks/{uid}, dùng cho mọi ván: tin chữ của người bị chặn trả
// về hidden với người chặn.

// ReportChat ghi báo cáo tin seq trong chat key và, nếu block, chặn người gửi.
// Trả chữ DM cho admin. Gọi lại với cùng tin thì ghi đè báo cáo cũ, nên người
// dùng bấm lại sau lỗi mạng không sinh báo cáo trùng.
func (s *GameStore) ReportChat(ctx context.Context, gameID, key string, seq int64, block bool, v GameViewer, wall time.Time) (string, error) {
	if seq < 1 {
		return "", invalidRequest()
	}
	cfg, err := s.loadConfig(ctx)
	if err != nil {
		return "", err
	}
	g, registered, err := s.readVisibleGame(ctx, gameID, cfg, v.UID)
	if err != nil {
		return "", err
	}
	if !registered {
		return "", errNotGamePlayer
	}
	st, err := s.loadState(ctx, g.Ref)
	if err != nil {
		return "", err
	}
	// Người đã chết vẫn đọc được chat nên vẫn báo cáo được.
	if member, _ := chatAccess(st, g.Data(), key, v.UID); !member {
		return "", errChatNotFound
	}
	d, err := chatRef(g.Ref, key).Collection("chatMessages").Doc(fmt.Sprintf("%010d", seq)).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", errChatNoMsg
	}
	if err != nil {
		return "", err
	}
	m := d.Data()
	author := stringValue(m["uid"])
	if stringValue(m["kind"]) != "text" || author == v.UID {
		return "", invalidRequest()
	}
	players, err := s.loadPlayers(ctx, g.Ref)
	if err != nil {
		return "", err
	}
	index := playerIndex(players)
	text := stringValue(m["text"])
	if _, err := g.Ref.Collection("chatReports").Doc(fmt.Sprintf("%s_%d_%s", key, seq, v.UID)).Set(ctx, map[string]any{
		"chatKey": key, "seq": seq, "author": author, "reporter": v.UID, "text": text, "block": block, "at": wall,
	}); err != nil {
		return "", err
	}
	note := ""
	if block {
		if _, err := s.blocksRef(v.UID).Set(ctx, map[string]any{"uids": firestore.ArrayUnion(author), "updatedAt": wall}, firestore.MergeAll); err != nil {
			return "", err
		}
		note = " và chặn người này"
	}
	return fmt.Sprintf("Báo cáo chat Ma Sói: %s báo cáo tin của %s%s.\nVán %s, chat %s, tin #%d (author %s):\n\n%s",
		index[v.UID].name, index[author].name, note, gameID, chatLabels[key], seq, author, text), nil
}

func (s *GameStore) blocksRef(uid string) *firestore.DocumentRef {
	return s.db.Collection("gameBlocks").Doc(uid)
}

// blockedBy là những uid mà uid đã chặn.
func (s *GameStore) blockedBy(ctx context.Context, uid string) (map[string]bool, error) {
	d, err := s.blocksRef(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	out := map[string]bool{}
	for _, v := range anyList(d.Data()["uids"]) {
		out[stringValue(v)] = true
	}
	return out, nil
}

// alertChatReport DM báo cáo cho admin đã liên kết. Báo cáo đã nằm trong
// Firestore; DM lỗi thì trả lỗi để người dùng bấm lại, vì admin cần biết trong ngày.
func (s *Server) alertChatReport(ctx context.Context, text string) error {
	tg := s.deps.Telegram
	if tg == nil || !tg.Enabled() {
		slog.WarnContext(ctx, "game.chat_report_no_telegram")
		return nil
	}
	chats, err := s.deps.Games.adminChats(ctx)
	if err != nil {
		return err
	}
	if len(chats) == 0 {
		slog.WarnContext(ctx, "game.chat_report_no_admin")
		return nil
	}
	return sendToAny(ctx, tg, chats, []string{text})
}
