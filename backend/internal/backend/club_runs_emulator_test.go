//go:build emulator

package backend

import (
	"fmt"
	"net/url"
	"reflect"
	"testing"
)

func TestClubRunsEmulator(t *testing.T) {
	db := emulatorDB(t)
	h := newAPIHarness(t, NewGameStore(db, testPscChat))
	h.deps.Activities = NewActivityService(db, nil, nil, nil, nil, "", "")

	seed(t, db, "publicProfiles/pub", map[string]any{"uid": "pub", "profileVisibility": "public"})
	seed(t, db, "publicProfiles/pub2", map[string]any{"uid": "pub2", "profileVisibility": "public"})
	seed(t, db, "publicProfiles/priv", map[string]any{"uid": "priv", "profileVisibility": "private"})
	run := func(id, startedAt string, extra map[string]any) map[string]any {
		m := map[string]any{"id": id, "name": "Buổi " + id, "sportType": "Run", "startedAt": startedAt,
			"distanceMeters": 5000.0, "movingTimeSeconds": 1800,
			"routePoints": []any{map[string]any{"latitude": 21.0, "longitude": 105.8}},
			"streams":     map[string]any{"heartrate": []any{140.0}}}
		for k, v := range extra {
			m[k] = v
		}
		return m
	}
	// 25 buổi mới nhất là của người để riêng tư hoặc không có hồ sơ, nhiều hơn
	// một lượt đọc (20 buổi): trang đầu phải đọc tiếp qua chúng chứ không trả rỗng.
	for i := 0; i < 25; i++ {
		seed(t, db, fmt.Sprintf("users/priv/activities/v%d", i), run(fmt.Sprintf("v%d", i), fmt.Sprintf("2026-10-26T00:%02d:00Z", i), nil))
	}
	seed(t, db, "users/noprofile/activities/n", run("n", "2026-10-25T10:00:00Z", nil))
	seed(t, db, "users/pub/activities/a", run("a", "2026-10-24T08:00:00Z", nil))
	seed(t, db, "users/pub/activities/dup", run("dup", "2026-10-24T07:00:00Z", map[string]any{"duplicateOfActivityId": "a"}))
	// b và c cùng giờ bắt đầu ở hai người khác nhau: sang trang không mất, không lặp.
	seed(t, db, "users/pub/activities/b", run("b", "2026-10-23T06:00:00Z", nil))
	seed(t, db, "users/pub2/activities/c", run("c", "2026-10-23T06:00:00Z", nil))

	page := func(query string) (got []string, cursor string, runs []any) {
		t.Helper()
		r := h.call("viewer", "GET", "/v1/club/runs?"+query, nil, "")
		h.want(r, 200, "")
		runs, _ = r.body["runs"].([]any)
		for _, item := range runs {
			m := item.(map[string]any)
			got = append(got, m["ownerUid"].(string)+"/"+m["activity"].(map[string]any)["id"].(string))
		}
		cursor, _ = r.body["cursor"].(string)
		return got, cursor, runs
	}

	got, cursor, runs := page("limit=1")
	if !reflect.DeepEqual(got, []string{"pub/a"}) || cursor == "" {
		t.Fatalf("trang 1 = %v cursor %q, mong đợi [pub/a] và có cursor", got, cursor)
	}
	first := runs[0].(map[string]any)["activity"].(map[string]any)
	for _, k := range []string{"routePoints", "streams"} {
		if _, ok := first[k]; ok {
			t.Fatalf("feed không được trả %s", k)
		}
	}
	if first["name"] != "Buổi a" || first["distanceMeters"] != 5000.0 {
		t.Fatalf("thiếu field danh sách cần: %v", first)
	}

	var all []string
	all = append(all, got...)
	for cursor != "" {
		got, cursor, _ = page("limit=1&cursor=" + url.QueryEscape(cursor))
		all = append(all, got...)
	}
	want := []string{"pub/a", "pub2/c", "pub/b"}
	if !reflect.DeepEqual(all, want) {
		t.Fatalf("cả feed = %v, mong đợi %v", all, want)
	}

	got, _, _ = page("limit=20")
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("một trang = %v, mong đợi %v", got, want)
	}

	for _, q := range []string{"limit=0", "limit=51", "limit=x", "cursor=thieu", "cursor=a|b"} {
		h.want(h.call("viewer", "GET", "/v1/club/runs?"+q, nil, ""), 400, "")
	}
}
