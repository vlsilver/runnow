//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"errors"
	"testing"
	"time"
)

// fakeDigestWriter giữ lại số liệu nhận được và trả bài cố định, hoặc lỗi.
type fakeDigestWriter struct {
	calls int
	facts digestFacts
	post  homeDigestPost
	err   error
}

func (f *fakeDigestWriter) Write(_ context.Context, facts string) (homeDigestPost, error) {
	f.calls++
	if err := json.Unmarshal([]byte(facts), &f.facts); err != nil {
		return homeDigestPost{}, err
	}
	return f.post, f.err
}

// Bài ngày 31/10 viết lúc 06:30. Số mong đợi tính tay:
//   - an: chạy 8 km ngày 30 và 5 km lúc 05:40 sáng 31, nên hôm qua chỉ 8 km.
//   - binh: chạy 3 km ngày 30.
//   - cuong: chạy ngày 29, hôm qua nghỉ.
//   - kin: hồ sơ kín, chạy 20 km ngày 30, không được lọt vào bài.
//   - 7 ngày: an 13, binh 3 (lấy từ stepLeaderboardEntries).
func TestEmulatorHomeDigestYesterdayFacts(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	at := func(day, hour, minute int) time.Time { return time.Date(2026, 10, day, hour, minute, 0, 0, vietnam) }
	seed(t, db, "stepLeaderboardEntries/an", map[string]any{"profileVisibility": "public", "nickname": "An", "rollingSevenDaysTotalDistance": 13000.0})
	seed(t, db, "stepLeaderboardEntries/binh", map[string]any{"profileVisibility": "public", "nickname": "Bình", "rollingSevenDaysTotalDistance": 3000.0})
	seed(t, db, "stepLeaderboardEntries/kin", map[string]any{"profileVisibility": "private", "nickname": "Kín", "rollingSevenDaysTotalDistance": 20000.0})
	seedRankActivity(t, db, "an", "a1", "strava", "Run", at(30, 6, 0), 8000)
	seedRankActivity(t, db, "an", "a2", "strava", "Run", at(31, 5, 40), 5000)
	seedRankActivity(t, db, "binh", "b1", "strava", "Run", at(30, 18, 0), 3000)
	seedRankActivity(t, db, "kin", "k1", "strava", "Run", at(30, 6, 0), 20000)
	// cuong công khai nhưng chạy hôm kia, hôm qua nghỉ: không tính vào hôm qua.
	seed(t, db, "stepLeaderboardEntries/cuong", map[string]any{"profileVisibility": "public", "nickname": "Cường"})
	seedRankActivity(t, db, "cuong", "c1", "strava", "Run", at(29, 6, 0), 4000)
	seed(t, db, "runRooms/r1", map[string]any{"privacy": "public", "status": "open", "title": "Hồ Tây", "hostName": "An", "runnerCount": 2, "maxRunners": 8, "startsAt": at(31, 18, 0), "closesAt": at(32, 0, 0)})
	seed(t, db, "runRooms/r2", map[string]any{"privacy": "private", "status": "open", "title": "Kín", "hostName": "Kín", "runnerCount": 1, "maxRunners": 8, "startsAt": at(31, 18, 0), "closesAt": at(32, 0, 0)})

	writer := &fakeDigestWriter{post: homeDigestPost{Title: " Sáng thứ Bảy ", Body: "An 8 km"}}
	svc := NewHomeDigestService(db, writer, "model-x")
	now := at(31, 6, 30)
	if err := svc.Run(ctx, "2026-10-31", now); err != nil {
		t.Fatal(err)
	}

	y := writer.facts.Yesterday
	if y.Date != "2026-10-30" || y.RunnerCount != 2 || y.TotalRunKm != 11 {
		t.Fatalf("hôm qua = %+v, muốn 2 người, 11 km ngày 30", y)
	}
	if len(y.Top) != 2 || y.Top[0] != (digestRunner{Name: "An", RunKm: 8, Runs: 1}) || y.Top[1].Name != "Bình" {
		t.Fatalf("top hôm qua = %+v", y.Top)
	}
	if w := writer.facts.Last7Days; len(w) != 2 || w[0] != (digestRunner{Name: "An", RunKm: 13}) {
		t.Fatalf("7 ngày = %+v", w)
	}
	if r := writer.facts.OpenRooms; len(r) != 1 || r[0].Title != "Hồ Tây" || r[0].StartsAt != "18:00 31/10/2026" {
		t.Fatalf("phòng = %+v, muốn đúng phòng công khai", r)
	}
	got := rankDoc(t, db, "homeDigests/2026-10-31")
	if got["title"] != "Sáng thứ Bảy" || got["body"] != "An 8 km" || got["model"] != "model-x" {
		t.Fatalf("bài = %v", got)
	}

	// Chạy lại trong ngày: bài đã có thì không gọi model nữa.
	if err := svc.Run(ctx, "2026-10-31", now.Add(10*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if writer.calls != 1 {
		t.Fatalf("model bị gọi %d lần, muốn 1", writer.calls)
	}
}

func TestEmulatorHomeDigestModelFailureWritesNothing(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	now := time.Date(2026, 10, 31, 6, 30, 0, 0, vietnam)
	for name, writer := range map[string]*fakeDigestWriter{
		"model lỗi":   {err: errors.New("quota")},
		"bài rỗng":    {post: homeDigestPost{Title: "Chào", Body: "  "}},
		"tiêu đề dài": {post: homeDigestPost{Title: string(make([]rune, homeDigestTitleMax+1)), Body: "x"}},
	} {
		if err := NewHomeDigestService(db, writer, "m").Run(ctx, "2026-10-31", now); err == nil {
			t.Fatalf("%s: muốn lỗi để task chạy lại", name)
		}
		snap, err := db.Doc("homeDigests/2026-10-31").Get(ctx)
		if err == nil && snap.Exists() {
			t.Fatalf("%s: không được ghi bài", name)
		}
	}
}
