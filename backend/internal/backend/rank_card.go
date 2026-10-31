package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/genai"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Thẻ BXH: 12:00 giờ VN ngày đầu kỳ mới, backend chốt top 10 của kỳ vừa hết ở
// ba bảng (Chạy·Đi bộ, Bước chân, Đạp xe), cả tuần lẫn tháng. Mỗi bảng là một
// doc rankBoards/{boardId} cùng một thẻ users/{uid}/rankCards/{boardId} cho
// từng người trong top 10, ghi chung một batch Create: bảng đã có thì cả batch
// gặp AlreadyExists, nên chạy lại hay hai task chạy cùng lúc đều không ghi đôi
// và thẻ luôn khớp bảng. Số liệu tính lại từ stepDays và activities của đúng
// kỳ, vì tới lúc chốt các doc leaderboard đã sang kỳ mới. Trễ 12 tiếng để buổi
// đồng bộ muộn của tối cuối kỳ kịp vào.
const (
	rankCloseDelay = 12 * time.Hour
	rankTopN       = 10
	// rankQuoteMaxRunes chặn câu model trả quá dài, vượt chỗ trên thẻ.
	rankQuoteMaxRunes = 110
)

type rankRange string

const (
	rankWeek  rankRange = "week"
	rankMonth rankRange = "month"
)

type rankSport string

const (
	rankRun   rankSport = "run"
	rankSteps rankSport = "steps"
	rankBike  rankSport = "bike"
)

var rankSports = []rankSport{rankRun, rankSteps, rankBike}

// closedRankPeriods là tuần và tháng gần nhất đã chốt lúc now.
func closedRankPeriods(now time.Time) (week, month Period) {
	p := PeriodsAt(now.Add(-rankCloseDelay))
	return Period{Start: p.Week.Start.AddDate(0, 0, -7), End: p.Week.Start},
		Period{Start: p.Month.Start.AddDate(0, -1, 0), End: p.Month.Start}
}

func rankBoardID(r rankRange, sport rankSport, start time.Time) string {
	return string(r) + "_" + dateKey(start) + "_" + string(sport)
}

// rankTier: tuần #1 huyền thoại, #2–3 siêu hiếm, còn lại hiếm; tháng lên một bậc.
func rankTier(r rankRange, rank int) runCardTier {
	tiers := [3]runCardTier{runCardLegendary, runCardEpic, runCardRare}
	if r == rankMonth {
		tiers = [3]runCardTier{runCardMythic, runCardLegendary, runCardEpic}
	}
	switch {
	case rank == 1:
		return tiers[0]
	case rank <= 3:
		return tiers[1]
	default:
		return tiers[2]
	}
}

// rankMember là số của một người public trong một kỳ.
type rankMember struct {
	uid, name  string
	avatar     any
	runMeters  float64
	walkMeters float64
	steps      int64
	days10k    int
	rideMeters float64
	rides      int
	longest    float64
}

func (m *rankMember) score(sport rankSport) float64 {
	switch sport {
	case rankSteps:
		return float64(m.steps)
	case rankBike:
		return m.rideMeters
	default:
		return m.runMeters + m.walkMeters
	}
}

type rankedMember struct {
	rank   int
	member *rankMember
	score  float64
}

// rankMembers xếp như app (club_ranking.dart): chỉ ai có số trong kỳ, bằng số
// thì chung hạng và người sau nhảy hạng (1, 1, 3), tên làm thứ tự phụ.
func rankMembers(members []*rankMember, sport rankSport) []rankedMember {
	out := []rankedMember{}
	for _, m := range members {
		if s := m.score(sport); s > 0 {
			out = append(out, rankedMember{member: m, score: s})
		}
	}
	sort.SliceStable(out, func(i, j int) bool {
		if out[i].score != out[j].score {
			return out[i].score > out[j].score
		}
		return out[i].member.name < out[j].member.name
	})
	for i := range out {
		if i > 0 && out[i].score == out[i-1].score {
			out[i].rank = out[i-1].rank
		} else {
			out[i].rank = i + 1
		}
	}
	return out
}

// rankQuoter viết mỗi thẻ một câu từ dòng dữ kiện của thẻ đó, trả đúng thứ tự.
type rankQuoter interface {
	Quotes(ctx context.Context, facts []string) ([]string, error)
}

type RankCardService struct {
	db *firestore.Client
	// quoter nil thì mọi thẻ dùng câu mẫu.
	quoter rankQuoter
}

func NewRankCardService(db *firestore.Client, quoter rankQuoter) *RankCardService {
	return &RankCardService{db: db, quoter: quoter}
}

// Close chốt những bảng của tuần và tháng gần nhất đã hết mà chưa có. Gọi lại
// bao nhiêu lần cũng được; bảng đã có thì chỉ tốn một lượt đọc.
func (s *RankCardService) Close(ctx context.Context, now time.Time) error {
	week, month := closedRankPeriods(now)
	if err := s.closePeriod(ctx, rankWeek, week); err != nil {
		return err
	}
	return s.closePeriod(ctx, rankMonth, month)
}

func (s *RankCardService) closePeriod(ctx context.Context, r rankRange, period Period) error {
	var missing []rankSport
	for _, sport := range rankSports {
		_, err := s.db.Collection("rankBoards").Doc(rankBoardID(r, sport, period.Start)).Get(ctx)
		if status.Code(err) == codes.NotFound {
			missing = append(missing, sport)
			continue
		}
		if err != nil {
			return err
		}
	}
	if len(missing) == 0 {
		return nil
	}
	members, err := s.periodMembers(ctx, period)
	if err != nil {
		return err
	}
	for _, sport := range missing {
		if err := s.writeBoard(ctx, r, sport, period, members); err != nil {
			return err
		}
	}
	return nil
}

// periodMembers tính số trong kỳ của mọi người đang để hồ sơ public. Chạy·Đi bộ
// tính như stepLeaderboardEntries: km chạy chính thức cộng đi bộ thuần (Apple
// đi+chạy trừ km chạy ngày đó). Đạp xe tính như leaderboardEntries.ride.
func (s *RankCardService) periodMembers(ctx context.Context, period Period) ([]*rankMember, error) {
	profiles, err := s.db.Collection("publicProfiles").Where("profileVisibility", "==", "public").Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	startKey, endKey := dateKey(period.Start), dateKey(period.End)
	members := make([]*rankMember, 0, len(profiles))
	for _, p := range profiles {
		data := p.Data()
		m := &rankMember{uid: p.Ref.ID, name: preferredName(data), avatar: nullableString(data["avatarUrl"])}
		// Lùi một ngày như officialRunMetersByDay, để khử trùng buổi vắt qua
		// nửa đêm đầu kỳ giống hệt lúc tính BXH.
		facts, err := activityFactsBetween(ctx, s.db, m.uid, period.Start.Add(-24*time.Hour), period.End)
		if err != nil {
			return nil, err
		}
		runByDay := officialMetersByDay(facts)
		for day, meters := range runByDay {
			if day >= startKey && day < endKey {
				m.runMeters += meters
			}
		}
		for _, f := range facts {
			if f.SportType != "Ride" || f.StartedAt.Before(period.Start) || !f.StartedAt.Before(period.End) {
				continue
			}
			m.rideMeters += f.DistanceMeters
			m.rides++
			if f.DistanceMeters > m.longest {
				m.longest = f.DistanceMeters
			}
		}
		if err := s.addStepDays(ctx, m, startKey, endKey, runByDay); err != nil {
			return nil, err
		}
		members = append(members, m)
	}
	return members, nil
}

func (s *RankCardService) addStepDays(ctx context.Context, m *rankMember, startKey, endKey string, runByDay map[string]float64) error {
	iter := s.db.Collection("users").Doc(m.uid).Collection("stepDays").
		Where("date", ">=", startKey).Where("date", "<", endKey).Documents(ctx)
	defer iter.Stop()
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			return nil
		}
		if err != nil {
			return err
		}
		data := doc.Data()
		steps := int64(number(data["steps"]))
		m.steps += steps
		if steps >= 10000 {
			m.days10k++
		}
		if walk := number(data["distanceMeters"]) - runByDay[stringValue(data["date"])]; walk > 0 {
			m.walkMeters += walk
		}
	}
}

func (s *RankCardService) writeBoard(ctx context.Context, r rankRange, sport rankSport, period Period, members []*rankMember) error {
	ranked := rankMembers(members, sport)
	top := ranked
	for i, rm := range ranked {
		if rm.rank > rankTopN {
			top = ranked[:i]
			break
		}
	}
	boardID := rankBoardID(r, sport, period.Start)
	quotes := s.quotes(ctx, boardID, r, sport, period, ranked, len(top))
	days := int(period.End.Sub(period.Start).Hours()/24 + 0.5)
	entries := make([]map[string]any, 0, len(top))
	b := s.db.Batch()
	for i, rm := range top {
		m := rm.member
		entries = append(entries, map[string]any{"uid": m.uid, "rank": rm.rank, "displayName": m.name, "avatarUrl": m.avatar, "score": rm.score})
		card := map[string]any{
			"boardId":      boardID,
			"range":        string(r),
			"sport":        string(sport),
			"periodStart":  dateKey(period.Start),
			"periodEnd":    dateKey(period.End),
			"rank":         rm.rank,
			"participants": len(ranked),
			"tier":         string(rankTier(r, rm.rank)),
			"score":        rm.score,
			"displayName":  m.name,
			"stats":        rankStats(m, sport, days),
			"quote":        quotes[i],
			"awardedAt":    firestore.ServerTimestamp,
			"revealedAt":   nil,
		}
		b.Create(s.db.Collection("users").Doc(m.uid).Collection("rankCards").Doc(boardID), card)
	}
	b.Create(s.db.Collection("rankBoards").Doc(boardID), map[string]any{
		"range":        string(r),
		"sport":        string(sport),
		"periodStart":  dateKey(period.Start),
		"periodEnd":    dateKey(period.End),
		"participants": len(ranked),
		"entries":      entries,
		"closedAt":     firestore.ServerTimestamp,
	})
	_, err := b.Commit(ctx)
	if status.Code(err) == codes.AlreadyExists {
		return nil
	}
	if err != nil {
		return err
	}
	slog.InfoContext(ctx, "rank_card.closed", "board", boardID, "cards", len(top), "participants", len(ranked))
	return nil
}

// rankStats là hai số phụ dưới số chính của thẻ.
func rankStats(m *rankMember, sport rankSport, days int) map[string]any {
	switch sport {
	case rankSteps:
		return map[string]any{"avgSteps": m.steps / int64(days), "days10k": m.days10k, "days": days}
	case rankBike:
		return map[string]any{"rides": m.rides, "longestMeters": m.longest}
	default:
		return map[string]any{"runMeters": m.runMeters, "walkMeters": m.walkMeters}
	}
}

// quotes trả câu cho count thẻ đầu. Model lỗi, trả thiếu hay câu quá dài thì
// thẻ đó dùng câu mẫu; thẻ vẫn ra đúng giờ, chỉ câu kém hay hơn.
func (s *RankCardService) quotes(ctx context.Context, boardID string, r rankRange, sport rankSport, period Period, ranked []rankedMember, count int) []string {
	out := make([]string, count)
	for i := range out {
		out[i] = rankTemplateQuote(r, sport, ranked, i)
	}
	if s.quoter == nil || count == 0 {
		return out
	}
	facts := make([]string, count)
	for i := range facts {
		facts[i] = rankQuoteFact(r, sport, period, ranked, i)
	}
	got, err := s.quoter.Quotes(withLLMLabel(ctx, "rank_quote", ""), facts)
	if err != nil {
		slog.WarnContext(ctx, "rank_card.quote_fallback", "board", boardID, "error", err)
		return out
	}
	for i := range out {
		if i < len(got) {
			if q := strings.TrimSpace(got[i]); q != "" && utf8.RuneCountInString(q) <= rankQuoteMaxRunes {
				out[i] = q
				continue
			}
		}
		slog.WarnContext(ctx, "rank_card.quote_fallback", "board", boardID, "index", i, "error", "missing or too long")
	}
	return out
}

func rankPeriodWord(r rankRange) string {
	if r == rankMonth {
		return "tháng"
	}
	return "tuần"
}

// rankNeighbours là người gần nhất có số cao hơn và thấp hơn ranked[i].
func rankNeighbours(ranked []rankedMember, i int) (above, below *rankedMember) {
	for j := i - 1; j >= 0; j-- {
		if ranked[j].score > ranked[i].score {
			above = &ranked[j]
			break
		}
	}
	for j := i + 1; j < len(ranked); j++ {
		if ranked[j].score < ranked[i].score {
			below = &ranked[j]
			break
		}
	}
	return above, below
}

func rankTemplateQuote(r rankRange, sport rankSport, ranked []rankedMember, i int) string {
	period := rankPeriodWord(r)
	above, below := rankNeighbours(ranked, i)
	switch {
	case above != nil:
		return fmt.Sprintf("Chỉ còn %s nữa là lên hạng %d.", rankValueLabel(above.score-ranked[i].score, sport), above.rank)
	case below != nil:
		return fmt.Sprintf("Dẫn đầu cả %s, hơn hạng %d tới %s.", period, below.rank, rankValueLabel(ranked[i].score-below.score, sport))
	default:
		return fmt.Sprintf("Dẫn đầu cả %s.", period)
	}
}

// rankQuoteFact là dòng dữ kiện gửi model: chỉ số, không tên, để tên người dùng
// tự đặt không thành lời nhắn tới model.
func rankQuoteFact(r rankRange, sport rankSport, period Period, ranked []rankedMember, i int) string {
	rm := ranked[i]
	m := rm.member
	parts := []string{
		fmt.Sprintf("BXH %s %s–%s", rankPeriodWord(r), period.Start.In(vietnam).Format("02/01"), period.End.Add(-time.Hour).In(vietnam).Format("02/01")),
		fmt.Sprintf("hạng %d trên %d người", rm.rank, len(ranked)),
	}
	switch sport {
	case rankSteps:
		parts = append(parts, "bảng Bước chân", "tổng "+rankValueLabel(rm.score, sport), fmt.Sprintf("%d ngày từ 10.000 bước", m.days10k))
	case rankBike:
		parts = append(parts, "bảng Đạp xe", "tổng "+rankValueLabel(rm.score, sport), fmt.Sprintf("%d buổi", m.rides), "buổi dài nhất "+rankValueLabel(m.longest, sport))
	default:
		parts = append(parts, "bảng Chạy và Đi bộ", "tổng "+rankValueLabel(rm.score, sport), "chạy "+rankValueLabel(m.runMeters, sport), "đi bộ "+rankValueLabel(m.walkMeters, sport))
	}
	above, below := rankNeighbours(ranked, i)
	if above != nil {
		parts = append(parts, fmt.Sprintf("kém hạng %d %s", above.rank, rankValueLabel(above.score-rm.score, sport)))
	}
	if below != nil {
		parts = append(parts, fmt.Sprintf("hơn hạng %d %s", below.rank, rankValueLabel(rm.score-below.score, sport)))
	}
	return strings.Join(parts, "; ")
}

// rankValueLabel viết số kiểu Việt: "4,5 km", "12.400 bước".
func rankValueLabel(value float64, sport rankSport) string {
	if sport == rankSteps {
		return groupThousands(int64(value+0.5)) + " bước"
	}
	return strings.Replace(strconv.FormatFloat(value/1000, 'f', 1, 64), ".", ",", 1) + " km"
}

func groupThousands(n int64) string {
	raw := strconv.FormatInt(n, 10)
	var b strings.Builder
	for i, c := range raw {
		if i > 0 && (len(raw)-i)%3 == 0 {
			b.WriteByte('.')
		}
		b.WriteRune(c)
	}
	return b.String()
}

const rankQuotePrompt = `Bạn viết câu ngắn in trên thẻ thành tích bảng xếp hạng của một nhóm chạy bộ.
Đầu vào: mỗi dòng là dữ kiện của một thẻ, đánh số từ 1.
Trả mảng JSON, mỗi dòng đúng một câu tiếng Việt, cùng thứ tự, tối đa 90 ký tự.
Chỉ dùng số có trong dòng của thẻ đó, không bịa thêm số, tên hay chuyện. Giọng vui, khen thật lòng, không mỉa mai.
Không gọi tên người, không dùng ngoặc kép.`

type genaiRankQuoter struct {
	client *genai.Client
	model  string
}

func (g genaiRankQuoter) Quotes(ctx context.Context, facts []string) ([]string, error) {
	var input strings.Builder
	for i, f := range facts {
		fmt.Fprintf(&input, "%d. %s\n", i+1, f)
	}
	cfg := &genai.GenerateContentConfig{
		SystemInstruction: &genai.Content{Parts: []*genai.Part{{Text: rankQuotePrompt}}},
		ResponseMIMEType:  "application/json",
		ResponseSchema:    &genai.Schema{Type: genai.TypeArray, Items: &genai.Schema{Type: genai.TypeString}},
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	started := time.Now()
	resp, err := g.client.Models.GenerateContent(ctx, g.model, []*genai.Content{{Role: genai.RoleUser, Parts: []*genai.Part{{Text: input.String()}}}}, cfg)
	if err != nil {
		return nil, err
	}
	logLLMUsage(ctx, llmLabelOf(ctx), g.model, resp, started, 0)
	var out []string
	if err := json.Unmarshal([]byte(resp.Text()), &out); err != nil {
		return nil, fmt.Errorf("rank quote: %w", err)
	}
	if len(out) != len(facts) {
		return nil, errors.New("rank quote: số câu không khớp số thẻ")
	}
	return out, nil
}

// rankCloseTaskFor là task chốt của kỳ gần nhất đã hết. schedule-tick hẹn mỗi
// 10 phút; TaskID theo kỳ nên Cloud Tasks gộp các lần hẹn trùng, còn lần chạy
// lại sau đó chỉ đọc thấy bảng đã có rồi thôi.
func rankCloseTaskFor(now time.Time) PublishTask {
	week, month := closedRankPeriods(now)
	identity := []string{dateKey(week.Start), dateKey(month.Start)}
	return PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/rank-close", Payload: map[string]any{"week": identity[0], "month": identity[1]}, TaskID: StableTaskID("rank-close", identity)}
}

func (s *Server) enqueueRankClose(ctx context.Context, now time.Time) error {
	publish := s.enqueueTask()
	if publish == nil {
		return errors.New("rank-close: chưa cấu hình Cloud Tasks")
	}
	_, err := publish(ctx, rankCloseTaskFor(now))
	return err
}

// rankClose chốt theo giờ lúc chạy chứ không theo payload: task trễ qua kỳ sau
// thì chốt luôn kỳ mới, kỳ cũ đã có từ lần trước.
func (s *Server) rankClose(w http.ResponseWriter, r *http.Request) error {
	if s.deps.RankCards == nil {
		w.WriteHeader(http.StatusNoContent)
		return nil
	}
	if err := s.deps.RankCards.Close(r.Context(), s.now()); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}
