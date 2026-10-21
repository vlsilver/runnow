package backend

import (
	"context"
	"errors"
	"time"

	"cloud.google.com/go/firestore"
)

type TokenStore struct {
	db      *firestore.Client
	gateway *StravaGateway
	now     func() time.Time
}

func NewTokenStore(db *firestore.Client, g *StravaGateway) *TokenStore {
	return &TokenStore{db: db, gateway: g, now: time.Now}
}

func (s *TokenStore) Connection(ctx context.Context, uid string) (StravaConnection, error) {
	snap, err := s.db.Collection("stravaConnections").Doc(uid).Get(ctx)
	if err != nil {
		return StravaConnection{}, err
	}
	var c StravaConnection
	if err = snap.DataTo(&c); err != nil {
		return c, err
	}
	if c.Status == "revoked" {
		return c, &ConnectionRevokedError{UID: uid}
	}
	return c, nil
}
func (s *TokenStore) WithAccessToken(ctx context.Context, uid string, operation func(string) error) error {
	c, err := s.validConnection(ctx, uid)
	if err != nil {
		return err
	}
	if err = operation(c.AccessToken); err == nil {
		return nil
	}
	var api *StravaAPIError
	if !errors.As(err, &api) || api.Status != 401 {
		return err
	}
	c, err = s.refresh(ctx, c, true)
	if err != nil {
		return err
	}
	return operation(c.AccessToken)
}
func (s *TokenStore) validConnection(ctx context.Context, uid string) (StravaConnection, error) {
	c, err := s.Connection(ctx, uid)
	if err != nil {
		return c, err
	}
	if c.ExpiresAt > s.now().Unix()+3600 {
		return c, nil
	}
	return s.refresh(ctx, c, false)
}
func (s *TokenStore) refresh(ctx context.Context, original StravaConnection, force bool) (StravaConnection, error) {
	if !force && original.ExpiresAt > s.now().Unix()+3600 {
		return original, nil
	}
	fresh, err := s.gateway.RefreshToken(ctx, original.RefreshToken)
	if err != nil {
		var api *StravaAPIError
		if errors.As(err, &api) && api.Status >= 400 && api.Status < 500 {
			winner, werr := s.Connection(ctx, original.UID)
			if werr == nil && winner.TokenVersion != original.TokenVersion {
				return winner, nil
			}
			if markErr := s.markRevoked(ctx, original.UID, "refresh_"+itoa(api.Status)); markErr != nil {
				return original, markErr
			}
			return original, &ConnectionRevokedError{UID: original.UID}
		}
		return original, err
	}
	ref := s.db.Collection("stravaConnections").Doc(original.UID)
	var result StravaConnection
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := tx.Get(ref)
		if err != nil {
			return err
		}
		var current StravaConnection
		if err = snap.DataTo(&current); err != nil {
			return err
		}
		if current.TokenVersion != original.TokenVersion {
			result = current
			return nil
		}
		result = current
		result.AccessToken = fresh.AccessToken
		result.RefreshToken = fresh.RefreshToken
		result.ExpiresAt = fresh.ExpiresAt
		result.TokenVersion++
		return tx.Set(ref, map[string]any{"accessToken": fresh.AccessToken, "refreshToken": fresh.RefreshToken, "expiresAt": fresh.ExpiresAt, "tokenVersion": result.TokenVersion, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	})
	return result, err
}
func (s *TokenStore) markRevoked(ctx context.Context, uid, reason string) error {
	b := s.db.Batch()
	b.Set(s.db.Collection("stravaConnections").Doc(uid), map[string]any{"status": "revoked", "accessToken": firestore.Delete, "refreshToken": firestore.Delete, "lastErrorCode": reason, "revokedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	b.Set(s.db.Collection("users").Doc(uid), map[string]any{"stravaConnected": false, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	b.Set(s.db.Collection("publicProfiles").Doc(uid), map[string]any{"stravaConnected": false, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	_, err := b.Commit(ctx)
	return err
}
func itoa(value int) string {
	const digits = "0123456789"
	if value == 0 {
		return "0"
	}
	var b [20]byte
	i := len(b)
	for value > 0 {
		i--
		b[i] = digits[value%10]
		value /= 10
	}
	return string(b[i:])
}
