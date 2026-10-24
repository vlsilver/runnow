//go:build emulator

package backend

import (
	"context"
	"sync"
	"testing"
	"time"
)

func runCardHarness(t *testing.T, rolls ...int64) *apiHarness {
	t.Helper()
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	var mu sync.Mutex
	h.deps.RunCards = &RunCardStore{db: db, now: func() time.Time { return time.Date(2026, 10, 25, 1, 0, 0, 0, time.UTC) }, roll: func() (int64, error) {
		mu.Lock()
		defer mu.Unlock()
		r := rolls[0]
		if len(rolls) > 1 {
			rolls = rolls[1:]
		}
		return r, nil
	}}
	return h
}

func seedRun(t *testing.T, h *apiHarness, uid, id string, extra map[string]any) {
	t.Helper()
	m := map[string]any{"id": id, "name": "Buổi " + id, "source": "strava", "sportType": "Run", "startedAt": "2026-10-24T23:00:00Z",
		"distanceMeters": 23500.0, "movingTimeSeconds": 7200, "elapsedTimeSeconds": 7500,
		"routePoints": []any{map[string]any{"latitude": 21.03, "longitude": 105.85}, map[string]any{"latitude": 21.04, "longitude": 105.86}},
		"splits":      []any{map[string]any{"distanceMeters": 1000.0, "movingTimeSeconds": 300.0}}}
	for k, v := range extra {
		m[k] = v
	}
	seed(t, h.store.db, "users/"+uid+"/activities/"+id, m)
}

func TestEmulatorRunCardRollOnceAndKeep(t *testing.T) {
	// 23,5 km: 0 / 50,5 / 31 / 14 / 4,5 %. Số quay 820000 rơi vào bậc huyền thoại
	// (đoạn 815000..954999); lần quay sau ra số khác nhưng thẻ không đổi.
	h := runCardHarness(t, 820000, 0)
	seedRun(t, h, "u1", "a1", nil)

	r := h.call("u1", "GET", "/v1/activities/a1/card", nil, "")
	h.want(r, 200, "")
	if r.body["card"] != nil {
		t.Fatalf("chưa lật mà có thẻ: %s", r.raw)
	}
	odds := r.body["odds"].([]any)
	if o := odds[1].(map[string]any); o["tier"] != "rare" || o["percent"] != 50.5 {
		t.Fatalf("tỉ lệ hiếm = %v, muốn 50.5", o)
	}

	r = h.call("u1", "POST", "/v1/activities/a1/card", nil, "")
	h.want(r, 200, "")
	card := r.body["card"].(map[string]any)
	if card["tier"] != "legendary" || card["km"] != 23.5 || card["rollPpm"] != 820000.0 || card["startedAt"] != "2026-10-24T23:00:00Z" {
		t.Fatalf("thẻ = %v", card)
	}
	snap := card["snapshot"].(map[string]any)
	if snap["name"] != "Buổi a1" || len(snap["route"].([]any)) != 2 || len(snap["splits"].([]any)) != 1 {
		t.Fatalf("snapshot = %v", snap)
	}

	r = h.call("u1", "POST", "/v1/activities/a1/card", nil, "")
	h.want(r, 200, "")
	if r.body["card"].(map[string]any)["tier"] != "legendary" {
		t.Fatalf("lật lại phải trả thẻ cũ: %s", r.raw)
	}

	// Xoá buổi chạy thì thẻ vẫn còn đủ dữ liệu.
	if _, err := h.store.db.Doc("users/u1/activities/a1").Delete(context.Background()); err != nil {
		t.Fatal(err)
	}
	r = h.call("u1", "GET", "/v1/activities/a1/card", nil, "")
	h.want(r, 200, "")
	if c, _ := r.body["card"].(map[string]any); c == nil || c["tier"] != "legendary" {
		t.Fatalf("xoá buổi chạy làm mất thẻ: %s", r.raw)
	}
}

func TestEmulatorRunCardConcurrentRollsGiveOneCard(t *testing.T) {
	// Số quay 0 ra hiếm, 999999 ra thần thoại: hai request cùng lúc phải trả
	// cùng một thẻ, không thẻ nào bị ghi đè.
	h := runCardHarness(t, 0, 999999)
	seedRun(t, h, "u1", "a1", nil)
	h.token("u1")
	var wg sync.WaitGroup
	tiers := make([]any, 2)
	for i := range tiers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := h.call("u1", "POST", "/v1/activities/a1/card", nil, "")
			if r.status == 200 {
				tiers[i] = r.body["card"].(map[string]any)["tier"]
			}
		}()
	}
	wg.Wait()
	if tiers[0] == nil || tiers[0] != tiers[1] {
		t.Fatalf("hai lần lật cùng lúc ra %v", tiers)
	}
	snap, err := h.store.db.Doc("users/u1/runCards/a1").Get(context.Background())
	if err != nil || snap.Data()["tier"] != tiers[0] {
		t.Fatalf("doc thẻ = %v (%v), muốn %v", snap.Data(), err, tiers[0])
	}
}

func TestEmulatorRunCardRejects(t *testing.T) {
	h := runCardHarness(t, 0)
	seedRun(t, h, "u1", "ride", map[string]any{"sportType": "Ride"})
	seedRun(t, h, "u1", "short", map[string]any{"distanceMeters": 400.0})
	seedRun(t, h, "u1", "dup", map[string]any{"source": "runnow", "duplicateOfActivityId": "a1"})
	seedRun(t, h, "u1", "a1", nil)
	// Cùng lần chạy ghi ở Apple Health, chưa gắn duplicateOfActivityId.
	seedRun(t, h, "u1", "health", map[string]any{"source": "apple_health", "startedAt": "2026-10-24T23:10:00Z"})
	// Buổi chiều cùng ngày, không trùng.
	seedRun(t, h, "u1", "later", map[string]any{"startedAt": "2026-10-25T10:00:00Z"})

	for id, code := range map[string]string{"ride": "card_not_eligible", "short": "card_not_eligible", "dup": "card_duplicate"} {
		r := h.call("u1", "GET", "/v1/activities/"+id+"/card", nil, "")
		h.want(r, 200, "")
		if r.body["reason"] != code || r.body["odds"] != nil {
			t.Fatalf("GET %s = %s, muốn reason %s", id, r.raw, code)
		}
		h.want(h.call("u1", "POST", "/v1/activities/"+id+"/card", nil, ""), 409, code)
	}
	h.want(h.call("u1", "GET", "/v1/activities/khong-co/card", nil, ""), 404, "activity_not_found")
	h.want(h.call("u1", "POST", "/v1/activities/khong-co/card", nil, ""), 404, "activity_not_found")
	// Người khác không thấy buổi chạy của u1.
	h.want(h.call("u2", "POST", "/v1/activities/a1/card", nil, ""), 404, "activity_not_found")
	h.want(h.call("u1", "GET", "/v1/activities/__x__/card", nil, ""), 400, "")

	h.want(h.call("u1", "POST", "/v1/activities/a1/card", nil, ""), 200, "")
	h.want(h.call("u1", "POST", "/v1/activities/health/card", nil, ""), 409, "card_duplicate")
	h.want(h.call("u1", "POST", "/v1/activities/later/card", nil, ""), 200, "")
}

func TestEmulatorArtStyles(t *testing.T) {
	h := runCardHarness(t, 0)
	r := h.call("u1", "GET", "/v1/art-styles?kind=run", nil, "")
	h.want(r, 200, "")
	if n := len(r.body["styles"].([]any)); n != 39 {
		t.Fatalf("có %d phong cách, muốn 39", n)
	}
	h.want(h.call("u1", "GET", "/v1/art-styles?kind=werewolf", nil, ""), 400, "")
	h.want(h.call("u1", "GET", "/v1/art-styles", nil, ""), 400, "")
}
