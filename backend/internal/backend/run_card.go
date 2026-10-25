package backend

import (
	"context"
	"crypto/rand"
	"math"
	"math/big"
	"net/http"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
)

// Thẻ buổi chạy: mỗi buổi chạy được lật một thẻ, bậc quay ngẫu nhiên trên
// server theo bảng tỉ lệ của số km. Lật rồi thì giữ nguyên, không lật lại.
//
//	users/{uid}/runCards/{activityId}  thẻ; client chỉ đọc, backend ghi
//
// Thẻ chép lại số liệu buổi chạy (snapshot) lúc lật, nên xoá buổi chạy thì thẻ
// vẫn còn đủ để vẽ cả hai mặt.

type runCardTier string

const (
	runCardCommon    runCardTier = "common"
	runCardRare      runCardTier = "rare"
	runCardEpic      runCardTier = "epic"
	runCardLegendary runCardTier = "legendary"
	runCardMythic    runCardTier = "mythic"
)

var runCardTiers = [5]runCardTier{runCardCommon, runCardRare, runCardEpic, runCardLegendary, runCardMythic}

// runCardOddsAnchor là tỉ lệ (%) từng bậc ở một mốc km, theo thứ tự runCardTiers.
type runCardOddsAnchor struct {
	km  float64
	pct [5]float64
}

// runCardBands: mỗi khoảng km có tỉ lệ ở hai đầu, giữa hai đầu thì nội suy
// tuyến tính, nên thêm km là bậc cao dễ ra hơn. Khoảng sau loại hẳn bậc thấp
// nhất của khoảng trước. Quá mốc cuối thì giữ tỉ lệ mốc cuối.
var runCardBands = [][2]runCardOddsAnchor{
	{{0.5, [5]float64{70, 22, 6, 1.7, 0.3}}, {5, [5]float64{45, 30, 16, 7, 2}}},
	{{5, [5]float64{0, 66, 24, 8, 2}}, {42, [5]float64{0, 35, 38, 20, 7}}},
	{{42, [5]float64{0, 0, 55, 33, 12}}, {60, [5]float64{0, 0, 35, 45, 20}}},
}

// runCardPpm là đơn vị quay: một triệu phần.
const runCardPpm = 1_000_000

// runCardOdds là tỉ lệ từng bậc (phần triệu, tổng đúng runCardPpm) ở km đã làm
// tròn 0,1. Phần lệch do làm tròn cộng vào bậc có tỉ lệ lớn nhất.
func runCardOdds(km float64) [5]int64 {
	band := runCardBands[0]
	for _, b := range runCardBands {
		if km >= b[0].km {
			band = b
		}
	}
	from, to := band[0], band[1]
	t := min(max((km-from.km)/(to.km-from.km), 0), 1)
	var out [5]int64
	var sum int64
	largest := 0
	for i := range out {
		p := from.pct[i] + t*(to.pct[i]-from.pct[i])
		out[i] = int64(math.Round(p * runCardPpm / 100))
		sum += out[i]
		if out[i] > out[largest] {
			largest = i
		}
	}
	out[largest] += runCardPpm - sum
	return out
}

// Buổi ngắn hơn runCardShortKm (km đã làm tròn) chỉ có runCardShortChancePpm
// cơ hội ra thẻ; trượt thì ghi lại và buổi đó không lật được nữa.
const (
	runCardShortKm        = 3.0
	runCardShortChancePpm = 200_000
)

// runCardChancePpm là cơ hội ra thẻ (phần triệu) khi lật buổi km.
func runCardChancePpm(km float64) int64 {
	if km < runCardShortKm {
		return runCardShortChancePpm
	}
	return runCardPpm
}

// runCardPick là bậc ứng với số quay r trong [0, runCardPpm).
func runCardPick(odds [5]int64, r int64) runCardTier {
	for i, w := range odds {
		if r < w {
			return runCardTiers[i]
		}
		r -= w
	}
	return runCardTiers[len(runCardTiers)-1]
}

func cryptoRoll() (int64, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(runCardPpm))
	if err != nil {
		return 0, err
	}
	return n.Int64(), nil
}

const (
	runCardMinMeters = 500
	// runCardRoutePoints và runCardSplitsMax giới hạn snapshot cho doc thẻ nhỏ:
	// tem đường chạy và bản đồ mặt sau không cần mịn hơn, buổi siêu dài vẫn vừa.
	runCardRoutePoints = 80
	runCardSplitsMax   = 150
)

var (
	errRunCardNoActivity = &HTTPError{Status: http.StatusNotFound, Code: "activity_not_found", Message: "Không thấy buổi chạy này."}
	errRunCardNotRun     = &HTTPError{Status: http.StatusConflict, Code: "card_not_eligible", Message: "Chỉ buổi chạy bộ từ 500 m mới lật được thẻ."}
	errRunCardDuplicate  = &HTTPError{Status: http.StatusConflict, Code: "card_duplicate", Message: "Buổi này trùng một buổi khác đã có hoặc sẽ có thẻ."}
	errRunCardMissed     = &HTTPError{Status: http.StatusConflict, Code: "card_missed", Message: "Lần lật này không ra thẻ. Buổi dưới 3 km chỉ có 1/5 cơ hội ra thẻ."}
)

// runCardEligible kiểm buổi chạy được lật thẻ: chạy bộ (cả trail và máy chạy),
// từ 500 m, và không phải bản trùng của buổi Strava. Trùng với buổi đã có thẻ
// thì kiểm riêng trong transaction.
func runCardEligible(data map[string]any) error {
	if !runSportTypes[defaultString(data["sportType"], "Run")] || number(data["distanceMeters"]) < runCardMinMeters {
		return errRunCardNotRun
	}
	if stringValue(data["duplicateOfActivityId"]) != "" {
		return errRunCardDuplicate
	}
	return nil
}

func runCardKm(meters float64) float64 { return math.Round(meters/100) / 10 }

// runCardSnapshot chép số liệu buổi chạy cần để vẽ hai mặt thẻ.
func runCardSnapshot(data map[string]any) map[string]any {
	out := map[string]any{"route": runCardRoute(data["routePoints"]), "splits": runCardSplits(data["splits"])}
	for _, k := range []string{"name", "sportType", "source", "startedAt"} {
		if v := stringValue(data[k]); v != "" {
			out[k] = v
		}
	}
	for _, k := range []string{"distanceMeters", "movingTimeSeconds", "elapsedTimeSeconds", "elevationGainMeters", "averageHeartRate"} {
		if v, ok := data[k]; ok && v != nil {
			out[k] = number(v)
		}
	}
	return out
}

func runCardRoute(raw any) []any {
	points := anyList(raw)
	out := []any{}
	for _, i := range sampleIndexes(len(points), runCardRoutePoints) {
		p, _ := points[i].(map[string]any)
		lat, lng := number(p["latitude"]), number(p["longitude"])
		if lat == 0 && lng == 0 {
			continue
		}
		out = append(out, map[string]any{"lat": math.Round(lat*1e5) / 1e5, "lng": math.Round(lng*1e5) / 1e5})
	}
	return out
}

func runCardSplits(raw any) []any {
	out := []any{}
	for _, v := range anyList(raw) {
		if len(out) == runCardSplitsMax {
			break
		}
		m, _ := v.(map[string]any)
		d, s := number(m["distanceMeters"]), number(m["movingTimeSeconds"])
		if d <= 0 || s <= 0 {
			continue
		}
		out = append(out, map[string]any{"distanceMeters": d, "movingTimeSeconds": s})
	}
	return out
}

type RunCardOdd struct {
	Tier    runCardTier `json:"tier"`
	Percent float64     `json:"percent"`
}

func runCardOddList(odds [5]int64) []RunCardOdd {
	out := make([]RunCardOdd, len(odds))
	for i, w := range odds {
		out[i] = RunCardOdd{Tier: runCardTiers[i], Percent: float64(w) / (runCardPpm / 100)}
	}
	return out
}

// RunCardView là trả lời GET thẻ: Card khi đã lật; chưa lật thì Odds là tỉ lệ
// từng bậc khi ra thẻ và Chance là phần trăm cơ hội ra thẻ, hoặc Reason khi
// buổi này không lật được (kể cả đã lật mà trượt).
type RunCardView struct {
	Card   map[string]any `json:"card"`
	Odds   []RunCardOdd   `json:"odds,omitempty"`
	Chance float64        `json:"chance,omitempty"`
	Reason string         `json:"reason,omitempty"`
}

type RunCardStore struct {
	db   *firestore.Client
	roll func() (int64, error)
	now  func() time.Time
	// artist vẽ tranh thẻ; chỉ có trên service bot (xem SetArtist).
	artist *runCardArtist
}

func NewRunCardStore(db *firestore.Client) *RunCardStore {
	return &RunCardStore{db: db, roll: cryptoRoll, now: time.Now}
}

func (s *RunCardStore) cardRef(uid, activityID string) *firestore.DocumentRef {
	return s.db.Collection("users").Doc(uid).Collection("runCards").Doc(activityID)
}

// missRef ghi lượt lật trượt của buổi ngắn; chỉ backend đọc, rule không mở.
func (s *RunCardStore) missRef(uid, activityID string) *firestore.DocumentRef {
	return s.db.Collection("users").Doc(uid).Collection("runCardMisses").Doc(activityID)
}

func (s *RunCardStore) activityRef(uid, activityID string) *firestore.DocumentRef {
	return s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID)
}

// runCardJSON là doc thẻ gửi cho app, cùng tên field app đọc khi nghe doc.
func runCardJSON(id string, data map[string]any) map[string]any {
	out := cloneMap(data)
	out["id"] = id
	for _, k := range []string{"startedAt", "rolledAt"} {
		if t, ok := data[k].(time.Time); ok {
			out[k] = t.UTC().Format(time.RFC3339Nano)
		}
	}
	if art, ok := data["art"].(map[string]any); ok {
		out["art"] = runCardArtJSON(art)
	}
	return out
}

func (s *RunCardStore) Get(ctx context.Context, uid, activityID string) (RunCardView, error) {
	card, err := getData(ctx, s.cardRef(uid, activityID))
	if err != nil {
		return RunCardView{}, err
	}
	if card != nil {
		return RunCardView{Card: runCardJSON(activityID, card)}, nil
	}
	miss, err := getData(ctx, s.missRef(uid, activityID))
	if err != nil {
		return RunCardView{}, err
	}
	if miss != nil {
		return RunCardView{Reason: errRunCardMissed.Code}, nil
	}
	act, err := getData(ctx, s.activityRef(uid, activityID))
	if err != nil {
		return RunCardView{}, err
	}
	if act == nil {
		return RunCardView{}, errRunCardNoActivity
	}
	if err := runCardEligible(act); err != nil {
		return RunCardView{Reason: err.(*HTTPError).Code}, nil
	}
	km := runCardKm(number(act["distanceMeters"]))
	return RunCardView{
		Odds:   runCardOddList(runCardOdds(km)),
		Chance: float64(runCardChancePpm(km)) / (runCardPpm / 100),
	}, nil
}

// Roll lật thẻ cho buổi chạy. Đã lật thì trả thẻ cũ, đã trượt thì trả
// errRunCardMissed, nên app gửi lại (mạng chập, bấm hai lần) không quay lại.
// Bậc và cơ hội quay trước transaction và chỉ dùng khi chưa có kết quả, nên
// transaction chạy lại vẫn ra một kết quả.
func (s *RunCardStore) Roll(ctx context.Context, uid, activityID string) (map[string]any, error) {
	r, err := s.roll()
	if err != nil {
		return nil, err
	}
	chance, err := s.roll()
	if err != nil {
		return nil, err
	}
	var card map[string]any
	// Trượt vẫn phải commit doc trượt, nên transaction trả nil và báo qua cờ này.
	var missed bool
	ref := s.cardRef(uid, activityID)
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		missed = false
		snap, err := getOptional(tx, ref)
		if err != nil {
			return err
		}
		if snap.Exists() {
			card = snap.Data()
			return nil
		}
		missSnap, err := getOptional(tx, s.missRef(uid, activityID))
		if err != nil {
			return err
		}
		if missSnap.Exists() {
			missed = true
			return nil
		}
		actSnap, err := getOptional(tx, s.activityRef(uid, activityID))
		if err != nil {
			return err
		}
		if !actSnap.Exists() {
			return errRunCardNoActivity
		}
		act := actSnap.Data()
		if err := runCardEligible(act); err != nil {
			return err
		}
		fact := activityFact(activityID, act)
		if fact.StartedAt.IsZero() {
			return errRunCardNotRun
		}
		if dup, err := s.overlapsCard(tx, uid, fact); err != nil || dup {
			if err == nil {
				err = errRunCardDuplicate
			}
			return err
		}
		km := runCardKm(fact.DistanceMeters)
		if ppm := runCardChancePpm(km); chance >= ppm {
			missed = true
			return tx.Create(s.missRef(uid, activityID), map[string]any{
				"activityId": activityID, "km": km, "chancePpm": ppm, "rollPpm": chance,
				"startedAt": fact.StartedAt, "rolledAt": s.now(), "snapshot": runCardSnapshot(act),
			})
		}
		odds := runCardOdds(km)
		card = map[string]any{
			"activityId": activityID, "tier": string(runCardPick(odds, r)), "odds": runCardOddMaps(odds), "rollPpm": r,
			"km": km, "startedAt": fact.StartedAt, "rolledAt": s.now(), "snapshot": runCardSnapshot(act),
		}
		return tx.Create(ref, card)
	})
	if err != nil {
		return nil, err
	}
	if missed {
		return nil, errRunCardMissed
	}
	return runCardJSON(activityID, card), nil
}

func runCardOddMaps(odds [5]int64) []any {
	out := make([]any, len(odds))
	for i, o := range runCardOddList(odds) {
		out[i] = map[string]any{"tier": string(o.Tier), "percent": o.Percent}
	}
	return out
}

// overlapsCard là buổi fact trùng (sameRun) một buổi khác của uid đã lật, ra
// thẻ hay trượt: cùng một lần chạy ghi ở hai nguồn chỉ được lật một lần. Chỉ
// xét lượt lật bắt đầu trong vòng một ngày trước fact, vì buổi bắt đầu sớm hơn
// nữa không chạm được.
func (s *RunCardStore) overlapsCard(tx *firestore.Transaction, uid string, fact ActivityFact) (bool, error) {
	end := fact.StartedAt.Add(time.Duration(max(fact.ElapsedTimeSeconds, fact.MovingTimeSeconds, 1)) * time.Second)
	for _, coll := range []string{"runCards", "runCardMisses"} {
		q := s.db.Collection("users").Doc(uid).Collection(coll).
			Where("startedAt", ">=", fact.StartedAt.Add(-24*time.Hour)).Where("startedAt", "<", end)
		docs, err := tx.Documents(q).GetAll()
		if err != nil {
			return false, err
		}
		for _, d := range docs {
			snapshot, _ := d.Data()["snapshot"].(map[string]any)
			if d.Ref.ID != fact.ID && sameRun(fact, activityFact(d.Ref.ID, snapshot)) {
				return true, nil
			}
		}
	}
	return false, nil
}

// runCardActivityID là activityId trên path, đã chặn những tên Firestore không
// nhận làm id doc.
func runCardActivityID(r *http.Request) (string, error) {
	id := r.PathValue("activityId")
	if id == "" || len(id) > 128 || id == "." || id == ".." || (strings.HasPrefix(id, "__") && strings.HasSuffix(id, "__")) {
		return "", invalidRequest()
	}
	return id, nil
}
