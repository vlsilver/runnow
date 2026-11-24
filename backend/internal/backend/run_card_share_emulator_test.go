//go:build emulator

package backend

import (
	"context"
	"slices"
	"testing"
	"time"
)

func (e *artEnv) clubCard(id string) map[string]any {
	e.t.Helper()
	club, err := getData(context.Background(), e.store.db.Doc("clubCards/u1_"+id))
	if err != nil {
		e.t.Fatal(err)
	}
	return club
}

func TestEmulatorRunCardShareHidesRouteAndHeartRate(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	seedRun(t, e.apiHarness, "u1", "a0", nil)
	e.want(e.call("u1", "POST", "/v1/activities/a0/card/share", nil, ""), 404, "card_not_found")

	e.card("a1", map[string]any{"averageHeartRate": 151.0, "elevationGainMeters": 120.0})
	// Người khác không khoe được thẻ của u1: với u2 buổi a1 không có thẻ.
	e.want(e.call("u2", "POST", "/v1/activities/a1/card/share", nil, ""), 404, "card_not_found")

	r := e.call("u1", "POST", "/v1/activities/a1/card/share", nil, "")
	e.want(r, 200, "")
	if got := r.body["card"].(map[string]any); got["id"] != "a1" || got["ownerUid"] != "u1" || got["sharedAt"] != "2026-10-25T01:00:00Z" {
		t.Fatalf("thẻ trả về = %v", got)
	}
	club := e.clubCard("a1")
	card, err := getData(context.Background(), e.store.db.Doc("users/u1/runCards/a1"))
	if err != nil {
		t.Fatal(err)
	}
	keys := make([]string, 0, len(club))
	for k := range club {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	if !slices.Equal(keys, []string{"activityId", "km", "odds", "ownerUid", "rolledAt", "sharedAt", "snapshot", "startedAt", "tier", "variant"}) {
		t.Fatalf("field thẻ khoe = %v", keys)
	}
	if club["tier"] != card["tier"] || club["km"] != 23.5 || club["ownerUid"] != "u1" {
		t.Fatalf("thẻ khoe = %v", club)
	}
	snap := club["snapshot"].(map[string]any)
	if _, ok := snap["route"]; ok {
		t.Fatal("thẻ khoe lộ đường chạy")
	}
	if _, ok := snap["averageHeartRate"]; ok {
		t.Fatal("thẻ khoe lộ nhịp tim")
	}
	if snap["name"] != "Buổi a1" || snap["distanceMeters"] != 23500.0 || snap["movingTimeSeconds"] != 7200.0 || snap["elevationGainMeters"] != 120.0 || len(snap["splits"].([]any)) != 1 {
		t.Fatalf("snapshot thẻ khoe = %v", snap)
	}

	// Khoe lại giữ giờ khoe đầu, để thẻ không nhảy lên đầu mục.
	e.clock = e.clock.Add(time.Hour)
	e.want(e.call("u1", "POST", "/v1/activities/a1/card/share", nil, ""), 200, "")
	if at := e.clubCard("a1")["sharedAt"].(time.Time); !at.Equal(time.Date(2026, 10, 25, 1, 0, 0, 0, time.UTC)) {
		t.Fatalf("sharedAt sau khi khoe lại = %v", at)
	}
}

func TestEmulatorRunCardShareFollowsArt(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	e.card("a1", nil)
	e.want(e.call("u1", "POST", "/v1/activities/a1/card/share", nil, ""), 200, "")

	// Đang khoe mà tranh vẽ xong: thẻ khoe có tranh.
	e.want(e.ask("a1", "anime_cel", ""), 200, "")
	e.draw(e.lastTask())
	if art, _ := e.clubCard("a1")["art"].(map[string]any); art["status"] != "done" || art["path"] != "users/u1/runCards/a1/art-1.png" || len(art) != 2 {
		t.Fatalf("tranh thẻ khoe = %v", art)
	}

	// Tranh xong trước rồi mới khoe: khoe mang tranh luôn. Mỗi buổi bắt đầu một
	// ngày khác để không bị tính là trùng a1.
	e.card("a2", map[string]any{"startedAt": "2026-10-23T23:00:00Z"})
	e.want(e.ask("a2", "anime_cel", ""), 200, "")
	e.draw(e.lastTask())
	r := e.call("u1", "POST", "/v1/activities/a2/card/share", nil, "")
	e.want(r, 200, "")
	if art := r.body["card"].(map[string]any)["art"].(map[string]any); art["path"] != "users/u1/runCards/a2/art-1.png" {
		t.Fatalf("tranh trả về = %v", art)
	}

	// Bỏ khoe hai lần đều được; bỏ rồi thì vẽ xong không dựng lại thẻ khoe.
	e.want(e.call("u1", "DELETE", "/v1/activities/a1/card/share", nil, ""), 204, "")
	e.want(e.call("u1", "DELETE", "/v1/activities/a1/card/share", nil, ""), 204, "")
	if e.clubCard("a1") != nil {
		t.Fatal("bỏ khoe mà thẻ còn")
	}
	e.card("a3", map[string]any{"startedAt": "2026-10-22T23:00:00Z"})
	e.want(e.ask("a3", "anime_cel", ""), 200, "")
	e.draw(e.lastTask())
	if e.clubCard("a3") != nil {
		t.Fatal("chưa khoe mà vẽ xong lại có thẻ khoe")
	}
}

func TestEmulatorAccountDeleteRemovesClubCards(t *testing.T) {
	db := emulatorDB(t)
	seed(t, db, "clubCards/uA_a1", map[string]any{"ownerUid": "uA"})
	seed(t, db, "clubCards/uB_a1", map[string]any{"ownerUid": "uB"})
	accounts := &AccountService{db: db}
	if err := accounts.deleteOwnedDocuments(context.Background(), "uA", ""); err != nil {
		t.Fatal(err)
	}
	if club, err := getData(context.Background(), db.Doc("clubCards/uA_a1")); err != nil || club != nil {
		t.Fatalf("xoá tài khoản mà còn thẻ khoe (%v)", err)
	}
	if club, err := getData(context.Background(), db.Doc("clubCards/uB_a1")); err != nil || club == nil {
		t.Fatalf("thẻ khoe của người khác bị xoá (%v)", err)
	}
}
