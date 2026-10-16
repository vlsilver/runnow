package backend

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

// I5 "Xong khi": game lỗi thì lịch bot vẫn chạy, và ngược lại. Lỗi, panic hay
// hết giờ của một việc không đụng tới việc kia; tick vẫn báo lỗi ra ngoài.
func TestRunTickJobsIsolatesFailures(t *testing.T) {
	now := time.Date(2026, 10, 16, 22, 0, 0, 0, vietnam)
	boom := errors.New("boom")
	var ran []string
	ok := func(name string) tickJob {
		return tickJob{name: name, timeout: time.Second, run: func(ctx context.Context, at time.Time) error {
			if ctx.Err() != nil || !at.Equal(now) {
				t.Errorf("%s nhận ctx %v, giờ %v", name, ctx.Err(), at)
			}
			ran = append(ran, name)
			return nil
		}}
	}
	for _, c := range []struct {
		name string
		jobs []tickJob
		want string // chuỗi phải có trong lỗi
	}{
		{"game lỗi", []tickJob{{name: "game", timeout: time.Second, run: func(context.Context, time.Time) error { return boom }}, ok("bot")}, "game: boom"},
		{"game panic", []tickJob{{name: "game", timeout: time.Second, run: func(context.Context, time.Time) error { panic("nil map") }}, ok("bot")}, "game: panic: nil map"},
		{"game hết giờ", []tickJob{{name: "game", timeout: 10 * time.Millisecond, run: func(ctx context.Context, _ time.Time) error {
			<-ctx.Done()
			return ctx.Err()
		}}, ok("bot")}, "game: context deadline exceeded"},
		{"bot lỗi", []tickJob{ok("game"), {name: "bot", timeout: time.Second, run: func(context.Context, time.Time) error { return boom }}}, "bot: boom"},
	} {
		ran = nil
		err := runTickJobs(context.Background(), now, c.jobs)
		if err == nil || !strings.Contains(err.Error(), c.want) || len(ran) != 1 {
			t.Fatalf("%s: lỗi %v, việc đã chạy %v", c.name, err, ran)
		}
	}
	ran = nil
	if err := runTickJobs(context.Background(), now, []tickJob{ok("game"), ok("bot")}); err != nil || strings.Join(ran, ",") != "game,bot" {
		t.Fatalf("không lỗi: %v, thứ tự %v", err, ran)
	}
}
