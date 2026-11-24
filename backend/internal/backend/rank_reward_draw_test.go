package backend

import (
	"maps"
	"math"
	"slices"
	"testing"
)

// Bảng Chạy·Đi bộ tuần, số theo mét. Mốc bốc thăm 15 km.
func drawBoard() []rankedMember {
	km := []struct {
		uid  string
		rank int
		m    float64
	}{
		{"minh", 1, 57180}, {"nvl", 2, 40570}, {"tam", 3, 24220},
		{"loc", 4, 21640}, {"hung", 5, 13400}, {"lan", 6, 15000}, {"mai", 7, 14999},
	}
	out := make([]rankedMember, len(km))
	for i, k := range km {
		out[i] = rankedMember{rank: k.rank, member: &rankMember{uid: k.uid}, score: k.m}
	}
	return out
}

func winnersOf(top []rankedMember, got []*RankRewardItem) map[string]string {
	out := map[string]string{}
	for i, it := range got {
		if it != nil {
			out[top[i].member.uid] = it.ID
		}
	}
	return out
}

func TestRankRewardsAssignDraw(t *testing.T) {
	top := drawBoard()
	ao := RankRewardItem{ID: "ao", Kind: rankRewardDraw, MinScore: 15000, Slots: 2, Name: "Áo", Icon: "shirt"}
	keep := func([]int) {} // giữ thứ tự bảng: người đứng trên trúng trước

	t.Run("chỉ người từ 15 km, mốc tính cả đúng 15 km", func(t *testing.T) {
		r := &rankRewards{items: []RankRewardItem{{ID: "ao", Kind: rankRewardDraw, MinScore: 15000, Slots: 10, Name: "Áo", Icon: "shirt"}}}
		got := winnersOf(top, r.assign(top, keep))
		want := map[string]string{"minh": "ao", "nvl": "ao", "tam": "ao", "loc": "ao", "lan": "ao"}
		if !maps.Equal(got, want) {
			t.Fatalf("người trúng %v, muốn %v", got, want)
		}
	})

	t.Run("bốc đúng số suất trong số người đủ mốc", func(t *testing.T) {
		r := &rankRewards{items: []RankRewardItem{ao}}
		var pool []int
		reverse := func(idx []int) { pool = slices.Clone(idx); slices.Reverse(idx) }
		got := winnersOf(top, r.assign(top, reverse))
		// Ứng viên theo thứ tự bảng: minh nvl tam loc lan; đảo lại thì lan, loc trúng.
		if !slices.Equal(pool, []int{0, 1, 2, 3, 5}) {
			t.Fatalf("ứng viên %v", pool)
		}
		if want := map[string]string{"lan": "ao", "loc": "ao"}; !maps.Equal(got, want) {
			t.Fatalf("người trúng %v, muốn %v", got, want)
		}
	})

	t.Run("người đã có quà theo hạng không vào lượt bốc", func(t *testing.T) {
		r := &rankRewards{items: []RankRewardItem{{ID: "giay", FromRank: 1, ToRank: 1, Name: "Giày", Icon: "shoes"}, ao}}
		got := winnersOf(top, r.assign(top, keep))
		if want := map[string]string{"minh": "giay", "nvl": "ao", "tam": "ao"}; !maps.Equal(got, want) {
			t.Fatalf("người trúng %v, muốn %v", got, want)
		}
	})

	t.Run("không ai đủ mốc thì không ai trúng", func(t *testing.T) {
		r := &rankRewards{items: []RankRewardItem{{ID: "ao", Kind: rankRewardDraw, MinScore: 100000, Slots: 2, Name: "Áo", Icon: "shirt"}}}
		if got := winnersOf(top, r.assign(top, keep)); len(got) != 0 {
			t.Fatalf("người trúng %v", got)
		}
	})
}

func TestNormalizeRankRewardDraw(t *testing.T) {
	const board = "week_2026-11-23_run"
	draw := RankRewardItem{Kind: rankRewardDraw, MinScore: 15000, Slots: 2, Name: "Áo Kiprun", Icon: "shirt"}
	rank := RankRewardItem{FromRank: 1, ToRank: 1, Name: "Giày", Icon: "shoes"}
	with := func(it RankRewardItem, f func(*RankRewardItem)) RankRewardItem { f(&it); return it }

	got, err := normalizeRankRewardItems(board, []RankRewardItem{draw, rank})
	if err != nil {
		t.Fatal(err)
	}
	if got[0].Name != "Giày" || got[1].Kind != rankRewardDraw {
		t.Fatalf("quà theo hạng đứng trước, bốc thăm sau: %+v", got)
	}
	// Hai món bốc thăm không chồng hạng với nhau hay với quà theo hạng.
	if _, err := normalizeRankRewardItems(board, []RankRewardItem{draw, draw, rank}); err != nil {
		t.Fatalf("hai món bốc thăm: %v", err)
	}
	// Suất bốc thăm không bị giới hạn bởi top 10, chỉ bởi tổng 20 suất.
	twenty := with(draw, func(it *RankRewardItem) { it.Slots = 20 })
	if _, err := normalizeRankRewardItems(board, []RankRewardItem{twenty}); err != nil {
		t.Fatalf("20 suất: %v", err)
	}
	if _, err := normalizeRankRewardItems(board, []RankRewardItem{twenty, with(draw, func(it *RankRewardItem) { it.Slots = 1 })}); err != errRankRewardInvalid {
		t.Fatalf("tổng 21 suất: lỗi %v, muốn invalid_reward", err)
	}
	// Cộng hai số suất lớn không được tràn số mà lọt qua mốc tổng.
	huge := with(draw, func(it *RankRewardItem) { it.Slots = math.MaxInt })
	if _, err := normalizeRankRewardItems(board, []RankRewardItem{with(draw, func(it *RankRewardItem) { it.Slots = 1 }), huge}); err != errRankRewardInvalid {
		t.Fatalf("suất tràn số: lỗi %v, muốn invalid_reward", err)
	}

	bad := map[string]RankRewardItem{
		"không suất":        with(draw, func(it *RankRewardItem) { it.Slots = 0 }),
		"quá 20 suất":       with(draw, func(it *RankRewardItem) { it.Slots = 21 }),
		"không mốc":         with(draw, func(it *RankRewardItem) { it.MinScore = 0 }),
		"mốc âm":            with(draw, func(it *RankRewardItem) { it.MinScore = -1 }),
		"bốc thăm có hạng":  with(draw, func(it *RankRewardItem) { it.FromRank, it.ToRank = 1, 3 }),
		"theo hạng có mốc":  with(rank, func(it *RankRewardItem) { it.MinScore = 15000 }),
		"theo hạng có suất": with(rank, func(it *RankRewardItem) { it.Slots = 2 }),
		"kiểu lạ":           with(draw, func(it *RankRewardItem) { it.Kind = "lucky" }),
	}
	for name, it := range bad {
		if _, err := normalizeRankRewardItems(board, []RankRewardItem{it}); err != errRankRewardInvalid {
			t.Errorf("%s: lỗi %v, muốn invalid_reward", name, err)
		}
	}
}

func TestKeepsOldDraw(t *testing.T) {
	old := &rankRewards{items: []RankRewardItem{{ID: "ao", Kind: rankRewardDraw, MinScore: 15000, Slots: 2, Name: "Áo", Icon: "shirt"}}}
	same := old.items[0]
	for name, f := range map[string]func(*RankRewardItem){
		"bớt suất": func(it *RankRewardItem) { it.Slots = 1 },
		"đổi mốc":  func(it *RankRewardItem) { it.MinScore = 20000 },
		"đổi kiểu": func(it *RankRewardItem) { it.Kind, it.FromRank, it.ToRank, it.MinScore, it.Slots = "", 1, 2, 0, 0 },
	} {
		it := same
		f(&it)
		if keepsOld(old, []RankRewardItem{it}) {
			t.Errorf("%s: kỳ đang chạy mà vẫn cho sửa", name)
		}
	}
	more := same
	more.Icon, more.Slots = "other", 3
	if !keepsOld(old, []RankRewardItem{more}) {
		t.Error("đổi icon và thêm suất phải được")
	}
}
