//go:build emulator

package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"net"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/cloudtasks/apiv2"
	"cloud.google.com/go/cloudtasks/apiv2/cloudtaskspb"
	"google.golang.org/api/option"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// recordingTasks giữ lại mọi task được tạo, để test đọc payload rồi tự chạy.
type recordingTasks struct {
	cloudtaskspb.UnimplementedCloudTasksServer
	mu    sync.Mutex
	tasks []*cloudtaskspb.Task
}

func (r *recordingTasks) CreateTask(_ context.Context, req *cloudtaskspb.CreateTaskRequest) (*cloudtaskspb.Task, error) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.tasks = append(r.tasks, req.Task)
	return req.Task, nil
}

func (r *recordingTasks) bodiesTo(t *testing.T, path string) [][]byte {
	t.Helper()
	r.mu.Lock()
	defer r.mu.Unlock()
	var out [][]byte
	for _, task := range r.tasks {
		if req := task.GetHttpRequest(); req != nil && req.Url == "https://worker"+path {
			out = append(out, req.Body)
		}
	}
	return out
}

func newRecordingTaskPublisher(t *testing.T) (*TaskPublisher, *recordingTasks) {
	t.Helper()
	lis, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	rec := &recordingTasks{}
	srv := grpc.NewServer()
	cloudtaskspb.RegisterCloudTasksServer(srv, rec)
	go func() { _ = srv.Serve(lis) }()
	t.Cleanup(srv.Stop)
	client, err := cloudtasks.NewClient(context.Background(),
		option.WithEndpoint(lis.Addr().String()),
		option.WithoutAuthentication(),
		option.WithGRPCDialOption(grpc.WithTransportCredentials(insecure.NewCredentials())))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return NewTaskPublisher(client, Config{ProjectID: "p", Region: "r", DerivedQueue: "derived", WorkerBaseURL: "https://worker"}), rec
}

// Nhập Health một lô trải hai tuần, kèm một buổi cũ bị xoá khỏi app Sức khoẻ:
// một task rebuild phủ đủ mọi ngày/tuần/tháng bị đụng. Field run* bỏ đi bộ
// Strava, pace nhanh nhất bỏ buổi dưới 1 km, ngày không còn buổi chạy thì kỷ
// lục cũ bị xoá.
func TestEmulatorHealthImportRebuildsEveryTouchedPeriod(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	tasks, rec := newRecordingTaskPublisher(t)
	activities := NewActivityService(db, nil, nil, tasks, nil, "", "")
	vn := func(day, hour int) time.Time { return time.Date(2026, 10, day, hour, 0, 0, 0, vietnam) }
	utc := func(t time.Time) string { return t.UTC().Format(time.RFC3339Nano) }

	seed(t, db, "users/u1/activities/9001", map[string]any{"id": "9001", "source": "strava", "sportType": "Walk", "startedAt": utc(vn(6, 5)), "distanceMeters": 3000.0, "movingTimeSeconds": 2400, "elapsedTimeSeconds": 2400})
	seed(t, db, "users/u1/activities/health-old", map[string]any{"id": "health-old", "source": "apple_health", "sportType": "Run", "startedAt": utc(vn(8, 6)), "distanceMeters": 3000.0, "movingTimeSeconds": 900, "elapsedTimeSeconds": 900})
	seed(t, db, "users/u1/periodStats/day:2026-10-08", map[string]any{"runCount": 1, "runFastestPaceSecondsPerKm": 300.0})

	workouts := []healthWorkout{
		{SourceID: "a", SportType: "Run", StartedAt: vn(6, 6).Format(time.RFC3339), DistanceMeters: 5000, MovingTimeSeconds: 1500},
		{SourceID: "b", SportType: "Run", StartedAt: vn(6, 18).Format(time.RFC3339), DistanceMeters: 800, MovingTimeSeconds: 180},
		{SourceID: "c", SportType: "Run", StartedAt: vn(13, 6).Format(time.RFC3339), DistanceMeters: 10000, MovingTimeSeconds: 3300},
	}
	if n, err := activities.ImportHealthWorkouts(ctx, "u1", workouts, "apple_health", vn(1, 0).Format(time.RFC3339), vn(20, 0).Format(time.RFC3339)); err != nil || n != 3 {
		t.Fatalf("import = %d, %v", n, err)
	}

	bodies := rec.bodiesTo(t, "/tasks/rebuild-period-stats")
	if len(bodies) != 1 {
		t.Fatalf("%d task rebuild-period-stats, mong đợi 1", len(bodies))
	}
	var payload struct{ StartedAts []string }
	if err := json.Unmarshal(bodies[0], &payload); err != nil || len(payload.StartedAts) != 3 {
		t.Fatalf("payload = %s, %v; mong đợi 3 ngày (6, 8, 13/10)", bodies[0], err)
	}
	worker := NewWorkerServer(Config{}, &Dependencies{Firestore: db, PeriodStats: NewPeriodStatsService(db)})
	w := httptest.NewRecorder()
	worker.ServeHTTP(w, httptest.NewRequest("POST", "/tasks/rebuild-period-stats", bytes.NewReader(bodies[0])))
	if w.Code != 200 {
		t.Fatalf("rebuild: %d %s", w.Code, w.Body)
	}

	for doc, want := range map[string]map[string]float64{
		// 5 km 25 phút + 800 m 3 phút; đi bộ Strava 3 km chỉ vào distanceMeters.
		"day:2026-10-06": {"distanceMeters": 8800, "runDistanceMeters": 5800, "runMovingTimeSeconds": 1680, "runCount": 2, "runActiveDays": 1, "runLongestDistanceMeters": 5000, "runFastestPaceSecondsPerKm": 300},
		"week:2026-W41":  {"runDistanceMeters": 5800, "runCount": 2, "runFastestPaceSecondsPerKm": 300},
		"week:2026-W42":  {"runDistanceMeters": 10000, "runCount": 1, "runFastestPaceSecondsPerKm": 330},
		"month:2026-10":  {"distanceMeters": 18800, "runDistanceMeters": 15800, "runMovingTimeSeconds": 4980, "runCount": 3, "runActiveDays": 2, "runLongestDistanceMeters": 10000, "runFastestPaceSecondsPerKm": 300},
		"day:2026-10-08": {"runDistanceMeters": 0, "runCount": 0},
		"day:2026-10-13": {"runDistanceMeters": 10000, "runFastestPaceSecondsPerKm": 330},
	} {
		snap, err := db.Doc("users/u1/periodStats/" + doc).Get(ctx)
		if err != nil {
			t.Fatalf("%s: %v", doc, err)
		}
		got := snap.Data()
		for field, v := range want {
			if number(got[field]) != v {
				t.Fatalf("%s.%s = %v, mong đợi %v", doc, field, got[field], v)
			}
		}
	}
	old, err := db.Doc("users/u1/periodStats/day:2026-10-08").Get(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if _, ok := old.Data()["runFastestPaceSecondsPerKm"]; ok {
		t.Fatalf("ngày 8/10 không còn buổi chạy mà vẫn giữ kỷ lục pace: %v", old.Data())
	}
}
