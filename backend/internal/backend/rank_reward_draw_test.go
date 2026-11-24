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

// Hai món bốc thăm lần lượt: món sau chỉ bốc trong số người món trước chưa
// lấy. Giày hạng 1, áo 2 suất mốc 15 km, tất 1 suất mốc 20 km.
func TestRankRewardsDrawPools(t *testing.T) {
	top := drawBoard() // đủ 15 km: minh nvl tam loc lan; đủ 20 km: minh nvl tam loc
	r := &rankRewards{items: []RankRewardItem{
		{ID: "giay", FromRank: 1, ToRank: 1, Name: "Giày", Icon: "shoes"},
		{ID: "ao", Kind: rankRewardDraw, MinScore: 15000, Slots: 2, Name: "Áo", Icon: "shirt"},
		{ID: "tat", Kind: rankRewardDraw, MinScore: 20000, Slots: 1, Name: "Tất", Icon: "socks"},
	}}
	keep := func([]int) {}
	items := r.assign(top, keep) // áo về nvl, tam; tất về loc
	got := r.drawPools(top, items)
	// Áo: nvl tam loc lan (minh có giày). Tất: loc (nvl, tam đã có áo).
	if want := map[string]int{"ao": 4, "tat": 1}; !maps.Equal(got, want) {
		t.Fatalf("pools %v, muốn %v", got, want)
	}
}

func TestRankRewardAnnounceText(t *testing.T) {
	key, _ := parseRankBoardID("week_2026-11-23_run")
	entries := []any{
		map[string]any{"uid": "minh", "rank": 1, "displayName": "Minh", "reward": map[string]any{"name": "Giày"}},
		map[string]any{"rank": 2, "displayName": "Nam"},
		map[string]any{"uid": "an", "rank": 14, "displayName": "<An>", "reward": map[string]any{"name": "Áo & tất", "kind": "draw", "pool": 23}},
	}
	want := "🏆 Quà BXH tuần 23/11–29/11 đã có chủ!\n" +
		"🎁 <b>Giày</b> → <a href=\"tg://user?id=5551\">Minh</a> (hạng 1)\n" +
		"🎁 <b>Áo &amp; tất</b> → &lt;An&gt; (bốc thăm trong 23 người)\n" +
		"Mở thẻ quà để nhận quà và khoe với mọi người."
	// Minh đã liên kết Telegram nên được tag; An chưa liên kết thì tên thường.
	if got := rankRewardAnnounceText(key, entries, map[string]string{"minh": "5551"}); got != want {
		t.Fatalf("bài báo quà:\n%s\nmuốn:\n%s", got, want)
	}
	if got := rankRewardAnnounceText(key, entries[1:2], nil); got != "" {
		t.Fatalf("không ai trúng mà có bài: %q", got)
	}
}
