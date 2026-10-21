package backend

import (
	"math"
	"time"
)

func IsSupportedActivity(a StravaActivity) bool {
	sport := a.SportType
	if sport == "" {
		sport = a.Type
	}
	return supportedSports[sport]
}
func NormalizeActivity(a StravaActivity, hydrated bool, eventTime *int64) map[string]any {
	sport := a.SportType
	if sport == "" {
		sport = a.Type
	}
	if sport == "" {
		sport = "Run"
	}
	name := a.Name
	if name == "" {
		name = "Hoat dong"
	}
	started := a.StartDate
	if parsed, err := time.Parse(time.RFC3339, started); err == nil {
		started = parsed.UTC().Format(time.RFC3339Nano)
	}
	out := map[string]any{"id": itoa64(a.ID), "name": name, "source": "strava", "sourceActivityId": itoa64(a.ID), "sportType": sport, "startedAt": started, "distanceMeters": finite(a.Distance), "movingTimeSeconds": max64(0, a.MovingTime), "elapsedTimeSeconds": max64(0, a.ElapsedTime), "schemaVersion": 1, "officialState": "official", "updatedBy": "backend"}
	if a.Manual != nil {
		out["manual"] = *a.Manual
	}
	if a.DeviceName != nil {
		out["recordingDevice"] = *a.DeviceName
	}
	putFloat(out, "averageHeartRate", a.AverageHeartRate)
	putFloat(out, "averageCadence", a.AverageCadence)
	putFloat(out, "elevationGainMeters", a.ElevationGain)
	if a.Map != nil {
		if a.Map.Polyline != nil && *a.Map.Polyline != "" {
			out["polyline"] = *a.Map.Polyline
		} else if a.Map.SummaryPolyline != nil && *a.Map.SummaryPolyline != "" {
			out["polyline"] = *a.Map.SummaryPolyline
		}
	}
	if hydrated {
		out["hydrated"] = true
		putFloat(out, "calories", a.Calories)
		if a.Gear != nil && a.Gear.Name != "" {
			out["gearName"] = a.Gear.Name
		}
		out["splits"] = normalizeIntervals(a.Splits)
		out["laps"] = normalizeIntervals(a.Laps)
	}
	if eventTime != nil {
		out["sourceEventTime"] = *eventTime
	}
	return out
}
func SummaryChanged(previous, next map[string]any) bool {
	if previous == nil {
		return true
	}
	for _, key := range []string{"name", "sportType", "startedAt", "distanceMeters", "movingTimeSeconds", "elapsedTimeSeconds", "manual", "averageHeartRate", "averageCadence", "elevationGainMeters", "officialState"} {
		if !equalScalar(previous[key], next[key]) {
			return true
		}
	}
	return false
}
func normalizeIntervals(values []map[string]any) []map[string]any {
	out := make([]map[string]any, 0, len(values))
	for _, v := range values {
		row := map[string]any{}
		for from, to := range map[string]string{"name": "name", "split": "split", "distance": "distanceMeters", "moving_time": "movingTimeSeconds", "elapsed_time": "elapsedTimeSeconds", "average_speed": "averageSpeedMetersPerSecond", "average_heartrate": "averageHeartRate"} {
			if value, ok := v[from]; ok && value != nil {
				row[to] = value
			}
		}
		out = append(out, row)
	}
	return out
}
func putFloat(target map[string]any, key string, value *float64) {
	if value != nil && !math.IsNaN(*value) && !math.IsInf(*value, 0) {
		target[key] = *value
	}
}
func finite(value float64) float64 {
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return 0
	}
	return value
}
func max64(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
func equalScalar(a, b any) bool    { return valueString(a) == valueString(b) }
func valueString(value any) string { raw, _ := jsonMarshal(value); return string(raw) }
