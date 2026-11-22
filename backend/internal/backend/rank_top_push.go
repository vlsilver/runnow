package backend

import (
	"context"
	"net/http"
	"strconv"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Push "lọt top 3": lúc chốt bảng tuần, tháng, mỗi người hạng 1–3 được báo
// riêng hạng của mình. Người có quà đã nhận push quà BXH (rank_reward), trong
// đó đã nói họ thắng, nên bỏ qua để không nhận hai push cho một bảng. Mỗi người
// một task, nên Cloud Tasks gửi lại một người không làm người khác nhận hai lần.
const (
	rankTopPushPath = "/tasks/rank-top-push"
	rankTopPushKind = "rank_top"
	rankTopPushMax  = 3
)

type rankTopPushTask struct {
	BoardID string `json:"boardId"`
	UID     string `json:"uid"`
}

// rankTopPushUIDs là người cần push top 3 của một bảng: hạng 1–3 và không có quà.
func rankTopPushUIDs(entries []map[string]any) []string {
	var uids []string
	for _, e := range entries {
		if int(number(e["rank"])) <= rankTopPushMax && e["reward"] == nil {
			uids = append(uids, stringValue(e["uid"]))
		}
	}
	return uids
}

func rankSportWord(sport rankSport) string {
	switch sport {
	case rankSteps:
		return "bước chân"
	case rankBike:
		return "đạp xe"
	default:
		return "chạy bộ"
	}
}

// DeliverRankTopPush đọc lại bảng lúc gửi: người không còn ở hạng 1–3 hay đã có
// quà thì thôi.
func DeliverRankTopPush(ctx context.Context, db *firestore.Client, push *PushService, t rankTopPushTask) error {
	off, err := pushKindOff(ctx, db, rankTopPushKind)
	if err != nil || off {
		return err
	}
	key, ok := parseRankBoardID(t.BoardID)
	if !ok {
		return nil
	}
	board, err := db.Collection("rankBoards").Doc(t.BoardID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	for _, raw := range anyList(board.Data()["entries"]) {
		e, _ := raw.(map[string]any)
		if stringValue(e["uid"]) != t.UID {
			continue
		}
		rank := int(number(e["rank"]))
		if rank > rankTopPushMax || e["reward"] != nil {
			return nil
		}
		return push.Send(ctx, []string{t.UID}, pushNote{
			Title: "Bạn hạng " + strconv.Itoa(rank) + " BXH " + rankPeriodWord(key.r) + " " + rankSportWord(key.sport),
			Body:  "Mở thẻ hạng để xem và khoe với mọi người.",
			Data:  map[string]string{"kind": rankTopPushKind, "boardId": t.BoardID},
		})
	}
	return nil
}

func (s *Server) rankTopPush(w http.ResponseWriter, r *http.Request) error {
	var task rankTopPushTask
	if decodeJSON(r, &task) != nil || task.BoardID == "" || task.UID == "" || s.deps.Push == nil {
		w.WriteHeader(204)
		return nil
	}
	if err := DeliverRankTopPush(r.Context(), s.deps.Firestore, s.deps.Push, task); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
