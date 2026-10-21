package backend

import (
	"context"
	"log/slog"
	"strings"

	"cloud.google.com/go/firestore"
)

// Track chunks: app đẩy DẦN đoạn điểm/streams của buổi chạy vào
// users/{uid}/activities/{id}/track/{seq} mỗi ~10s (append-only) để không mất
// buổi khi crash/hết pin. Bấm Stop, app gọi FinalizeTracked với phần SUMMARY
// nhẹ (không kèm route/streams); backend ghép các chunk lại thành routePoints +
// streams đầy đủ rồi dựng activity như thường. Nhờ vậy KHÔNG còn "cú dump khổng
// lồ" ở cuối — dữ liệu nặng đã được sync sẵn.

func (s *ActivityService) trackCol(uid, activityID string) *firestore.CollectionRef {
	return s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID).Collection("track")
}

// readTrackChunks đọc mọi chunk theo thứ tự seq và nối thành routePoints +
// streams (mỗi stream nối theo key). Chunk lưu điểm/streams ở ĐÚNG shape cuối
// (lat/lng/timestamp gọn) nên ghép chỉ là nối mảng.
func (s *ActivityService) readTrackChunks(ctx context.Context, uid, activityID string) ([]any, map[string]any, error) {
	docs, err := s.trackCol(uid, activityID).OrderBy("seq", firestore.Asc).Documents(ctx).GetAll()
	if err != nil {
		return nil, nil, err
	}
	var points []any
	streams := map[string]any{}
	for _, d := range docs {
		m := d.Data()
		if ps, ok := m["points"].([]any); ok {
			points = append(points, ps...)
		}
		if st, ok := m["streams"].(map[string]any); ok {
			for k, v := range st {
				arr, ok := v.([]any)
				if !ok {
					continue
				}
				if cur, ok := streams[k].([]any); ok {
					streams[k] = append(cur, arr...)
				} else {
					streams[k] = append([]any{}, arr...)
				}
			}
		}
	}
	return points, streams, nil
}

func (s *ActivityService) deleteTrackChunks(ctx context.Context, uid, activityID string) {
	docs, err := s.trackCol(uid, activityID).Documents(ctx).GetAll()
	if err != nil {
		slog.WarnContext(ctx, "track.chunk_cleanup_list_failed", "error", err)
		return
	}
	for _, d := range docs {
		if _, err := d.Ref.Delete(ctx); err != nil {
			slog.WarnContext(ctx, "track.chunk_delete_failed", "error", err)
		}
	}
}

// FinalizeTracked hoàn tất buổi chạy đã sync theo chunk: ghép chunk vào phần
// summary (nhẹ) do app gửi rồi tái dùng SaveTracked (normalize + downsample +
// ghi + derived + period + notify). Xoá chunk sau khi lưu xong (best-effort).
func (s *ActivityService) FinalizeTracked(ctx context.Context, uid string, summary map[string]any) (TrackedActivityResult, error) {
	activityID := strings.TrimSpace(stringValue(summary["id"]))
	if activityID == "" || !strings.HasPrefix(activityID, "runnow-") {
		return TrackedActivityResult{}, invalidRequest()
	}
	points, streams, err := s.readTrackChunks(ctx, uid, activityID)
	if err != nil {
		return TrackedActivityResult{}, err
	}
	// Ưu tiên track đã sync qua chunk; nếu app vẫn kèm sẵn thì giữ cái to hơn.
	if len(points) > 0 {
		summary["routePoints"] = points
	}
	if len(streams) > 0 {
		summary["streams"] = streams
	}
	result, err := s.SaveTracked(ctx, uid, summary)
	if err != nil {
		return result, err
	}
	s.deleteTrackChunks(ctx, uid, activityID)
	return result, nil
}
