package backend

type StravaAthlete struct {
	ID        int64  `json:"id"`
	FirstName string `json:"firstname,omitempty"`
	LastName  string `json:"lastname,omitempty"`
	Profile   string `json:"profile,omitempty"`
}

type StravaTokenResponse struct {
	AccessToken  string         `json:"access_token"`
	RefreshToken string         `json:"refresh_token"`
	ExpiresAt    int64          `json:"expires_at"`
	Scope        string         `json:"scope,omitempty"`
	Athlete      *StravaAthlete `json:"athlete,omitempty"`
}

type StravaMap struct {
	Polyline        *string `json:"polyline"`
	SummaryPolyline *string `json:"summary_polyline"`
}
type StravaGear struct {
	Name string `json:"name"`
}

type StravaActivity struct {
	ID               int64            `json:"id"`
	Name             string           `json:"name"`
	SportType        string           `json:"sport_type"`
	Type             string           `json:"type"`
	StartDate        string           `json:"start_date"`
	Distance         float64          `json:"distance"`
	MovingTime       int64            `json:"moving_time"`
	ElapsedTime      int64            `json:"elapsed_time"`
	Manual           *bool            `json:"manual,omitempty"`
	DeviceName       *string          `json:"device_name,omitempty"`
	AverageHeartRate *float64         `json:"average_heartrate,omitempty"`
	AverageCadence   *float64         `json:"average_cadence,omitempty"`
	ElevationGain    *float64         `json:"total_elevation_gain,omitempty"`
	Calories         *float64         `json:"calories,omitempty"`
	Gear             *StravaGear      `json:"gear,omitempty"`
	Map              *StravaMap       `json:"map,omitempty"`
	Splits           []map[string]any `json:"splits_metric,omitempty"`
	Laps             []map[string]any `json:"laps,omitempty"`
}

type StravaWebhookEvent struct {
	ObjectType     string         `json:"object_type"`
	ObjectID       int64          `json:"object_id"`
	AspectType     string         `json:"aspect_type"`
	OwnerID        int64          `json:"owner_id"`
	SubscriptionID int64          `json:"subscription_id"`
	EventTime      int64          `json:"event_time"`
	Updates        map[string]any `json:"updates"`
}

type StravaConnection struct {
	UID          string   `firestore:"uid"`
	AthleteID    string   `firestore:"athleteId"`
	AccessToken  string   `firestore:"accessToken"`
	RefreshToken string   `firestore:"refreshToken"`
	ExpiresAt    int64    `firestore:"expiresAt"`
	Scopes       []string `firestore:"scopes"`
	Status       string   `firestore:"status"`
	TokenVersion int64    `firestore:"tokenVersion"`
}

var supportedSports = map[string]bool{"Run": true, "TrailRun": true, "VirtualRun": true, "Walk": true, "Hike": true}
