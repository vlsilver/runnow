//go:build emulator

package backend

import (
	"net/url"
	"reflect"
	"testing"
)

func TestActivityListEmulator(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	h.deps.Activities = NewActivityService(db, nil, nil, nil, nil, "", "")

	heavy := map[string]any{
		"routePoints":   []any{map[string]any{"latitude": 21.0, "longitude": 105.8}},
		"streams":       map[string]any{"heartrate": []any{140.0, 150.0}},
		"trackingDebug": map[string]any{"gpsFixes": 900},
	}
	run := func(id, startedAt string, extra map[string]any) map[string]any {
		m := map[string]any{"id": id, "name": "Buổi " + id, "source": "strava", "sportType": "Run",
			"startedAt": startedAt, "distanceMeters": 5000.0, "movingTimeSeconds": 1800, "elapsedTimeSeconds": 1900}
		for k, v := range extra {
			m[k] = v
		}
		return m
	}
	seed(t, db, "users/u1/activities/a", run("a", "2026-10-24T06:00:00Z", heavy))
	// b và c cùng giờ bắt đầu (buổi 3i trùng buổi Strava): sang trang không được mất hay lặp.
	seed(t, db, "users/u1/activities/b", run("b", "2026-10-23T06:00:00Z", map[string]any{"source": "runnow", "duplicateOfActivityId": "c"}))
	seed(t, db, "users/u1/activities/c", run("c", "2026-10-23T06:00:00Z", nil))
	seed(t, db, "users/u1/activities/d", run("d", "2026-10-22T06:00:00Z", nil))
	seed(t, db, "users/u2/activities/x", run("x", "2026-10-24T07:00:00Z", nil))

	page := func(query string) (ids []string, cursor string, acts []any) {
		t.Helper()
		r := h.call("u1", "GET", "/v1/activities?"+query, nil, "")
		h.want(r, 200, "")
		acts, _ = r.body["activities"].([]any)
		for _, a := range acts {
			ids = append(ids, a.(map[string]any)["id"].(string))
		}
		cursor, _ = r.body["cursor"].(string)
		return ids, cursor, acts
	}

	ids, cursor, acts := page("limit=2")
	if !reflect.DeepEqual(ids, []string{"a", "c"}) || cursor == "" {
		t.Fatalf("trang 1 = %v cursor %q, mong đợi [a c] và có cursor", ids, cursor)
	}
	first := acts[0].(map[string]any)
	for _, k := range []string{"routePoints", "streams", "trackingDebug"} {
		if _, ok := first[k]; ok {
			t.Fatalf("danh sách không được trả %s", k)
		}
	}
	if first["name"] != "Buổi a" || first["distanceMeters"] != 5000.0 || first["startedAt"] != "2026-10-24T06:00:00Z" {
		t.Fatalf("thiếu field danh sách cần: %v", first)
	}

	ids, cursor, acts = page("limit=2&cursor=" + url.QueryEscape(cursor))
	if !reflect.DeepEqual(ids, []string{"b", "d"}) || cursor == "" {
		t.Fatalf("trang 2 = %v cursor %q, mong đợi [b d] và có cursor", ids, cursor)
	}
	if acts[0].(map[string]any)["duplicateOfActivityId"] != "c" {
		t.Fatalf("buổi 3i trùng Strava phải giữ duplicateOfActivityId: %v", acts[0])
	}

	ids, cursor, _ = page("limit=2&cursor=" + url.QueryEscape(cursor))
	if len(ids) != 0 || cursor != "" {
		t.Fatalf("trang 3 = %v cursor %q, mong đợi rỗng, hết trang", ids, cursor)
	}

	for _, q := range []string{"limit=0", "limit=51", "limit=x", "cursor=khong-co-id"} {
		h.want(h.call("u1", "GET", "/v1/activities?"+q, nil, ""), 400, "")
	}
}
