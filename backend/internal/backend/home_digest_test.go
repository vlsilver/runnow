package backend

import (
	"testing"
	"time"
)

func TestHomeDigestTaskWindow(t *testing.T) {
	at := func(hour, minute int) time.Time { return time.Date(2026, 10, 31, hour, minute, 0, 0, vietnam) }
	for _, tc := range []struct {
		now  time.Time
		want bool
	}{
		{at(6, 29), false},
		{at(6, 30), true},
		{at(9, 59), true},
		{at(10, 0), false},
		// 23:40 UTC ngày 30 là 06:40 VN ngày 31.
		{time.Date(2026, 10, 30, 23, 40, 0, 0, time.UTC), true},
	} {
		task, ok := homeDigestTaskFor(tc.now)
		if ok != tc.want {
			t.Fatalf("%v: hẹn = %v, muốn %v", tc.now, ok, tc.want)
		}
		if ok && task.Payload.(homeDigestTask).Day != "2026-10-31" {
			t.Fatalf("%v: ngày = %v, muốn 2026-10-31", tc.now, task.Payload)
		}
	}
}
