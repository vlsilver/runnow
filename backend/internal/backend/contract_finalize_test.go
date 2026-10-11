package backend

import (
	"testing"
	"time"
)

func TestContractDueForFinalize(t *testing.T) {
	loc := time.FixedZone("VN", 7*3600)
	finalizeAt := time.Date(2026, 10, 5, 6, 0, 0, 0, loc) // 06:00 sau ngày kết thúc
	doc := func(status string, finalize any) map[string]any {
		return map[string]any{"status": status, "finalizeAt": finalize}
	}

	cases := []struct {
		name string
		d    map[string]any
		now  time.Time
		want bool
	}{
		{"đúng 06:00 là tới hạn", doc("active", finalizeAt), finalizeAt, true},
		{"06:05 tới hạn", doc("active", finalizeAt), finalizeAt.Add(5 * time.Minute), true},
		{"05:59 còn trong grace", doc("active", finalizeAt), finalizeAt.Add(-time.Minute), false},
		{"đã chốt thì thôi", doc("completed", finalizeAt), finalizeAt.Add(time.Hour), false},
		{"đã huỷ thì thôi", doc("cancelled", finalizeAt), finalizeAt.Add(time.Hour), false},
		{"thiếu finalizeAt thì không đoán", doc("active", nil), finalizeAt.Add(time.Hour), false},
	}
	for _, c := range cases {
		if got := contractDueForFinalize(c.d, c.now); got != c.want {
			t.Errorf("%s: muốn %v, được %v", c.name, c.want, got)
		}
	}
}

func TestContractFinalStatus(t *testing.T) {
	cases := []struct {
		metric           string
		progress, target float64
		want             string
	}{
		{"distance", 50, 50, "completed"},
		{"distance", 49.9, 50, "failed"},
		// Làm tròn tới mét như client (contractTargetMet): 4.9996km = 5000m.
		{"longest_run", 4.9996, 5, "completed"},
		{"longest_run", 4.9994, 5, "failed"},
		{"activity_count", 3, 3, "completed"},
		{"activity_count", 2, 3, "failed"},
		{"active_days", 5, 5, "completed"},
		{"route_completion", 0, 1, "failed"},
	}
	for _, c := range cases {
		if got := contractFinalStatus(c.metric, c.progress, c.target); got != c.want {
			t.Errorf("%s %.4f/%.4f: muốn %s, được %s", c.metric, c.progress, c.target, c.want, got)
		}
	}
}

func TestFormatContractMetricValueUsesStoredMetricKeys(t *testing.T) {
	cases := map[string]struct {
		v    float64
		want string
	}{
		"distance":         {12.5, "12.5 km"},
		"longest_run":      {10, "10 km"},
		"activity_count":   {3, "3 buổi"},
		"active_days":      {4, "4 ngày"},
		"route_completion": {2, "2 lần"},
	}
	for metric, c := range cases {
		if got := formatContractMetricValue(metric, c.v); got != c.want {
			t.Errorf("%s: muốn %q, được %q", metric, c.want, got)
		}
	}
}

func TestRecalcCoversParticipants(t *testing.T) {
	d := map[string]any{
		"metric":       "distance",
		"participants": map[string]any{"a": map[string]any{}, "b": map[string]any{}},
	}
	full := []ContractRecalcResult{{UID: "a", ContractID: "k1"}, {UID: "b", ContractID: "k1"}}
	if !recalcCoversParticipants("k1", d, full) {
		t.Fatal("đủ 2 người đã recalc thì phải chốt được")
	}
	// b recalc lỗi (RecalcActiveContracts log rồi bỏ qua) → không có dòng của b.
	partial := []ContractRecalcResult{{UID: "a", ContractID: "k1"}, {UID: "b", ContractID: "k2"}}
	if recalcCoversParticipants("k1", d, partial) {
		t.Fatal("thiếu kết quả recalc của b thì không được chốt")
	}
	// route_completion BE không tính, chốt theo số client ghi lần cuối.
	route := map[string]any{"metric": "route_completion", "participants": d["participants"]}
	if !recalcCoversParticipants("k1", route, nil) {
		t.Fatal("route_completion không cần recalc BE")
	}
}

func TestContractPeriodEnded(t *testing.T) {
	end := time.Date(2026, 10, 5, 0, 0, 0, 0, time.FixedZone("VN", 7*3600))
	d := map[string]any{"endAtExclusive": end}
	if contractPeriodEnded(d, end.Add(-time.Second)) {
		t.Fatal("23:59:59 ngày cuối vẫn đang chạy")
	}
	if !contractPeriodEnded(d, end) {
		t.Fatal("tới endAtExclusive là hết kỳ")
	}
	if contractPeriodEnded(map[string]any{}, end) {
		t.Fatal("thiếu endAtExclusive thì giữ như cũ (coi là đang chạy)")
	}
}
