package backend

import (
	"strings"
	"testing"
	"time"
)

func TestLiveAnnouncePlain(t *testing.T) {
	if got := liveAnnouncePlain("An", liveEventStart, 600, 200, 0); got == "" {
		t.Fatal("start plain rỗng")
	}
	milestone := liveAnnouncePlain("An", liveEventMilestone, 5000, 1500, 5)
	if milestone == "" || !strings.Contains(milestone, "5km") {
		t.Fatalf("milestone plain sai: %q", milestone)
	}
	finish := liveAnnouncePlain("An", liveEventFinish, 10000, 3000, 0)
	if finish == "" || !strings.Contains(finish, "10.00") {
		t.Fatalf("finish plain thiếu quãng đường: %q", finish)
	}
	if liveAnnouncePlain("An", "bogus", 0, 0, 0) != "" {
		t.Fatal("event lạ phải trả rỗng")
	}
}

func TestRunnowStartMs(t *testing.T) {
	if got := runnowStartMs("runnow-1785619792289"); got != 1785619792289 {
		t.Fatalf("parse start ms sai: %d", got)
	}
	if runnowStartMs("strava-123") != 0 {
		t.Fatal("id không phải runnow phải trả 0")
	}
}

func TestLiveFinishAlreadyCovered(t *testing.T) {
	now := time.Date(2026, 8, 3, 10, 0, 0, 0, time.UTC)
	startMs := time.Date(2026, 8, 3, 9, 0, 0, 0, time.UTC).UnixMilli()
	profile := map[string]any{
		"lastLiveFinishStartMs": float64(startMs),
		"lastLiveFinishAt":      now.Add(-30 * time.Minute),
	}
	// Buổi Strava trùng: xuất phát lệch 2 phút → coi là đã tường thuật live.
	stravaDup := map[string]any{"source": "strava", "startedAt": time.Date(2026, 8, 3, 9, 2, 0, 0, time.UTC).Format(time.RFC3339)}
	if !liveFinishAlreadyCovered(profile, stravaDup, now) {
		t.Fatal("buổi Strava trùng phải bị nuốt")
	}
	// Buổi Strava khác giờ hẳn → không nuốt.
	stravaOther := map[string]any{"source": "strava", "startedAt": time.Date(2026, 8, 3, 6, 0, 0, 0, time.UTC).Format(time.RFC3339)}
	if liveFinishAlreadyCovered(profile, stravaOther, now) {
		t.Fatal("buổi Strava khác không được nuốt")
	}
	// Mốc live quá cũ (>6h) → không nuốt dù trùng giờ.
	staleProfile := map[string]any{"lastLiveFinishStartMs": float64(startMs), "lastLiveFinishAt": now.Add(-8 * time.Hour)}
	if liveFinishAlreadyCovered(staleProfile, stravaDup, now) {
		t.Fatal("mốc live cũ >6h không được nuốt")
	}
	// Chưa từng live-finish → không nuốt.
	if liveFinishAlreadyCovered(map[string]any{}, stravaDup, now) {
		t.Fatal("chưa có mốc live thì không nuốt")
	}
}
