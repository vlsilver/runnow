package backend

import (
	"context"
	"testing"
)

// Hạn mức chat riêng = 10 câu sẵn + 10 câu mỗi km chạy trọn, không quá trần.
func TestAgentDMQuota(t *testing.T) {
	lim := func(cap, base, perKm int64) agentLimits {
		return agentLimits{dmDailyMax: cap, dmBase: base, dmPerKm: perKm}
	}
	f, i := func(v float64) *float64 { return &v }, func(v int64) *int64 { return &v }
	cases := []struct {
		name    string
		lim     agentLimits
		runKm   float64
		max     int64
		nextKm  *float64
		nextMax *int64
	}{
		{"chưa chạy", lim(100, 10, 10), 0, 10, f(1), i(20)},
		{"chưa đủ 1 km", lim(100, 10, 10), 0.99, 10, f(1), i(20)},
		{"đúng 1 km", lim(100, 10, 10), 1, 20, f(2), i(30)},
		{"4,1 km", lim(100, 10, 10), 4.1, 50, f(5), i(60)},
		{"mốc kế chạm trần", lim(55, 10, 10), 4.1, 50, f(5), i(55)},
		{"đã chạm trần", lim(100, 10, 10), 9.5, 100, nil, nil},
		{"không thưởng km", lim(100, 10, 0), 7, 10, nil, nil},
		{"trần 0", lim(0, 10, 10), 3, 0, nil, nil},
		{"câu sẵn quá trần", lim(5, 10, 10), 0, 5, nil, nil},
	}
	for _, c := range cases {
		q := newAgentDMQuota(c.lim, c.runKm)
		if q.runKm != c.runKm || q.max != c.max || !eqPtr(q.nextKm, c.nextKm) || !eqPtr(q.nextMax, c.nextMax) {
			t.Errorf("%s: %+v (next %v/%v), muốn max %d, next %v/%v", c.name, q, deref(q.nextKm), deref(q.nextMax), c.max, deref(c.nextKm), deref(c.nextMax))
		}
	}
}

// Hết lượt mà còn mốc km thì bot chỉ cách mở thêm, vì trên Telegram chủ không
// thấy thẻ km của app; không còn mốc thì giữ câu nghỉ cũ.
func TestDMLimitReply(t *testing.T) {
	ctx := context.Background()
	lim := parseAgentLimits(ctx, nil)
	if got, want := dmLimitReply(newAgentDMQuota(lim, 4.1)), "Hôm nay mình hết lượt nói rồi. Bạn chạy hay đi bộ thêm 0,9 km là mình nói tiếp được 10 câu nữa, không thì qua 0h mình nói tiếp nhé."; got != want {
		t.Fatalf("4,1 km:\n got %q\nwant %q", got, want)
	}
	if got, want := dmLimitReply(newAgentDMQuota(lim, 0)), "Hôm nay mình hết lượt nói rồi. Bạn chạy hay đi bộ thêm 1 km là mình nói tiếp được 10 câu nữa, không thì qua 0h mình nói tiếp nhé."; got != want {
		t.Fatalf("chưa chạy:\n got %q\nwant %q", got, want)
	}
	if got := dmLimitReply(newAgentDMQuota(lim, 12)); got != agentBudgetReply {
		t.Fatalf("đã chạm trần: %q", got)
	}
}

func eqPtr[T comparable](a, b *T) bool { return (a == nil) == (b == nil) && (a == nil || *a == *b) }

func deref[T any](p *T) any {
	if p == nil {
		return nil
	}
	return *p
}
