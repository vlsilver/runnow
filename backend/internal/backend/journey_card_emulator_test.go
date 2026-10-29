//go:build emulator

package backend

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

// Route rút ngắn cho dễ tính tay. Người chơi chọn cung hcm_trail cho Xuyên
// Việt nên mốc của chặng 3 là 30 + 40 = 70 km, còn offset của Đông Nam Á vẫn
// cộng cung đầu (coastal) như app: 10 + 20 + 50 = 80 km, mốc 180 km.
func seedJourneyRoutes(t *testing.T, db *firestore.Client) {
	t.Helper()
	for id, meters := range map[string]float64{
		"athens_marathon":    10000,
		"tour_du_mont_blanc": 20000,
		"coastal":            50000,
		"hcm_trail":          40000,
		"dong_nam_a":         100000,
	} {
		seed(t, db, "journeyRoutes/"+id, map[string]any{"totalLengthMeters": meters})
	}
}

func seedJourneyActivity(t *testing.T, db *firestore.Client, id, sport string, at time.Time, meters float64) {
	t.Helper()
	seed(t, db, "users/u1/activities/"+id, map[string]any{"id": id, "source": "strava", "sportType": sport, "startedAt": at.UTC().Format(time.RFC3339Nano), "distanceMeters": meters, "movingTimeSeconds": int(meters / 3), "elapsedTimeSeconds": int(meters / 3)})
}

func rebuildPeriodStats(t *testing.T, worker http.Handler, instants ...time.Time) {
	t.Helper()
	var raw []string
	for _, at := range instants {
		raw = append(raw, at.Format(time.RFC3339))
	}
	body, _ := json.Marshal(map[string]any{"uid": "u1", "startedAts": raw})
	w := httptest.NewRecorder()
	worker.ServeHTTP(w, httptest.NewRequest("POST", "/tasks/rebuild-period-stats", bytes.NewReader(body)))
	if w.Code != 200 {
		t.Fatalf("rebuild-period-stats: %d %s", w.Code, w.Body)
	}
}

func journeyCards(t *testing.T, db *firestore.Client) map[string]map[string]any {
	t.Helper()
	docs, err := db.Collection("users").Doc("u1").Collection("journeyCards").Documents(context.Background()).GetAll()
	if err != nil {
		t.Fatal(err)
	}
	out := map[string]map[string]any{}
	for _, doc := range docs {
		out[doc.Ref.ID] = doc.Data()
	}
	return out
}

func wantJourneyCard(t *testing.T, card map[string]any, routeID, tier string, level, meters, runs float64, finishedAt time.Time) {
	t.Helper()
	if card == nil {
		t.Fatalf("thiếu thẻ %s", routeID)
	}
	if card["routeId"] != routeID || card["tier"] != tier || number(card["level"]) != level || number(card["distanceMeters"]) != meters || number(card["runCount"]) != runs {
		t.Fatalf("thẻ = %v, mong đợi route %s tier %s level %v %v m %v buổi", card, routeID, tier, level, meters, runs)
	}
	if got, _ := card["finishedAt"].(time.Time); !got.Equal(finishedAt) {
		t.Fatalf("finishedAt = %v, mong đợi %v", card["finishedAt"], finishedAt)
	}
}

// Thẻ hành trình ra khi tổng km trọn đời vượt mốc về đích của từng chặng, ghi
// một lần rồi giữ nguyên; buổi đạp xe không được cộng vào.
func TestEmulatorJourneyCardsAwardedWhenCampaignFinished(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	seedJourneyRoutes(t, db)
	seed(t, db, "users/u1", map[string]any{"journeyRouteId": "hcm_trail"})
	vn := func(month, day int) time.Time { return time.Date(2026, time.Month(month), day, 6, 0, 0, 0, vietnam) }

	// Cộng dồn: 6, 12 (qua mốc 10 → xong marathon), 27, 32 (qua 30 → xong
	// Mont Blanc), 62 km. Buổi đạp xe 50 km mà bị cộng thì Xuyên Việt (70 km)
	// cũng ra thẻ.
	seedJourneyActivity(t, db, "a1", "Run", vn(10, 1), 6000)
	seedJourneyActivity(t, db, "a2", "Run", vn(10, 2), 6000)
	seedJourneyActivity(t, db, "a3", "Run", vn(10, 3), 15000)
	seedJourneyActivity(t, db, "ride", "Ride", vn(10, 4), 50000)
	seedJourneyActivity(t, db, "a4", "Walk", vn(11, 1), 5000)
	seedJourneyActivity(t, db, "a5", "Run", vn(11, 5), 30000)

	worker := NewWorkerServer(Config{}, &Dependencies{Firestore: db, PeriodStats: NewPeriodStatsService(db), JourneyCards: NewJourneyCardService(db)})
	rebuildPeriodStats(t, worker, vn(10, 1), vn(11, 1))

	cards := journeyCards(t, db)
	if len(cards) != 2 {
		t.Fatalf("có thẻ %v, mong đợi marathon và mont_blanc", cards)
	}
	// Marathon: a1, a2. Mont Blanc (10 → 30 km): a2 (6 → 12), a3, a4.
	wantJourneyCard(t, cards["marathon"], "athens_marathon", "rare", 1, 10000, 2, vn(10, 2))
	wantJourneyCard(t, cards["mont_blanc"], "tour_du_mont_blanc", "epic", 2, 20000, 3, vn(11, 1))

	// Thẻ đã có thì không ghi lại, kể cả khi số liệu tính lại khác.
	if _, err := db.Doc("users/u1/journeyCards/marathon").Update(ctx, []firestore.Update{{Path: "runCount", Value: 99}}); err != nil {
		t.Fatal(err)
	}
	seedJourneyActivity(t, db, "a6", "Run", vn(12, 1), 10000)
	rebuildPeriodStats(t, worker, vn(12, 1))

	cards = journeyCards(t, db)
	if len(cards) != 3 || number(cards["marathon"]["runCount"]) != 99 {
		t.Fatalf("có thẻ %v, mong đợi thêm xuyen_viet và marathon giữ nguyên", cards)
	}
	// Xuyên Việt cung hcm_trail (30 → 70 km): a4 (27 → 32), a5, a6 (62 → 72).
	wantJourneyCard(t, cards["xuyen_viet"], "hcm_trail", "legendary", 3, 40000, 3, vn(12, 1))

	// 172 km: chưa tới mốc 180 km của Đông Nam Á. Lấy cung đã chọn (40 km) làm
	// offset thì mốc tụt còn 170 km và thẻ ra sai.
	seedJourneyActivity(t, db, "a7", "Run", vn(12, 20), 100000)
	rebuildPeriodStats(t, worker, vn(12, 20))
	if cards = journeyCards(t, db); cards["dong_nam_a"] != nil {
		t.Fatalf("172 km đã có thẻ Đông Nam Á: %v", cards["dong_nam_a"])
	}
	// 182 km: về đích ở a8. Chặng 80 → 180 km gồm a7 (72 → 172) và a8.
	seedJourneyActivity(t, db, "a8", "Run", vn(12, 21), 10000)
	rebuildPeriodStats(t, worker, vn(12, 21))
	wantJourneyCard(t, journeyCards(t, db)["dong_nam_a"], "dong_nam_a", "mythic", 4, 100000, 2, vn(12, 21))
}

// Thiếu doc route thì không đoán mốc: task trả lỗi để Cloud Tasks chạy lại.
func TestEmulatorJourneyCardsFailWithoutRoute(t *testing.T) {
	db := emulatorDB(t)
	seed(t, db, "users/u1", map[string]any{})
	seedJourneyActivity(t, db, "a1", "Run", time.Date(2026, 10, 1, 6, 0, 0, 0, vietnam), 6000)

	_, err := NewJourneyCardService(db).AwardFinished(context.Background(), "u1")
	if err == nil || !strings.Contains(err.Error(), "athens_marathon") {
		t.Fatalf("err = %v, mong đợi lỗi nêu route athens_marathon", err)
	}
}
