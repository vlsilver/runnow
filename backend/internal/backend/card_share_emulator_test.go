//go:build emulator

package backend

import (
	"slices"
	"testing"
	"time"
)

func sortedKeys(m map[string]any) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	slices.Sort(keys)
	return keys
}

func TestEmulatorGameCardShare(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	e.want(e.call("u1", "POST", "/v1/cards/game/g1/share", nil, ""), 404, "card_not_found")

	ended := time.Date(2026, 10, 20, 14, 0, 0, 0, time.UTC)
	seed(t, e.store.db, "users/u1/gameCards/g1", map[string]any{
		"gameId": "g1", "tier": "rare", "role": "seer", "team": "village", "winner": "village",
		"alive": false, "deathRound": int64(2), "rounds": int64(4), "playerCount": int64(8), "endedAt": ended,
		// Field không có trong danh sách khoe thì không được chép.
		"note": "riêng",
	})
	// Người khác không khoe được thẻ của u1.
	e.want(e.call("u2", "POST", "/v1/cards/game/g1/share", nil, ""), 404, "card_not_found")
	e.want(e.call("u1", "POST", "/v1/cards/game/g1/share", nil, ""), 204, "")

	club := e.clubCard("game_g1")
	if got := sortedKeys(club); !slices.Equal(got, []string{"alive", "deathRound", "endedAt", "gameId", "kind", "ownerUid", "playerCount", "role", "rounds", "sharedAt", "team", "tier", "winner"}) {
		t.Fatalf("field thẻ khoe = %v", got)
	}
	if club["kind"] != "game" || club["ownerUid"] != "u1" || club["role"] != "seer" || club["rounds"] != int64(4) || !club["endedAt"].(time.Time).Equal(ended) {
		t.Fatalf("thẻ khoe = %v", club)
	}

	// Khoe lại giữ giờ khoe đầu.
	e.clock = e.clock.Add(time.Hour)
	e.want(e.call("u1", "POST", "/v1/cards/game/g1/share", nil, ""), 204, "")
	if at := e.clubCard("game_g1")["sharedAt"].(time.Time); !at.Equal(time.Date(2026, 10, 25, 1, 0, 0, 0, time.UTC)) {
		t.Fatalf("sharedAt sau khi khoe lại = %v", at)
	}

	// Thẻ ván thử không lên club.
	seed(t, e.store.db, "users/u1/gameCards/g2", map[string]any{"gameId": "g2", "tier": "common", "testMode": true})
	e.want(e.call("u1", "POST", "/v1/cards/game/g2/share", nil, ""), 409, "card_test_mode")
	if e.clubCard("game_g2") != nil {
		t.Fatal("thẻ ván thử lên club")
	}

	e.want(e.call("u1", "DELETE", "/v1/cards/game/g1/share", nil, ""), 204, "")
	e.want(e.call("u1", "DELETE", "/v1/cards/game/g1/share", nil, ""), 204, "")
	if e.clubCard("game_g1") != nil {
		t.Fatal("bỏ khoe mà thẻ còn")
	}
}

func TestEmulatorJourneyCardShare(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	finished := time.Date(2026, 9, 1, 0, 30, 0, 0, time.UTC)
	seed(t, e.store.db, "users/u1/journeyCards/marathon", map[string]any{
		"campaign": "marathon", "routeId": "athens_marathon", "level": int64(1), "tier": "rare",
		"distanceMeters": 42195.0, "runCount": int64(9), "finishedAt": finished, "awardedAt": finished,
	})
	e.want(e.call("u1", "POST", "/v1/cards/journey/marathon/share", nil, ""), 204, "")
	club := e.clubCard("journey_marathon")
	if got := sortedKeys(club); !slices.Equal(got, []string{"campaign", "distanceMeters", "finishedAt", "kind", "level", "ownerUid", "routeId", "runCount", "sharedAt", "tier"}) {
		t.Fatalf("field thẻ khoe = %v", got)
	}
	if club["kind"] != "journey" || club["distanceMeters"] != 42195.0 || club["runCount"] != int64(9) {
		t.Fatalf("thẻ khoe = %v", club)
	}
	e.want(e.call("u1", "DELETE", "/v1/cards/journey/marathon/share", nil, ""), 204, "")
	if e.clubCard("journey_marathon") != nil {
		t.Fatal("bỏ khoe mà thẻ còn")
	}
}

func TestEmulatorCardShareUnknownKind(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	// Thẻ buổi chạy khoe qua /v1/activities, không qua đây.
	e.want(e.call("u1", "POST", "/v1/cards/run/a1/share", nil, ""), 400, "invalid_request")
	e.want(e.call("u1", "DELETE", "/v1/cards/badge/b1/share", nil, ""), 400, "invalid_request")
}

func TestEmulatorRankCardShare(t *testing.T) {
	e := newArtEnv(t, map[string]any{})
	card := map[string]any{
		"boardId": "month_steps_2026-09-01", "range": "month", "sport": "steps",
		"periodStart": "2026-09-01", "periodEnd": "2026-10-01", "rank": int64(3), "participants": int64(20),
		"tier": "rare", "score": 312000.0, "displayName": "An", "quote": "Đi bộ không nghỉ.",
		"stats":     map[string]any{"avgSteps": int64(10400), "days10k": int64(18), "days": int64(30)},
		"awardedAt": time.Date(2026, 10, 1, 5, 0, 0, 0, time.UTC), "revealedAt": nil,
	}
	seed(t, e.store.db, "users/u1/rankCards/month_steps_2026-09-01", card)
	// Thẻ còn úp: chưa khoe được, để hạng không lộ trước khi chủ lật.
	e.want(e.call("u1", "POST", "/v1/cards/rank/month_steps_2026-09-01/share", nil, ""), 409, "card_face_down")
	if e.clubCard("rank_month_steps_2026-09-01") != nil {
		t.Fatal("thẻ còn úp lên club")
	}

	card["revealedAt"] = time.Date(2026, 10, 2, 0, 0, 0, 0, time.UTC)
	seed(t, e.store.db, "users/u1/rankCards/month_steps_2026-09-01", card)
	e.want(e.call("u1", "POST", "/v1/cards/rank/month_steps_2026-09-01/share", nil, ""), 204, "")
	club := e.clubCard("rank_month_steps_2026-09-01")
	if got := sortedKeys(club); !slices.Equal(got, []string{"awardedAt", "boardId", "displayName", "kind", "ownerUid", "participants", "periodEnd", "periodStart", "quote", "range", "rank", "revealedAt", "score", "sharedAt", "sport", "stats", "tier"}) {
		t.Fatalf("field thẻ khoe = %v", got)
	}
	if club["kind"] != "rank" || club["sport"] != "steps" || club["rank"] != int64(3) {
		t.Fatalf("thẻ khoe = %v", club)
	}
}
