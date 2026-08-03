package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

type handler func(http.ResponseWriter, *http.Request) error
type Server struct {
	config Config
	deps   *Dependencies
	mux    *http.ServeMux
	worker bool
}

func NewAPIServer(config Config, deps *Dependencies) http.Handler {
	s := &Server{config: config, deps: deps, mux: http.NewServeMux()}
	s.apiRoutes()
	return s.withCORS(s.mux)
}
func NewWorkerServer(config Config, deps *Dependencies) http.Handler {
	s := &Server{config: config, deps: deps, mux: http.NewServeMux(), worker: true}
	s.workerRoutes()
	return s.mux
}

// NewBotServer phục vụ riêng phần XỬ LÝ bot/AI. Đây là service PRIVATE (như
// worker): chỉ nhận task đã xác thực (bot-message, và sau này notify + chưng
// cất). Webhook Telegram public thì GIỮ trên api — nó chỉ enqueue, siêu nhẹ,
// và trộn public webhook với private task vào một service sẽ hở endpoint task.
func NewBotServer(config Config, deps *Dependencies) http.Handler {
	s := &Server{config: config, deps: deps, mux: http.NewServeMux(), worker: true}
	s.botRoutes()
	return s.mux
}
func (s *Server) botRoutes() {
	s.route("GET /health", func(w http.ResponseWriter, r *http.Request) error {
		return writeJSON(w, 200, map[string]any{"ok": true, "service": "runnow-bot"})
	})
	s.route("GET /healthz", func(w http.ResponseWriter, r *http.Request) error {
		return writeJSON(w, 200, map[string]any{"ok": true, "service": "runnow-bot"})
	})
	s.route("POST /tasks/bot-message", s.botMessage)
	// Cả hai đây cũng là việc AI (notify sinh nhận xét, chưng cất trí nhớ) —
	// dời sang service bot. Định tuyến queue/scheduler đổi ở deploy.sh.
	s.route("POST /tasks/notify-telegram", s.notifyTelegram)
	s.route("POST /tasks/live-announce", s.liveAnnounce)
	s.route("POST /tasks/consolidate-memory", s.consolidateMemory)
	// Cloud Scheduler gõ mỗi 10 phút → chạy các lịch bot tự đặt tới hạn.
	s.route("POST /tasks/schedule-tick", func(w http.ResponseWriter, r *http.Request) error {
		if s.deps.Bot == nil {
			w.WriteHeader(204)
			return nil
		}
		ctx, cancel := context.WithTimeout(r.Context(), 240*time.Second)
		defer cancel()
		if err := s.deps.Bot.RunDueSchedules(ctx, time.Now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
}

// telegramWebhook nhận update từ Telegram, xác thực secret, rồi CHỈ enqueue vào
// queue bot-inbound (không tự xử lý). Việc gọi Gemini nặng để handler botMessage
// lo trong một task thật — full CPU, timeout dài, tự retry.
func (s *Server) telegramWebhook(w http.ResponseWriter, r *http.Request) error {
	if s.config.TelegramWebhookSecret == "" ||
		r.Header.Get("X-Telegram-Bot-Api-Secret-Token") != s.config.TelegramWebhookSecret {
		return &HTTPError{Status: 401, Code: "unauthenticated", Message: "Invalid webhook secret"}
	}
	// KHÔNG dùng decodeJSONWithLimit: nó bật DisallowUnknownFields, mà update
	// thật của Telegram có mấy chục field mình không model — decoder chặt sẽ
	// từ chối cả payload. Decode lỏng, chỉ lấy phần cần.
	var update TelegramUpdate
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil || json.Unmarshal(body, &update) != nil {
		w.WriteHeader(http.StatusOK)
		return nil
	}
	// Chỉ cần Tasks để enqueue — webhook KHÔNG cần Bot/Gemini (xử lý ở
	// runnow-bot). Nhờ vậy api có thể bỏ token Telegram mà webhook vẫn chạy.
	if s.deps.Tasks != nil {
		name := senderName(update)
		chatID, question, isQuestion := botQuestion(update, s.config.TelegramBotUsername)
		recordChatID, _, rawText, hasText := incomingMessage(update)
		if isQuestion || hasText {
			task := botMessageTask{IsQuestion: isQuestion, Name: name, SenderID: senderID(update), PhotoFileID: photoFileID(update)}
			if isQuestion {
				task.ChatID, task.Question = chatID, question
			} else {
				task.ChatID, task.RawText = recordChatID, rawText
			}
			if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{
				Queue:       QueueBotInbound,
				HandlerPath: "/tasks/bot-message",
				Payload:     task,
				TaskID:      StableTaskID("botmsg", update.UpdateID),
			}); err != nil {
				slog.ErrorContext(r.Context(), "telegram.enqueue_failed", "error", err)
			}
		}
	}
	w.WriteHeader(http.StatusOK)
	return nil
}

// botMessage xử lý một tin bot đẩy từ queue bot-inbound: chạy trong request
// thật (full CPU, timeout 240s); lỗi → non-2xx để Cloud Tasks retry.
func (s *Server) botMessage(w http.ResponseWriter, r *http.Request) error {
	if s.deps.Bot == nil {
		w.WriteHeader(204)
		return nil
	}
	var task botMessageTask
	if decodeJSON(r, &task) != nil || task.ChatID == "" {
		w.WriteHeader(204)
		return nil
	}
	ctx, cancel := context.WithTimeout(r.Context(), 240*time.Second)
	defer cancel()
	if task.IsQuestion {
		if err := s.deps.Bot.HandleMessage(ctx, task.ChatID, task.SenderID, task.Name, task.Question, task.PhotoFileID); err != nil {
			return err
		}
	} else if err := s.deps.Bot.RecordIncoming(ctx, task.ChatID, task.SenderID, task.Name, task.RawText); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// notifyTelegram gửi thông báo buổi chạy (sinh nhận xét bằng Gemini). Việc AI,
// nên chạy trên service bot; dùng chung với worker qua method này.
func (s *Server) notifyTelegram(w http.ResponseWriter, r *http.Request) error {
	var task struct {
		UID        string `json:"uid"`
		ActivityID string `json:"activityId"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" || task.ActivityID == "" {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Activities.NotifyTelegram(r.Context(), task.UID, task.ActivityID); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// liveAnnounce: task chạy trên bot — tường thuật LIVE 1 sự kiện buổi tập (app
// gọi qua /v1/live/announce). Việc AI + gửi group nên nằm ở runnow-bot.
func (s *Server) liveAnnounce(w http.ResponseWriter, r *http.Request) error {
	var task struct {
		UID               string  `json:"uid"`
		ActivityID        string  `json:"activityId"`
		Event             string  `json:"event"`
		DistanceMeters    float64 `json:"distanceMeters"`
		MovingTimeSeconds float64 `json:"movingTimeSeconds"`
		MilestoneKm       int     `json:"milestoneKm"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" || task.ActivityID == "" || task.Event == "" {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Activities.LiveAnnounce(r.Context(), task.UID, task.ActivityID, task.Event, task.DistanceMeters, task.MovingTimeSeconds, task.MilestoneKm); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// consolidateMemory chưng cất trí nhớ nhóm (Gemini). Việc AI, chạy trên bot.
func (s *Server) consolidateMemory(w http.ResponseWriter, r *http.Request) error {
	if s.deps.Memory == nil {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Memory.ConsolidateAll(r.Context()); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
func (s *Server) route(pattern string, h handler) {
	s.mux.HandleFunc(pattern, func(w http.ResponseWriter, r *http.Request) {
		if err := h(w, r); err != nil {
			s.writeError(w, r, err)
		}
	})
}
func (s *Server) apiRoutes() {
	s.route("GET /health", func(w http.ResponseWriter, r *http.Request) error {
		return writeJSON(w, 200, map[string]any{"ok": true, "service": "runnow-api"})
	})
	s.route("GET /healthz", func(w http.ResponseWriter, r *http.Request) error {
		return writeJSON(w, 200, map[string]any{"ok": true, "service": "runnow-api"})
	})
	s.route("GET /v1/strava/status", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		connection, err := s.deps.OAuth.Status(r.Context(), uid)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, connection)
	}))
	s.route("POST /v1/strava/authorization", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			ReturnTarget string `json:"returnTarget"`
		}
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		u, err := s.deps.OAuth.Authorization(r.Context(), uid, body.ReturnTarget)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"authorizationUrl": u})
	}))
	s.route("GET /v1/strava/callback", func(w http.ResponseWriter, r *http.Request) error {
		q := r.URL.Query()
		redirect, err := s.deps.OAuth.Callback(r.Context(), OAuthCallback{State: q.Get("state"), Code: q.Get("code"), OAuthError: q.Get("error"), Scope: q.Get("scope")})
		if err != nil {
			return err
		}
		http.Redirect(w, r, redirect, http.StatusFound)
		return nil
	})
	s.route("POST /v1/strava/disconnect", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.OAuth.Disconnect(r.Context(), uid); err != nil {
			return err
		}
		w.WriteHeader(http.StatusNoContent)
		return nil
	}))
	// Xoá tài khoản vĩnh viễn. Bắt buộc phải có theo chính sách của cả
	// Google Play lẫn App Store với app cho phép tạo tài khoản.
	s.route("POST /v1/account/delete", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Accounts.Delete(r.Context(), uid); err != nil {
			return err
		}
		w.WriteHeader(http.StatusNoContent)
		return nil
	}))
	s.route("POST /v1/strava/repair", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.requireStravaConnection(r, uid); err != nil {
			return err
		}
		var body struct {
			Full bool `json:"full"`
		}
		if r.ContentLength != 0 {
			if err := decodeJSON(r, &body); err != nil {
				return invalidRequest()
			}
		}
		bucket := time.Now().Unix() / (5 * 60)
		runID := fmt.Sprintf("manual-%d", bucket)
		payload := map[string]any{"uid": uid, "page": 1, "runId": runID}
		if !body.Full {
			payload["after"] = time.Now().Unix() - 10*24*60*60
		}
		_, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBackfill, HandlerPath: "/tasks/backfill-page", Payload: payload, TaskID: fmt.Sprintf("repair-%s-%d-1", uid, bucket)})
		if err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"accepted": true})
	}))
	s.route("POST /v1/activities/{activityId}/hydrate", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.requireStravaConnection(r, uid); err != nil {
			return err
		}
		id := r.PathValue("activityId")
		if id == "" || len(id) > 64 {
			return invalidRequest()
		}
		bucket := time.Now().Unix() / (5 * 60)
		_, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueEvents, HandlerPath: "/tasks/hydrate-activity", Payload: map[string]any{"uid": uid, "activityId": id}, TaskID: fmt.Sprintf("hydrate-%s-%s-%d", uid, id, bucket)})
		if err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"accepted": true})
	}))
	// Telegram đẩy update về đây (xem telegramWebhook). Handler tách thành
	// method để service bot dùng chung — dời webhook sang bot chỉ là đổi chỗ
	// mount, không nhân đôi code.
	s.route("POST /v1/telegram/webhook", s.telegramWebhook)
	// Đích cũ của nút "Xem chi tiết" trong Telegram, trước đây là một trang
	// HTML backend tự dựng. Giờ chỉ chuyển hướng về app — giữ route để các
	// tin nhắn đã gửi trước đây không chết link.
	s.route("GET /v1/public/activities/{uid}/{activityId}", func(w http.ResponseWriter, r *http.Request) error {
		uid := r.PathValue("uid")
		id := r.PathValue("activityId")
		if uid == "" || id == "" || len(uid) > 128 || len(id) > 64 {
			return invalidRequest()
		}
		http.Redirect(w, r, activityDetailURL(s.config.WebBaseURL, uid, id), http.StatusFound)
		return nil
	})
	// JSON công khai (không cần đăng nhập) cho trang activity detail chia sẻ:
	// web app gọi endpoint này để hiển thị buổi tập cho BẤT KỲ ai mở link từ
	// group, kể cả chưa đăng nhập. Dùng Admin SDK nên bỏ qua Firestore rules;
	// trả về đúng các chuỗi hiển thị đã tính sẵn (sport-aware) để client chỉ việc
	// render, không phải lặp lại logic format.
	s.route("GET /v1/public/activities/{uid}/{activityId}/summary", func(w http.ResponseWriter, r *http.Request) error {
		uid := r.PathValue("uid")
		id := r.PathValue("activityId")
		if uid == "" || id == "" || len(uid) > 128 || len(id) > 64 {
			return invalidRequest()
		}
		sum, err := s.deps.Activities.PublicSummary(r.Context(), uid, id)
		if err != nil {
			return err
		}
		disp := sportDisplayFor(sum.Fact.SportType)
		paceLabel, paceValue := paceOrSpeed(sum.Fact)
		body := map[string]any{
			"displayName":      sum.DisplayName,
			"activityName":     defaultString(sum.ActivityName, disp.defaultName),
			"sportType":        sum.Fact.SportType,
			"sportVerb":        disp.verb,
			"sportEmoji":       disp.emoji,
			"distance":         formatDistanceKm(sum.Fact.DistanceMeters),
			"duration":         formatDurationHMS(sum.Fact.MovingTimeSeconds),
			"paceLabel":        paceLabel,
			"paceValue":        paceValue,
			"distanceMeters":   sum.Fact.DistanceMeters,
			"movingTimeSecond": sum.Fact.MovingTimeSeconds,
		}
		if sum.Fact.ElevationGainMeters >= 1 {
			body["elevation"] = formatElevationM(sum.Fact.ElevationGainMeters)
		}
		if !sum.Fact.StartedAt.IsZero() {
			body["startedAt"] = sum.Fact.StartedAt.In(vietnam).Format(time.RFC3339)
			body["startedAtDisplay"] = telegramActivityTime(sum.Fact.StartedAt)
		}
		return writeJSON(w, 200, body)
	})
	s.route("POST /v1/live/announce", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// App 3i gọi khi tới mốc trong lúc tập (start / mỗi 5km / finish). Chỉ
		// enqueue task nhẹ sang bot để viết + gửi group; không chặn app. TaskID
		// ổn định theo (buổi, sự kiện, mốc) nên gọi lặp không bắn trùng.
		var body struct {
			ActivityID        string  `json:"activityId"`
			Event             string  `json:"event"`
			DistanceMeters    float64 `json:"distanceMeters"`
			MovingTimeSeconds float64 `json:"movingTimeSeconds"`
			MilestoneKm       int     `json:"milestoneKm"`
		}
		if decodeJSON(r, &body) != nil || body.ActivityID == "" || body.Event == "" {
			return invalidRequest()
		}
		payload := map[string]any{"uid": uid, "activityId": body.ActivityID, "event": body.Event, "distanceMeters": body.DistanceMeters, "movingTimeSeconds": body.MovingTimeSeconds, "milestoneKm": body.MilestoneKm}
		dedup := map[string]any{"activityId": body.ActivityID, "event": body.Event, "km": body.MilestoneKm}
		if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/live-announce", Payload: payload, TaskID: StableTaskID("live", dedup)}); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"ok": true})
	}))
	s.route("POST /v1/activities/tracked", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Activity map[string]any `json:"activity"`
		}
		// 10MB: buổi chạy DÀI (route dày + streams) có payload lớn — trần 2MB cũ
		// chặn ngay ở decode → 400, mất buổi (vd buổi race 10.4km). Cho payload
		// to lọt vào, rồi SaveTracked tự bỏ trackingDebug + downsample cho gọn.
		if err := decodeJSONWithLimit(r, &body, 10<<20); err != nil || body.Activity == nil {
			return invalidRequest()
		}
		result, err := s.deps.Activities.SaveTracked(r.Context(), uid, body.Activity)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, result)
	}))
	// Hoàn tất buổi chạy đã SYNC THEO CHUNK: body chỉ mang phần summary nhẹ
	// (không route/streams — chúng đã được đẩy dần vào track/{seq}); backend ghép
	// chunk lại. Nhờ vậy không còn payload khổng lồ ở cuối.
	s.route("POST /v1/activities/tracked/finalize", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Activity map[string]any `json:"activity"`
		}
		if err := decodeJSONWithLimit(r, &body, 2<<20); err != nil || body.Activity == nil {
			return invalidRequest()
		}
		result, err := s.deps.Activities.FinalizeTracked(r.Context(), uid, body.Activity)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, result)
	}))
	s.route("POST /v1/profile", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body ProfileUpdate
		if err := decodeJSON(r, &body); err != nil {
			return invalidRequest()
		}
		if err := s.deps.Profiles.Update(r.Context(), uid, body); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"accepted": true})
	}))
	s.route("GET /v1/strava/webhook", func(w http.ResponseWriter, r *http.Request) error {
		q := r.URL.Query()
		value, err := s.deps.Webhook.Verification(q.Get("hub.mode"), q.Get("hub.challenge"), q.Get("hub.verify_token"))
		if err != nil {
			return err
		}
		return writeJSON(w, 200, value)
	})
	s.route("POST /v1/strava/webhook", func(w http.ResponseWriter, r *http.Request) error {
		var event StravaWebhookEvent
		if err := decodeJSON(r, &event); err != nil || !validWebhook(event) {
			return invalidRequest()
		}
		if _, err := s.deps.Webhook.Receive(r.Context(), event); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"received": true})
	})
}

func (s *Server) requireStravaConnection(r *http.Request, uid string) error {
	connection, err := s.deps.OAuth.Status(r.Context(), uid)
	if err != nil {
		return err
	}
	if !connection.Connected {
		return &HTTPError{
			Status:  http.StatusConflict,
			Code:    "strava_not_connected",
			Message: "Strava is not connected",
		}
	}
	return nil
}

func (s *Server) workerRoutes() {
	s.route("GET /health", func(w http.ResponseWriter, r *http.Request) error {
		return writeJSON(w, 200, map[string]any{"ok": true, "service": "runnow-worker"})
	})
	s.route("GET /healthz", func(w http.ResponseWriter, r *http.Request) error {
		return writeJSON(w, 200, map[string]any{"ok": true, "service": "runnow-worker"})
	})
	s.route("POST /tasks/strava-event", func(w http.ResponseWriter, r *http.Request) error {
		var task struct {
			EventKey string             `json:"eventKey"`
			Event    StravaWebhookEvent `json:"event"`
		}
		if decodeJSON(r, &task) != nil || task.EventKey == "" || !validWebhook(task.Event) {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.Activities.ProcessWebhook(r.Context(), task.EventKey, task.Event); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
	s.route("POST /tasks/backfill-page", func(w http.ResponseWriter, r *http.Request) error {
		var task struct {
			UID   string `json:"uid"`
			Page  int    `json:"page"`
			RunID string `json:"runId"`
			After *int64 `json:"after"`
		}
		if decodeJSON(r, &task) != nil || task.UID == "" || task.Page < 1 || task.RunID == "" {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.Activities.BackfillPage(r.Context(), task.UID, task.Page, task.RunID, task.After); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
	s.route("POST /tasks/hydrate-activity", func(w http.ResponseWriter, r *http.Request) error {
		var task struct {
			UID        string `json:"uid"`
			ActivityID string `json:"activityId"`
		}
		if decodeJSON(r, &task) != nil || task.UID == "" || task.ActivityID == "" {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.Activities.Hydrate(r.Context(), task.UID, task.ActivityID); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
	s.route("POST /tasks/rebuild-derived-data", func(w http.ResponseWriter, r *http.Request) error {
		var task struct{ UID, Cause string }
		if decodeJSON(r, &task) != nil || task.UID == "" || task.Cause == "" {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.Derived.RebuildCurrent(r.Context(), task.UID, time.Now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true, "cause": task.Cause})
	})
	s.route("POST /tasks/rebuild-period-stats", func(w http.ResponseWriter, r *http.Request) error {
		var task struct{ UID, StartedAt string }
		if decodeJSON(r, &task) != nil || task.UID == "" || task.StartedAt == "" {
			w.WriteHeader(204)
			return nil
		}
		startedAt, parseErr := time.Parse(time.RFC3339, task.StartedAt)
		if parseErr != nil {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.PeriodStats.RebuildForInstant(r.Context(), task.UID, startedAt); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
	s.route("POST /tasks/refresh-leaderboard", func(w http.ResponseWriter, r *http.Request) error {
		// FIX GỐC bug "người ma 0 km": leaderboardEntries chỉ rebuild khi CHÍNH
		// chủ nó có activity mới, nên người ngừng chạy vẫn kẹt số kỳ cũ
		// (currentWeek/Month/rollingSevenDays) Ở NGUỒN. Cron hằng ngày (sau nửa
		// đêm VN) fan-out rebuild-derived-data cho MỌI member → RebuildCurrent
		// tính lại theo kỳ hiện tại (0 nếu không chạy) và tự bỏ ghi nếu không
		// đổi. Nhờ vậy cả app lẫn bot đọc đúng ngay tại nguồn; guard read-side
		// chỉ còn đỡ cửa sổ vài phút trước khi cron kịp chạy.
		docs, err := s.deps.Firestore.Collection("leaderboardEntries").Documents(r.Context()).GetAll()
		if err != nil {
			return err
		}
		cause := "daily-refresh-" + dateKey(time.Now())
		enqueued := 0
		for _, doc := range docs {
			payload := map[string]any{"uid": doc.Ref.ID, "cause": cause}
			if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{
				Queue:       QueueDerived,
				HandlerPath: "/tasks/rebuild-derived-data",
				Payload:     payload,
				TaskID:      StableTaskID("derived", payload),
			}); err != nil {
				return err
			}
			enqueued++
		}
		return writeJSON(w, 200, map[string]any{"ok": true, "enqueued": enqueued})
	})
	s.route("POST /tasks/reconcile-connections", func(w http.ResponseWriter, r *http.Request) error {
		var task struct {
			Cursor string `json:"cursor"`
		}
		if r.ContentLength != 0 && decodeJSON(r, &task) != nil {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.Reconciliation.ReconcileConnections(r.Context(), task.Cursor); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
	// notify-telegram, bot-message, consolidate-memory đã dời sang runnow-bot
	// (xem botRoutes) — worker không còn phần AI nào.
}

func (s *Server) authenticated(next func(http.ResponseWriter, *http.Request, string) error) handler {
	return func(w http.ResponseWriter, r *http.Request) error {
		header := r.Header.Get("Authorization")
		if !strings.HasPrefix(header, "Bearer ") {
			return &HTTPError{Status: 401, Code: "unauthenticated", Message: "Missing Firebase ID token"}
		}
		token, err := s.deps.Auth.VerifyIDToken(r.Context(), strings.TrimPrefix(header, "Bearer "))
		if err != nil {
			return &HTTPError{Status: 401, Code: "unauthenticated", Message: "Invalid Firebase ID token"}
		}
		return next(w, r, token.UID)
	}
}
func (s *Server) withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" {
			if _, ok := s.config.AllowedWebOrigins[origin]; !ok {
				writeJSON(w, 403, map[string]any{"error": "origin_not_allowed"})
				return
			}
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(204)
			return
		}
		next.ServeHTTP(w, r)
	})
}
func (s *Server) writeError(w http.ResponseWriter, r *http.Request, err error) {
	var httpErr *HTTPError
	if errors.As(err, &httpErr) {
		_ = writeJSON(w, httpErr.Status, map[string]any{"error": httpErr.Code, "message": httpErr.Message})
		return
	}
	if s.worker {
		var revoked *ConnectionRevokedError
		if errors.As(err, &revoked) {
			slog.Warn("discarding task for revoked Strava connection", "uid", revoked.UID)
			w.WriteHeader(204)
			return
		}
		var api *StravaAPIError
		if errors.As(err, &api) && api.Status == 429 {
			if api.RetryAfter != "" {
				w.Header().Set("Retry-After", api.RetryAfter)
			}
			_ = writeJSON(w, 429, map[string]any{"error": "strava_rate_limited"})
			return
		}
	}
	slog.Error("request failed", "method", r.Method, "path", r.URL.Path, "error", err)
	_ = writeJSON(w, 500, map[string]any{"error": "internal_error", "message": "Request failed"})
}
func decodeJSON(r *http.Request, target any) error {
	return decodeJSONWithLimit(r, target, 1<<20)
}
func decodeJSONWithLimit(r *http.Request, target any, limit int64) error {
	decoder := json.NewDecoder(io.LimitReader(r.Body, limit))
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}
func writeJSON(w http.ResponseWriter, statusCode int, value any) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if statusCode == 204 {
		return nil
	}
	return json.NewEncoder(w).Encode(value)
}
func invalidRequest() error {
	return &HTTPError{Status: 400, Code: "invalid_request", Message: "Request is invalid"}
}
func validWebhook(e StravaWebhookEvent) bool {
	return (e.ObjectType == "activity" || e.ObjectType == "athlete") && (e.AspectType == "create" || e.AspectType == "update" || e.AspectType == "delete") && e.OwnerID > 0 && e.SubscriptionID > 0 && e.EventTime > 0
}
