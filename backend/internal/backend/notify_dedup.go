package backend

import (
	"context"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// claimOnce đặt cờ dedup [markerField] trên [ref] một cách ATOMIC (transaction),
// trả về true nếu LẦN NÀY là lần claim (chưa ai đặt cờ trước đó). Dùng TRƯỚC khi
// gửi Telegram/Gemini để retry Cloud Tasks (tuần tự) lẫn giao song song không
// bắn lặp: đã claim thì lần sau bỏ qua. Đánh đổi: nếu gửi HỎNG sau khi claim thì
// mất tin — chấp nhận "mất tin còn hơn gửi đôi".
//
// [update] là map ghi khi claim (thường {markerField: ServerTimestamp}, hoặc kèm
// field phụ). Doc chưa tồn tại vẫn claim được (dùng cho state doc tạo mới).
func claimOnce(
	ctx context.Context,
	db *firestore.Client,
	ref *firestore.DocumentRef,
	markerField string,
	update map[string]any,
) (bool, error) {
	claimed := false
	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, gerr := tx.Get(ref)
		if gerr != nil && status.Code(gerr) != codes.NotFound {
			return gerr // lỗi Firestore thật → abort, chưa gửi gì nên an toàn retry
		}
		if gerr == nil && snap.Exists() && snap.Data()[markerField] != nil {
			claimed = false // ai đó đã claim/gửi rồi
			return nil
		}
		claimed = true
		return tx.Set(ref, update, firestore.MergeAll)
	})
	return claimed, err
}
