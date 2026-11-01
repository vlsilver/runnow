//go:build emulator

package backend

import (
	"context"
	"sync"
	"testing"
	"time"
)

// seedContract ghi một kèo đã chốt; participants là uid → progressValue.
func seedContract(t *testing.T, h *apiHarness, id string, extra map[string]any, participants map[string]float64) {
	t.Helper()
	parts := map[string]any{}
	for uid, progress := range participants {
		parts[uid] = map[string]any{"uid": uid, "progressValue": progress}
	}
	m := map[string]any{
		"title": "Tuần 30 km", "metric": "distance", "targetValue": 30.0, "periodType": "weekly",
		"startAt":        time.Date(2026, 10, 18, 17, 0, 0, 0, time.UTC),
		"endAtExclusive": time.Date(2026, 10, 25, 17, 0, 0, 0, time.UTC),
		"status":         "completed", "visibility": "club", "creatorUid": "u1",
		"participants": parts,
	}
	for k, v := range extra {
		m[k] = v
	}
	seed(t, h.store.db, "runContracts/"+id, m)
}

func TestEmulatorContractCardRollOnceAndKeep(t *testing.T) {
	// u1 tích được 23,5 km: cùng bảng tỉ lệ thẻ buổi chạy 23,5 km, số quay
	// 820000 rơi vào bậc huyền thoại (815000..954999).
	h := runCardHarness(t, 820000, 10000, 0)
	seed(t, h.store.db, "publicProfiles/u1", map[string]any{"displayName": "An"})
	seedContract(t, h, "k1", map[string]any{"targetValue": 20.0}, map[string]float64{"u1": 23.5, "u2": 25, "u3": 4})

	r := h.call("u1", "GET", "/v1/contracts/k1/card", nil, "")
	h.want(r, 200, "")
	if r.body["card"] != nil || r.body["km"] != 23.5 {
		t.Fatalf("chưa lật: %s", r.raw)
	}
	if o := r.body["odds"].([]any)[1].(map[string]any); o["tier"] != "rare" || o["percent"] != 50.5 {
		t.Fatalf("tỉ lệ hiếm = %v, muốn 50.5", o)
	}

	r = h.call("u1", "POST", "/v1/contracts/k1/card", nil, "")
	h.want(r, 200, "")
	card := r.body["card"].(map[string]any)
	if card["tier"] != "legendary" || card["km"] != 23.5 || card["rollPpm"] != 820000.0 || card["contractId"] != "k1" {
		t.Fatalf("thẻ = %v", card)
	}
	snap := card["snapshot"].(map[string]any)
	want := map[string]any{
		"title": "Tuần 30 km", "metric": "distance", "targetValue": 20.0, "progressValue": 23.5,
		"periodType": "weekly", "startAt": "2026-10-18T17:00:00Z", "endAtExclusive": "2026-10-25T17:00:00Z",
		"participants": 3.0, "achievers": 2.0, "displayName": "An",
	}
	for k, v := range want {
		if snap[k] != v {
			t.Fatalf("snapshot[%s] = %v, muốn %v (%v)", k, snap[k], v, snap)
		}
	}

	r = h.call("u1", "POST", "/v1/contracts/k1/card", nil, "")
	h.want(r, 200, "")
	if r.body["card"].(map[string]any)["tier"] != "legendary" {
		t.Fatalf("lật lại phải trả thẻ cũ: %s", r.raw)
	}
}

func TestEmulatorContractCardConcurrentRollsGiveOneCard(t *testing.T) {
	// Số quay 0 ra hiếm, 999999 ra thần thoại: hai request cùng lúc phải trả
	// cùng một thẻ, không thẻ nào bị ghi đè.
	h := runCardHarness(t, 0, 999999)
	seedContract(t, h, "k1", nil, map[string]float64{"u1": 31})
	h.token("u1")
	var wg sync.WaitGroup
	tiers := make([]any, 2)
	for i := range tiers {
		wg.Add(1)
		go func() {
			defer wg.Done()
			r := h.call("u1", "POST", "/v1/contracts/k1/card", nil, "")
			if r.status == 200 {
				tiers[i] = r.body["card"].(map[string]any)["tier"]
			}
		}()
	}
	wg.Wait()
	if tiers[0] == nil || tiers[0] != tiers[1] {
		t.Fatalf("hai lần lật cùng lúc ra %v", tiers)
	}
	snap, err := h.store.db.Doc("users/u1/contractCards/k1").Get(context.Background())
	if err != nil || snap.Data()["tier"] != tiers[0] {
		t.Fatalf("doc thẻ = %v (%v), muốn %v", snap.Data(), err, tiers[0])
	}
}

func TestEmulatorContractCardKmFromCountedRuns(t *testing.T) {
	// Kèo 3 buổi: km tích luỹ là tổng các buổi đã tính vào kèo, 23,5 + 4,2 + 6,0
	// = 33,7 km; buổi a9 không tính vào kèo thì không cộng.
	h := runCardHarness(t, 0)
	seedRun(t, h, "u1", "a1", nil)
	seedRun(t, h, "u1", "a2", map[string]any{"distanceMeters": 4200.0})
	seedRun(t, h, "u1", "a3", map[string]any{"distanceMeters": 6000.0})
	seedRun(t, h, "u1", "a9", map[string]any{"distanceMeters": 50000.0})
	seedContract(t, h, "k3", map[string]any{"metric": "activity_count", "targetValue": 3.0, "participants": map[string]any{"u1": map[string]any{
		"uid": "u1", "progressValue": 3.0, "countedActivityIds": []any{"a1", "a2", "a3", "gone"},
	}}}, nil)

	r := h.call("u1", "GET", "/v1/contracts/k3/card", nil, "")
	h.want(r, 200, "")
	if r.body["km"] != 33.7 {
		t.Fatalf("km = %v, muốn 33.7", r.body["km"])
	}
	r = h.call("u1", "POST", "/v1/contracts/k3/card", nil, "")
	h.want(r, 200, "")
	if card := r.body["card"].(map[string]any); card["km"] != 33.7 {
		t.Fatalf("thẻ = %s", r.raw)
	}
}

func TestEmulatorContractCardOnlyWhenOwnTargetMet(t *testing.T) {
	h := runCardHarness(t, 0)
	seedContract(t, h, "open", map[string]any{"status": "active"}, map[string]float64{"u1": 40})
	seedContract(t, h, "cancel", map[string]any{"status": "cancelled"}, map[string]float64{"u1": 40})
	// Chủ kèo hụt nên kèo trượt, nhưng u2 tự đạt 30 km thì vẫn lật được.
	seedContract(t, h, "fail", map[string]any{"status": "failed"}, map[string]float64{"u1": 12, "u2": 30})

	for _, c := range []struct {
		uid, id, code string
		status        int
	}{
		{"u1", "open", "card_contract_open", 409},
		{"u1", "cancel", "card_contract_cancelled", 409},
		{"u1", "fail", "card_contract_failed", 409},
		{"u9", "fail", "contract_not_found", 404},
		{"u1", "none", "contract_not_found", 404},
	} {
		r := h.call(c.uid, "POST", "/v1/contracts/"+c.id+"/card", nil, "")
		h.want(r, c.status, c.code)
		r = h.call(c.uid, "GET", "/v1/contracts/"+c.id+"/card", nil, "")
		if c.status == 404 {
			h.want(r, 404, c.code)
		} else if h.want(r, 200, ""); r.body["reason"] != c.code || r.body["odds"] != nil {
			t.Fatalf("GET %s của %s: %s", c.id, c.uid, r.raw)
		}
	}

	// Từ 30 km bảng tỉ lệ không còn bậc thường, số quay 0 rơi vào bậc hiếm.
	r := h.call("u2", "POST", "/v1/contracts/fail/card", nil, "")
	h.want(r, 200, "")
	if card := r.body["card"].(map[string]any); card["tier"] != "rare" || card["km"] != 30.0 {
		t.Fatalf("thẻ u2 = %s", r.raw)
	}
}
