package backend

import (
	"context"
	"log/slog"
	"strings"

	"cloud.google.com/go/firestore"
)

// Topic Live Track của PSC: tin về buổi chạy (Live báo bắt đầu, mốc km, về
// đích, ảnh giữa buổi, tin buổi chạy xong) vào topic này thay cho General.
// Admin gõ /livetrack trong topic để đặt, "/livetrack tat" để trả về General.
// Bot API không liệt kê được topic, nên lấy message_thread_id từ chính tin gõ
// lệnh. Topic bị xoá thì các hàm gửi tự rơi về General.
//
//	appConfig/telegram.liveTrackThreadId   thiếu là General

const liveTrackCommand = "/livetrack"

func liveTrackRef(db *firestore.Client) *firestore.DocumentRef {
	return db.Collection("appConfig").Doc("telegram")
}

// liveTrackThread là topic nhận tin buổi chạy; 0 là General.
func liveTrackThread(ctx context.Context, db *firestore.Client) (int64, error) {
	cfg, err := getData(ctx, liveTrackRef(db))
	if err != nil {
		return 0, err
	}
	return int64(number(cfg["liveTrackThreadId"])), nil
}

func (s *Server) liveTrackCommandText(ctx context.Context, update TelegramUpdate, arg string) (string, error) {
	if s.deps == nil || s.deps.Firestore == nil || s.deps.TelegramLinks == nil || s.deps.Games == nil {
		return "Lệnh này chưa bật trên server.", nil
	}
	uid, refusal, err := s.pscAdmin(ctx, update)
	if refusal != "" {
		return refusal, err
	}
	thread := messageThreadID(update)
	off := map[string]bool{"tat": true, "tắt": true, "off": true}[strings.ToLower(strings.TrimSpace(arg))]
	if off {
		thread = 0
	} else if thread == 0 {
		return "Gõ lệnh này trong topic muốn nhận tin buổi chạy, không phải General.", nil
	}
	var v any = thread
	if thread == 0 {
		v = firestore.Delete
	}
	if _, err := liveTrackRef(s.deps.Firestore).Set(ctx, map[string]any{"liveTrackThreadId": v, "liveTrackSetBy": uid, "liveTrackSetAt": s.now()}, firestore.MergeAll); err != nil {
		return adminFailedText, err
	}
	slog.InfoContext(ctx, "telegram.live_track_set", "uid", uid, "thread", thread)
	if off {
		return "Tin buổi chạy về lại General.", nil
	}
	return "Topic này giờ nhận tin buổi chạy: Live bắt đầu, mốc km, về đích, ảnh giữa buổi và tin chạy xong.", nil
}
