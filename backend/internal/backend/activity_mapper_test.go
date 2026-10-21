package backend

import "testing"

func TestNormalizeActivityPreservesFlutterContract(t *testing.T) {
	heart := 151.5
	activity := StravaActivity{ID: 42, Name: "Morning Run", SportType: "Run", StartDate: "2026-07-17T00:00:00Z", Distance: 5030, MovingTime: 1800, ElapsedTime: 1900, AverageHeartRate: &heart}
	got := NormalizeActivity(activity, false, nil)
	for key, want := range map[string]any{"id": "42", "source": "strava", "sourceActivityId": "42", "sportType": "Run", "distanceMeters": float64(5030), "schemaVersion": 1, "officialState": "official", "updatedBy": "backend"} {
		if !equalScalar(got[key], want) {
			t.Fatalf("%s = %#v, want %#v", key, got[key], want)
		}
	}
	if got["hydrated"] != nil {
		t.Fatal("summary import must not claim detail hydration")
	}
}

func TestSupportedSportFilter(t *testing.T) {
	for _, sport := range []string{"Run", "TrailRun", "VirtualRun", "Walk", "Hike"} {
		if !IsSupportedActivity(StravaActivity{SportType: sport}) {
			t.Fatalf("%s should be supported", sport)
		}
	}
	if IsSupportedActivity(StravaActivity{SportType: "Ride"}) {
		t.Fatal("Ride must not be imported")
	}
}
