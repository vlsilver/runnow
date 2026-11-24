//go:build emulator

package backend

import (
	"context"
	"errors"
	"fmt"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// fakeRankQuoter ghi lại dòng dữ kiện và trả "câu <số dòng>"; lô của bảng Đạp
// xe thì lỗi để thẻ đó dùng câu mẫu.
type fakeRankQuoter struct {
	calls int
	facts map[string]string
}

func (f *fakeRankQuoter) Quotes(_ context.Context, facts []string) ([]string, error) {
	f.calls++
	if f.facts == nil {
		f.facts = map[string]string{}
	}
	out := make([]string, len(facts))
	for i, fact := range facts {
		if strings.Contains(fact, "Đạp xe") {
			return nil, errors.New("model lỗi")
		}
		out[i] = fmt.Sprintf("câu %d", i+1)
		f.facts[fact] = out[i]
	}
	return out, nil
}

func seedRankActivity(t *testing.T, db *firestore.Client, uid, id, source, sport string, at time.Time, meters float64) {
	t.Helper()
	seed(t, db, "users/"+uid+"/activities/"+id, map[string]any{"source": source, "sportType": sport, "startedAt": at.UTC().Format(time.RFC3339Nano), "distanceMeters": meters, "movingTimeSeconds": 1800, "elapsedTimeSeconds": 1800})
}

func seedStepDay(t *testing.T, db *firestore.Client, uid, date string, steps, meters float64) {
	t.Helper()
	seed(t, db, "users/"+uid+"/stepDays/"+date, map[string]any{"date": date, "steps": steps, "distanceMeters": meters})
}

func rankDoc(t *testing.T, db *firestore.Client, path string) map[string]any {
	t.Helper()
	snap, err := db.Doc(path).Get(context.Background())
	if err != nil {
		t.Fatalf("đọc %s: %v", path, err)
	}
	return snap.Data()
}

// Chốt tuần 26/10–1/11 và tháng 10 lúc 12:30 thứ Hai 2/11. Số mong đợi tính tay:
//   - an: chạy 10 km ngày 27; Apple 12 km ngày 27 (đi bộ thuần 2 km) và 3 km
//     ngày 28 → tuần 15 km, 23.000 bước. Thêm 7 km tối 25/10 chỉ vào tháng → 22 km.
//   - binh: chạy 20 km (3i) ngày 29, Apple 21 km → đi bộ 1 km → 21 km, 20.000
//     bước; đạp 30 km ngày 30, buổi đạp sáng 2/11 thuộc tuần sau.
//   - chi: 23.000 bước, Apple 5 km không chạy → 5 km; bằng bước an nên chung hạng 1.
//   - phong để private, zed public mà không có gì: không vào bảng nào.
func TestEmulatorRankCloseWritesBoardsAndCards(t *testing.T) {
	db := emulatorDB(t)
	vn := func(month, day, hour, minute int) time.Time {
		return time.Date(2026, time.Month(month), day, hour, minute, 0, 0, vietnam)
	}
	for uid, p := range map[string]map[string]any{
		"an":    {"profileVisibility": "public", "nickname": "An", "avatarUrl": "https://a/an.png"},
		"binh":  {"profileVisibility": "public", "displayName": "Bình"},
		"chi":   {"profileVisibility": "public", "nickname": "Chi"},
		"phong": {"profileVisibility": "private", "nickname": "Phong"},
		"zed":   {"profileVisibility": "public", "nickname": "Zed"},
	} {
		seed(t, db, "publicProfiles/"+uid, p)
	}
	seedRankActivity(t, db, "an", "a1", "strava", "Run", vn(10, 27, 6, 0), 10000)
	seedRankActivity(t, db, "an", "a0", "strava", "Run", vn(10, 25, 23, 0), 7000)
	seedStepDay(t, db, "an", "2026-10-27", 15000, 12000)
	seedStepDay(t, db, "an", "2026-10-28", 8000, 3000)
	seedRankActivity(t, db, "binh", "b1", "runnow", "Run", vn(10, 29, 6, 0), 20000)
	seedStepDay(t, db, "binh", "2026-10-29", 20000, 21000)
	seedRankActivity(t, db, "binh", "b2", "apple_health", "Ride", vn(10, 30, 6, 0), 30000)
	seedRankActivity(t, db, "binh", "b3", "apple_health", "Ride", vn(11, 2, 8, 0), 50000)
	seedStepDay(t, db, "chi", "2026-10-30", 23000, 5000)
	seedRankActivity(t, db, "phong", "p1", "strava", "Run", vn(10, 28, 6, 0), 100000)

	quoter := &fakeRankQuoter{}
	now := vn(11, 2, 12, 30)
	deps := &Dependencies{Firestore: db, RankCards: NewRankCardService(db, quoter), Now: func() time.Time { return now }}
	bot := NewBotServer(Config{}, deps)
	close := func() {
		t.Helper()
		w := httptest.NewRecorder()
		bot.ServeHTTP(w, httptest.NewRequest("POST", "/tasks/rank-close", strings.NewReader("{}")))
		if w.Code != 200 {
			t.Fatalf("rank-close: %d %s", w.Code, w.Body)
		}
	}
	close()

	board := rankDoc(t, db, "rankBoards/week_2026-10-26_run")
	entries, _ := board["entries"].([]any)
	var got []string
	for _, e := range entries {
		m := e.(map[string]any)
		got = append(got, fmt.Sprintf("%s#%d", m["uid"], int(number(m["rank"]))))
	}
	if strings.Join(got, " ") != "binh#1 an#2 chi#3" || number(board["participants"]) != 3 || board["periodEnd"] != "2026-11-02" {
		t.Fatalf("bảng tuần Chạy = %v participants %v", got, board["participants"])
	}

	card := rankDoc(t, db, "users/binh/rankCards/week_2026-10-26_run")
	stats := card["stats"].(map[string]any)
	if number(card["rank"]) != 1 || card["tier"] != "legendary" || number(card["score"]) != 21000 || number(stats["runMeters"]) != 20000 || number(stats["walkMeters"]) != 1000 || card["revealedAt"] != nil {
		t.Fatalf("thẻ Chạy của binh = %v", card)
	}
	wantFact := "BXH tuần 26/10–01/11; hạng 1 trên 3 người; bảng Chạy và Đi bộ; tổng 21,0 km; chạy 20,0 km; đi bộ 1,0 km; hơn hạng 2 6,0 km"
	if quoter.facts[wantFact] != "câu 1" || card["quote"] != "câu 1" {
		t.Fatalf("quote = %q, dữ kiện gửi model: %v", card["quote"], quoter.facts)
	}

	for _, uid := range []string{"an", "chi"} {
		steps := rankDoc(t, db, "users/"+uid+"/rankCards/week_2026-10-26_steps")
		if number(steps["rank"]) != 1 || steps["tier"] != "legendary" || number(steps["score"]) != 23000 {
			t.Fatalf("thẻ Bước của %s = %v", uid, steps)
		}
	}
	anSteps := rankDoc(t, db, "users/an/rankCards/week_2026-10-26_steps")["stats"].(map[string]any)
	if number(anSteps["avgSteps"]) != 3285 || number(anSteps["days10k"]) != 1 || number(anSteps["days"]) != 7 {
		t.Fatalf("số phụ Bước của an = %v", anSteps)
	}
	if third := rankDoc(t, db, "users/binh/rankCards/week_2026-10-26_steps"); number(third["rank"]) != 3 || third["tier"] != "epic" {
		t.Fatalf("thẻ Bước của binh = %v", third)
	}

	bike := rankDoc(t, db, "users/binh/rankCards/week_2026-10-26_bike")
	bikeStats := bike["stats"].(map[string]any)
	if number(bike["score"]) != 30000 || number(bikeStats["rides"]) != 1 || number(bikeStats["longestMeters"]) != 30000 || bike["quote"] != "Dẫn đầu cả tuần." {
		t.Fatalf("thẻ Đạp xe của binh = %v", bike)
	}

	month := rankDoc(t, db, "users/an/rankCards/month_2026-10-01_run")
	if number(month["rank"]) != 1 || month["tier"] != "mythic" || number(month["score"]) != 22000 {
		t.Fatalf("thẻ tháng của an = %v", month)
	}
	if second := rankDoc(t, db, "users/binh/rankCards/month_2026-10-01_run"); second["tier"] != "legendary" {
		t.Fatalf("thẻ tháng của binh = %v", second)
	}

	for _, uid := range []string{"phong", "zed"} {
		cards, err := db.Collection("users").Doc(uid).Collection("rankCards").Documents(context.Background()).GetAll()
		if err != nil {
			t.Fatal(err)
		}
		if len(cards) != 0 {
			t.Fatalf("%s không được có thẻ, có %d", uid, len(cards))
		}
	}

	// Chạy lại sau khi có buổi mới: bảng đã chốt giữ nguyên, model không bị gọi lại.
	calls := quoter.calls
	seedRankActivity(t, db, "chi", "c1", "strava", "Run", vn(10, 31, 6, 0), 40000)
	close()
	if quoter.calls != calls {
		t.Fatalf("chạy lại gọi model %d lần", quoter.calls-calls)
	}
	if again := rankDoc(t, db, "users/binh/rankCards/week_2026-10-26_run"); number(again["rank"]) != 1 {
		t.Fatalf("thẻ đã chốt bị đổi: %v", again)
	}
}

// Trước 12:00 thứ Hai thì tuần vừa hết chưa chốt.
func TestEmulatorRankCloseWaitsUntilNoon(t *testing.T) {
	db := emulatorDB(t)
	seed(t, db, "publicProfiles/an", map[string]any{"profileVisibility": "public", "nickname": "An"})
	seedStepDay(t, db, "an", "2026-10-27", 15000, 0)
	svc := NewRankCardService(db, nil)
	if err := svc.Close(context.Background(), time.Date(2026, 11, 2, 11, 59, 0, 0, vietnam)); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Doc("rankBoards/week_2026-10-26_steps").Get(context.Background()); err == nil {
		t.Fatal("tuần 26/10 đã chốt trước 12:00")
	}
	if err := svc.Close(context.Background(), time.Date(2026, 11, 2, 12, 0, 0, 0, vietnam)); err != nil {
		t.Fatal(err)
	}
	card := rankDoc(t, db, "users/an/rankCards/week_2026-10-26_steps")
	if card["quote"] != "Dẫn đầu cả tuần." {
		t.Fatalf("thẻ = %v", card)
	}
}

// schedule-tick hẹn task chốt với TaskID theo kỳ.
func TestEmulatorScheduleTickEnqueuesRankClose(t *testing.T) {
	db := emulatorDB(t)
	now := time.Date(2026, 11, 2, 12, 30, 0, 0, vietnam)
	var tasks []PublishTask
	publish := func(_ context.Context, task PublishTask) (string, error) {
		tasks = append(tasks, task)
		return task.TaskID, nil
	}
	deps := &Dependencies{Firestore: db, RankCards: NewRankCardService(db, nil), EnqueueTask: publish, Now: func() time.Time { return now }}
	w := httptest.NewRecorder()
	NewBotServer(Config{}, deps).ServeHTTP(w, httptest.NewRequest("POST", "/tasks/schedule-tick", strings.NewReader("{}")))
	if w.Code != 200 || len(tasks) != 1 || tasks[0].HandlerPath != "/tasks/rank-close" || tasks[0].TaskID != StableTaskID("rank-close", []string{"2026-10-26", "2026-10-01"}) {
		t.Fatalf("tick: %d, tasks %+v", w.Code, tasks)
	}
}

// Quà bốc thăm cho người từ 15 km tuần 26/10–1/11, bảng Chạy·Đi bộ. Số tính tay:
// binh 21 km, an đúng 15 km (chạy 10, đi bộ thuần 5), chi 14,9 km. Ba suất mà
// chỉ hai người đạt mốc, nên khỏi phụ thuộc kết quả bốc: binh và an trúng, chi không.
func TestEmulatorRankCloseDrawReward(t *testing.T) {
	db := emulatorDB(t)
	vn := func(day, hour int) time.Time { return time.Date(2026, 10, day, hour, 0, 0, 0, vietnam) }
	for uid, name := range map[string]string{"an": "An", "binh": "Bình", "chi": "Chi"} {
		seed(t, db, "publicProfiles/"+uid, map[string]any{"profileVisibility": "public", "nickname": name})
	}
	seedRankActivity(t, db, "binh", "b1", "strava", "Run", vn(29, 6), 21000)
	seedRankActivity(t, db, "an", "a1", "strava", "Run", vn(27, 6), 10000)
	seedStepDay(t, db, "an", "2026-10-27", 15000, 15000)
	seedStepDay(t, db, "chi", "2026-10-28", 20000, 14900)
	seed(t, db, "rankRewards/week_2026-10-26_run", map[string]any{
		"giverUid": "binh", "giverName": "Bình",
		"items": []any{map[string]any{"id": "ao", "kind": "draw", "minScore": 15000, "slots": 3, "name": "Áo Kiprun", "icon": "shirt", "photos": []any{}}},
	})

	now := time.Date(2026, 11, 2, 12, 30, 0, 0, vietnam)
	if err := NewRankCardService(db, nil).Close(context.Background(), now); err != nil {
		t.Fatal(err)
	}
	board := rankDoc(t, db, "rankBoards/week_2026-10-26_run")
	won := map[string]bool{}
	for _, e := range board["entries"].([]any) {
		m := e.(map[string]any)
		if m["reward"] != nil {
			won[m["uid"].(string)] = true
		}
	}
	if len(won) != 2 || !won["binh"] || !won["an"] {
		t.Fatalf("người trúng trên bảng = %v, entries %v", won, board["entries"])
	}
	card := rankDoc(t, db, "users/an/rankCards/week_2026-10-26_run")
	reward, _ := card["reward"].(map[string]any)
	if reward["itemId"] != "ao" || reward["name"] != "Áo Kiprun" || reward["giverName"] != "Bình" {
		t.Fatalf("quà trên thẻ an = %v", card["reward"])
	}
	if chi := rankDoc(t, db, "users/chi/rankCards/week_2026-10-26_run"); chi["reward"] != nil {
		t.Fatalf("chi 14,9 km mà có quà: %v", chi["reward"])
	}
}

// Bốc thăm lấy cả người ngoài top 10: 12 người đều trên 15 km, top 10 đã có
// giày, nên suất áo duy nhất về hạng 11 hoặc 12. Người trúng có thẻ, có tên ở
// cuối entries (app chỉ mở thẻ của người trong entries), admin thấy họ trong
// danh sách trúng và họ nhận push quà.
func TestEmulatorRankCloseDrawOutsideTop(t *testing.T) {
	db := emulatorDB(t)
	const boardID = "week_2026-10-26_run"
	vn := func(day, hour int) time.Time { return time.Date(2026, 10, day, hour, 0, 0, 0, vietnam) }
	for i := 1; i <= 12; i++ {
		uid := fmt.Sprintf("r%02d", i)
		seed(t, db, "publicProfiles/"+uid, map[string]any{"profileVisibility": "public", "nickname": uid})
		seedRankActivity(t, db, uid, uid+"-run", "strava", "Run", vn(28, 6), float64(31000-i*1000))
		seed(t, db, "pushTokens/tok-"+uid, map[string]any{"uid": uid, "token": "tok-" + uid})
	}
	seed(t, db, "rankRewards/"+boardID, map[string]any{
		"giverUid": "r01", "giverName": "r01",
		"items": []any{
			map[string]any{"id": "giay", "fromRank": 1, "toRank": 10, "name": "Giày", "icon": "shoes", "photos": []any{}},
			map[string]any{"id": "ao", "kind": "draw", "minScore": 15000, "slots": 1, "name": "Áo Kiprun", "icon": "shirt", "photos": []any{}},
		},
	})

	now := time.Date(2026, 11, 2, 12, 30, 0, 0, vietnam)
	if err := NewRankCardService(db, nil).Close(context.Background(), now); err != nil {
		t.Fatal(err)
	}
	entries := rankDoc(t, db, "rankBoards/"+boardID)["entries"].([]any)
	if len(entries) != 11 {
		t.Fatalf("entries có %d người, muốn top 10 và một người trúng: %v", len(entries), entries)
	}
	w := entries[10].(map[string]any)
	winner := w["uid"].(string)
	loser := map[string]string{"r11": "r12", "r12": "r11"}[winner]
	if loser == "" || w["reward"].(map[string]any)["itemId"] != "ao" {
		t.Fatalf("người trúng ngoài top = %v", w)
	}
	card := rankDoc(t, db, "users/"+winner+"/rankCards/"+boardID)
	if reward, _ := card["reward"].(map[string]any); reward["itemId"] != "ao" || number(card["rank"]) != number(w["rank"]) {
		t.Fatalf("thẻ người trúng = %v", card)
	}
	if _, err := db.Doc("users/" + loser + "/rankCards/" + boardID).Get(context.Background()); status.Code(err) != codes.NotFound {
		t.Fatalf("%s không trúng mà có thẻ: %v", loser, err)
	}

	view, err := NewRankRewardService(db, nil).View(context.Background(), boardID, now)
	if err != nil {
		t.Fatal(err)
	}
	got := map[string]string{}
	for _, v := range view.Winners {
		got[v.UID] = v.ItemID
	}
	if len(got) != 11 || got[winner] != "ao" || got["r10"] != "giay" {
		t.Fatalf("admin thấy người trúng %v", got)
	}

	push, sender := newFakePush(db)
	if err := DeliverRankRewardPush(context.Background(), db, push, boardID); err != nil {
		t.Fatal(err)
	}
	sentTo := map[string]bool{}
	for _, m := range sender.sent {
		sentTo[m.Token] = true
	}
	if len(sentTo) != 11 || !sentTo["tok-"+winner] || sentTo["tok-"+loser] {
		t.Fatalf("push quà tới %v", sentTo)
	}
}

// Push gửi được cho hơn 30 người: truy vấn in của Firestore nhận tối đa 30 uid.
func TestEmulatorPushSendOver30(t *testing.T) {
	db := emulatorDB(t)
	var uids []string
	for i := range 31 {
		uid := fmt.Sprintf("u%02d", i)
		uids = append(uids, uid)
		seed(t, db, "pushTokens/tok-"+uid, map[string]any{"uid": uid, "token": "tok-" + uid})
	}
	push, sender := newFakePush(db)
	if err := push.Send(context.Background(), uids, pushNote{Title: "t", Body: "b"}); err != nil {
		t.Fatal(err)
	}
	if len(sender.sent) != 31 {
		t.Fatalf("gửi %d tin, muốn 31", len(sender.sent))
	}
}
