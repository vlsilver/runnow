//go:build emulator

package backend

import "testing"

// Màn chi tiết ván trả cả thẻ luật lẫn chuỗi luật đầy đủ mà app cũ đang đọc.
func TestEmulatorGameDetailCarriesRulesCard(t *testing.T) {
	h := newAPIHarness(t, NewGameStore(emulatorDB(t), testPscChat))
	d := h.call("an", "GET", "/v1/games/"+openUserGame(t, h), nil, "1.13.0")
	card, _ := d.body["rulesCard"].([]any)
	if len(card) == 0 || card[0].(map[string]any)["title"] != "Một vòng" {
		t.Fatalf("rulesCard = %v", d.body["rulesCard"])
	}
	if d.body["rulesText"] == "" || d.body["rulesText"] == nil {
		t.Fatalf("rulesText = %v", d.body["rulesText"])
	}
}
