package backend

import (
	"context"
	"net/http"
	"time"

	"cloud.google.com/go/firestore"
)

// Thẻ Kèo: kèo đã chốt mà người tham gia đạt mục tiêu của chính mình thì người
// đó lật được một thẻ. Bậc quay trên server bằng bảng tỉ lệ của thẻ buổi chạy,
// theo số km tích luỹ trong kèo, nên tích càng nhiều thì bậc cao càng dễ ra.
// Không có lượt trượt như buổi ngắn: đạt kèo là chắc có thẻ. Lật rồi thì giữ
// nguyên.
//
//	users/{uid}/contractCards/{contractId}  thẻ; client chỉ đọc, backend ghi
//
// Thẻ chép thông tin và kết quả kèo (snapshot) lúc lật, nên xoá hay sửa kèo về
// sau thì thẻ vẫn vẽ được. Kết quả xét theo progressValue đang ghi trong kèo,
// cùng số mà app và bước chốt kèo dùng.

var (
	errContractCardNotFound = &HTTPError{Status: http.StatusNotFound, Code: "contract_not_found", Message: "Không thấy kèo này."}
	errContractCardOpen     = &HTTPError{Status: http.StatusConflict, Code: "card_contract_open", Message: "Kèo chưa chốt, chốt xong mới lật được thẻ."}
	errContractCardFailed   = &HTTPError{Status: http.StatusConflict, Code: "card_contract_failed", Message: "Bạn chưa đạt kèo này nên thẻ không lật được."}
	errContractCardCanceled = &HTTPError{Status: http.StatusConflict, Code: "card_contract_cancelled", Message: "Kèo đã huỷ nên không có thẻ."}
)

// contractCardMaxActivities giới hạn số buổi đọc để cộng km tích luỹ.
const contractCardMaxActivities = 300

func (s *RunCardStore) contractCardRef(uid, contractID string) *firestore.DocumentRef {
	return s.db.Collection("users").Doc(uid).Collection("contractCards").Doc(contractID)
}

// contractCardEligible kiểm uid lật được thẻ của kèo d, trả phần participant
// của uid.
func contractCardEligible(d map[string]any, uid string) (map[string]any, error) {
	parts, _ := d["participants"].(map[string]any)
	p, ok := parts[uid].(map[string]any)
	if !ok {
		return nil, errContractCardNotFound
	}
	switch stringValue(d["status"]) {
	case "completed", "failed":
	case "active":
		return nil, errContractCardOpen
	default:
		return nil, errContractCardCanceled
	}
	if !contractMetTarget(stringValue(d["metric"]), number(p["progressValue"]), number(d["targetValue"])) {
		return nil, errContractCardFailed
	}
	return p, nil
}

// contractCardKm là số km tích luỹ trong kèo: kèo quãng đường thì chính tiến
// độ (đã gồm đi bộ), kèo khác thì cộng km các buổi đã tính vào kèo.
func (s *RunCardStore) contractCardKm(tx *firestore.Transaction, uid string, d, p map[string]any) (float64, error) {
	if stringValue(d["metric"]) == "distance" {
		return runCardKm(number(p["progressValue"]) * 1000), nil
	}
	ids, _ := p["countedActivityIds"].([]any)
	var refs []*firestore.DocumentRef
	for _, raw := range ids {
		if id := stringValue(raw); id != "" && len(refs) < contractCardMaxActivities {
			refs = append(refs, s.activityRef(uid, id))
		}
	}
	if len(refs) == 0 {
		return 0, nil
	}
	snaps, err := tx.GetAll(refs)
	if err != nil {
		return 0, err
	}
	var meters float64
	for _, snap := range snaps {
		if snap.Exists() {
			meters += number(snap.Data()["distanceMeters"])
		}
	}
	return runCardKm(meters), nil
}

// contractCardSnapshot chép thông tin và kết quả kèo cần để vẽ thẻ.
func contractCardSnapshot(d, p map[string]any, displayName string) map[string]any {
	parts, _ := d["participants"].(map[string]any)
	achievers := 0
	for _, raw := range parts {
		if q, ok := raw.(map[string]any); ok && contractMetTarget(stringValue(d["metric"]), number(q["progressValue"]), number(d["targetValue"])) {
			achievers++
		}
	}
	out := map[string]any{
		"title": stringValue(d["title"]), "metric": stringValue(d["metric"]),
		"targetValue": number(d["targetValue"]), "progressValue": number(p["progressValue"]),
		"periodType": stringValue(d["periodType"]), "visibility": stringValue(d["visibility"]),
		"participants": len(parts), "achievers": achievers, "displayName": displayName,
	}
	for _, k := range []string{"startAt", "endAtExclusive"} {
		if t, ok := d[k].(time.Time); ok {
			out[k] = t.UTC().Format(time.RFC3339)
		}
	}
	return out
}

func (s *RunCardStore) GetContractCard(ctx context.Context, uid, contractID string) (RunCardView, error) {
	card, err := getData(ctx, s.contractCardRef(uid, contractID))
	if err != nil {
		return RunCardView{}, err
	}
	if card != nil {
		return RunCardView{Card: runCardJSON(contractID, card)}, nil
	}
	var view RunCardView
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := getOptional(tx, s.db.Collection("runContracts").Doc(contractID))
		if err != nil {
			return err
		}
		if !snap.Exists() {
			return errContractCardNotFound
		}
		d := snap.Data()
		p, err := contractCardEligible(d, uid)
		if err != nil {
			if e, ok := err.(*HTTPError); ok && e != errContractCardNotFound {
				view = RunCardView{Reason: e.Code}
				return nil
			}
			return err
		}
		km, err := s.contractCardKm(tx, uid, d, p)
		if err != nil {
			return err
		}
		view = RunCardView{Odds: runCardOddList(runCardOdds(km)), Km: km}
		return nil
	}, firestore.ReadOnly)
	return view, err
}

// RollContractCard lật thẻ kèo cho uid. Đã lật thì trả thẻ cũ, nên app gửi
// lại không quay lại. Bậc và bản Ẩn quay trước transaction, nên transaction
// chạy lại vẫn ra một kết quả.
func (s *RunCardStore) RollContractCard(ctx context.Context, uid, contractID string) (map[string]any, error) {
	r, err := s.roll()
	if err != nil {
		return nil, err
	}
	secret, err := s.roll()
	if err != nil {
		return nil, err
	}
	var card map[string]any
	ref := s.contractCardRef(uid, contractID)
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := getOptional(tx, ref)
		if err != nil {
			return err
		}
		if snap.Exists() {
			card = snap.Data()
			return nil
		}
		contract, err := getOptional(tx, s.db.Collection("runContracts").Doc(contractID))
		if err != nil {
			return err
		}
		if !contract.Exists() {
			return errContractCardNotFound
		}
		d := contract.Data()
		p, err := contractCardEligible(d, uid)
		if err != nil {
			return err
		}
		km, err := s.contractCardKm(tx, uid, d, p)
		if err != nil {
			return err
		}
		profile, err := getOptional(tx, s.db.Collection("publicProfiles").Doc(uid))
		if err != nil {
			return err
		}
		odds := runCardOdds(km)
		card = map[string]any{
			"contractId": contractID, "tier": string(runCardPick(odds, r)), "odds": runCardOddMaps(odds), "rollPpm": r,
			"km": km, "rolledAt": s.now(), "variantRollPpm": secret,
			"snapshot": contractCardSnapshot(d, p, stringValue(profile.Data()["displayName"])),
		}
		if v := runCardVariant(secret); v != "" {
			card["variant"] = v
		}
		return tx.Create(ref, card)
	})
	if err != nil {
		return nil, err
	}
	return runCardJSON(contractID, card), nil
}
