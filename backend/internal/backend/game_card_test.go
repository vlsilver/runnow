package backend

import (
	"fmt"
	"math"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

func TestGameCardTierIsStablePerGameAndPlayer(t *testing.T) {
	a, b := ww.Seed{1}, ww.Seed{2}
	if gameCardTier(a, "u1") != gameCardTier(a, "u1") {
		t.Fatal("cùng ván cùng người ra hai bậc")
	}
	// Đổi ván hay đổi người thì phải bốc lại: trong 200 cặp không thể trùng hết.
	sameGame, samePlayer := 0, 0
	for i := range 200 {
		uid := fmt.Sprintf("u%d", i)
		if gameCardTier(a, uid) == gameCardTier(b, uid) {
			sameGame++
		}
		if gameCardTier(a, uid) == gameCardTier(a, uid+"x") {
			samePlayer++
		}
	}
	if sameGame == 200 || samePlayer == 200 {
		t.Fatalf("bậc không đổi theo ván (%d) hay theo người (%d)", sameGame, samePlayer)
	}
}

// Tỉ lệ 45/30/16/7/2 %, giống thẻ buổi chạy 5 km. 40.000 lần bốc thì sai số
// chuẩn của bậc 45 % là 0,25 điểm; lệch quá 1,5 điểm là sai bảng.
func TestGameCardTierFollowsTheOdds(t *testing.T) {
	want := map[runCardTier]float64{
		runCardCommon: 45, runCardRare: 30, runCardEpic: 16, runCardLegendary: 7, runCardMythic: 2,
	}
	const n = 40000
	got := map[runCardTier]int{}
	for i := range n {
		seed := ww.Seed{byte(i), byte(i >> 8), byte(i >> 16)}
		got[gameCardTier(seed, "u")]++
	}
	for tier, pct := range want {
		if p := float64(got[tier]) * 100 / n; math.Abs(p-pct) > 1.5 {
			t.Errorf("%s = %.2f %%, mong đợi %.0f %%", tier, p, pct)
		}
	}
}
