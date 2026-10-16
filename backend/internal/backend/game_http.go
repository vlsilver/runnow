package backend

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// gameRoutes là API Ma Sói của app (3.8). Handler chỉ đọc request và gọi
// GameStore; kiểm quyền, luật và lỗi đều nằm ở store.
func (s *Server) gameRoutes() {
	s.route("GET /v1/games", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		list, err := s.deps.Games.List(r.Context(), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, list)
	}))
	s.route("POST /v1/games", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body CreateGameRequest
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		id, err := s.deps.Games.Create(r.Context(), body, v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 201, map[string]any{"id": id})
	}))
	s.route("GET /v1/games/{id}", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		d, err := s.deps.Games.Detail(r.Context(), r.PathValue("id"), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, d)
	}))
	s.route("GET /v1/games/{id}/feed", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		feed, err := s.deps.Games.Feed(r.Context(), r.PathValue("id"), r.URL.Query().Get("cursor"), v)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, feed)
	}))
	s.route("GET /v1/games/{id}/me", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		me, err := s.deps.Games.Me(r.Context(), r.PathValue("id"), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, me)
	}))
	s.route("POST /v1/games/{id}/registration", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		res, err := s.deps.Games.Register(r.Context(), r.PathValue("id"), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, res)
	}))
	s.route("DELETE /v1/games/{id}/registration", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		res, err := s.deps.Games.Unregister(r.Context(), r.PathValue("id"), v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, res)
	}))
	s.route("POST /v1/games/{id}/actions", s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		received := time.Now()
		var body gameActionBody
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		id := r.PathValue("id")
		if err := s.submitGameAction(r, ActionRequest{GameID: id, UID: v.UID, Source: "app", ReceivedAt: received}, body); err != nil {
			return err
		}
		me, err := s.deps.Games.Me(r.Context(), id, v, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, me)
	}))

	// Start (2.4): dryRun trả ai sẽ bị loại; Start thật đặt starting rồi giao bot.
	s.route("POST /v1/games/{id}/start", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		id := r.PathValue("id")
		if r.URL.Query().Get("dryRun") == "true" {
			preview, err := s.deps.Games.StartPreview(r.Context(), id)
			if err != nil {
				return err
			}
			return writeJSON(w, 200, preview)
		}
		publish := s.enqueueTask()
		if publish == nil || s.config.GameInboundQueue == "" {
			return &HTTPError{Status: http.StatusServiceUnavailable, Code: "tasks_unavailable", Message: "Chưa cấu hình queue game-inbound."}
		}
		attempt, err := s.deps.Games.RequestStart(r.Context(), id, v.UID, time.Now())
		if err != nil {
			return err
		}
		// Enqueue lỗi thì ván nằm ở starting mà không có task; admin bấm Start lại
		// được, lần sau có TaskID mới.
		if _, err := publish(r.Context(), gameStartTaskFor(id, attempt)); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"status": gameStarting, "attempt": attempt})
	}))
	for _, action := range []string{"pause", "resume", "cancel"} {
		s.route("POST /v1/games/{id}/admin/"+action, s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
			run := map[string]func(context.Context, string, string, time.Time) error{
				"pause": s.deps.Games.AdminPause, "resume": s.deps.Games.AdminResume, "cancel": s.deps.Games.AdminCancel,
			}[action]
			id := r.PathValue("id")
			if err := run(r.Context(), id, v.UID, time.Now()); err != nil {
				return err
			}
			s.kickGameFlush(r.Context(), id)
			return writeJSON(w, 200, map[string]any{"ok": true})
		}))
	}

	// Lệnh admin của ván thử (X1). Store từ chối nếu ván không phải ván thử.
	s.route("POST /v1/games/{id}/admin/advance", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body struct {
			ExpectedKey string `json:"expectedKey"`
		}
		if err := decodeJSON(r, &body); err != nil || body.ExpectedKey == "" {
			return invalidRequest()
		}
		id := r.PathValue("id")
		res, err := s.deps.Games.AdminAdvance(r.Context(), id, body.ExpectedKey, time.Now())
		if err != nil {
			return err
		}
		if res.Steps > 0 {
			s.kickGameFlush(r.Context(), id)
		}
		return writeJSON(w, 200, map[string]any{"steps": res.Steps, "status": res.Status, "taskKey": res.TaskKey, "nextAt": res.NextAt})
	}))
	s.route("POST /v1/games/{id}/admin/act-as", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		received := time.Now()
		var body struct {
			UID string `json:"uid"`
			gameActionBody
		}
		if err := decodeJSON(r, &body); err != nil || body.UID == "" {
			return invalidRequest()
		}
		req := ActionRequest{GameID: r.PathValue("id"), UID: body.UID, Source: "admin", ReceivedAt: received, ActAs: true}
		if err := s.submitGameAction(r, req, body.gameActionBody); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("POST /v1/games/{id}/admin/km", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body struct {
			Round int     `json:"round"`
			UID   string  `json:"uid"`
			Km    float64 `json:"km"`
		}
		if err := decodeJSON(r, &body); err != nil || body.UID == "" {
			return invalidRequest()
		}
		if err := s.deps.Games.AdminSetKm(r.Context(), r.PathValue("id"), body.Round, body.UID, body.Km, time.Now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("POST /v1/games/{id}/admin/roles", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body struct {
			Roles map[string]werewolf.Role `json:"roles"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		if err := s.deps.Games.SetForcedRoles(r.Context(), r.PathValue("id"), body.Roles, time.Now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("POST /v1/games/{id}/admin/fake-players", s.gameAdmin(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		var body struct {
			Count int `json:"count"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		uids, err := s.deps.Games.SetFakePlayers(r.Context(), r.PathValue("id"), body.Count, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"uids": uids})
	}))
}

type gameActionBody struct {
	Kind    werewolf.Kind `json:"kind"`
	Targets []string      `json:"targets"`
	Choice  string        `json:"choice"`
	Clear   bool          `json:"clear"`
}

// submitGameAction gửi một hành động qua W0; luật từ chối thì trả 409/422.
func (s *Server) submitGameAction(r *http.Request, req ActionRequest, body gameActionBody) error {
	if body.Kind == "" || len(body.Targets) > 2 {
		return invalidRequest()
	}
	req.Kind, req.Targets, req.Choice, req.Clear = body.Kind, body.Targets, body.Choice, body.Clear
	res, err := s.deps.Games.SubmitAction(r.Context(), req)
	if err != nil {
		return err
	}
	if res.Reject != nil {
		return rejectHTTP(req.Kind, res.Reject)
	}
	if res.Applied {
		s.kickGameFlush(r.Context(), req.GameID)
	}
	return nil
}

// kickGameFlush giao bot gửi outbox ngay sau khi commit (3.2 bước 5). Enqueue
// lỗi thì chỉ log: tin vẫn nằm pending, lượt gửi sau gửi bù.
func (s *Server) kickGameFlush(ctx context.Context, gameID string) {
	publish := s.enqueueTask()
	if publish == nil || s.config.GameInboundQueue == "" {
		return
	}
	if _, err := publish(ctx, gameFlushTaskFor(gameID, time.Time{})); err != nil {
		slog.WarnContext(ctx, "game.flush_enqueue_failed", "gameId", gameID, "error", err)
	}
}

// enqueueTask là Dependencies.EnqueueTask nếu có, không thì Tasks.Publish.
func (s *Server) enqueueTask() taskPublishFunc {
	if s.deps.EnqueueTask != nil {
		return s.deps.EnqueueTask
	}
	if s.deps.Tasks != nil {
		return s.deps.Tasks.Publish
	}
	return nil
}

func (s *Server) gameHandler(next func(http.ResponseWriter, *http.Request, GameViewer) error) handler {
	return s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		return next(w, r, GameViewer{UID: uid, AppVersion: r.Header.Get("X-App-Version")})
	})
}

func (s *Server) gameAdmin(next func(http.ResponseWriter, *http.Request, GameViewer) error) handler {
	return s.gameHandler(func(w http.ResponseWriter, r *http.Request, v GameViewer) error {
		if err := s.deps.Games.RequireAdmin(r.Context(), v.UID); err != nil {
			return err
		}
		return next(w, r, v)
	})
}

// gameStart là chặng của bot trong Start: hỏi getChatMember ở PSC cho từng
// người đã liên kết (ghi lại inPsc), rồi chia vai. Payload hỏng thì 204 cho
// task thôi retry; Telegram hay Firestore lỗi thì trả lỗi để task chạy lại.
func (s *Server) gameStart(w http.ResponseWriter, r *http.Request) error {
	var task gameStartTask
	if err := decodeJSON(r, &task); err != nil || task.GameID == "" {
		slog.WarnContext(r.Context(), "game.start_bad_payload")
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if s.deps.Telegram == nil || !s.deps.Telegram.Enabled() || s.deps.TelegramLinks == nil || s.deps.Games == nil {
		return errors.New("game-start cần Telegram, TelegramLinks và Games")
	}
	inPsc := func(ctx context.Context, tg int64) (bool, error) {
		checkedAt := time.Now()
		m, err := s.deps.Telegram.GetChatMember(ctx, s.deps.Telegram.ChatID(), tg)
		if err != nil {
			return false, err
		}
		if err := s.deps.TelegramLinks.RecordMembership(ctx, tg, m, checkedAt); err != nil {
			return false, err
		}
		return m.InChat(), nil
	}
	out, err := s.deps.Games.RunStart(r.Context(), task.GameID, inPsc, time.Now())
	if err != nil {
		return err
	}
	slog.InfoContext(r.Context(), "game.start_done", "gameId", task.GameID, "attempt", task.Attempt, "result", out.Result, "players", out.Players, "excluded", len(out.Excluded))
	// Cả khi skipped: lần trước có thể đã chia bài xong mà chưa kịp enqueue.
	// reverted thì không có tin nào.
	if out.Result != "reverted" {
		s.kickGameFlush(r.Context(), task.GameID)
	}
	return writeJSON(w, 200, out)
}

// gameFlush gửi outbox của một ván (3.4). Còn chat phải chờ (429, bộ gửi khác
// đang giữ lease) thì hẹn một lượt nữa đúng mốc đó. Lỗi thì trả 5xx để task
// retry; tin chưa gửi vẫn nằm pending.
func (s *Server) gameFlush(w http.ResponseWriter, r *http.Request) error {
	var task gameFlushTask
	if err := decodeJSON(r, &task); err != nil || task.GameID == "" {
		slog.WarnContext(r.Context(), "game.flush_bad_payload")
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if s.deps.Telegram == nil || !s.deps.Telegram.Enabled() || s.deps.Games == nil {
		return errors.New("game-flush cần Telegram và Games")
	}
	res, err := s.deps.Games.FlushGame(r.Context(), task.GameID, s.deps.Telegram, time.Now)
	if !res.RetryAt.IsZero() {
		at := res.RetryAt.Add(time.Second)
		publish := s.enqueueTask()
		if publish == nil || s.config.GameInboundQueue == "" {
			slog.WarnContext(r.Context(), "game.flush_retry_unscheduled", "gameId", task.GameID, "retryAt", at)
		} else if _, perr := publish(r.Context(), gameFlushTaskFor(task.GameID, at)); perr != nil {
			err = errors.Join(err, perr)
		}
	}
	if err != nil {
		return err
	}
	slog.InfoContext(r.Context(), "game.flush_done", "gameId", task.GameID, "sent", res.Sent, "failed", res.Failed, "skipped", res.Skipped, "retryAt", res.RetryAt)
	return writeJSON(w, 200, res)
}
