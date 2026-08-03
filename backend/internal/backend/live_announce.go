package backend

import (
	"context"
	"fmt"
	"log/slog"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
)

// Tường thuật LIVE: app 3i gọi POST /v1/live/announce tại các mốc trong lúc tập
// (bắt đầu / qua mỗi 5km / về đích). Bot viết 1 câu bằng giọng của nó rồi bắn
// vào group. Event-driven (app tự biết mốc) nên KHÔNG cần cron poll.
//
// Chỉ member để hồ sơ công khai mới được tường thuật (như live-view club).
// Mỗi sự kiện đánh dấu trong liveAnnounceState/{activityID} để app gọi lại
// (retry) không bắn trùng.

const (
	liveEventStart     = "start"
	liveEventMilestone = "milestone"
	liveEventFinish    = "finish"
)

func liveAnnounceMarkerKey(event string, milestoneKm int) string {
	if event == liveEventMilestone {
		return fmt.Sprintf("km-%d", milestoneKm)
	}
	return event
}

func (s *ActivityService) LiveAnnounce(ctx context.Context, uid, activityID, event string, distanceMeters, movingTimeSeconds float64, milestoneKm int) error {
	if !s.telegram.Enabled() {
		return nil
	}
	switch event {
	case liveEventStart, liveEventMilestone, liveEventFinish:
	default:
		return nil
	}
	profile, err := resolveProfile(ctx, s.db, uid)
	if err != nil {
		return err
	}
	// Tôn trọng riêng tư: chỉ tường thuật member để hồ sơ công khai, giống
	// live-view của club. Người để private không bị khoe lên group.
	if stringValue(profile["profileVisibility"]) != "public" {
		return nil
	}
	displayName := preferredName(profile)

	marker := liveAnnounceMarkerKey(event, milestoneKm)
	stateRef := s.db.Collection("liveAnnounceState").Doc(activityID)
	state, err := getData(ctx, stateRef)
	if err != nil {
		return err
	}
	if state != nil {
		if done, _ := state[marker].(bool); done {
			return nil // đã báo sự kiện này rồi
		}
	}

	hasBot := s.broadcast != nil && s.broadcast.Enabled()
	text := ""
	if hasBot {
		text = s.broadcast.LiveAnnouncement(ctx, displayName, event, distanceMeters, movingTimeSeconds, milestoneKm)
	}
	if text == "" {
		text = liveAnnouncePlain(displayName, event, distanceMeters, movingTimeSeconds, milestoneKm)
	}
	if err := s.telegram.SendChatMessage(ctx, s.telegram.ChatID(), text); err != nil {
		return err
	}
	if hasBot {
		if err := s.broadcast.RecordBroadcast(ctx, s.telegram.ChatID(), text); err != nil {
			slog.WarnContext(ctx, "live.broadcast_record_failed", "error", err)
		}
	}

	update := map[string]any{marker: true, "uid": uid, "updatedAt": firestore.ServerTimestamp}
	if event == liveEventFinish {
		// Chống double-notify: buổi này đã live-finish. Khi bản Strava trùng
		// sync về sau, NotifyTelegram dò mốc dưới đây để nuốt tin lặp. startMs
		// nằm sẵn trong id "runnow-<ms>".
		if ms := runnowStartMs(activityID); ms > 0 {
			update["liveFinishStartMs"] = ms
			if _, err := s.db.Collection("users").Doc(uid).Set(ctx, map[string]any{
				"lastLiveFinishStartMs": ms,
				"lastLiveFinishAt":      firestore.ServerTimestamp,
			}, firestore.MergeAll); err != nil {
				slog.WarnContext(ctx, "live.finish_marker_failed", "error", err)
			}
		}
	}
	_, err = stateRef.Set(ctx, update, firestore.MergeAll)
	return err
}

// runnowStartMs tách mốc thời gian bắt đầu (ms) từ id buổi 3i "runnow-<ms>".
func runnowStartMs(activityID string) int64 {
	if !strings.HasPrefix(activityID, "runnow-") {
		return 0
	}
	ms, err := strconv.ParseInt(strings.TrimPrefix(activityID, "runnow-"), 10, 64)
	if err != nil {
		return 0
	}
	return ms
}

// liveFinishAlreadyCovered: buổi Strava đang xét có TRÙNG một buổi vừa được
// tường thuật live không (cùng người, xuất phát lệch < 10 phút, mốc live trong
// 6h qua). Nếu có thì đừng notify lần nữa. profile là bản merge users+public
// (đã có lastLiveFinishStartMs/At do LiveAnnounce ghi lúc finish).
func liveFinishAlreadyCovered(profile, activity map[string]any, now time.Time) bool {
	finishStartMs := int64(number(profile["lastLiveFinishStartMs"]))
	if finishStartMs == 0 {
		return false
	}
	finishAt, ok := profile["lastLiveFinishAt"].(time.Time)
	if !ok || now.Sub(finishAt) > 6*time.Hour {
		return false
	}
	started, err := time.Parse(time.RFC3339, stringValue(activity["startedAt"]))
	if err != nil {
		return false
	}
	diff := started.UnixMilli() - finishStartMs
	if diff < 0 {
		diff = -diff
	}
	return diff < (10 * time.Minute).Milliseconds()
}

func liveAnnouncePlain(name, event string, distanceMeters, movingTimeSeconds float64, milestoneKm int) string {
	n := strings.TrimSpace(name)
	switch event {
	case liveEventStart:
		return fmt.Sprintf("🏃 %s vừa bắt đầu một buổi tập — cùng cổ vũ nào!", n)
	case liveEventMilestone:
		return fmt.Sprintf("🔥 %s vừa chạm mốc %dkm! Cố lên!", n, milestoneKm)
	case liveEventFinish:
		return fmt.Sprintf("🏁 %s về đích: %s trong %s. Quá đỉnh!", n, formatDistanceKm(distanceMeters), formatDurationHMS(int64(movingTimeSeconds)))
	}
	return ""
}
