package backend

import (
	"fmt"
	"strings"
	"testing"
	"time"
)

func TestLearnStamp(t *testing.T) {
	for _, c := range []struct {
		at   time.Time
		want string
	}{
		{time.Date(2026, 10, 20, 0, 1, 0, 0, time.UTC), "[T3 20/10/2026 07:01]"},
		// 17:30 UTC thứ 7 đã là 00:30 chủ nhật ở VN.
		{time.Date(2026, 10, 24, 17, 30, 0, 0, time.UTC), "[CN 25/10/2026 00:30]"},
		{time.Date(2026, 10, 24, 6, 0, 0, 0, vietnam), "[T7 24/10/2026 06:00]"},
	} {
		if got := learnStamp(c.at); got != c.want {
			t.Errorf("learnStamp(%v) = %q, muốn %q", c.at, got, c.want)
		}
	}
}

func TestAgentLearnTaskForWindow(t *testing.T) {
	base := time.Date(2026, 10, 20, 7, 0, 0, 0, vietnam)
	id := func(d time.Duration) string { return agentLearnTaskFor(base.Add(d)).TaskID }
	// Tick 10 phút một lần: ba lần hẹn trong một khung 30 phút ra cùng một task.
	if id(0) != id(10*time.Minute) || id(0) != id(29*time.Minute) {
		t.Fatal("cùng khung 30 phút mà khác TaskID")
	}
	if id(0) == id(30*time.Minute) {
		t.Fatal("khung mới mà trùng TaskID khung cũ")
	}
	if p := agentLearnTaskFor(base).HandlerPath; p != "/tasks/agent-learn" {
		t.Fatalf("handler %q", p)
	}
}

func TestApplyLearnActions(t *testing.T) {
	old := time.Date(2026, 10, 1, 0, 0, 0, 0, time.UTC)
	now := time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)
	facts := []learnedFact{
		{ID: "f1", Text: "An chạy dài chủ nhật", CreatedAt: old, UpdatedAt: old},
		{ID: "f2", Text: "An đi giày Pegasus", CreatedAt: old, UpdatedAt: old},
	}
	res := applyLearnActions(facts, 2, []learnAction{
		{Op: "ADD", Text: "  An đăng ký full Đà Nẵng tháng 12/2026 "},
		{Op: "ADD", Text: "An chạy dài chủ nhật"}, // trùng ký ức đã có
		{Op: "ADD", Text: ""},
		{Op: "ADD", Text: strings.Repeat("x", agentMemoryMaxRunes+1)},
		{Op: "UPDATE", ID: "f1", Text: "An chạy dài thứ 7"},
		{Op: "UPDATE", ID: "f9", Text: "id không có"},
		{Op: "DELETE", ID: "f2"},
		{Op: "DELETE", ID: "f2"}, // đã xoá ở lệnh trên
		{Op: "MERGE", ID: "f1"},
	}, now)
	want := []learnedFact{
		{ID: "f1", Text: "An chạy dài thứ 7", CreatedAt: old, UpdatedAt: now},
		{ID: "f3", Text: "An đăng ký full Đà Nẵng tháng 12/2026", CreatedAt: now, UpdatedAt: now},
	}
	if len(res.facts) != len(want) {
		t.Fatalf("facts = %+v", res.facts)
	}
	for i := range want {
		if res.facts[i] != want[i] {
			t.Errorf("fact %d = %+v, muốn %+v", i, res.facts[i], want[i])
		}
	}
	if res.nextID != 3 || res.added != 1 || res.skipped != 6 || res.full {
		t.Errorf("nextID=%d added=%d skipped=%d full=%v", res.nextID, res.added, res.skipped, res.full)
	}
	wantChanges := []learnChange{
		{op: "UPDATE", id: "f1", before: "An chạy dài chủ nhật", after: "An chạy dài thứ 7"},
		{op: "DELETE", id: "f2", before: "An đi giày Pegasus"},
	}
	if len(res.changes) != 2 || res.changes[0] != wantChanges[0] || res.changes[1] != wantChanges[1] {
		t.Errorf("changes = %+v", res.changes)
	}
	// Danh sách gốc không bị sửa: transaction chạy lại thì áp lại từ đầu.
	if facts[0].Text != "An chạy dài chủ nhật" || len(facts) != 2 {
		t.Errorf("sửa vào slice gốc: %+v", facts)
	}
}

func TestApplyLearnActionsFull(t *testing.T) {
	now := time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)
	var facts []learnedFact
	for i := range agentLearnedLimit {
		facts = append(facts, learnedFact{ID: fmt.Sprintf("f%d", i+1), Text: fmt.Sprintf("ký ức %d", i+1), UpdatedAt: now})
	}
	res := applyLearnActions(facts, 50, []learnAction{{Op: "ADD", Text: "mới"}, {Op: "UPDATE", ID: facts[0].ID, Text: "sửa vẫn được"}}, now)
	if !res.full || res.added != 0 || len(res.facts) != agentLearnedLimit || res.facts[0].Text != "sửa vẫn được" {
		t.Fatalf("đầy: full=%v added=%d len=%d first=%q", res.full, res.added, len(res.facts), res.facts[0].Text)
	}
}

func TestNewestFactsKeepsOrder(t *testing.T) {
	at := func(h int) time.Time { return time.Date(2026, 10, 20, h, 0, 0, 0, time.UTC) }
	facts := []learnedFact{{ID: "f1", UpdatedAt: at(5)}, {ID: "f2", UpdatedAt: at(1)}, {ID: "f3", UpdatedAt: at(9)}, {ID: "f4", UpdatedAt: at(3)}}
	var got []string
	for _, f := range newestFacts(facts, 2) {
		got = append(got, f.ID)
	}
	if strings.Join(got, ",") != "f1,f3" {
		t.Fatalf("newestFacts = %v, muốn f1,f3", got)
	}
	if len(newestFacts(facts, 4)) != 4 || facts[1].ID != "f2" {
		t.Fatal("newestFacts đổi slice gốc hoặc bỏ mục khi chưa vượt giới hạn")
	}
}

func TestLiveFactsDropsExpired(t *testing.T) {
	now := time.Date(2026, 10, 20, 0, 0, 0, 0, time.UTC)
	got := liveFacts([]any{
		map[string]any{"id": "f1", "text": "mới sửa", "updatedAt": now.Add(-89 * 24 * time.Hour)},
		map[string]any{"id": "f2", "text": "quá 90 ngày", "updatedAt": now.Add(-91 * 24 * time.Hour)},
		map[string]any{"text": "thiếu id", "updatedAt": now},
	}, now)
	if len(got) != 1 || got[0].ID != "f1" {
		t.Fatalf("liveFacts = %+v", got)
	}
}

func TestScrubNames(t *testing.T) {
	names := []string{"An", "Linh Vũ"}
	for _, c := range []struct{ in, want string }{
		{"Đội gồm An, Bình, Dũng", "Đội gồm một thành viên, Bình, Dũng"},
		{"An, An và Bình", "một thành viên, một thành viên và Bình"},
		// Thà gỡ nhầm tên người khác trùng chữ còn hơn sót tên người đã xoá.
		{"Anh Tuấn rủ Hoàng An chạy", "Anh Tuấn rủ Hoàng một thành viên chạy"},
		{"Ana không phải An.", "Ana không phải một thành viên."},
		{"Linh Vũ dẫn đoàn, Linh thì không", "một thành viên dẫn đoàn, Linh thì không"},
		{"Ân chạy", "Ân chạy"},
	} {
		if got := scrubNames(c.in, names); got != c.want {
			t.Errorf("scrubNames(%q) = %q, muốn %q", c.in, got, c.want)
		}
	}
}
