package backend

import (
	"context"
	"encoding/json"
	"math"
	"sort"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type ActivityFact struct {
	ID, Source, SportType                 string
	StartedAt                             time.Time
	DistanceMeters, ElevationGainMeters   float64
	MovingTimeSeconds, ElapsedTimeSeconds int64
}
type Period struct{ Start, End time.Time }
type CurrentPeriods struct{ Rolling, Week, Month Period }
type DerivedDataService struct{ db *firestore.Client }

func NewDerivedDataService(db *firestore.Client) *DerivedDataService {
	return &DerivedDataService{db: db}
}

func (s *DerivedDataService) RebuildCurrent(ctx context.Context, uid string, now time.Time) error {
	periods := PeriodsAt(now)
	queryStart := earliest(periods.Rolling.Start, periods.Week.Start, periods.Month.Start).Add(-24 * time.Hour)
	queryEnd := latest(periods.Rolling.End, periods.Week.End, periods.Month.End)
	iter := s.db.Collection("users").Doc(uid).Collection("activities").Where("startedAt", ">=", queryStart.UTC().Format(time.RFC3339Nano)).Where("startedAt", "<", queryEnd.UTC().Format(time.RFC3339Nano)).OrderBy("startedAt", firestore.Desc).Documents(ctx)
	defer iter.Stop()
	facts := []ActivityFact{}
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return err
		}
		facts = append(facts, activityFact(doc.Ref.ID, doc.Data()))
	}
	official := SelectOfficialActivities(facts)
	leaderRef := s.db.Collection("leaderboardEntries").Doc(uid)
	statsRef := s.db.Collection("users").Doc(uid).Collection("stats").Doc("current")
	profile, err := resolveProfile(ctx, s.db, uid)
	if err != nil {
		return err
	}
	displayName := preferredName(profile)
	payload := map[string]any{"uid": uid, "displayName": displayName, "nickname": displayName, "profileVisibility": defaultString(profile["profileVisibility"], "private"), "avatarUrl": nullableString(profile["avatarUrl"]), "rollingSevenDays": StatsFor(official, periods.Rolling), "currentWeek": StatsFor(official, periods.Week), "currentMonth": StatsFor(official, periods.Month), "currentWeekStart": dateKey(periods.Week.Start), "currentMonthStart": dateKey(periods.Month.Start)}
	currentLeader, err := getData(ctx, leaderRef)
	if err != nil {
		return err
	}
	currentStats, err := getData(ctx, statsRef)
	if err != nil {
		return err
	}
	leaderChanged := payloadChanged(currentLeader, payload)
	statsChanged := payloadChanged(currentStats, payload)
	if !leaderChanged && !statsChanged {
		return nil
	}
	shared := cloneMap(payload)
	shared["sourceRevision"] = firestore.Increment(1)
	shared["updatedAt"] = firestore.ServerTimestamp
	b := s.db.Batch()
	if leaderChanged {
		b.Set(leaderRef, shared, firestore.MergeAll)
	}
	if statsChanged {
		b.Set(statsRef, shared, firestore.MergeAll)
	}
	_, err = b.Commit(ctx)
	return err
}

func activityFact(id string, data map[string]any) ActivityFact {
	started, _ := time.Parse(time.RFC3339, stringValue(data["startedAt"]))
	return ActivityFact{ID: id, Source: defaultString(data["source"], "strava"), SportType: defaultString(data["sportType"], "Run"), StartedAt: started, DistanceMeters: number(data["distanceMeters"]), ElevationGainMeters: number(data["elevationGainMeters"]), MovingTimeSeconds: int64(number(data["movingTimeSeconds"])), ElapsedTimeSeconds: int64(number(data["elapsedTimeSeconds"]))}
}
// runSportTypes are the pure-running sport types. Now used only where "a run"
// specifically is meant (the bot's run-analysis tool). Leaderboard counting
// uses leaderboardSportTypes; the Telegram alert uses notifySportTypes — three
// deliberately distinct sets so a change to one never silently moves the others.
var runSportTypes = map[string]bool{"Run": true, "TrailRun": true, "VirtualRun": true}

// leaderboardSportTypes are the Strava sport types that COUNT toward the
// leaderboard / stats: running and walking. Cycling is announced to the group
// (see notifySportTypes) but deliberately NOT counted here — a distance
// leaderboard mixing bikes would be meaningless for a run/walk club.
var leaderboardSportTypes = map[string]bool{
	"Run": true, "TrailRun": true, "VirtualRun": true,
	"Walk": true, "Hike": true,
}

// resolveProfile merges `users/{uid}` with `publicProfiles/{uid}` the same
// way RebuildCurrent has always derived a leaderboard entry's display
// name/avatar — reused by the Telegram notify handler so both paths agree
// on "who is this activity from".
func resolveProfile(ctx context.Context, db *firestore.Client, uid string) (map[string]any, error) {
	user, err := getData(ctx, db.Collection("users").Doc(uid))
	if err != nil {
		return nil, err
	}
	public, err := getData(ctx, db.Collection("publicProfiles").Doc(uid))
	if err != nil {
		return nil, err
	}
	profile := map[string]any{}
	for k, v := range user {
		profile[k] = v
	}
	for k, v := range public {
		profile[k] = v
	}
	return profile, nil
}

func SelectOfficialActivities(activities []ActivityFact) []ActivityFact {
	// Strava activities that count (run + walk). Also the pool a 3i-tracked
	// activity is de-duplicated against.
	counted := []ActivityFact{}
	for _, a := range activities {
		if a.Source == "strava" && leaderboardSportTypes[a.SportType] {
			counted = append(counted, a)
		}
	}
	out := []ActivityFact{}
	for _, a := range activities {
		if a.Source == "strava" {
			// Only run/walk count toward the leaderboard; cycling (and any
			// other Strava sport) is excluded here even though it still gets
			// announced to the group.
			if leaderboardSportTypes[a.SportType] {
				out = append(out, a)
			}
			continue
		}
		if a.SportType != "Run" || a.DistanceMeters < 500 {
			continue
		}
		duplicate := false
		for _, other := range counted {
			if overlapRatio(a, other) > 0.3 {
				duplicate = true
				break
			}
		}
		if !duplicate {
			out = append(out, a)
		}
	}
	return out
}
func overlapRatio(candidate, other ActivityFact) float64 {
	duration := time.Duration(max64(candidate.ElapsedTimeSeconds, max64(candidate.MovingTimeSeconds, 1))) * time.Second
	otherDuration := time.Duration(max64(other.ElapsedTimeSeconds, max64(other.MovingTimeSeconds, 1))) * time.Second
	start := candidate.StartedAt
	if other.StartedAt.After(start) {
		start = other.StartedAt
	}
	end := candidate.StartedAt.Add(duration)
	if otherEnd := other.StartedAt.Add(otherDuration); otherEnd.Before(end) {
		end = otherEnd
	}
	if !end.After(start) {
		return 0
	}
	return float64(end.Sub(start)) / float64(duration)
}
func StatsFor(activities []ActivityFact, period Period) map[string]any {
	distance := float64(0)
	elevation := float64(0)
	moving := int64(0)
	count := int64(0)
	longest := float64(0)
	fastest := math.Inf(1)
	days := map[string]bool{}
	for _, a := range activities {
		if a.StartedAt.Before(period.Start) || !a.StartedAt.Before(period.End) {
			continue
		}
		distance += a.DistanceMeters
		elevation += a.ElevationGainMeters
		moving += a.MovingTimeSeconds
		count++
		longest = math.Max(longest, a.DistanceMeters)
		days[dateKey(a.StartedAt)] = true
		if a.DistanceMeters > 0 {
			pace := float64(a.MovingTimeSeconds) / (a.DistanceMeters / 1000)
			if pace > 0 && pace < fastest {
				fastest = pace
			}
		}
	}
	out := map[string]any{"distanceMeters": distance, "elevationGainMeters": elevation, "movingTimeSeconds": moving, "activityCount": count, "activeDays": int64(len(days)), "longestDistanceMeters": longest}
	if !math.IsInf(fastest, 1) {
		out["fastestPaceSecondsPerKm"] = fastest
	}
	return out
}

var vietnam = time.FixedZone("Asia/Ho_Chi_Minh", 7*60*60)

func PeriodsAt(now time.Time) CurrentPeriods {
	local := now.In(vietnam)
	today := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, vietnam)
	tomorrow := today.AddDate(0, 0, 1)
	daysSinceMonday := (int(today.Weekday()) + 6) % 7
	week := today.AddDate(0, 0, -daysSinceMonday)
	month := time.Date(local.Year(), local.Month(), 1, 0, 0, 0, 0, vietnam)
	return CurrentPeriods{Rolling: Period{Start: tomorrow.AddDate(0, 0, -7), End: tomorrow}, Week: Period{Start: week, End: week.AddDate(0, 0, 7)}, Month: Period{Start: month, End: month.AddDate(0, 1, 0)}}
}
func dateKey(value time.Time) string { return value.In(vietnam).Format("2006-01-02") }
func earliest(values ...time.Time) time.Time {
	sort.Slice(values, func(i, j int) bool { return values[i].Before(values[j]) })
	return values[0]
}
func latest(values ...time.Time) time.Time {
	sort.Slice(values, func(i, j int) bool { return values[i].After(values[j]) })
	return values[0]
}
func preferredName(profile map[string]any) string {
	if v := stringValue(profile["nickname"]); v != "" {
		return v
	}
	if v := stringValue(profile["displayName"]); v != "" {
		return v
	}
	return "3i member"
}
func defaultString(v any, fallback string) string {
	if value := stringValue(v); value != "" {
		return value
	}
	return fallback
}
func nullableString(v any) any {
	if value := stringValue(v); value != "" {
		return value
	}
	return nil
}
func getData(ctx context.Context, ref *firestore.DocumentRef) (map[string]any, error) {
	snap, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return snap.Data(), nil
}
func cloneMap(value map[string]any) map[string]any {
	out := map[string]any{}
	for k, v := range value {
		out[k] = v
	}
	return out
}
func payloadChanged(previous, next map[string]any) bool {
	if previous == nil {
		return true
	}
	project := map[string]any{}
	for k := range next {
		project[k] = previous[k]
	}
	a, _ := json.Marshal(project)
	b, _ := json.Marshal(next)
	return string(a) != string(b)
}
