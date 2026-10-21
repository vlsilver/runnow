//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// Khung kết thúc 22:00 ngày 15/10 VN, tức [14/10 15:00Z, 15/10 15:00Z).
var emuFrameEnd = time.Date(2026, 10, 15, 22, 0, 0, 0, vietnam)

func seedActivity(t *testing.T, db *firestore.Client, uid, id, source, startedAt string, meters float64, minutes int64) {
	t.Helper()
	seed(t, db, "users/"+uid+"/activities/"+id, map[string]any{
		"source": source, "sportType": "Run", "startedAt": startedAt, "distanceMeters": meters,
		"movingTimeSeconds": minutes * 60, "elapsedTimeSeconds": minutes * 60,
	})
}

// startedAt là chuỗi, Strava ghi không có phần giây lẻ, app ghi có ".000Z", và
// query so chuỗi. Test này kiểm query lấy đúng khung trên Firestore thật:
//   - 21:59:59 VN (Strava) và 8:00 VN (app) thuộc khung;
//   - 22:00:00.000 VN hôm nay thuộc khung sau;
//   - bản Health 22:00:30 hôm qua trùng buổi Strava 21:59 hôm qua, chỉ khử được
//     nếu query nạp cả 12 giờ trước khung;
//   - buổi của người khác không lẫn vào.
func TestEmulatorLoadFrameKmQueriesFrameAcrossStringFormats(t *testing.T) {
	db := emulatorDB(t)
	seedActivity(t, db, "u1", "s-in", "strava", "2026-10-15T14:59:59Z", 5000, 25)
	seedActivity(t, db, "u1", "app-in", "runnow", "2026-10-15T01:00:00.000Z", 3000, 18)
	seedActivity(t, db, "u1", "app-next", "runnow", "2026-10-15T15:00:00.000Z", 4000, 22)
	seedActivity(t, db, "u1", "s-prev", "strava", "2026-10-14T14:59:00Z", 7000, 31)
	seedActivity(t, db, "u1", "h-dup", "apple_health", "2026-10-14T15:00:30.000Z", 5100, 30)
	seedActivity(t, db, "u2", "other", "strava", "2026-10-15T02:00:00Z", 9000, 45)

	got, err := LoadFrameKm(context.Background(), db, "u1", emuFrameEnd)
	if err != nil {
		t.Fatal(err)
	}
	if got.OfficialMeters != 8000 || got.Meters != 8000 || got.Source != "official" {
		t.Fatalf("km = %+v, mong đợi official 8000", got)
	}
}

// stepDays hôm qua: distance 3000, hourly[22]=1000, [23]=500 → scale 2, góp 3000.
// Hôm nay: distance 6000, hourly[6]=2000, [22]=1000 → scale 2, góp 2000×2 = 4000.
// Health = 7000. Firestore trả số nguyên là int64, nên trộn int và float.
func TestEmulatorLoadFrameKmReadsStepDays(t *testing.T) {
	db := emulatorDB(t)
	yesterday := make([]any, 24)
	today := make([]any, 24)
	for i := range yesterday {
		yesterday[i], today[i] = int64(0), 0.0
	}
	yesterday[22], yesterday[23] = int64(1000), 500.0
	today[6], today[22] = 2000.0, int64(1000)
	seed(t, db, "users/u1/stepDays/2026-10-14", map[string]any{"distanceMeters": int64(3000), "hourlyDistance": yesterday})
	seed(t, db, "users/u1/stepDays/2026-10-15", map[string]any{"distanceMeters": 6000.0, "hourlyDistance": today})

	got, err := LoadFrameKm(context.Background(), db, "u1", emuFrameEnd)
	if err != nil {
		t.Fatal(err)
	}
	if got.HealthMeters != 7000 || got.Meters != 7000 || got.Source != "health" || !got.HourlyYesterday || !got.HourlyToday {
		t.Fatalf("km = %+v, mong đợi health 7000 có hourly cả hai ngày", got)
	}
}

// Chưa sync gì là kết quả rỗng hợp lệ, không phải lỗi.
func TestEmulatorLoadFrameKmNoDataIsZeroNotError(t *testing.T) {
	db := emulatorDB(t)
	got, err := LoadFrameKm(context.Background(), db, "u1", emuFrameEnd)
	if err != nil || got.Meters != 0 || got.Source != "none" {
		t.Fatalf("km = %+v, err = %v", got, err)
	}
}

// Firestore lỗi thì trả lỗi, không coi là 0 km (mất phiếu của người ta).
func TestEmulatorLoadFrameKmFirestoreErrorIsReturned(t *testing.T) {
	db := emulatorDB(t)
	seedActivity(t, db, "u1", "s-in", "strava", "2026-10-15T02:00:00Z", 5000, 25)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if got, err := LoadFrameKm(ctx, db, "u1", emuFrameEnd); err == nil {
		t.Fatalf("context đã huỷ mà không lỗi, km = %+v", got)
	}
}
