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
	}
	for _, c := range cases {
		got := kmTable(running, goalState(c.cfg), nil, wall)
		if got == nil || got.UnitLabel != c.unitLabel || got.CutLabel != c.cutLabel {
			t.Fatalf("%s: kmTable = %+v", c.name, got)
		}
	}
}
