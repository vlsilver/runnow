package backend

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
)

// Push của ván Ma Sói chỉ có một loại: ván đã bắt đầu. Các bước trong ván do
// Telegram nhắc, thêm push từng bước thì mỗi người nhận hai lần.
const (
	gamePushStarted = "game_started"
	gamePushPath    = "/tasks/game-push"
)

type gamePushTask struct {
	Kind   string `json:"kind"`
	GameID string `json:"gameId"`
}

func gamePushTaskFor(kind, gameID string) PublishTask {
	t := gamePushTask{Kind: kind, GameID: gameID}
	return PublishTask{Queue: QueueNotify, HandlerPath: gamePushPath, Payload: t, TaskID: StableTaskID("game-push", t)}
}

// DeliverPush đọc ván lúc gửi: ván đã huỷ thì thôi, người bị loại lúc chia bài
// đã không còn trong players.
func (s *GameStore) DeliverPush(ctx context.Context, push *PushService, t gamePushTask) error {
	off, err := pushKindOff(ctx, s.db, t.Kind)
	if err != nil || off {
		return err
	}
	g, err := s.readStartGame(ctx, t.GameID)
	if errors.Is(err, errGameNotFound) {
		return nil
	}
	if err != nil {
		return err
	}
	if stringValue(g.Data()["status"]) != gameRunning {
		return nil
	}
	players, err := g.Ref.Collection("players").Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	uids := make([]string, 0, len(players))
	for _, p := range players {
		uids = append(uids, p.Ref.ID)
	}
	return push.Send(ctx, uids, pushNote{
		Title: gameTitle,
		Body:  "Ván đã bắt đầu. Vào xem lá bài của bạn.",
		Data:  map[string]string{"kind": t.Kind, "gameId": t.GameID},
	})
}

func (s *Server) gamePush(w http.ResponseWriter, r *http.Request) error {
	var task gamePushTask
	if decodeJSON(r, &task) != nil || task.Kind == "" || task.GameID == "" {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Games.DeliverPush(r.Context(), s.deps.Push, task); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// kickGamePush hẹn push sau khi ván đã chia bài. Hẹn hỏng thì chỉ log, không
// trả lỗi: ván đã chạy, trả lỗi chỉ làm task Start chạy lại mà không ích gì.
func (s *Server) kickGamePush(ctx context.Context, kind, gameID string) {
	publish := s.enqueueTask()
	if publish == nil {
		return
	}
	if _, err := publish(ctx, gamePushTaskFor(kind, gameID)); err != nil {
		slog.ErrorContext(ctx, "game.push_enqueue_failed", "kind", kind, "gameId", gameID, "error", err)
	}
}
