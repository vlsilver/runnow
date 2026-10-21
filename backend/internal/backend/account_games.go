package backend

import (
	"context"
	"fmt"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// deleteGameData gỡ dữ liệu Ma Sói của uid: chỗ của họ trong từng ván, tin
// chat phe, báo cáo tin nhắn và danh sách chặn. Chạy lại bao nhiêu lần cũng ra
// cùng kết quả.
//
// Ván là dữ liệu chung như kèo. Ván đang đăng ký thì rút hẳn ra như tự huỷ
// đăng ký. Ván đã bắt đầu thì giữ players/{uid}, vì state, events và feed của
// cả ván đều trỏ tới uid này: readLeft cần doc còn đó (thiếu thì cả ván dừng),
// và bỏ tgUserId là đủ để R33 tính họ đã rời PSC ở mốc chốt kế tiếp. Uid còn
// lại trong lịch sử ván không còn trỏ tới ai sau khi Auth user bị xoá.
func (s *AccountService) deleteGameData(ctx context.Context, uid string) error {
	// Mỗi lúc chỉ có một ván mở, cả lịch sử chỉ vài chục ván, nên đọc hết rồi
	// tra players/{uid} một lượt rẻ hơn thêm index collection group.
	games, err := s.db.Collection("games").Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	if len(games) > 0 {
		refs := make([]*firestore.DocumentRef, len(games))
		for i, g := range games {
			refs[i] = g.Ref.Collection("players").Doc(uid)
		}
		players, err := s.db.GetAll(ctx, refs)
		if err != nil {
			return err
		}
		for i, p := range players {
			if !p.Exists() {
				continue
			}
			if err := s.leaveGame(ctx, games[i].Ref, uid); err != nil {
				return fmt.Errorf("game %s: %w", games[i].Ref.ID, err)
			}
		}
	}
	return s.deleteGameBlocks(ctx, uid)
}

func (s *AccountService) leaveGame(ctx context.Context, game *firestore.DocumentRef, uid string) error {
	removed, err := s.unregisterPlayer(ctx, game, uid)
	if err != nil {
		return err
	}
	if !removed {
		_, err := game.Collection("players").Doc(uid).Update(ctx, []firestore.Update{
			{Path: "name", Value: firestore.Delete},
			{Path: "tgUserId", Value: firestore.Delete},
		})
		// RunStart có thể vừa loại người chưa liên kết và xoá doc.
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
	}

	snap, err := game.Get(ctx)
	if err != nil {
		return err
	}
	if gameClosed(stringValue(snap.Data()["status"])) {
		// km theo giờ là dữ liệu sức khoẻ. Ván đang chạy thì để yên: engine chụp
		// km của vòng rồi mới đọc lại lúc chốt, xoá chen giữa thì bước chốt hỏng.
		// rounds/{n} chưa bao giờ được ghi nên phải duyệt cả doc "missing".
		rounds, err := game.Collection("rounds").DocumentRefs(ctx).GetAll()
		if err != nil {
			return err
		}
		for _, round := range rounds {
			if _, err := round.Collection("km").Doc(uid).Delete(ctx); err != nil && status.Code(err) != codes.NotFound {
				return err
			}
		}
	}

	chats, err := game.Collection("chats").DocumentRefs(ctx).GetAll()
	if err != nil {
		return err
	}
	queries := []firestore.Query{
		game.Collection("chatReports").Where("author", "==", uid),
		game.Collection("chatReports").Where("reporter", "==", uid),
	}
	for _, chat := range chats {
		queries = append(queries, chat.Collection("chatMessages").Where("uid", "==", uid))
	}
	for _, query := range queries {
		if err := s.deleteQuery(ctx, query); err != nil {
			return err
		}
	}
	return nil
}

// unregisterPlayer rút uid khỏi ván còn đang đăng ký, cùng cách
// GameStore.Unregister đếm lại playerCount. removed=false khi ván đã qua bước
// đăng ký hoặc uid không có trong ván.
func (s *AccountService) unregisterPlayer(ctx context.Context, game *firestore.DocumentRef, uid string) (bool, error) {
	removed := false
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		removed = false
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		if stringValue(g.Data()["status"]) != gameRegistering {
			return nil
		}
		players, err := tx.Documents(game.Collection("players")).GetAll()
		if err != nil {
			return err
		}
		count := len(players)
		for _, p := range players {
			if p.Ref.ID != uid {
				continue
			}
			if err := tx.Delete(p.Ref); err != nil {
				return err
			}
			removed = true
			count--
		}
		if !removed {
			return nil
		}
		return tx.Update(game, []firestore.Update{
			{Path: "playerCount", Value: count},
			{Path: "updatedAt", Value: firestore.ServerTimestamp},
		})
	})
	return removed, err
}

// deleteGameBlocks xoá danh sách chặn của uid và gỡ uid khỏi danh sách chặn
// của người khác (gameBlocks/{người chặn}.uids).
func (s *AccountService) deleteGameBlocks(ctx context.Context, uid string) error {
	if _, err := s.db.Collection("gameBlocks").Doc(uid).Delete(ctx); err != nil && status.Code(err) != codes.NotFound {
		return err
	}
	docs, err := s.db.Collection("gameBlocks").Where("uids", "array-contains", uid).Documents(ctx).GetAll()
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
