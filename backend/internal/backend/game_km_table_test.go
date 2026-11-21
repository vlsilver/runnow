package backend

import (
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Nhãn mốc km và đường cắt theo luật phiếu: chỉ luật cut mới có người mất
// phiếu; flat thì km không đụng tới phiếu nên không có nhãn nào.
func TestKmTableVoteLabels(t *testing.T) {
	wall := time.Date(2026, 11, 7, 15, 0, 0, 0, vietnam)
	running := map[string]any{"status": "running"}
	cases := []struct {
		name      string
		cfg       ww.Config
		unitLabel string
		cutLabel  string
	}{
		{"cut", ww.Config{KmPerUnit: 2}, "giữ phiếu", "Dưới 2 km · có thể mất phiếu"},
		{"top", ww.Config{KmPerUnit: 2, Vote: ww.VoteTop}, "tranh x2 phiếu", ""},
		{"flat", ww.Config{KmPerUnit: 2, Vote: ww.VoteFlat}, "", ""},
		// Riêng: dưới mốc là chắc mất phiếu, không phụ thuộc người khác.
		{"solo", ww.Config{KmPerUnit: 2, Vote: ww.VoteSolo, Ruleset: ww.RulesetKm}, "giữ phiếu", "Dưới 2 km · mất phiếu"},
	}
	for _, c := range cases {
		got := kmTable(running, goalState(c.cfg), nil, wall)
		if got == nil || got.UnitLabel != c.unitLabel || got.CutLabel != c.cutLabel {
			t.Fatalf("%s: kmTable = %+v", c.name, got)
		}
	}
}

// Nhãn x2 đi theo km đang gom, theo đúng luật top của engine: chưa đủ mốc thì
// không được, ván không có suất top thì không ai có nhãn.
func TestLiveVoteTags(t *testing.T) {
	meters := map[string]float64{"s1": 5000, "v1": 3000, "v2": 2500, "w1": 500}
	live := &liveKm{Meters: meters}

	// goalState có 1 sói còn sống nên mặc định top 2.
	got := liveVoteTags(goalState(ww.Config{KmPerUnit: 2, Vote: ww.VoteTop}), live)
	if len(got) != 2 || got["s1"] != "x2" || got["v1"] != "x2" {
		t.Fatalf("top: %v", got)
	}
	// Bằng km ở suất cuối mà nhiều người hơn số suất thì chưa ai được nhãn đó.
	tied := map[string]float64{"s1": 5000, "v1": 3000, "v2": 3000, "w1": 500}
	got = liveVoteTags(goalState(ww.Config{KmPerUnit: 2, Vote: ww.VoteTop}), &liveKm{Meters: tied})
	if len(got) != 1 || got["s1"] != "x2" {
		t.Fatalf("hoà suất cuối: %v", got)
	}
	if got := liveVoteTags(goalState(ww.Config{KmPerUnit: 2, Vote: ww.VoteFlat}), live); len(got) != 0 {
		t.Fatalf("flat: %v", got)
	}
	// Ván thử không có km sống.
	if got := liveVoteTags(goalState(ww.Config{KmPerUnit: 2, Vote: ww.VoteTop}), nil); len(got) != 0 {
		t.Fatalf("không có live: %v", got)
	}
}
