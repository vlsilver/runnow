package backend

import (
	"context"
	"errors"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func TestReadAgainOnUnavailable(t *testing.T) {
	unavailable := status.Error(codes.Unavailable, "connection reset by peer")
	other := status.Error(codes.PermissionDenied, "denied")
	cases := []struct {
		name      string
		errs      []error // lỗi của từng lần đọc
		wantCalls int
		want      error
	}{
		{"đọc được ngay", []error{nil}, 1, nil},
		{"rớt kết nối một lần thì đọc lại", []error{unavailable, nil}, 2, nil},
		{"rớt hai lần thì trả lỗi", []error{unavailable, unavailable}, 2, unavailable},
		{"lỗi khác không đọc lại", []error{other}, 1, other},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			calls := 0
			got, err := readAgainOnUnavailable(context.Background(), func(context.Context) (int, error) {
				calls++
				return calls, c.errs[calls-1]
			})
			if calls != c.wantCalls || !errors.Is(err, c.want) {
				t.Fatalf("calls=%d err=%v, muốn calls=%d err=%v", calls, err, c.wantCalls, c.want)
			}
			if err == nil && got != calls {
				t.Fatalf("trả %d, muốn kết quả lần đọc cuối %d", got, calls)
			}
		})
	}

	t.Run("context đã huỷ thì không đọc lại", func(t *testing.T) {
		ctx, cancel := context.WithCancel(context.Background())
		cancel()
		calls := 0
		_, err := readAgainOnUnavailable(ctx, func(context.Context) (int, error) {
			calls++
			return 0, unavailable
		})
		if calls != 1 || !errors.Is(err, unavailable) {
			t.Fatalf("calls=%d err=%v", calls, err)
		}
	})
}
