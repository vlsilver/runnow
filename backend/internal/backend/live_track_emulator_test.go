//go:build emulator

package backend

import (
	"context"
	"reflect"
	"strings"
	"testing"
)

const liveTrackTopic = 88

// Admin gõ /livetrack trong topic thì topic đó nhận tin buổi chạy; người
// thường hay gõ ở General thì không đổi gì; "/livetrack tat" trả về General.
func TestEmulatorLiveTrackCommand(t *testing.T) {
	e := newMybotEnv(t)
	linkUser(t, e.apiHarness, "cuong", "5001", true)
	linkUser(t, e.apiHarness, "an", "5002", true)

	if r := e.manager(topicMsg(101, 5001, liveTrackTopic, "/livetrack")); r.body["text"] != "Lệnh này chỉ dành cho admin." {
		t.Fatalf("/livetrack của người thường: %s", r.raw)
	}
	if r := e.manager(topicMsg(102, 5002, 0, "/livetrack")); !strings.Contains(r.body["text"].(string), "không phải General") {
		t.Fatalf("/livetrack ở General: %s", r.raw)
	}
	if e.fsDoc("appConfig/telegram")["liveTrackThreadId"] != nil {
		t.Fatal("lệnh bị từ chối mà vẫn đặt topic")
	}

	r := e.manager(topicMsg(103, 5002, liveTrackTopic, "/livetrack@Run3IBot"))
	if !strings.HasPrefix(r.body["text"].(string), "Topic này giờ nhận tin buổi chạy") || r.body["message_thread_id"] != float64(liveTrackTopic) {
		t.Fatalf("/livetrack của admin: %s", r.raw)
	}
	if got := e.fsDoc("appConfig/telegram")["liveTrackThreadId"]; got != int64(liveTrackTopic) {
		t.Fatalf("liveTrackThreadId = %v", got)
	}

	if r := e.manager(topicMsg(104, 5002, liveTrackTopic, "/livetrack tat")); r.body["text"] != "Tin buổi chạy về lại General." {
		t.Fatalf("/livetrack tat: %s", r.raw)
	}
	if got, ok := e.fsDoc("appConfig/telegram")["liveTrackThreadId"]; ok {
		t.Fatalf("tắt rồi mà liveTrackThreadId = %v", got)
	}
}

// photoThreads là bot không viết câu nào (để rơi về bản plain), chỉ ghi lại
// topic được giao cho mỗi ảnh live.
type photoThreads struct{ threads []int64 }

func (*photoThreads) RecordBroadcast(context.Context, string, string) error { return nil }
func (*photoThreads) ActivityAnnouncement(context.Context, string, string, string, ActivityFact) string {
	return ""
}
func (*photoThreads) LiveAnnouncement(context.Context, string, string, string, float64, float64, int) string {
	return ""
}
func (p *photoThreads) LivePhotoAnnouncement(_ context.Context, threadID int64, _, _, _ string, _ float64) error {
	p.threads = append(p.threads, threadID)
	return nil
}
func (*photoThreads) ContractRoast(context.Context, string, string, []roastFailer) string { return "" }
func (*photoThreads) Enabled() bool                                                       { return true }

// Tin Live và tin buổi chạy xong vào topic Live Track khi đã đặt; chưa đặt
// thì vẫn ở General như trước.
func TestEmulatorRunNewsGoToLiveTrackTopic(t *testing.T) {
	ctx := context.Background()
	db := emulatorDB(t)
	tg := newFakeTelegram(t)
	acts := NewActivityService(db, nil, nil, nil, tg.service(testPscChat), "", "https://web.test")
	photos := &photoThreads{}
	acts.SetBroadcastRecorder(photos)
	seed(t, db, "users/u1", map[string]any{"profileVisibility": "public", "displayName": "An"})
	seed(t, db, "users/u1/activities/runnow-1785619792289", map[string]any{"name": "Chạy sáng", "source": "runnow",
		"sportType": "Run", "startedAt": "2026-08-01T22:49:52Z", "distanceMeters": 5000.0, "movingTimeSeconds": 1800})

	if err := acts.LiveAnnounce(ctx, "u1", "runnow-1785619792289", liveEventStart, 400, 120, 0, ""); err != nil {
		t.Fatal(err)
	}
	seed(t, db, "appConfig/telegram", map[string]any{"liveTrackThreadId": int64(liveTrackTopic)})
	if err := acts.LiveAnnounce(ctx, "u1", "runnow-1785619792289", liveEventMilestone, 5000, 1500, 5, ""); err != nil {
		t.Fatal(err)
	}
	if err := acts.LiveAnnounce(ctx, "u1", "runnow-1785619792289", liveEventPhoto, 2500, 700, 0, "live/u1/a.jpg"); err != nil {
		t.Fatal(err)
	}
	if err := acts.NotifyTelegram(ctx, "u1", "runnow-1785619792289"); err != nil {
		t.Fatal(err)
	}

	var threads []any
	for _, c := range tg.Calls("sendMessage") {
		threads = append(threads, c.Params["message_thread_id"])
	}
	if want := []any{nil, float64(liveTrackTopic), float64(liveTrackTopic)}; !reflect.DeepEqual(threads, want) {
		t.Fatalf("thread của bắt đầu, mốc 5km, chạy xong = %v, muốn %v", threads, want)
	}
	if !reflect.DeepEqual(photos.threads, []int64{liveTrackTopic}) {
		t.Fatalf("thread của ảnh live = %v", photos.threads)
	}
}
