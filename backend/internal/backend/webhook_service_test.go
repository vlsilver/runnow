package backend

import "testing"

func TestEventIdentityIsStableAcrossMapOrder(t *testing.T) {
	a := StravaWebhookEvent{ObjectType: "activity", ObjectID: 1, AspectType: "update", OwnerID: 2, SubscriptionID: 3, EventTime: 4, Updates: map[string]any{"b": 2, "a": 1}}
	b := a
	b.Updates = map[string]any{"a": 1, "b": 2}
	if EventIdentity(a) != EventIdentity(b) {
		t.Fatal("equivalent events must have the same identity")
	}
}

func TestWebhookVerification(t *testing.T) {
	s := &WebhookService{verifyToken: "secret"}
	if _, err := s.Verification("subscribe", "challenge", "secret"); err != nil {
		t.Fatal(err)
	}
	if _, err := s.Verification("subscribe", "challenge", "wrong"); err == nil {
		t.Fatal("wrong token must fail")
	}
}
