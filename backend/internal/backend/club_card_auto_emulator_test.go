//go:build emulator

package backend

import (
	"context"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

func clubCardOf(t *testing.T, db *firestore.Client, id string) map[string]any {
	t.Helper()
	club, err := getData(context.Background(), db.Doc("clubCards/"+id))
	if err != nil {
		t.Fatal(err)
	}
	return club
}

func TestEmulatorRunCardRollSharesWhenProfilePublic(t *testing.T) {
	// Mọi lượt quay ra 10000: 23,5 km thì bậc thường 0 %, nên ra bậc hiếm (đoạn 0..504999), và chắc chắn trúng thẻ.
	h := runCardHarness(t, 10000)
	seed(t, h.store.db, "publicProfiles/u1", map[string]any{"profileVisibility": "public"})
	seed(t, h.store.db, "publicProfiles/u2", map[string]any{"profileVisibility": "private"})
	for _, uid := range []string{"u1", "u2", "u3"} {
		seedRun(t, h, uid, "a1", nil)
		h.want(h.call(uid, "POST", "/v1/activities/a1/card", nil, ""), 200, "")
	}

	club := clubCardOf(t, h.store.db, "u1_a1")
	if club == nil {
		t.Fatal("hồ sơ công khai mà thẻ không lên club")
	}
	if at := club["sharedAt"].(time.Time); !at.Equal(time.Date(2026, 10, 25, 1, 0, 0, 0, time.UTC)) || club["ownerUid"] != "u1" || club["tier"] != "rare" {
		t.Fatalf("thẻ khoe = %v", club)
	}
	if _, ok := club["snapshot"].(map[string]any)["route"]; ok {
		t.Fatal("thẻ khoe có đường chạy")
	}
	// Riêng tư hay chưa có hồ sơ thì không lên.
	for _, id := range []string{"u2_a1", "u3_a1"} {
		if clubCardOf(t, h.store.db, id) != nil {
			t.Fatalf("%s lên club", id)
		}
	}
}

func TestEmulatorGameEndSharesPublicWinners(t *testing.T) {
	db := emulatorDB(t)
	seed(t, db, "publicProfiles/u1", map[string]any{"profileVisibility": "public"})
	seed(t, db, "publicProfiles/u2", map[string]any{"profileVisibility": "private"})
	seed(t, db, "publicProfiles/w1", map[string]any{"profileVisibility": "public"})
	wall := time.Date(2026, 10, 28, 15, 0, 0, 0, time.UTC)
	state := func(phase werewolf.Phase, testMode bool) *werewolf.State {
		return &werewolf.State{
			Config: werewolf.Config{TestMode: testMode}, Round: 3, Phase: phase, Winner: werewolf.TeamVillage,
			Players: map[string]*werewolf.Player{
				"u1": {Role: werewolf.Seer, Alive: true},
				"u2": {Role: werewolf.Villager, Alive: false, DeathRound: 2},
				"u3": {Role: werewolf.Villager, Alive: true},
				"w1": {Role: werewolf.Wolf, Alive: false, DeathRound: 3},
			},
		}
	}
	end := func(gameID string, testMode bool) {
		t.Helper()
		err := db.RunTransaction(context.Background(), func(ctx context.Context, tx *firestore.Transaction) error {
			before, after := state(werewolf.PhaseTrial, testMode), state(werewolf.PhaseEnded, testMode)
			public, err := publicWinners(tx, db.Collection("publicProfiles"), before, after)
			if err != nil {
				return err
			}
			w := stepWrite{tx: tx, game: db.Doc("games/" + gameID), gameData: map[string]any{}, before: before, after: after,
				wall: wall, users: db.Collection("users"), clubCards: db.Collection("clubCards"), public: public}
			return w.writeGameCards()
		})
		if err != nil {
			t.Fatal(err)
		}
	}

	end("g1", false)
	club := clubCardOf(t, db, "u1_game_g1")
	if club == nil {
		t.Fatal("người thắng để công khai mà thẻ không lên club")
	}
	if club["kind"] != "game" || club["role"] != "seer" || club["team"] != "village" || !club["sharedAt"].(time.Time).Equal(wall) {
		t.Fatalf("thẻ khoe = %v", club)
	}
	// u2 riêng tư, u3 chưa có hồ sơ, w1 công khai nhưng thua.
	for _, id := range []string{"u2_game_g1", "u3_game_g1", "w1_game_g1"} {
		if clubCardOf(t, db, id) != nil {
			t.Fatalf("%s lên club", id)
		}
	}

	end("g2", true)
	if clubCardOf(t, db, "u1_game_g2") != nil {
		t.Fatal("thẻ ván thử lên club")
	}
}

func TestEmulatorSyncClubFollowsProfile(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	now := time.Date(2026, 10, 30, 9, 0, 0, 0, time.UTC)
	store := &RunCardStore{db: db, now: func() time.Time { return now }}
	rolled := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	ended := time.Date(2026, 9, 2, 0, 0, 0, 0, time.UTC)
	awarded := time.Date(2026, 9, 3, 0, 0, 0, 0, time.UTC)
	finished := time.Date(2026, 9, 4, 0, 0, 0, 0, time.UTC)

	seed(t, db, "publicProfiles/u1", map[string]any{"profileVisibility": "public"})
	seed(t, db, "users/u1/runCards/r1", map[string]any{"tier": "rare", "km": 10.2, "rolledAt": rolled,
		"snapshot": map[string]any{"name": "Sáng", "route": []any{map[string]any{"latitude": 21.0}}}})
	seed(t, db, "users/u1/runCards/r2", map[string]any{"tier": "common", "rolledAt": rolled})
	// r2 đã khoe từ trước: giữ nguyên, không ghi đè.
	seed(t, db, "clubCards/u1_r2", map[string]any{"ownerUid": "u1", "sharedAt": now, "mark": "cũ"})
	seed(t, db, "users/u1/gameCards/g1", map[string]any{"gameId": "g1", "tier": "epic", "role": "wolf", "endedAt": ended})
	seed(t, db, "users/u1/gameCards/g2", map[string]any{"gameId": "g2", "tier": "common", "testMode": true, "endedAt": ended})
	seed(t, db, "users/u1/journeyCards/marathon", map[string]any{"campaign": "marathon", "tier": "rare", "awardedAt": awarded, "finishedAt": finished})
	seed(t, db, "users/u1/journeyCards/xuyen_viet", map[string]any{"campaign": "xuyen_viet", "tier": "legendary", "finishedAt": finished})
	seed(t, db, "clubCards/u2_r9", map[string]any{"ownerUid": "u2", "sharedAt": now})

	for range 2 {
		if err := store.SyncClub(ctx, "u1"); err != nil {
			t.Fatal(err)
		}
	}
	want := map[string]time.Time{
		"u1_r1": rolled, "u1_r2": now, "u1_game_g1": ended,
		"u1_journey_marathon": awarded, "u1_journey_xuyen_viet": finished,
	}
	docs, err := db.Collection("clubCards").Where("ownerUid", "==", "u1").Documents(ctx).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	if len(docs) != len(want) {
		t.Fatalf("có %d thẻ khoe, muốn %d", len(docs), len(want))
	}
	for _, doc := range docs {
		at, ok := want[doc.Ref.ID]
		if !ok || !doc.Data()["sharedAt"].(time.Time).Equal(at) {
			t.Fatalf("%s sharedAt = %v, muốn %v", doc.Ref.ID, doc.Data()["sharedAt"], at)
		}
	}
	if club := clubCardOf(t, db, "u1_r2"); club["mark"] != "cũ" {
		t.Fatalf("thẻ đã khoe bị ghi đè: %v", club)
	}
	if _, ok := clubCardOf(t, db, "u1_r1")["snapshot"].(map[string]any)["route"]; ok {
		t.Fatal("thẻ khoe bù có đường chạy")
	}
	if club := clubCardOf(t, db, "u1_game_g1"); club["kind"] != "game" || club["role"] != "wolf" {
		t.Fatalf("thẻ Ma Sói khoe bù = %v", club)
	}

	// Chuyển riêng tư: gỡ hết thẻ của u1, thẻ người khác còn.
	seed(t, db, "publicProfiles/u1", map[string]any{"profileVisibility": "private"})
	if err := store.SyncClub(ctx, "u1"); err != nil {
		t.Fatal(err)
	}
	docs, err = db.Collection("clubCards").Where("ownerUid", "==", "u1").Documents(ctx).GetAll()
	if err != nil || len(docs) != 0 {
		t.Fatalf("riêng tư mà còn %d thẻ khoe (%v)", len(docs), err)
	}
	if clubCardOf(t, db, "u2_r9") == nil {
		t.Fatal("gỡ nhầm thẻ của người khác")
	}
}

// Task dựng lại dữ liệu phái sinh (chạy khi đổi hồ sơ và mỗi đêm) khoe bù thẻ.
func TestEmulatorDerivedRebuildSyncsClubCards(t *testing.T) {
	db := emulatorDB(t)
	seed(t, db, "users/u1", map[string]any{"displayName": "An"})
	seed(t, db, "publicProfiles/u1", map[string]any{"profileVisibility": "public"})
	seed(t, db, "users/u1/runCards/r1", map[string]any{"tier": "rare", "rolledAt": time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)})

	worker := NewWorkerServer(Config{}, &Dependencies{Firestore: db, Derived: NewDerivedDataService(db), RunCards: NewRunCardStore(db)})
	w := httptest.NewRecorder()
	worker.ServeHTTP(w, httptest.NewRequest("POST", "/tasks/rebuild-derived-data", strings.NewReader(`{"uid":"u1","cause":"profile-update"}`)))
	if w.Code != 200 {
		t.Fatalf("rebuild-derived-data: %d %s", w.Code, w.Body)
	}
	if clubCardOf(t, db, "u1_r1") == nil {
		t.Fatal("dựng lại xong mà thẻ chưa lên club")
	}
}

// Job đêm refresh-leaderboard khoe bù thẻ cho mọi user ngay trong request,
// không qua task: task rebuild-derived-data trùng tên trong ngày bị bỏ qua.
func TestEmulatorRefreshLeaderboardSyncsClubCards(t *testing.T) {
	db := emulatorDB(t)
	rolled := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	seed(t, db, "publicProfiles/u1", map[string]any{"profileVisibility": "public"})
	seed(t, db, "publicProfiles/u2", map[string]any{"profileVisibility": "private"})
	// u1 không có doc users/u1, chỉ có thẻ bên dưới.
	seed(t, db, "users/u1/runCards/r1", map[string]any{"tier": "rare", "rolledAt": rolled})
	seed(t, db, "users/u2", map[string]any{"displayName": "B"})
	seed(t, db, "users/u2/runCards/r2", map[string]any{"tier": "rare", "rolledAt": rolled})

	tasks, _ := newRecordingTaskPublisher(t)
	worker := NewWorkerServer(Config{}, &Dependencies{Firestore: db, Tasks: tasks, RunCards: NewRunCardStore(db)})
	w := httptest.NewRecorder()
	worker.ServeHTTP(w, httptest.NewRequest("POST", "/tasks/refresh-leaderboard", nil))
	if w.Code != 200 {
		t.Fatalf("refresh-leaderboard: %d %s", w.Code, w.Body)
	}
	if clubCardOf(t, db, "u1_r1") == nil {
		t.Fatal("job đêm chạy xong mà thẻ chưa lên club")
	}
	if clubCardOf(t, db, "u2_r2") != nil {
		t.Fatal("thẻ của người để riêng tư lên club")
	}
}
