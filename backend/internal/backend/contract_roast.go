package backend

import (
	"context"
	"fmt"
	"log/slog"
	"sort"
	"strings"

	"cloud.google.com/go/firestore"
)

// Khi 1 KÈO (runContract) đóng mà có người ĐĂNG KÝ tham gia nhưng KHÔNG hoàn
// thành mục tiêu, để 3i "bôi tro trét trấu" đích danh họ lên group cho vui.
// App (chủ kèo) gọi POST /v1/contracts/announce-result sau khi chốt kèo; backend
// enqueue task sang bot. Chỉ kèo PUBLIC (club) mới bêu, và mỗi kèo chỉ bêu 1 lần
// (đánh dấu roastedAt trên chính doc kèo).

type roastFailer struct {
	name     string
	progress string // tiến độ đạt được, đã format theo metric
}

// formatContractMetricValue format 1 giá trị theo đơn vị của metric kèo — để
// bot đọc đúng "km / buổi / ngày / lần".
func formatContractMetricValue(metric string, v float64) string {
	switch metric {
	case "distance", "longestRun":
		if v == float64(int64(v)) {
			return fmt.Sprintf("%d km", int64(v))
		}
		return fmt.Sprintf("%.1f km", v)
	case "activityCount":
		return fmt.Sprintf("%d buổi", int64(v+0.5))
	case "activeDays":
		return fmt.Sprintf("%d ngày", int64(v+0.5))
	case "routeCompletion":
		return fmt.Sprintf("%d lần", int64(v+0.5))
	default:
		return fmt.Sprintf("%.1f", v)
	}
}

// contractMetTarget: participant đạt mục tiêu chưa. Với km dùng ngưỡng mm để
// tránh sai số dấu phẩy động (khớp contractTargetMet phía client).
func contractMetTarget(metric string, progress, target float64) bool {
	if metric == "distance" || metric == "longestRun" {
		return int64(progress*1000+0.5) >= int64(target*1000+0.5)
	}
	return progress+1e-6 >= target
}

// AnnounceContractResult bêu những người trượt của 1 kèo vừa đóng. callerUID
// phải là người tạo kèo. No-op êm nếu: bot/telegram tắt, kèo không public, kèo
// chưa đóng, đã bêu rồi, hoặc không có ai trượt.
func (s *ActivityService) AnnounceContractResult(ctx context.Context, callerUID, contractID string) error {
	if !s.telegram.Enabled() || contractID == "" {
		return nil
	}
	ref := s.db.Collection("runContracts").Doc(contractID)
	data, err := getData(ctx, ref)
	if err != nil {
		return err
	}
	if data == nil {
		return nil
	}
	// Chỉ người tạo kèo mới được kích hoạt (chống lạm dụng gọi hộ người khác).
	if stringValue(data["creatorUid"]) != callerUID {
		return nil
	}
	// Chỉ kèo PUBLIC trong club — kèo riêng tư không bêu lên group.
	if stringValue(data["visibility"]) != "club" {
		return nil
	}
	// Kèo phải đã ĐÓNG (completed/failed).
	switch stringValue(data["status"]) {
	case "completed", "failed":
	default:
		return nil
	}
	// Đã bêu rồi thì thôi (app gọi lại/retry không bắn trùng).
	if _, done := data["roastedAt"]; done {
		return nil
	}

	metric := stringValue(data["metric"])
	target := number(data["targetValue"])
	participants, _ := data["participants"].(map[string]any)

	var failers []roastFailer
	for uid, raw := range participants {
		p, ok := raw.(map[string]any)
		if !ok {
			continue
		}
		progress := number(p["progressValue"])
		if contractMetTarget(metric, progress, target) {
			continue // đạt mục tiêu — tha
		}
		name := uid
		if profile, perr := resolveProfile(ctx, s.db, uid); perr == nil {
			if n := preferredName(profile); strings.TrimSpace(n) != "" {
				name = n
			}
		}
		failers = append(failers, roastFailer{
			name:     name,
			progress: formatContractMetricValue(metric, progress),
		})
	}
	// Không ai trượt → không bêu (đánh dấu để khỏi tính lại mỗi lần gọi).
	if len(failers) == 0 {
		_, _ = ref.Set(ctx, map[string]any{"roastedAt": firestore.ServerTimestamp}, firestore.MergeAll)
		return nil
	}
	// Thứ tự ổn định (theo tên) để lời bêu không đổi mỗi lần chạy.
	sort.Slice(failers, func(i, j int) bool { return failers[i].name < failers[j].name })

	title := strings.TrimSpace(stringValue(data["title"]))
	if title == "" {
		title = "kèo"
	}
	targetLabel := formatContractMetricValue(metric, target)

	text := ""
	if s.broadcast != nil && s.broadcast.Enabled() {
		text = s.broadcast.ContractRoast(ctx, title, targetLabel, failers)
	}
	if text == "" {
		text = contractRoastPlain(title, targetLabel, failers)
	}
	// Claim cờ TRƯỚC khi gửi để retry không bêu lặp; gửi lỗi sau claim thì thôi.
	claimed, err := claimOnce(ctx, s.db, ref, "roastedAt", map[string]any{
		"roastedAt": firestore.ServerTimestamp,
	})
	if err != nil {
		return err
	}
	if !claimed {
		return nil
	}
	if err := s.telegram.SendChatMessage(ctx, s.telegram.ChatID(), text); err != nil {
		slog.WarnContext(ctx, "roast.telegram_send_failed_after_claim", "error", err)
		return nil
	}
	if s.broadcast != nil && s.broadcast.Enabled() {
		if err := s.broadcast.RecordBroadcast(ctx, s.telegram.ChatID(), text); err != nil {
			slog.WarnContext(ctx, "roast.broadcast_record_failed", "error", err)
		}
	}
	return nil
}

// contractRoastPlain: bản mẫu tĩnh khi bot tắt/model lỗi — vẫn bêu được, chỉ là
// không "mặn" bằng giọng AI.
func contractRoastPlain(title, targetLabel string, failers []roastFailer) string {
	names := make([]string, len(failers))
	for i, f := range failers {
		names[i] = f.name
	}
	return fmt.Sprintf("😏 Kèo \"%s\" (mục tiêu %s) đã đóng — và %s đăng ký cho vui chứ có về đích đâu. Hẹn kèo sau gỡ gạc nha!",
		title, targetLabel, strings.Join(names, ", "))
}
