//go:build emulator

package backend

import (
	"context"
	"slices"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// fakeTerritoryTasks ghi lại task thay Cloud Tasks.
type fakeTerritoryTasks struct {
	mu    sync.Mutex
	tasks []PublishTask
}

func (f *fakeTerritoryTasks) Publish(_ context.Context, in PublishTask) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.tasks = append(f.tasks, in)
	return "created", nil
}

func (f *fakeTerritoryTasks) paths(path string) []PublishTask {
	f.mu.Lock()
	defer f.mu.Unlock()
	var out []PublishTask
	for _, t := range f.tasks {
		if t.HandlerPath == path {
			out = append(out, t)
		}
	}
	return out
}

type territoryHarness struct {
	t     *testing.T
	db    *firestore.Client
	svc   *TerritoryService
	tasks *fakeTerritoryTasks
	push  *fakePushSender
	now   time.Time
}

func newTerritoryHarness(t *testing.T) *territoryHarness {
	db := emulatorDB(t)
	push, sender := newFakePush(db)
	tasks := &fakeTerritoryTasks{}
	h := &territoryHarness{t: t, db: db, svc: NewTerritoryService(db, tasks, push), tasks: tasks, push: sender,
		now: time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC)}
	return h
}

func (h *territoryHarness) person(uid, visibility string) {
	seed(h.t, h.db, "publicProfiles/"+uid, map[string]any{"uid": uid, "displayName": "Người " + uid, "profileVisibility": visibility})
	seed(h.t, h.db, "users/"+uid, map[string]any{"displayName": "Người " + uid, "profileVisibility": visibility})
	if err := h.svc.push.Register(context.Background(), uid, "tok-"+uid, "ios", h.now); err != nil {
		h.t.Fatal(err)
	}
}

func (h *territoryHarness) enable() {
	seed(h.t, h.db, "config/territory", map[string]any{"enabled": true, "enabledAt": h.now.Add(-10 * 24 * time.Hour)})
}

// run ghi một buổi 3i chạy về phía đông dọc vĩ độ 10,776 (quận 1), laps lượt
// đi về trên cùng đoạn 1 400 m, pace 6:00/km. Bắt đầu lúc now − agoHours.
func (h *territoryHarness) run(uid, id string, agoHours float64, laps int) {
	start := h.now.Add(-time.Duration(agoHours * float64(time.Hour)))
	const lat, lng0 = 10.776, 106.700
	stepLng := 10.0 / (111195 * 0.98236) // 10 m theo kinh độ ở vĩ độ 10,776
	var points []any
	at := start
	n := 140 // 1 400 m
	for lap := 0; lap < laps; lap++ {
		for i := 0; i <= n; i++ {
			k := i
			if lap%2 == 1 {
				k = n - i
			}
			if lap > 0 && i == 0 {
				continue
			}
			points = append(points, map[string]any{"latitude": lat, "longitude": lng0 + float64(k)*stepLng, "timestamp": at.UTC().Format(time.RFC3339Nano), "accuracyMeters": 5.0})
			at = at.Add(3600 * time.Millisecond)
		}
	}
	elapsed := at.Sub(start).Seconds()
	seed(h.t, h.db, "users/"+uid+"/activities/"+id, map[string]any{
		"id": id, "source": "runnow", "sportType": "Run", "startedAt": start.UTC().Format(time.RFC3339Nano),
		"distanceMeters": float64(laps) * 1400, "movingTimeSeconds": elapsed, "elapsedTimeSeconds": elapsed,
		"routePoints": points, "routeSketch": []any{0, 0, 1000, 0}, "trackingSavedAt": start, "routeSavedAt": start,
	})
}

func (h *territoryHarness) sync(uid string) {
	h.t.Helper()
	if err := h.svc.Sync(context.Background(), uid, h.now); err != nil {
		h.t.Fatalf("sync %s: %v", uid, err)
	}
}

func (h *territoryHarness) activity(uid, id string) map[string]any {
	h.t.Helper()
	data, err := getData(context.Background(), h.db.Doc("users/"+uid+"/activities/"+id))
	if err != nil {
		h.t.Fatal(err)
	}
	t, _ := data["territory"].(map[string]any)
	return t
}

// owners đếm số ô mỗi người giữ trên mọi chunk.
func (h *territoryHarness) owners() map[string]int {
	h.t.Helper()
	docs, err := h.db.Collection("territoryChunks").Documents(context.Background()).GetAll()
	if err != nil {
		h.t.Fatal(err)
	}
	out := map[string]int{}
	for _, d := range docs {
		cells, _ := d.Data()["cells"].(map[string]any)
		for _, v := range cells {
			out[stringValue(v.(map[string]any)["u"])]++
		}
	}
	return out
}

func (h *territoryHarness) ownerDocCount(uid string) int {
	h.t.Helper()
	data, err := getData(context.Background(), h.db.Doc("territoryOwners/"+uid))
	if err != nil {
		h.t.Fatal(err)
	}
	by, _ := data["byChunk"].(map[string]any)
	total := 0
	for _, v := range by {
		total += int(number(v))
	}
	return total
}

func TestEmulatorTerritorySyncClaimsCells(t *testing.T) {
	h := newTerritoryHarness(t)
	h.person("A", "public")
	h.run("A", "a1", 30, 1)
	h.sync("A")

	ter := h.activity("A", "a1")
	cells, _ := ter["cells"].(map[string]any)
	if ter["counted"] != true || len(cells) == 0 {
		t.Fatalf("buổi của A phải được tính và có ô: %+v", ter)
	}
	// 1 400 m cắt 2×200 m còn 1 000 m, ô cạnh ~150 m: 7 hoặc 8 ô.
	if len(cells) < 6 || len(cells) > 9 {
		t.Fatalf("số ô = %d; muốn khoảng 7", len(cells))
	}
	if got := h.owners(); got["A"] != len(cells) {
		t.Fatalf("A phải giữ cả %d ô, chunk ghi %v", len(cells), got)
	}
	if got := h.ownerDocCount("A"); got != len(cells) {
		t.Fatalf("territoryOwners/A = %d; muốn %d", got, len(cells))
	}
	// Chưa bật: kết quả rỗng, không hẹn push.
	res, _ := ter["result"].(map[string]any)
	if res == nil || number(res["gained"]) != 0 || len(h.tasks.paths(territoryPushPath)) != 0 {
		t.Fatalf("chưa bật thì result rỗng, không push: %+v, %d push", res, len(h.tasks.paths(territoryPushPath)))
	}
	// Sync lại không đổi gì.
	h.sync("A")
	if got := h.owners(); got["A"] != len(cells) || h.ownerDocCount("A") != len(cells) {
		t.Fatalf("sync lại làm lệch số ô: %v", got)
	}
}

func TestEmulatorTerritoryTakeAndPush(t *testing.T) {
	h := newTerritoryHarness(t)
	h.enable()
	h.person("A", "public")
	h.person("B", "public")
	h.run("A", "a1", 30, 1)
	h.sync("A")
	a := h.activity("A", "a1")
	// Buổi đầu của A sau khi bật: mọi ô là ô mới, ghi từng ô vào bản nhỏ.
	aSmall, err := getData(context.Background(), h.db.Doc("territoryResults/A_a1"))
	if err != nil || aSmall == nil {
		t.Fatalf("thiếu territoryResults/A_a1: %v", err)
	}
	aCellsMap, _ := a["cells"].(map[string]any)
	newCells, _ := aSmall["newCells"].([]any)
	if len(newCells) == 0 || len(newCells) != len(aCellsMap) || number(aSmall["gained"]) != float64(len(newCells)) {
		t.Fatalf("newCells phải là mọi ô của A (%d), ra %v, gained %v", len(aCellsMap), newCells, aSmall["gained"])
	}
	n := len(a["cells"].(map[string]any))
	if res := a["result"].(map[string]any); int(number(res["gained"])) != n {
		t.Fatalf("A chạy ô trống phải được %d ô mới: %+v", n, res)
	}

	// B chạy đi về hai lượt trên cùng đoạn, 20 giờ sau A: gấp đôi mét, chiếm hết.
	h.run("B", "b1", 10, 2)
	h.sync("B")
	b := h.activity("B", "b1")
	res := b["result"].(map[string]any)
	taken, _ := res["taken"].(map[string]any)
	if number(taken["A"]) < float64(n-1) {
		t.Fatalf("B phải chiếm gần hết %d ô của A: %+v", n, res)
	}
	if got := h.owners(); got["A"] > 1 {
		t.Fatalf("A còn giữ quá nhiều ô: %v", got)
	}
	pushes := h.tasks.paths(territoryPushPath)
	if len(pushes) == 0 {
		t.Fatal("B chiếm ô thì phải hẹn push")
	}
	if err := h.svc.PushTaken(context.Background(), "B", "b1", h.now); err != nil {
		t.Fatal(err)
	}
	if err := h.svc.PushTaken(context.Background(), "B", "b1", h.now); err != nil {
		t.Fatal(err)
	}
	if len(h.push.sent) != 1 || h.push.sent[0].Token != "tok-A" || h.push.sent[0].Data["kind"] != territoryPushKind {
		t.Fatalf("A phải nhận đúng một push: %+v", h.push.sent)
	}
	// Push mang số ô và từng ô A mất, đúng như thân push.
	sent := h.push.sent[0].Data
	sentCells := strings.Split(sent["cells"], ",")
	if sent["to"] != "A" || sent["n"] != strconv.Itoa(len(sentCells)) || number(taken["A"]) != float64(len(sentCells)) {
		t.Fatalf("push phải mang %v ô, ra n=%q cells=%q", taken["A"], sent["n"], sent["cells"])
	}
	for _, cell := range sentCells {
		if aCellsMap[cell] == nil {
			t.Fatalf("ô %s trong push không phải ô của A", cell)
		}
	}
	// Push mở chunk của một ô A đã mất.
	aChunks := stringList(a["chunks"])
	if got := h.push.sent[0].Data["chunk"]; got == "" || !slices.Contains(aChunks, got) {
		t.Fatalf("push phải mở chunk A mất ô, ra %q, chunk của A %v", got, aChunks)
	}
	// Bản nhỏ cho app khớp territory.result.
	small, err := getData(context.Background(), h.db.Doc("territoryResults/B_b1"))
	if err != nil || small == nil {
		t.Fatalf("thiếu territoryResults/B_b1: %v", err)
	}
	if st, _ := small["taken"].(map[string]any); number(st["A"]) != number(taken["A"]) || stringValue(small["chunk"]) == "" {
		t.Fatalf("bản nhỏ lệch result: %+v vs %+v", small, res)
	}
	// Từng ô chiếm được, kèm người bị chiếm, để app vẽ ô A vừa mất.
	takenCells, _ := small["takenCells"].(map[string]any)
	if float64(len(takenCells)) != number(taken["A"]) {
		t.Fatalf("takenCells phải có %v ô, ra %d: %+v", taken["A"], len(takenCells), takenCells)
	}
	aCells, _ := a["cells"].(map[string]any)
	for cell, victim := range takenCells {
		if victim != "A" || aCells[cell] == nil {
			t.Fatalf("ô %s chiếm của %v, phải là ô của A", cell, victim)
		}
	}

	// B chuyển private: ô trả về A, owners của B rỗng.
	seed(h.t, h.db, "publicProfiles/B", map[string]any{"uid": "B", "profileVisibility": "private"})
	h.sync("B")
	if got := h.owners(); got["B"] != 0 || got["A"] != n {
		t.Fatalf("B private thì ô về A: %v", got)
	}
	if got := h.ownerDocCount("B"); got != 0 {
		t.Fatalf("owners của B phải về 0, còn %d", got)
	}
	// Public lại: tính lại kết quả và ô về B.
	seed(h.t, h.db, "publicProfiles/B", map[string]any{"uid": "B", "profileVisibility": "public"})
	h.sync("B")
	if got := h.owners(); got["B"] < n-1 {
		t.Fatalf("B public lại phải giữ lại ô: %v", got)
	}

	// Xoá buổi của B: sync tính lại các chunk B đang giữ, ô về A.
	if _, err := h.db.Doc("users/B/activities/b1").Delete(context.Background()); err != nil {
		t.Fatal(err)
	}
	h.sync("B")
	if got := h.owners(); got["B"] != 0 || got["A"] != n {
		t.Fatalf("xoá buổi của B thì ô về A: %v", got)
	}
}

func TestEmulatorTerritoryRunTogetherNoPush(t *testing.T) {
	h := newTerritoryHarness(t)
	h.enable()
	h.person("A", "public")
	h.person("B", "public")
	// Cùng giờ, B chạy hai lượt: B có nhiều mét hơn nên giữ ô, nhưng A vừa
	// chạy cùng nên không bị push.
	h.run("A", "a1", 5, 1)
	h.sync("A")
	h.run("B", "b1", 5, 2)
	h.sync("B")
	if got := h.owners(); got["B"] == 0 {
		t.Fatalf("B nhiều mét hơn phải giữ ô: %v", got)
	}
	if err := h.svc.PushTaken(context.Background(), "B", "b1", h.now); err != nil {
		t.Fatal(err)
	}
	if len(h.push.sent) != 0 {
		t.Fatalf("người chạy cùng không được push: %+v", h.push.sent)
	}
}

func TestEmulatorTerritoryStravaUsesDuplicateRoute(t *testing.T) {
	h := newTerritoryHarness(t)
	h.person("A", "public")
	h.run("A", "r1", 30, 1)
	// Bản Strava của cùng lần chạy: không tuyến, official; bản 3i trỏ về nó.
	r1 := h.activity("A", "r1")
	_ = r1
	snap, err := h.db.Doc("users/A/activities/r1").Get(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	d := snap.Data()
	seed(h.t, h.db, "users/A/activities/s1", map[string]any{
		"id": "s1", "source": "strava", "sportType": "Run", "startedAt": d["startedAt"],
		"distanceMeters": 1400.0, "movingTimeSeconds": d["movingTimeSeconds"], "elapsedTimeSeconds": d["elapsedTimeSeconds"],
	})
	if _, err := h.db.Doc("users/A/activities/r1").Update(context.Background(), []firestore.Update{{Path: "duplicateOfActivityId", Value: "s1"}}); err != nil {
		t.Fatal(err)
	}
	h.sync("A")
	s := h.activity("A", "s1")
	r := h.activity("A", "r1")
	if s["counted"] != true || stringValue(s["routeFrom"]) != "r1" || len(s["cells"].(map[string]any)) == 0 {
		t.Fatalf("buổi Strava phải được tính bằng tuyến của bản 3i: %+v", s)
	}
	if r["counted"] == true {
		t.Fatalf("bản 3i trùng không được tính: %+v", r)
	}
	// Ô chỉ tính một lần: số mét của A trong chunk bằng đúng một buổi.
	if got := h.owners(); got["A"] != len(s["cells"].(map[string]any)) {
		t.Fatalf("ô của A: %v", got)
	}
}

func TestEmulatorTerritoryDailyDropsExpired(t *testing.T) {
	h := newTerritoryHarness(t)
	h.person("A", "public")
	h.run("A", "a1", 30, 1)
	h.sync("A")
	// 31 ngày sau, việc hằng ngày hẹn tính lại từng chunk; chạy các task đó thì
	// ô hết lượt bị bỏ, và lần hằng ngày sau xoá doc owners rỗng.
	later := h.now.Add(31 * 24 * time.Hour)
	if err := h.svc.Daily(context.Background(), later); err != nil {
		t.Fatal(err)
	}
	rebuilds := h.tasks.paths(territoryRebuildPath)
	if len(rebuilds) == 0 {
		t.Fatal("việc hằng ngày phải hẹn tính lại chunk")
	}
	for _, task := range rebuilds {
		chunks := task.Payload.(map[string]any)["chunks"].([]string)
		if err := h.svc.RebuildChunks(context.Background(), chunks, later); err != nil {
			t.Fatal(err)
		}
	}
	if got := h.owners(); len(got) != 0 {
		t.Fatalf("ô hết lượt phải bị bỏ: %v", got)
	}
	if err := h.svc.Daily(context.Background(), later); err != nil {
		t.Fatal(err)
	}
	if data, _ := getData(context.Background(), h.db.Doc("territoryOwners/A")); data != nil {
		t.Fatalf("doc owners rỗng phải bị xoá: %v", data)
	}
}

func TestEmulatorTerritoryRejectsFakeRoute(t *testing.T) {
	h := newTerritoryHarness(t)
	h.person("A", "public")
	h.run("A", "a1", 30, 1)
	// Tuyến 1 400 m nhưng buổi khai 500 m: tổng mét trong ô vượt 1,3 lần quãng
	// đường, coi là tuyến hỏng.
	if _, err := h.db.Doc("users/A/activities/a1").Update(context.Background(), []firestore.Update{{Path: "distanceMeters", Value: 500.0}}); err != nil {
		t.Fatal(err)
	}
	h.sync("A")
	if cells, _ := h.activity("A", "a1")["cells"].(map[string]any); len(cells) != 0 {
		t.Fatalf("tuyến dài hơn quãng khai báo vẫn có ô: %d", len(cells))
	}
}

func TestEmulatorTerritoryResultNeedsEnabledAt(t *testing.T) {
	h := newTerritoryHarness(t)
	// enabledAt đặt nhưng enabled tắt: vẫn có kết quả, không hẹn push.
	seed(h.t, h.db, "config/territory", map[string]any{"enabled": false, "enabledAt": h.now.Add(-10 * 24 * time.Hour)})
	h.person("A", "public")
	h.run("A", "a1", 30, 1)
	h.sync("A")
	res := h.activity("A", "a1")["result"].(map[string]any)
	if number(res["gained"]) == 0 {
		t.Fatalf("enabledAt đã đặt thì phải có kết quả: %+v", res)
	}
	if n := len(h.tasks.paths(territoryPushPath)); n != 0 {
		t.Fatalf("enabled tắt thì không hẹn push, có %d", n)
	}
}
