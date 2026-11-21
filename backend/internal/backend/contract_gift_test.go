package backend

import (
	"slices"
	"testing"
	"time"
)

func TestContractGiftAnnounceLine(t *testing.T) {
	items := []any{
		map[string]any{"id": "a", "name": "Áo PSC", "icon": "shirt", "slots": 1},
		map[string]any{"id": "t", "name": "Tất", "icon": "socks", "slots": 3},
	}
	cases := []struct {
		gift map[string]any
		want string
	}{
		{nil, ""},
		{map[string]any{"kind": "draw", "items": []any{}}, ""},
		{map[string]any{"kind": "draw", "items": items}, "🎁 Quà Áo PSC, Tất ×3: bốc thăm trong số người đạt.\n"},
		{map[string]any{"kind": "rank", "items": items}, "🎁 Quà Áo PSC, Tất ×3: theo hạng trong số người đạt.\n"},
	}
	for _, c := range cases {
		if got := contractGiftAnnounceLine(c.gift); got != c.want {
			t.Errorf("%v: %q, mong đợi %q", c.gift["kind"], got, c.want)
		}
	}
}

// Bốc thăm khi người đạt nhiều hơn suất: thứ tự sau khi trộn quyết định ai
// trúng. Hàm trộn giả đảo ngược danh sách đã xếp theo lúc đạt (an, binh, chi),
// nên chi nhận Áo, binh nhận Tất, an trượt.
func TestResolveContractGiftsDrawsWhenOversubscribed(t *testing.T) {
	at := func(h int) time.Time { return time.Date(2026, 11, 4, h, 0, 0, 0, vietnam) }
	entrants := []giftEntrant{{UID: "chi", ReachedAt: at(9)}, {UID: "an", ReachedAt: at(7)}, {UID: "binh", ReachedAt: at(8)}}
	items := []ContractGiftItem{{ID: "ao", Slots: 1}, {ID: "tat", Slots: 1}}
	shuffled := 0
	reverse := func(es []giftEntrant) { shuffled++; slices.Reverse(es) }
	got := resolveContractGifts(contractGiftDraw, items, entrants, reverse)
	want := []giftWinner{{Slot: 0, ItemID: "ao", UID: "chi"}, {Slot: 1, ItemID: "tat", UID: "binh"}}
	if shuffled != 1 || !slices.Equal(got, want) {
		t.Fatalf("trộn %d lần, trúng %+v", shuffled, got)
	}
	// Đủ suất cho mọi người thì không trộn.
	items = append(items, ContractGiftItem{ID: "non", Slots: 1})
	shuffled = 0
	got = resolveContractGifts(contractGiftDraw, items, entrants, reverse)
	if shuffled != 0 || got[0].UID != "an" || got[2].UID != "chi" {
		t.Fatalf("trộn %d lần, trúng %+v", shuffled, got)
	}
}
