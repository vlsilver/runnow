package backend

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"strconv"
	"time"
)

// Route của bot cá nhân. Api chỉ ghi và enqueue; việc gọi model chạy ở bot
// service qua task agent-dm và agent-turn. Cập nhật dùng POST vì CORS của api
// chỉ cho GET, POST, DELETE.
func (s *Server) agentRoutes() {
	s.route("GET /v1/agents/me", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		me, err := s.deps.Agents.Me(r.Context(), uid, s.now())
		if err != nil {
			return err
		}
		if m := s.deps.ManagedBots; m != nil && me.Agent != nil && me.Agent.Created {
			if me.Telegram, err = m.Status(r.Context(), uid, me.Agent.Name); err != nil {
				return err
			}
		}
		return writeJSON(w, 200, me)
	}))
	s.route("POST /v1/agents/me", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Name    string `json:"name"`
			Persona string `json:"persona"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		p, err := s.deps.Agents.SaveProfile(r.Context(), uid, body.Name, body.Persona, s.now())
		if err != nil {
			return err
		}
		if m := s.deps.ManagedBots; m != nil {
			m.ProfileChanged(r.Context(), uid)
		}
		return writeJSON(w, 200, p)
	}))
	// Đồng ý gửi dữ liệu cho AI, version là consentVersion của GET /v1/agents/me.
	s.route("POST /v1/agents/me/consent", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Version int `json:"version"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		c, err := s.deps.Agents.RecordConsent(r.Context(), uid, body.Version, s.now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, c)
	}))
	s.route("POST /v1/agents/me/memories", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Text string `json:"text"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		if err := s.deps.Agents.requireAgent(r.Context(), uid); err != nil {
			return err
		}
		m, err := s.deps.Agents.AddMemory(r.Context(), uid, "", body.Text, agentSourceManual, s.now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, m)
	}))
	s.route("POST /v1/agents/me/memories/{id}", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Text string `json:"text"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		if err := s.deps.Agents.requireAgent(r.Context(), uid); err != nil {
			return err
		}
		m, err := s.deps.Agents.UpdateMemory(r.Context(), uid, r.PathValue("id"), body.Text, s.now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, m)
	}))
	s.route("DELETE /v1/agents/me/memories/{id}", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Agents.requireAgent(r.Context(), uid); err != nil {
			return err
		}
		if err := s.deps.Agents.DeleteMemory(r.Context(), uid, r.PathValue("id")); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	// Xoá lần hai vẫn 200 như xoá mục nhớ, để app bấm lại không báo lỗi.
	s.route("DELETE /v1/agents/me/learned/{id}", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Agents.requireMember(r.Context(), uid); err != nil {
			return err
		}
		if err := s.deps.Agents.ForgetLearnedFact(r.Context(), uid, r.PathValue("id"), s.now()); err != nil && !errors.Is(err, errLearnedNotFound) {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	// "Đừng học về tôi". Bật lần hai vẫn 200 và chạy lại phần xoá, để app bấm
	// lại được khi lần trước lỗi giữa chừng.
	s.route("POST /v1/agents/me/no-learn", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			On *bool `json:"on"`
		}
		if decodeJSON(r, &body) != nil || body.On == nil {
			return invalidRequest()
		}
		if err := s.deps.Agents.requireMember(r.Context(), uid); err != nil {
			return err
		}
		if err := s.deps.Agents.SetNoLearn(r.Context(), uid, *body.On, s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"noLearn": *body.On})
	}))
	s.route("GET /v1/agents/group-facts", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		facts, err := s.deps.Agents.GroupFacts(r.Context(), uid, s.now())
		if err != nil {
			return err
		}
		admin := s.deps.Games.RequireAdmin(r.Context(), uid)
		if admin != nil && !errors.Is(admin, errNotAdmin) {
			return admin
		}
		return writeJSON(w, 200, map[string]any{"facts": facts, "canDelete": admin == nil})
	}))
	s.route("DELETE /v1/agents/group-facts/{id}", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Games.RequireAdmin(r.Context(), uid); err != nil {
			return err
		}
		if err := s.deps.Agents.ForgetGroupFact(r.Context(), uid, r.PathValue("id"), s.now()); err != nil && !errors.Is(err, errLearnedNotFound) {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("GET /v1/agents/me/dm", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		page, err := s.deps.Agents.DM(r.Context(), uid, r.URL.Query().Get("cursor"), r.URL.Query().Get("after"))
		if err != nil {
			return err
		}
		return writeJSON(w, 200, page)
	}))
	s.route("POST /v1/agents/me/dm", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Text string `json:"text"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		msg, err := s.PostChannelDM(r.Context(), uid, agentChannelApp, body.Text)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, msg)
	}))
	s.route("GET /v1/agents/room", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		page, err := s.deps.Agents.Room(r.Context(), agentMainRoom, uid, r.URL.Query().Get("cursor"), r.URL.Query().Get("after"))
		if err != nil {
			return err
		}
		return writeJSON(w, 200, page)
	}))
	s.route("POST /v1/agents/room", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Text string `json:"text"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		seq, err := s.PostRoomMessage(r.Context(), agentMainRoom, uid, body.Text)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"seq": seq})
	}))
	s.route("POST /v1/agents/room/messages/{seq}/report", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body struct {
			Block bool `json:"block"`
		}
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		seq, err := strconv.ParseInt(r.PathValue("seq"), 10, 64)
		if err != nil {
			return invalidRequest()
		}
		text, err := s.deps.Agents.ReportRoom(r.Context(), agentMainRoom, uid, seq, body.Block, s.now())
		if err != nil {
			return err
		}
		// Admin có thể chưa liên kết Telegram, khi đó DM không tới ai: log để
		// vẫn tra được báo cáo mà không phải mở Firestore.
		slog.InfoContext(r.Context(), "agent.report", "seq", seq, "reporter", uid, "block", body.Block)
		if err := s.alertChatReport(r.Context(), text); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	s.route("GET /v1/agents/blocks", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		blocks, err := s.deps.Agents.Blocks(r.Context(), uid)
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"blocks": blocks})
	}))
	s.route("DELETE /v1/agents/blocks/{uid}", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Agents.Unblock(r.Context(), uid, r.PathValue("uid"), s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
}

// PostChannelDM ghi tin của chủ vào chat riêng của kênh channel (app hoặc
// telegram) rồi hẹn task agent-dm để bot trả lời. Route app gọi hàm này với
// kênh app; webhook Telegram gọi với kênh telegram. Lỗi trả ra giữ nguyên
// HTTPError của PostDM (agent_disabled, consent_required, agent_not_found,
// invalid_text, too_fast) để kênh gọi tự chọn câu báo người dùng.
func (s *Server) PostChannelDM(ctx context.Context, uid, channel, text string) (AgentMessage, error) {
	msg, err := s.deps.Agents.PostDM(ctx, uid, text, channel, s.now())
	if err != nil {
		return AgentMessage{}, err
	}
	// Tin đã ghi mà enqueue lỗi thì báo lỗi cho kênh gọi: không có tick nào
	// trả lời bù. Chủ gửi tin kế thì bot trả lời gộp cả hai.
	if err := s.publishAgentTask(ctx, agentDMTaskFor(uid, channel, msg.Seq)); err != nil {
		return AgentMessage{}, err
	}
	return msg, nil
}

// PostRoomMessage ghi tin của người vào phòng roomID rồi hẹn lượt bot đầu
// tiên của phòng đó. Route app gọi với phòng main; webhook Telegram gọi với
// phòng tg-psc.
func (s *Server) PostRoomMessage(ctx context.Context, roomID, uid, text string) (int64, error) {
	wall := s.now()
	seq, err := s.deps.Agents.PostRoom(ctx, roomID, uid, text, wall)
	if err != nil {
		return 0, err
	}
	if err := s.publishAgentTask(ctx, agentTurnTaskFor(roomID, seq, wall.Add(agentFirstTurnDelay))); err != nil {
		return 0, err
	}
	return seq, nil
}

func (s *Server) publishAgentTask(ctx context.Context, task PublishTask) error {
	publish := s.enqueueTask()
	if publish == nil {
		return errors.New("agent: chưa cấu hình Cloud Tasks")
	}
	if _, err := publish(ctx, task); err != nil {
		slog.ErrorContext(ctx, "agent.enqueue_failed", "path", task.HandlerPath, "error", err)
		return err
	}
	return nil
}

// agentDM là chặng của bot: trả lời tin chat riêng. Payload hỏng thì 204 cho
// task thôi retry; model hay Firestore lỗi thì trả lỗi để task chạy lại. Task
// không có channel là của bản trước, khi chỉ có kênh app.
func (s *Server) agentDM(w http.ResponseWriter, r *http.Request) error {
	var task agentDMTask
	err := decodeJSON(r, &task)
	if task.Channel == "" {
		task.Channel = agentChannelApp
	}
	if _, ok := agentDMChannels[task.Channel]; err != nil || !ok || task.UID == "" || task.Seq < 1 {
		slog.WarnContext(r.Context(), "agent.dm_bad_payload", "channel", task.Channel)
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if s.deps.AgentBrain == nil {
		return errors.New("agent-dm cần Gemini")
	}
	if err := s.deps.AgentBrain.ReplyDM(r.Context(), task.UID, task.Channel, task.Seq, s.now()); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// agentTurn: task không có roomID là của bản trước, khi chỉ có phòng main.
func (s *Server) agentTurn(w http.ResponseWriter, r *http.Request) error {
	var task agentTurnTask
	err := decodeJSON(r, &task)
	if task.RoomID == "" {
		task.RoomID = agentMainRoom
	}
	if _, ok := agentRoomChannels[task.RoomID]; err != nil || !ok || task.AfterSeq < 1 {
		slog.WarnContext(r.Context(), "agent.turn_bad_payload", "room", task.RoomID)
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if s.deps.AgentBrain == nil {
		return errors.New("agent-turn cần Gemini")
	}
	if err := s.deps.AgentBrain.RoomTurn(r.Context(), task.RoomID, task.AfterSeq, s.now()); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

// enqueueLearn hẹn task học ký ức của khung 30 phút hiện tại; việc học chạy ở
// task riêng vì gọi model lâu hơn ngân sách của tick.
func (s *Server) enqueueLearn(ctx context.Context, now time.Time) error {
	publish := s.enqueueTask()
	if publish == nil {
		return errors.New("agent-learn: chưa cấu hình Cloud Tasks")
	}
	_, err := publish(ctx, agentLearnTaskFor(now))
	return err
}

// agentLearn học một lô tin mới. Cờ đã tắt mà task còn trong queue thì 204.
func (s *Server) agentLearn(w http.ResponseWriter, r *http.Request) error {
	if s.deps.Learn == nil {
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if err := s.deps.Learn.Run(r.Context(), s.now()); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
