package backend

import "fmt"

type HTTPError struct {
	Status        int
	Code, Message string
}

func (e *HTTPError) Error() string { return e.Message }

type StravaAPIError struct {
	Status           int
	Body, RetryAfter string
}

func (e *StravaAPIError) Error() string { return fmt.Sprintf("Strava API returned %d", e.Status) }

type ConnectionRevokedError struct{ UID string }

func (e *ConnectionRevokedError) Error() string { return "Strava connection is revoked" }
