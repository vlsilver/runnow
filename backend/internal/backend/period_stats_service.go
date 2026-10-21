package backend

import (
	"context"
	"fmt"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// PeriodStatsService maintains users/{uid}/periodStats/{periodType}:{periodKey}
// — one document per calendar day/week/month, each fully recomputed from
// scratch (same rationale as DerivedDataService.RebuildCurrent: idempotent,
// self-correcting, no incremental counters to keep in sync). Quarter/year are
// intentionally not stored here — callers derive them by combining month
// documents (sum distance/time/count/activeDays, but MAX longestDistanceMeters
// and MIN fastestPaceSecondsPerKm — those two do not sum).
type PeriodStatsService struct{ db *firestore.Client }

func NewPeriodStatsService(db *firestore.Client) *PeriodStatsService {
	return &PeriodStatsService{db: db}
}

type periodBound struct {
	Type  string
	Key   string
	Start time.Time
	End   time.Time
}

// periodsFor returns the day/week/month bounds [instant] falls into, using
// the same Vietnam-local calendar as DerivedDataService.PeriodsAt. Week keys
// use proper ISO 8601 week-numbering (time.Time.ISOWeek), which can belong to
// a different year than the calendar date for the last/first days of a year.
func periodsFor(instant time.Time) []periodBound {
	local := instant.In(vietnam)
	day := time.Date(local.Year(), local.Month(), local.Day(), 0, 0, 0, 0, vietnam)
	daysSinceMonday := (int(day.Weekday()) + 6) % 7
	weekStart := day.AddDate(0, 0, -daysSinceMonday)
	monthStart := time.Date(local.Year(), local.Month(), 1, 0, 0, 0, 0, vietnam)
	isoYear, isoWeek := day.ISOWeek()
	return []periodBound{
		{Type: "day", Key: day.Format("2006-01-02"), Start: day, End: day.AddDate(0, 0, 1)},
		{Type: "week", Key: fmt.Sprintf("%04d-W%02d", isoYear, isoWeek), Start: weekStart, End: weekStart.AddDate(0, 0, 7)},
		{Type: "month", Key: monthStart.Format("2006-01"), Start: monthStart, End: monthStart.AddDate(0, 1, 0)},
	}
}

// saneStartedAt filters out corrupt activity timestamps (unparseable ones
// come back as the zero time; a few legacy docs carry absurd years) — the
// derived periodStart would exceed Firestore's timestamp range and the whole
// write would be rejected, so such activities are skipped instead.
func saneStartedAt(instant time.Time) bool {
	return instant.Year() >= 2000 && instant.Year() <= time.Now().Year()+1
}

// RebuildForInstant recomputes the day/week/month periodStats docs that
// [instant] falls into.
func (s *PeriodStatsService) RebuildForInstant(ctx context.Context, uid string, instant time.Time) error {
	if !saneStartedAt(instant) {
		return nil
	}
	for _, period := range periodsFor(instant) {
		if err := s.rebuildPeriod(ctx, uid, period); err != nil {
			return err
		}
	}
	return nil
}

// BackfillUser recomputes every day/week/month periodStats doc this user
// has ever had an activity in, from scratch — for one-time historical
// backfill after this feature is introduced. Loads all of the user's
// activities once and buckets them in memory (cheap at this app's scale),
// rather than issuing one Firestore query per historical period. Returns the
// number of period documents written.
func (s *PeriodStatsService) BackfillUser(ctx context.Context, uid string) (int, error) {
	iter := s.db.Collection("users").Doc(uid).Collection("activities").Documents(ctx)
	defer iter.Stop()
	facts := []ActivityFact{}
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return 0, err
		}
		facts = append(facts, activityFact(doc.Ref.ID, doc.Data()))
	}
	bounds := map[string]periodBound{}
	factsByPeriod := map[string][]ActivityFact{}
	for _, fact := range facts {
		if !saneStartedAt(fact.StartedAt) {
			continue
		}
		for _, period := range periodsFor(fact.StartedAt) {
			key := period.Type + ":" + period.Key
			bounds[key] = period
			factsByPeriod[key] = append(factsByPeriod[key], fact)
		}
	}
	for key, period := range bounds {
		official := SelectOfficialActivities(factsByPeriod[key])
		stats := StatsFor(official, Period{Start: period.Start, End: period.End})
		stats["uid"] = uid
		stats["periodType"] = period.Type
		stats["periodKey"] = period.Key
		stats["periodStart"] = period.Start
		stats["updatedAt"] = firestore.ServerTimestamp
		if _, err := s.db.Collection("users").Doc(uid).Collection("periodStats").Doc(key).Set(ctx, stats, firestore.MergeAll); err != nil {
			return len(bounds), err
		}
	}
	return len(bounds), nil
}

func (s *PeriodStatsService) rebuildPeriod(ctx context.Context, uid string, period periodBound) error {
	iter := s.db.Collection("users").Doc(uid).Collection("activities").
		Where("startedAt", ">=", period.Start.UTC().Format(time.RFC3339Nano)).
		Where("startedAt", "<", period.End.UTC().Format(time.RFC3339Nano)).
		Documents(ctx)
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
	// SelectOfficialActivities already guarantees a Strava/3i duplicate pair
	// (same real-world run recorded twice) contributes exactly once — Strava
	// wins whenever it overlaps a 3i recording by more than the threshold, so
	// StatsFor never double-counts an overlapping session.
	official := SelectOfficialActivities(facts)
	stats := StatsFor(official, Period{Start: period.Start, End: period.End})
	stats["uid"] = uid
	stats["periodType"] = period.Type
	stats["periodKey"] = period.Key
	stats["periodStart"] = period.Start
	stats["updatedAt"] = firestore.ServerTimestamp
	docID := period.Type + ":" + period.Key
	_, err := s.db.Collection("users").Doc(uid).Collection("periodStats").Doc(docID).Set(ctx, stats, firestore.MergeAll)
	return err
}
