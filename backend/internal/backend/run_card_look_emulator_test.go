//go:build emulator

package backend

import (
	"context"
	"reflect"
	"testing"
)

func (e *artEnv) look(uid, path string) any {
	e.t.Helper()
	doc, err := getData(context.Background(), e.store.db.Doc(path))
	if err != nil {
		e.t.Fatal(err)
	}
	return doc["look"]
}

// Chủ thẻ đặt kiểu và bộ màu: doc thẻ và thẻ đang khoe cùng đổi, thẻ khoe sau
// đó cũng mang theo; người khác không đặt được cho thẻ của mình.
func TestEmulatorRunCardLooksReachClubCard(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	e.card("a1", nil)
	e.card("a2", map[string]any{"startedAt": "2026-10-25T10:00:00Z"})
	e.want(e.call("u1", "POST", "/v1/activities/a1/card/share", nil, ""), 200, "")
	put := func(uid string, body map[string]any) apiResp {
		return e.call(uid, "PUT", "/v1/cards/looks", body, "")
	}
	looks := func(items ...map[string]any) map[string]any { return map[string]any{"looks": items} }

	e.want(put("u1", looks(
		map[string]any{"activityId": "a1", "style": "blueprint.top", "skin": "dark.fire"},
		map[string]any{"activityId": "a2", "style": "city.full.map"},
		map[string]any{"activityId": "gone", "style": "medal.full"},
	)), 204, "")
	want := map[string]any{"style": "blueprint.top", "skin": "dark.fire"}
	if got := e.look("u1", "users/u1/runCards/a1"); !reflect.DeepEqual(got, want) {
		t.Fatalf("look thẻ a1 = %v", got)
	}
	if got := e.look("u1", "clubCards/u1_a1"); !reflect.DeepEqual(got, want) {
		t.Fatalf("look thẻ khoe a1 = %v", got)
	}
	if gone, err := getData(context.Background(), e.store.db.Doc("users/u1/runCards/gone")); err != nil || gone != nil {
		t.Fatalf("thẻ không có mà bị tạo: %v, %v", gone, err)
	}
	if club, err := getData(context.Background(), e.store.db.Doc("clubCards/u1_a2")); err != nil || club != nil {
		t.Fatalf("thẻ chưa khoe mà có thẻ khoe: %v, %v", club, err)
	}
	// Khoe sau khi đặt: thẻ khoe mang look, GET thẻ cũng trả look.
	e.want(e.call("u1", "POST", "/v1/activities/a2/card/share", nil, ""), 200, "")
	if got := e.look("u1", "clubCards/u1_a2"); !reflect.DeepEqual(got, map[string]any{"style": "city.full.map"}) {
		t.Fatalf("look thẻ khoe a2 = %v", got)
	}
	card := e.call("u1", "GET", "/v1/activities/a1/card", nil, "").body["card"].(map[string]any)
	if !reflect.DeepEqual(card["look"], want) {
		t.Fatalf("GET thẻ trả look = %v", card["look"])
	}

	// u2 gửi id thẻ của u1: với u2 thẻ đó không có nên không gì đổi.
	e.want(put("u2", looks(map[string]any{"activityId": "a1", "style": "medal.full"})), 204, "")
	if got := e.look("u1", "users/u1/runCards/a1"); !reflect.DeepEqual(got, want) {
		t.Fatalf("u2 đổi được look thẻ của u1: %v", got)
	}

	// fill chỉ điền field còn thiếu; skin rỗng bỏ bộ màu, style giữ nguyên.
	fill := looks(
		map[string]any{"activityId": "a1", "style": "medal.full", "skin": "light.water"},
		map[string]any{"activityId": "a2", "style": "medal.full", "skin": "light.water"},
	)
	fill["fill"] = true
	e.want(put("u1", fill), 204, "")
	if got := e.look("u1", "users/u1/runCards/a1"); !reflect.DeepEqual(got, want) {
		t.Fatalf("fill đè look đã có: %v", got)
	}
	if got := e.look("u1", "clubCards/u1_a2"); !reflect.DeepEqual(got, map[string]any{"style": "city.full.map", "skin": "light.water"}) {
		t.Fatalf("fill không điền skin còn thiếu: %v", got)
	}
	e.want(put("u1", looks(map[string]any{"activityId": "a1", "skin": ""})), 204, "")
	if got := e.look("u1", "clubCards/u1_a1"); !reflect.DeepEqual(got, map[string]any{"style": "blueprint.top"}) {
		t.Fatalf("skin rỗng không bỏ bộ màu: %v", got)
	}
}
