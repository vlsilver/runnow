package backend

import (
	"context"
	"fmt"
	"log/slog"
	"strings"

	"cloud.google.com/go/firestore"
)

// AnnounceCoachPlan báo lên group khi có người mở hoặc đổi một giáo án AI Coach
// CÔNG KHAI. No-op êm nếu: telegram tắt, không đọc được doc, hoặc giáo án riêng
// tư (private không lên group).
func (s *ActivityService) AnnounceCoachPlan(ctx context.Context, ownerUID string, changed bool) error {
	if !s.telegram.Enabled() || ownerUID == "" {
		return nil
	}
	data, err := getData(ctx, s.db.Collection("coachPlans").Doc(ownerUID))
	if err != nil || data == nil {
		return err
	}
	if stringValue(data["visibility"]) != "club" {
		return nil
	}

	name := ownerUID
	if profile, perr := resolveProfile(ctx, s.db, ownerUID); perr == nil {
		if n := preferredName(profile); strings.TrimSpace(n) != "" {
			name = n
		}
	}
	goal := strings.TrimSpace(stringValue(data["goal"]))
	if goal == "" {
		goal = "giáo án chạy"
	}
	text := coachAnnouncePlain(name, goal, int(number(data["weeks"])), changed)

	if err := s.telegram.SendChatMessage(ctx, s.telegram.ChatID(), text); err != nil {
		return err
	}
	if s.broadcast != nil && s.broadcast.Enabled() {
		if err := s.broadcast.RecordBroadcast(ctx, s.telegram.ChatID(), text); err != nil {
			slog.WarnContext(ctx, "coach.announce_record_failed", "error", err)
		}
	}
	return nil
}

func coachAnnouncePlain(name, goal string, weeks int, changed bool) string {
	wk := ""
	if weeks > 0 {
		wk = fmt.Sprintf(" · %d tuần", weeks)
	}
	if changed {
		return fmt.Sprintf("🔁 %s vừa đổi giáo án: %s%s. Ai đang theo nhớ ngó lại lịch mới nhé!", name, goal, wk)
	}
	return fmt.Sprintf("🎯 %s vừa mở giáo án chung: %s%s.\nVào tab Kèo, bấm vào giáo án để tham gia — 3i dẫn lịch tập cho cả nhóm!", name, goal, wk)
}

// AnnounceNewContract báo lên group khi có kèo CÔNG KHAI mới được tạo. No-op êm
// nếu: telegram tắt, kèo riêng tư, người gọi không phải chủ, hoặc đã báo rồi
// (announcedAt) — app gọi lại/retry không bắn trùng.
func (s *ActivityService) AnnounceNewContract(ctx context.Context, callerUID, contractID string) error {
	if !s.telegram.Enabled() || contractID == "" {
		return nil
	}
	ref := s.db.Collection("runContracts").Doc(contractID)
	data, err := getData(ctx, ref)
	if err != nil || data == nil {
		return err
	}
	if stringValue(data["creatorUid"]) != callerUID {
		return nil
	}
	if stringValue(data["visibility"]) != "club" {
		return nil
	}
	if _, done := data["announcedAt"]; done {
		return nil
	}

	name := callerUID
	if profile, perr := resolveProfile(ctx, s.db, callerUID); perr == nil {
		if n := preferredName(profile); strings.TrimSpace(n) != "" {
			name = n
		}
	}
	title := strings.TrimSpace(stringValue(data["title"]))
	if title == "" {
		title = "một kèo mới"
	}
	targetLabel := formatContractMetricValue(stringValue(data["metric"]), number(data["targetValue"]))
	text := fmt.Sprintf("🔥 %s vừa mở kèo: %s — mục tiêu %s.\nVào tab Kèo bấm tham gia, đừng để bị bỏ lại!", name, title, targetLabel)

	if err := s.telegram.SendChatMessage(ctx, s.telegram.ChatID(), text); err != nil {
		return err
	}
	if s.broadcast != nil && s.broadcast.Enabled() {
		if err := s.broadcast.RecordBroadcast(ctx, s.telegram.ChatID(), text); err != nil {
			slog.WarnContext(ctx, "contract.announce_new_record_failed", "error", err)
		}
	}
	_, err = ref.Set(ctx, map[string]any{"announcedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	return err
}
