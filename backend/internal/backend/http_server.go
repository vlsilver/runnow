package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"runtime/debug"
	"strconv"
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
	s.route("POST /tasks/game-update", s.gameUpdate)
	s.route("POST /tasks/game-start", s.gameStart)
	s.route("POST /tasks/game-flush", s.gameFlush)
	// Cả hai đây cũng là việc AI (notify sinh nhận xét, chưng cất trí nhớ) —
	// dời sang service bot. Định tuyến queue/scheduler đổi ở deploy.sh.
	s.route("POST /tasks/notify-telegram", s.notifyTelegram)
	s.route("POST /tasks/live-announce", s.liveAnnounce)
	s.route("POST /tasks/contract-roast", s.contractRoast)
	s.route("POST /tasks/contract-announce-new", s.contractAnnounceNew)
	s.route("POST /tasks/coach-announce", s.coachAnnounce)
	s.route("POST /tasks/coach-announce-removed", s.coachAnnounceRemoved)
	s.route("POST /tasks/generate-plan", s.generatePlan)
	s.route("POST /tasks/coach-ask", s.coachAsk)
	s.route("POST /tasks/consolidate-memory", s.consolidateMemory)
	s.route("POST /tasks/game-advance", s.gameAdvance)
	s.route("POST /tasks/schedule-tick", s.scheduleTick)
	s.route("POST /tasks/agent-dm", s.agentDM)
	s.route("POST /tasks/agent-turn", s.agentTurn)
	s.route("POST /tasks/agent-learn", s.agentLearn)
	s.route("POST /tasks/managed-bot-sync", s.managedBotSync)
	s.route("POST /tasks/managed-send", s.managedSend)
}

// tickJob là một việc của schedule-tick, với timeout riêng.
type tickJob struct {
	name    string
	timeout time.Duration
	run     func(ctx context.Context, now time.Time) error
}

// scheduleTick: Cloud Scheduler gõ mỗi 10 phút. Game chạy trước, vì chốt phase
// trễ thì cả ván phải chờ; rồi tới alert của game (M1, cần biết phần game có
// lỗi không) và các lịch bot tự đặt. Tổng timeout dưới 300s mặc định của Cloud Run.
func (s *Server) scheduleTick(w http.ResponseWriter, r *http.Request) error {
	var gameErr error
	jobs := []tickJob{
		{name: "game", timeout: 40 * time.Second, run: func(ctx context.Context, now time.Time) error {
			gameErr = errors.New("panic") // panic thì dòng dưới không chạy, alert vẫn thấy lỗi
			gameErr = s.tickGame(ctx, now)
			return gameErr
		}},
		{name: "alert", timeout: 20 * time.Second, run: func(ctx context.Context, now time.Time) error {
			return s.tickAlerts(ctx, now, gameErr)
		}},
	}
	if s.deps.Learn != nil {
		jobs = append(jobs, tickJob{name: "learn", timeout: 5 * time.Second, run: s.enqueueLearn})
	}
	if s.deps.Bot != nil {
		jobs = append(jobs, tickJob{name: "bot", timeout: 230 * time.Second, run: s.deps.Bot.RunDueSchedules})
	}
	if err := runTickJobs(r.Context(), s.now(), jobs); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// runTickJobs chạy lần lượt từng việc, mỗi việc một context riêng. Việc nào lỗi,
// timeout hay panic thì vẫn chạy việc sau; lỗi gom lại trả ra để tick báo 5xx.
func runTickJobs(ctx context.Context, now time.Time, jobs []tickJob) error {
	var errs []error
	for _, j := range jobs {
		if err := runTickJob(ctx, now, j); err != nil {
			slog.ErrorContext(ctx, "tick.job_failed", "job", j.name, "error", err)
			errs = append(errs, fmt.Errorf("%s: %w", j.name, err))
		}
	}
	return errors.Join(errs...)
}

func runTickJob(ctx context.Context, now time.Time, j tickJob) (err error) {
	ctx, cancel := context.WithTimeout(ctx, j.timeout)
	defer cancel()
	defer func() {
		if p := recover(); p != nil {
			err = fmt.Errorf("panic: %v\n%s", p, debug.Stack())
		}
	}()
	return j.run(ctx, now)
}

// telegramWebhook nhận update từ Telegram, xác thực secret, rồi định tuyến
// (serveTelegramUpdate): nút bấm và lệnh cố định trả lời ngay, còn lại chỉ
// enqueue. Việc gọi Gemini nặng để handler botMessage lo trong một task thật —
// full CPU, timeout dài, tự retry.
func (s *Server) telegramWebhook(w http.ResponseWriter, r *http.Request) error {
	if s.config.TelegramWebhookSecret == "" ||
		r.Header.Get("X-Telegram-Bot-Api-Secret-Token") != s.config.TelegramWebhookSecret {
		return &HTTPError{Status: 401, Code: "unauthenticated", Message: "Invalid webhook secret"}
	}
	// KHÔNG dùng decodeJSONWithLimit: nó bật DisallowUnknownFields, mà update
	// thật của Telegram có mấy chục field mình không model — decoder chặt sẽ
	// từ chối cả payload. Decode lỏng, chỉ lấy phần cần.
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		w.WriteHeader(http.StatusOK)
		return nil
	}
	// Chỉ cần Tasks để enqueue — webhook KHÔNG cần Bot/Gemini (xử lý ở
	// runnow-bot). Nhờ vậy api có thể bỏ token Telegram mà webhook vẫn chạy.
	// enqueueTask là Tasks.Publish trên prod; test gài EnqueueTask để bắt task.
	s.serveTelegramUpdate(r.Context(), w, body, s.enqueueTask())
	return nil
}

// gameUpdate nhận update thành viên/join/migrate, và /start vừa liên kết xong,
// mà webhook chuyển sang. Với từng người trong update, hỏi getChatMember ở PSC
// rồi ghi inPsc lên tgLinks (L1). Hỏi lại thay vì tin trạng thái trong update,
// vì update có thể đến từ group khác (group kín, group test). Decode lỏng: thêm
// field không bị ràng buộc thứ tự deploy.
func (s *Server) gameUpdate(w http.ResponseWriter, r *http.Request) error {
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		return err
	}
	var task gameUpdateTask
	var kinds map[string]json.RawMessage
	if json.Unmarshal(body, &task) != nil || json.Unmarshal(task.Raw, &kinds) != nil {
		slog.WarnContext(r.Context(), "game.update_bad_payload")
		w.WriteHeader(204)
		return nil
	}
	names := make([]string, 0, len(kinds))
	for k := range kinds {
		if k != "update_id" {
			names = append(names, k)
		}
	}
	users := membershipUserIDs(task.Raw)
	slog.InfoContext(r.Context(), "game.update_received", "updateId", task.UpdateID, "kinds", names, "users", len(users))
	if len(users) == 0 {
		return writeJSON(w, 200, map[string]any{"ok": true})
	}
	if s.deps.Telegram == nil || !s.deps.Telegram.Enabled() || s.deps.TelegramLinks == nil {
		return errors.New("game-update cần Telegram và TelegramLinks để ghi inPsc")
	}
	for _, id := range users {
		checkedAt := time.Now()
		m, err := s.deps.Telegram.GetChatMember(r.Context(), s.deps.Telegram.ChatID(), id)
		if err != nil {
			return err
		}
		if err := s.deps.TelegramLinks.RecordMembership(r.Context(), id, m, checkedAt); err != nil {
			return err
		}
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// membershipUserIDs lấy những người cần kiểm lại inPsc: người được đổi trạng
// thái trong chat_member, người vào/rời trong tin dịch vụ, và người nhắn DM
// (/start vừa liên kết). Bỏ bot và id trùng.
func membershipUserIDs(raw []byte) []int64 {
	type user struct {
		ID    int64 `json:"id"`
		IsBot bool  `json:"is_bot"`
	}
	var u struct {
		ChatMember *struct {
			NewChatMember struct {
				User user `json:"user"`
			} `json:"new_chat_member"`
		} `json:"chat_member"`
		Message *struct {
			Chat struct {
				Type string `json:"type"`
			} `json:"chat"`
			From           *user  `json:"from"`
			NewChatMembers []user `json:"new_chat_members"`
			LeftChatMember *user  `json:"left_chat_member"`
		} `json:"message"`
	}
	if json.Unmarshal(raw, &u) != nil {
		return nil
	}
	var candidates []user
	if u.ChatMember != nil {
		candidates = append(candidates, u.ChatMember.NewChatMember.User)
	}
	if m := u.Message; m != nil {
		candidates = append(candidates, m.NewChatMembers...)
		if m.LeftChatMember != nil {
			candidates = append(candidates, *m.LeftChatMember)
		}
		if m.Chat.Type == "private" && m.From != nil {
			candidates = append(candidates, *m.From)
		}
	}
	seen := map[int64]bool{}
	var ids []int64
	for _, c := range candidates {
		if c.ID != 0 && !c.IsBot && !seen[c.ID] {
			seen[c.ID] = true
			ids = append(ids, c.ID)
		}
	}
	return ids
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
		if err := s.deps.Bot.HandleMessage(ctx, task.ChatID, task.ThreadID, task.SenderID, task.Name, task.Question, task.PhotoFileID); err != nil {
			return err
		}
	} else if err := s.deps.Bot.RecordIncoming(ctx, task.ChatID, task.ThreadID, task.SenderID, task.Name, task.RawText); err != nil {
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
		PhotoPath         string  `json:"photoPath"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" || task.ActivityID == "" || task.Event == "" {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Activities.LiveAnnounce(r.Context(), task.UID, task.ActivityID, task.Event, task.DistanceMeters, task.MovingTimeSeconds, task.MilestoneKm, task.PhotoPath); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// contractRoast: task chạy trên bot — bêu những người trượt của 1 kèo vừa đóng
// (app chủ kèo gọi qua /v1/contracts/announce-result). Việc AI + gửi group nên
// nằm ở runnow-bot.
func (s *Server) contractRoast(w http.ResponseWriter, r *http.Request) error {
	var task struct {
		UID        string `json:"uid"`
		ContractID string `json:"contractId"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" || task.ContractID == "" {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Activities.AnnounceContractResult(r.Context(), task.UID, task.ContractID); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// contractAnnounceNew: bot báo group có kèo public mới. Chạy trên bot (telegram).
func (s *Server) contractAnnounceNew(w http.ResponseWriter, r *http.Request) error {
	var task struct {
		UID        string `json:"uid"`
		ContractID string `json:"contractId"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" || task.ContractID == "" {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Activities.AnnounceNewContract(r.Context(), task.UID, task.ContractID); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// coachAnnounce: bot báo group có giáo án AI Coach công khai được mở/đổi.
func (s *Server) coachAnnounce(w http.ResponseWriter, r *http.Request) error {
	var task struct {
		UID     string `json:"uid"`
		Changed bool   `json:"changed"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Activities.AnnounceCoachPlan(r.Context(), task.UID, task.Changed); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// coachAnnounceRemoved: bot báo group chủ đã GỠ một giáo án công khai.
func (s *Server) coachAnnounceRemoved(w http.ResponseWriter, r *http.Request) error {
	var task struct {
		UID  string `json:"uid"`
		Goal string `json:"goal"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" {
		w.WriteHeader(204)
		return nil
	}
	if err := s.deps.Activities.AnnounceCoachRemoved(r.Context(), task.UID, task.Goal); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// generatePlan: task chạy trên bot — sinh giáo án AI Coach cho user rồi ghi
// users/{uid}/coach/current. Việc AI (Gemini) nên nằm ở runnow-bot.
func (s *Server) generatePlan(w http.ResponseWriter, r *http.Request) error {
	if s.deps.Bot == nil {
		w.WriteHeader(204)
		return nil
	}
	var task struct {
		UID        string `json:"uid"`
		Goal       string `json:"goal"`
		Visibility string `json:"visibility"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" {
		w.WriteHeader(204)
		return nil
	}
	ctx, cancel := context.WithTimeout(r.Context(), 120*time.Second)
	defer cancel()
	if err := s.deps.Bot.GenerateTrainingPlan(ctx, task.UID, task.Goal, task.Visibility); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// coachAsk: task chạy trên bot — trả lời câu hỏi cho AI Coach (Gemini) rồi ghi
// hỏi+đáp vào coach/chat/messages. Việc AI nên nằm ở runnow-bot.
func (s *Server) coachAsk(w http.ResponseWriter, r *http.Request) error {
	if s.deps.Bot == nil {
		w.WriteHeader(204)
		return nil
	}
	var task struct {
		UID      string `json:"uid"`
		PlanID   string `json:"planId"`
		Question string `json:"question"`
	}
	if decodeJSON(r, &task) != nil || task.UID == "" || strings.TrimSpace(task.Question) == "" {
		w.WriteHeader(204)
		return nil
	}
	ctx, cancel := context.WithTimeout(r.Context(), 90*time.Second)
	defer cancel()
	if _, err := s.deps.Bot.AskCoach(ctx, task.UID, task.PlanID, task.Question); err != nil {
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
	s.mybotRoutes()
	s.gameRoutes()
	s.agentRoutes()
	s.adminRoutes()
	s.agentConfigRoutes()
	// Liên kết Telegram cho Ma Sói (L1). App lấy mã, mở t.me/<bot>?start=<mã>,
	// rồi poll GET cho tới khi linked.
	s.route("POST /v1/telegram/link-code", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		code, err := s.deps.TelegramLinks.CreateLinkCode(r.Context(), uid, time.Now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, code)
	}))
	s.route("GET /v1/telegram/link", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		link, err := s.deps.TelegramLinks.Link(r.Context(), uid)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, link)
	}))
	s.route("DELETE /v1/telegram/link", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.TelegramLinks.Unlink(r.Context(), uid); err != nil {
			return err
		}
		return writeJSON(w, 200, LinkStatus{})
	}))
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
			PhotoPath         string  `json:"photoPath"`
		}
		if decodeJSON(r, &body) != nil || body.ActivityID == "" || body.Event == "" {
			return invalidRequest()
		}
		payload := map[string]any{"uid": uid, "activityId": body.ActivityID, "event": body.Event, "distanceMeters": body.DistanceMeters, "movingTimeSeconds": body.MovingTimeSeconds, "milestoneKm": body.MilestoneKm, "photoPath": body.PhotoPath}
		dedup := map[string]any{"activityId": body.ActivityID, "event": body.Event, "km": body.MilestoneKm, "photo": body.PhotoPath}
		if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/live-announce", Payload: payload, TaskID: StableTaskID("live", dedup)}); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"ok": true})
	}))
	s.route("POST /v1/contracts/announce-result", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// App (CHỦ kèo) gọi sau khi chốt kèo. Chỉ enqueue task nhẹ sang bot; việc
		// đọc kèo + tìm ai trượt + bêu để bot lo. TaskID theo contract nên gọi lại
		// không bắn trùng (bot còn chốt thêm bằng roastedAt trên doc kèo).
		var body struct {
			ContractID string `json:"contractId"`
		}
		if decodeJSON(r, &body) != nil || body.ContractID == "" {
			return invalidRequest()
		}
		payload := map[string]any{"uid": uid, "contractId": body.ContractID}
		if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/contract-roast", Payload: payload, TaskID: StableTaskID("roast", body.ContractID)}); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"ok": true})
	}))
	s.route("POST /v1/contracts/announce-new", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// App (CHỦ kèo) gọi sau khi tạo 1 kèo CÔNG KHAI. Bot báo group để rủ tham
		// gia. TaskID theo contract + announcedAt trên doc để không bắn trùng.
		var body struct {
			ContractID string `json:"contractId"`
		}
		if decodeJSON(r, &body) != nil || body.ContractID == "" {
			return invalidRequest()
		}
		payload := map[string]any{"uid": uid, "contractId": body.ContractID}
		if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/contract-announce-new", Payload: payload, TaskID: StableTaskID("announce-new", body.ContractID)}); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"ok": true})
	}))
	s.route("POST /v1/training-plan/generate", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// App (Coach tab) gọi để sinh giáo án. Kết quả ghi vào coach/DRAFT —
		// giáo án đang chạy không bị đụng tới cho tới khi user bấm xác nhận.
		// Enqueue sang bot vì Gemini nặng (tới 120s).
		var body struct {
			Goal       string `json:"goal"`
			Visibility string `json:"visibility"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		payload := map[string]any{"uid": uid, "goal": body.Goal, "visibility": body.Visibility}
		// KHÔNG đặt StableTaskID: sinh giáo án là hành động chủ ý; user có thể tạo
		// lại (kể cả cùng mục tiêu) trong ngày — dedup theo (uid,goal) sẽ chặn oan.
		if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/generate-plan", Payload: payload}); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"ok": true})
	}))
	// Xác nhận bản nháp → giáo án đang chạy. Chỉ đụng Firestore nên chạy thẳng
	// trên API, không qua hàng đợi: user vừa bấm nút và đang đợi màn hình đổi.
	s.route("POST /v1/training-plan/confirm", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// Thao tác Firestore thuần (draft→coachPlans) — chạy thẳng trên api, KHÔNG
		// cần Bot/Gemini (Bot nil trên api).
		vis, replaced, err := confirmCoachDraft(r.Context(), s.deps.Firestore, uid)
		if err != nil {
			return err
		}
		// Giáo án CÔNG KHAI thì báo group qua 3i bot (mở mới / đổi). Enqueue sang
		// bot vì telegram + broadcast nằm ở đó; api chỉ đẩy task.
		if vis == "club" {
			payload := map[string]any{"uid": uid, "changed": replaced}
			if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/coach-announce", Payload: payload, TaskID: StableTaskID("coach-announce", []any{uid, replaced})}); err != nil {
				return err
			}
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	// Bỏ bản nháp. Giáo án đang chạy giữ nguyên.
	s.route("POST /v1/training-plan/discard", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := discardCoachDraft(r.Context(), s.deps.Firestore, uid); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	// Hỏi đáp với coach. Đồng bộ vì user đang chờ câu trả lời trên màn chat;
	// hạn 60s để một câu hỏi treo không giữ kết nối mãi.
	s.route("POST /v1/coach/ask", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// Việc AI (Gemini) nằm ở runnow-bot; api CHỈ enqueue task. Câu hỏi + trả
		// lời được bot ghi vào coach/chat/messages nên app nhận qua stream — không
		// cần trả answer đồng bộ ở đây.
		var body struct {
			PlanID   string `json:"planId"`
			Question string `json:"question"`
		}
		if decodeJSON(r, &body) != nil || strings.TrimSpace(body.Question) == "" {
			return invalidRequest()
		}
		payload := map[string]any{"uid": uid, "planId": body.PlanID, "question": body.Question}
		if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/coach-ask", Payload: payload, TaskID: StableTaskID("coach-ask", []any{uid, body.PlanID, body.Question})}); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"ok": true})
	}))
	s.route("POST /v1/coach/announce-removed", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// App (CHỦ giáo án) gọi khi gỡ một giáo án công khai. Gửi kèm goal vì doc
		// sắp bị xoá; bot báo group. Enqueue sang bot (telegram nằm ở đó).
		var body struct {
			Goal string `json:"goal"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		payload := map[string]any{"uid": uid, "goal": body.Goal}
		if _, err := s.deps.Tasks.Publish(r.Context(), PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/coach-announce-removed", Payload: payload, TaskID: StableTaskID("coach-removed", []any{uid, body.Goal})}); err != nil {
			return err
		}
		return writeJSON(w, 202, map[string]any{"ok": true})
	}))
	s.route("GET /v1/activities", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		limit := 20
		if v := r.URL.Query().Get("limit"); v != "" {
			n, err := strconv.Atoi(v)
			if err != nil {
				return invalidRequest()
			}
			limit = n
		}
		page, err := s.deps.Activities.List(r.Context(), uid, r.URL.Query().Get("cursor"), limit)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, page)
	}))
	s.route("GET /v1/activities/{activityId}/card", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		id, err := runCardActivityID(r)
		if err != nil {
			return err
		}
		view, err := s.deps.RunCards.Get(r.Context(), uid, id)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, view)
	}))
	s.route("POST /v1/activities/{activityId}/card", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		id, err := runCardActivityID(r)
		if err != nil {
			return err
		}
		card, err := s.deps.RunCards.Roll(r.Context(), uid, id)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"card": card})
	}))
	s.route("GET /v1/art-styles", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		kind, ok := parseArtKind(r.URL.Query().Get("kind"))
		if !ok {
			return invalidRequest()
		}
		return writeJSON(w, 200, ArtStyles(kind))
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
	s.route("POST /v1/activities/health-import", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// App (iOS) đọc Workout từ Apple Health rồi đẩy lên; backend upsert +
		// dedup với Strava. Giới hạn batch để 1 lần đồng bộ không quá tải.
		var body struct {
			Workouts []healthWorkout `json:"workouts"`
			// Nguồn kho: "apple_health" (iOS) | "health_connect" (Android). Rỗng =
			// mặc định apple_health (tương thích client iOS cũ chưa gửi field này).
			Source string `json:"source"`
			// Khoảng [from,to) để dọn buổi đã xoá trong Health. Client CHỈ gửi khi
			// đọc trọn cửa sổ (không bị cap cắt); rỗng = không reconcile.
			ReconcileFrom string `json:"reconcileFrom"`
			ReconcileTo   string `json:"reconcileTo"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		if len(body.Workouts) > 500 {
			// Bị cắt → KHÔNG reconcile (kẻo xoá nhầm buổi nằm ngoài 500 đầu).
			body.Workouts = body.Workouts[:500]
			body.ReconcileFrom, body.ReconcileTo = "", ""
		}
		imported, err := s.deps.Activities.ImportHealthWorkouts(r.Context(), uid, body.Workouts, body.Source, body.ReconcileFrom, body.ReconcileTo)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"imported": imported})
	}))
	s.route("POST /v1/health/steps-import", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		// App (iOS) đọc số bước theo ngày từ Apple Health rồi đẩy lên; backend
		// upsert + dựng lại BXH bước. BXH bước RIÊNG, không dính km chạy/kèo.
		var body struct {
			Days []healthStepDay `json:"days"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		if len(body.Days) > 400 {
			body.Days = body.Days[:400]
		}
		if err := s.deps.Activities.ImportHealthSteps(r.Context(), uid, body.Days); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
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
		now := time.Now()
		if err := s.deps.Derived.RebuildCurrent(r.Context(), task.UID, now); err != nil {
			return err
		}
		// FIX GỐC đếm-đôi Tổng km: đi-bộ = Apple − run được tính trong
		// rebuildStepLeaderboard, TRƯỚC ĐÂY chỉ chạy khi sync bước → buổi chạy mới
		// (tạo sau lần sync bước cuối) không được trừ khỏi đi-bộ → đếm đôi. Giờ mỗi
		// khi ACTIVITY đổi cũng rebuild lại đi-bộ để 2 nguồn (chạy/đi-bộ) luôn khớp,
		// không đợi lần sync Apple Health kế tiếp. Lỗi ở đây KHÔNG chặn task chính.
		if err := RebuildStepLeaderboardFor(r.Context(), s.deps.Firestore, task.UID, now); err != nil {
			slog.Error("rebuild step leaderboard on derived failed", "uid", task.UID, "error", err)
		}
		return writeJSON(w, 200, map[string]any{"ok": true, "cause": task.Cause})
	})
	s.route("POST /tasks/rebuild-period-stats", func(w http.ResponseWriter, r *http.Request) error {
		// startedAt: một buổi; startedAts: cả lô (nhập Health, một trang backfill).
		var task struct {
			UID, StartedAt string
			StartedAts     []string
		}
		if decodeJSON(r, &task) != nil || task.UID == "" {
			w.WriteHeader(204)
			return nil
		}
		var instants []time.Time
		for _, raw := range append(task.StartedAts, task.StartedAt) {
			if t, err := time.Parse(time.RFC3339, raw); err == nil {
				instants = append(instants, t)
			}
		}
		if len(instants) == 0 {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.PeriodStats.RebuildForInstants(r.Context(), task.UID, instants); err != nil {
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
	s.route("POST /tasks/recalc-contracts", func(w http.ResponseWriter, r *http.Request) error {
		// Cron 06:05 + 14:05 + 20:05 VN: link buổi chạy CHƯA gán + tính lại tiến độ kèo (GỒM
		// đi bộ: km đi-bộ-thuần + luật >=2500 bước/ngày = 1 buổi) cho MỌI kèo
		// active — để kèo luôn tươi mà user khỏi phải mở app. routeCompletion bỏ
		// qua (client lo). Ghi progress khớp logic client (distance/count/days/
		// longest/journey).
		dry := r.URL.Query().Get("dry") == "1"
		results, err := RecalcActiveContracts(r.Context(), s.deps.Firestore, dry)
		if err != nil {
			return err
		}
		linked := 0
		for _, rr := range results {
			linked += rr.NewLinked
		}
		// Chốt kèo đã qua finalizeAt theo số vừa tính — chủ kèo không cần bấm.
		finalized, err := FinalizeDueContracts(r.Context(), s.deps.Firestore, s.deps.Tasks, results, time.Now(), dry)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true, "dry": dry, "contracts": len(results), "linked": linked, "results": results, "finalized": finalized})
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
			// X-App-*: Ma Sói đọc bản app để báo "cần cập nhật" (3.8). DELETE:
			// huỷ liên kết Telegram, rời ván. PATCH: admin sửa config bot trên web.
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type, X-App-Version, X-App-Platform")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
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
		body := map[string]any{"error": httpErr.Code, "message": httpErr.Message}
		for k, v := range httpErr.Extra {
			body[k] = v
		}
		_ = writeJSON(w, httpErr.Status, body)
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
