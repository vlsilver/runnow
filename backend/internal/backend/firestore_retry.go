package backend

import (
	"context"
	"log/slog"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// readAgainOnUnavailable chạy read, Firestore báo Unavailable thì đọc lại đúng
// một lần. Kết nối gRPC để lâu giữa hai lần tick có khi bị đầu kia đóng, lần
// đọc đầu gặp "connection reset by peer" mà client không tự thử lại với query
// dạng stream. Chỉ dùng cho việc chỉ đọc, vì đọc lại không ghi gì thêm.
func readAgainOnUnavailable[T any](ctx context.Context, read func(context.Context) (T, error)) (T, error) {
	v, err := read(ctx)
	if status.Code(err) != codes.Unavailable || ctx.Err() != nil {
		return v, err
	}
	slog.WarnContext(ctx, "firestore.read_again", "error", err)
	return read(ctx)
}
