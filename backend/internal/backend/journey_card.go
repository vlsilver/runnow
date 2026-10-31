package backend

import (
	"context"
	"fmt"
	"log/slog"
	"sort"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Thẻ Hành trình: về đích một chặng thì có thẻ ở
// users/{uid}/journeyCards/{campaign}, ghi một lần rồi giữ nguyên. Bậc cố định
// theo chặng, không bốc. Mốc về đích tính y như app (journey_timeline.dart):
// tổng km trọn đời là tổng distanceMeters các doc periodStats tháng; chặng sau
// bắt đầu ở tổng độ dài cung đầu của các chặng trước, còn mốc về đích cộng độ
// dài cung người chơi chọn.
type JourneyCardService struct{ db *firestore.Client }

func NewJourneyCardService(db *firestore.Client) *JourneyCardService {
	return &JourneyCardService{db: db}
}

type journeyCampaign struct {
	ID string
	// Routes là các cung của chặng; cung đầu là cung mặc định và là cung tính
	// offset cho chặng sau.
	Routes []string
	Tier   runCardTier
}

// journeyCampaigns theo đúng thứ tự journeyCampaignOrder của app.
var journeyCampaigns = []journeyCampaign{
	{ID: "marathon", Routes: []string{"athens_marathon"}, Tier: runCardRare},
	{ID: "mont_blanc", Routes: []string{"tour_du_mont_blanc"}, Tier: runCardEpic},
	{ID: "xuyen_viet", Routes: []string{"coastal", "hcm_trail"}, Tier: runCardLegendary},
	{ID: "dong_nam_a", Routes: []string{"dong_nam_a"}, Tier: runCardMythic},
}

type journeyLeg struct {
	campaign journeyCampaign
	level    int
	route    string
	// from, to là tổng km trọn đời (mét) lúc vào chặng và lúc về đích.
	from, to float64
}

// AwardFinished ghi thẻ cho mọi chặng đã về đích mà chưa có thẻ, trả số thẻ
// mới. Chạy lại bao nhiêu lần cũng được: thẻ đã có thì bỏ qua, hai task chạy
// cùng lúc thì Create của task sau gặp AlreadyExists.
func (s *JourneyCardService) AwardFinished(ctx context.Context, uid string) (int, error) {
	user := s.db.Collection("users").Doc(uid)
	owned, err := user.Collection("journeyCards").Documents(ctx).GetAll()
	if err != nil {
		return 0, err
	}
	have := map[string]bool{}
	for _, doc := range owned {
		have[doc.Ref.ID] = true
	}
	if len(have) >= len(journeyCampaigns) {
		return 0, nil
	}
	legs, err := s.legs(ctx, user)
	if err != nil {
		return 0, err
	}
	months, err := user.Collection("periodStats").Where("periodType", "==", "month").Documents(ctx).GetAll()
	if err != nil {
		return 0, err
	}
	lifetime := 0.0
	for _, doc := range months {
		lifetime += number(doc.Data()["distanceMeters"])
	}
	var due []journeyLeg
	for _, leg := range legs {
		if !have[leg.campaign.ID] && lifetime >= leg.to {
			due = append(due, leg)
		}
	}
	if len(due) == 0 {
		return 0, nil
	}
	official, err := s.officialActivities(ctx, user)
	if err != nil {
		return 0, err
	}
	awarded := 0
	for _, leg := range due {
		finishedAt, runs := legRuns(official, leg.from, leg.to)
		if finishedAt.IsZero() {
			// periodStats đã qua mốc mà activities chưa tới: chỉ lệch khi dedup
			// cắt ngang ranh giới tháng, nên lấy lúc trao làm lúc về đích.
			finishedAt = time.Now()
		}
		_, err := user.Collection("journeyCards").Doc(leg.campaign.ID).Create(ctx, map[string]any{
			"campaign":       leg.campaign.ID,
			"routeId":        leg.route,
			"level":          leg.level,
			"tier":           string(leg.campaign.Tier),
			"distanceMeters": leg.to - leg.from,
			"runCount":       runs,
			"finishedAt":     finishedAt,
			"awardedAt":      firestore.ServerTimestamp,
		})
		if status.Code(err) == codes.AlreadyExists {
			continue
		}
		if err != nil {
			return awarded, err
		}
		awarded++
		slog.InfoContext(ctx, "journey_card.awarded", "uid", uid, "campaign", leg.campaign.ID, "route", leg.route, "runs", runs)
	}
	return awarded, nil
}

// legs dựng mốc vào và về đích của từng chặng từ độ dài route trên Firestore.
// Thiếu route thì trả lỗi chứ không đoán mốc.
func (s *JourneyCardService) legs(ctx context.Context, user *firestore.DocumentRef) ([]journeyLeg, error) {
	profile, err := getData(ctx, user)
	if err != nil {
		return nil, err
	}
	chosen := stringValue(profile["journeyRouteId"])
	routes := s.db.Collection("journeyRoutes")
	var refs []*firestore.DocumentRef
	for _, c := range journeyCampaigns {
		for _, id := range c.Routes {
			refs = append(refs, routes.Doc(id))
		}
	}
	snaps, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return nil, err
	}
	length := map[string]float64{}
	for _, snap := range snaps {
		if !snap.Exists() {
			return nil, fmt.Errorf("journey card: thiếu journeyRoutes/%s", snap.Ref.ID)
		}
		length[snap.Ref.ID] = number(snap.Data()["totalLengthMeters"])
	}
	var legs []journeyLeg
	offset := 0.0
	for i, c := range journeyCampaigns {
		route := c.Routes[0]
		for _, id := range c.Routes {
			if id == chosen {
				route = id
			}
		}
		legs = append(legs, journeyLeg{campaign: c, level: i + 1, route: route, from: offset, to: offset + length[route]})
		offset += length[c.Routes[0]]
	}
	return legs, nil
}

// officialActivities là các buổi được tính km (cùng bộ lọc với periodStats),
// xếp theo giờ bắt đầu.
func (s *JourneyCardService) officialActivities(ctx context.Context, user *firestore.DocumentRef) ([]ActivityFact, error) {
	docs, err := user.Collection("activities").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	var facts []ActivityFact
	for _, doc := range docs {
		if fact := activityFact(doc.Ref.ID, doc.Data()); saneStartedAt(fact.StartedAt) {
			facts = append(facts, fact)
		}
	}
	official := SelectOfficialActivities(facts)
	sort.SliceStable(official, func(i, j int) bool {
		if !official[i].StartedAt.Equal(official[j].StartedAt) {
			return official[i].StartedAt.Before(official[j].StartedAt)
		}
		return official[i].ID < official[j].ID
	})
	return official, nil
}

// legRuns cộng dồn km theo thứ tự thời gian: buổi về đích là buổi đưa tổng
// lên tới mốc [to], số buổi của chặng là các buổi có km rơi vào (from, to]
// (buổi chạy vắt qua mốc vào chặng tính cho cả hai chặng). Chưa tới mốc thì
// buổi về đích là buổi cuối đã tính.
func legRuns(official []ActivityFact, from, to float64) (time.Time, int) {
	var finishedAt time.Time
	runs := 0
	total := 0.0
	for _, a := range official {
		if a.DistanceMeters <= 0 {
			continue
		}
		total += a.DistanceMeters
		if total <= from {
			continue
		}
		runs++
		finishedAt = a.StartedAt
		if total >= to {
			break
		}
	}
	return finishedAt, runs
}
