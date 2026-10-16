package backend

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Lệnh admin Ma Sói trong DM với bot (W2c): cùng việc với các route
// /v1/games/{id}/admin/*, áp lên ván ở gameState/current. Chỉ nhận trong DM, vì
// /xem và lỗi của lệnh không phải việc của cả group.

const adminOnlyText = "Lệnh này chỉ dành cho admin Ma Sói."

var adminCommands = map[string]bool{"/pause": true, "/resume": true, "/extend": true, "/retry": true, "/xem": true, "/cancel": true}

// adminReply trả câu trả lời (và nút, với /cancel) cho một lệnh admin. Lỗi trả
// về để log; lỗi tạm thời thì serveTelegramUpdate trả 5xx cho Telegram gửi lại.
func (s *Server) adminReply(ctx context.Context, update TelegramUpdate, cmd, arg string) (string, any, error) {
	if update.Message.Chat.Type != "private" {
		return "Lệnh admin Ma Sói chỉ dùng trong tin nhắn riêng với 3i.", nil, nil
	}
	if s.deps == nil || s.deps.Games == nil || s.deps.TelegramLinks == nil {
		slog.ErrorContext(ctx, "telegram.admin_unconfigured", "updateId", update.UpdateID)
		return adminFailedText, nil, nil
	}
	uid, gameID, err := s.adminTarget(ctx, update.Message.From.ID)
	if err != nil || uid == "" {
		text, err := adminErrText(err)
		return text, nil, err
	}
	if gameID == "" {
		return "Chưa có ván Ma Sói nào.", nil, nil
	}
	text, markup, err := s.runAdminCommand(ctx, gameID, uid, cmd, arg)
	if err != nil {
		text, err := adminErrText(err)
		return text, nil, err
	}
	return text, markup, nil
}

// adminTarget: uid rỗng (không lỗi) là Telegram chưa liên kết; uid không phải
// admin thì trả errNotAdmin.
func (s *Server) adminTarget(ctx context.Context, tgID int64) (uid, gameID string, err error) {
	uid, err = s.deps.TelegramLinks.UIDForTelegram(ctx, tgID)
	if err != nil || uid == "" {
		return "", "", err
	}
	if err := s.deps.Games.RequireAdmin(ctx, uid); err != nil {
		return "", "", err
	}
	gameID, err = s.deps.Games.currentGameID(ctx)
	return uid, gameID, err
}

const adminFailedText = "Chưa làm được lúc này, bạn thử lại sau nhé."

// adminErrText đổi lỗi thành câu trả lời: lỗi của store (409, 422…) hiện đúng
// câu của nó; lỗi khác thì trả câu chung kèm lỗi. err nil là Telegram chưa
// liên kết.
func adminErrText(err error) (string, error) {
	var he *HTTPError
	switch {
	case err == nil, errors.Is(err, errNotAdmin):
		return adminOnlyText, nil
	case errors.As(err, &he) && he.Status < 500:
		return he.Message, nil
	}
	return adminFailedText, err
}

func (s *Server) runAdminCommand(ctx context.Context, gameID, uid, cmd, arg string) (string, any, error) {
	games, now := s.deps.Games, time.Now()
	var text string
	var err error
	switch cmd {
	case "/xem":
		text, err = games.AdminSummary(ctx, gameID)
		return text, nil, err
	case "/cancel":
		data, err := gameButton{GameID: gameID, Op: opCancel}.data()
		if err != nil {
			return "", nil, err
		}
		return "Huỷ ván Ma Sói đang chạy? Huỷ rồi thì không chơi tiếp được.",
			inlineKeyboard([][]map[string]any{{{"text": "Huỷ ván", "callback_data": data}}}), nil
	case "/pause":
		text, err = "Đã tạm dừng ván.", games.AdminPause(ctx, gameID, uid, now)
	case "/resume":
		text, err = "Ván đã chạy tiếp.", games.AdminResume(ctx, gameID, uid, now)
	case "/extend":
		minutes, perr := strconv.Atoi(arg)
		if perr != nil || minutes < 1 || minutes > maxExtendMinutes {
			return fmt.Sprintf("Gõ /extend <số phút>, từ 1 tới %d.", maxExtendMinutes), nil, nil
		}
		text, err = fmt.Sprintf("Đã dời hạn thêm %d phút.", minutes), games.AdminExtend(ctx, gameID, uid, minutes, now)
	case "/retry":
		var n int
		n, err = games.AdminRetryOutbox(ctx, gameID, uid, now)
		text = fmt.Sprintf("Đã xếp lại %d tin lỗi để gửi lại.", n)
	default:
		return "", nil, fmt.Errorf("lệnh admin lạ %q", cmd)
	}
	if err != nil {
		return "", nil, err
	}
	s.kickGameFlush(ctx, gameID)
	return text, nil, nil
}

// cancelButtonReply xử lý nút "Huỷ ván" của /cancel. Telegram gửi lại cú bấm
// thì AdminCancel lần hai trả "Ván đã kết thúc hoặc đã huỷ.".
func (s *Server) cancelButtonReply(ctx context.Context, gameID, uid string) (string, error) {
	err := s.deps.Games.RequireAdmin(ctx, uid)
	if err == nil {
		if err = s.deps.Games.AdminCancel(ctx, gameID, uid, time.Now()); err == nil {
			s.kickGameFlush(ctx, gameID)
			return "Đã huỷ ván.", nil
		}
	}
	return adminErrText(err)
}

// AdminSummary là tin /xem: chỉ số đếm, không lộ ai chọn gì (C5). Không đếm
// hành động đêm, vì admin cũng có thể là người chơi.
func (s *GameStore) AdminSummary(ctx context.Context, gameID string) (string, error) {
	snap, err := s.readStartGame(ctx, gameID)
	if err != nil {
		return "", err
	}
	g, game := snap.Data(), snap.Ref
	lines := []string{"Trạng thái: " + statusLabel(g)}
	if stringValue(g["status"]) == gameRunning {
		lines = append(lines, "Lượt: "+phaseLabelOf(g))
		if d := nextDeadline(g); d != nil {
			lines = append(lines, "Hạn: "+vnTime(*d))
		}
	}
	players, err := s.loadPlayers(ctx, game)
	if err != nil {
		return "", err
	}
	alive := 0
	for _, p := range players {
		if p.data["alive"] != false {
			alive++
		}
	}
	lines = append(lines, fmt.Sprintf("Còn sống: %d/%d", alive, len(players)))
	if phase := werewolf.Phase(stringValue(g["phase"])); stringValue(g["status"]) == gameRunning && (phase == werewolf.PhaseDay || phase == werewolf.PhaseTrial) {
		docs, err := roundRef(game, int(number(g["round"]))).Collection("actions").
			Where("kind", "in", []string{string(werewolf.KindNominate), string(werewolf.KindVote)}).Documents(ctx).GetAll()
		if err != nil {
			return "", err
		}
		counts := map[string]int{}
		for _, d := range docs {
			if d.Data()["cleared"] != true {
				counts[stringValue(d.Data()["kind"])]++
			}
		}
		lines = append(lines, fmt.Sprintf("Đề cử: %d, phiếu: %d", counts[string(werewolf.KindNominate)], counts[string(werewolf.KindVote)]))
	}
	docs, err := game.Collection("outbox").Where("status", "in", []string{outboxPending, outboxSending, outboxFailed}).Documents(ctx).GetAll()
	if err != nil {
		return "", err
	}
	waiting, failed := 0, 0
	for _, d := range docs {
		switch {
		case d.Data()["status"] != outboxFailed:
			waiting++
		case d.Data()["retriedAs"] == nil:
			failed++
		}
	}
	line := fmt.Sprintf("Tin chờ gửi: %d, tin lỗi: %d", waiting, failed)
	if failed > 0 {
		line += " (gõ /retry để gửi lại)"
	}
	return strings.Join(append(lines, line), "\n"), nil
}
