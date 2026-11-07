package backend

import (
	"reflect"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Không gửi settings (app cũ) thì ván mới theo luật km: Theo nhóm, mỗi vai
// 1 km một lượt, sói nào cũng có phiếu cắn, tối đa 3 người lên giàn.
func TestGameSettingsDefaults(t *testing.T) {
	gc := ww.Config{KmPerUnit: 2}
	if err := applyGameSettings(&gc, nil); err != nil {
		t.Fatal(err)
	}
	want := ww.Config{KmPerUnit: 2, Vote: ww.VoteCut, Ruleset: ww.RulesetKm, MaxHang: 3,
		SkillKm: map[ww.Role]float64{ww.Wolf: 0, ww.Seer: 1, ww.Guard: 1, ww.Witch: 1, ww.Hunter: 1}}
	if !reflect.DeepEqual(gc, want) {
		t.Fatalf("config = %+v, mong đợi %+v", gc, want)
	}
}

func TestGameSettingsApplied(t *testing.T) {
	var gc ww.Config
	err := applyGameSettings(&gc, map[string]any{
		"extraWolves": 1.0, "wolfKm": 2.0, "seerKm": 0.0, "guardKm": 1.5, "witchKm": 3.0, "hunterKm": 1.0,
		"vote": "solo", "kmPerUnit": 2.5, "maxHang": 1.0, "topOn": true, "topVoters": 4.0, "topWeight": 3.0,
	})
	if err != nil {
		t.Fatal(err)
	}
	want := ww.Config{
		ExtraWolves: 1, KmPerUnit: 2.5, Ruleset: ww.RulesetKm, Vote: ww.VoteSolo, MaxHang: 1, TopVoters: 4, TopWeight: 3,
		SkillKm: map[ww.Role]float64{ww.Wolf: 2, ww.Seer: 0, ww.Guard: 1.5, ww.Witch: 3, ww.Hunter: 1},
	}
	if !reflect.DeepEqual(gc, want) {
		t.Fatalf("config = %+v, mong đợi %+v", gc, want)
	}

	gc = ww.Config{}
	if err := applyGameSettings(&gc, map[string]any{"kmOff": true}); err != nil || !gc.KmOff {
		t.Fatalf("tắt km = %+v, %v", gc, err)
	}
}

// Bốn ô độ dài pha (phút). Ván km: lịch 22h, một vòng 24 tiếng, chia lại pha.
// Ván cổ điển: độ dài vòng là tổng bốn pha, đè lên roundHours gửi kèm.
func TestGameSettingsPhases(t *testing.T) {
	var km ww.Config
	if err := applyGameSettings(&km, map[string]any{"nightMin": 60.0, "dawnMin": 660.0, "dayMin": 600.0, "trialMin": 120.0}); err != nil {
		t.Fatal(err)
	}
	if want := (ww.Schedule{StartHour: 22, RoundHours: 24, Rounds: 1, Phases: []int{60, 660, 600, 120}}); km.Schedule == nil || !reflect.DeepEqual(*km.Schedule, want) {
		t.Fatalf("ván km = %+v", km.Schedule)
	}
	if err := km.Validate(); err != nil {
		t.Fatal(err)
	}

	var classic ww.Config
	err := applyGameSettings(&classic, map[string]any{"kmOff": true, "startHour": 6.0, "roundHours": 24.0, "roundsPerDay": 2.0,
		"nightMin": 60.0, "dawnMin": 120.0, "dayMin": 240.0, "trialMin": 60.0})
	if err != nil {
		t.Fatal(err)
	}
	if want := (ww.Schedule{StartHour: 6, RoundHours: 8, Rounds: 2, Phases: []int{60, 120, 240, 60}}); !reflect.DeepEqual(*classic.Schedule, want) {
		t.Fatalf("ván cổ điển = %+v", classic.Schedule)
	}
	if err := classic.Validate(); err != nil {
		t.Fatal(err)
	}
}

// Ván km chọn được số vòng mỗi ngày: app cũ chỉ gửi roundsPerDay thì vòng dài
// 24/số vòng; app mới gửi kèm bốn pha cộng lại đúng 24/số vòng.
func TestGameSettingsKmRoundsPerDay(t *testing.T) {
	var old ww.Config
	if err := applyGameSettings(&old, map[string]any{"roundsPerDay": 3.0}); err != nil {
		t.Fatal(err)
	}
	if want := (ww.Schedule{StartHour: 22, RoundHours: 8, Rounds: 3}); old.Schedule == nil || !reflect.DeepEqual(*old.Schedule, want) {
		t.Fatalf("ván km 3 vòng = %+v", old.Schedule)
	}
	if err := old.Validate(); err != nil {
		t.Fatal(err)
	}

	var phased ww.Config
	err := applyGameSettings(&phased, map[string]any{"roundsPerDay": 2.0, "nightMin": 60.0, "dawnMin": 240.0, "dayMin": 360.0, "trialMin": 60.0})
	if err != nil {
		t.Fatal(err)
	}
	if want := (ww.Schedule{StartHour: 22, RoundHours: 12, Rounds: 2, Phases: []int{60, 240, 360, 60}}); !reflect.DeepEqual(*phased.Schedule, want) {
		t.Fatalf("ván km 2 vòng có pha = %+v", phased.Schedule)
	}
	if err := phased.Validate(); err != nil {
		t.Fatal(err)
	}

	// 5 vòng không chia đều 24 tiếng.
	var five ww.Config
	if err := applyGameSettings(&five, map[string]any{"roundsPerDay": 5.0}); err == nil && five.Validate() == nil {
		t.Fatal("ván km 5 vòng mỗi ngày không bị từ chối")
	}
}

// Hai vòng mỗi ngày, mỗi vòng một lịch pha: roundPhases đè bốn ô pha, vòng 1
// thành Phases để ô pha đọc ngược ra đúng. Sai hình thì 422.
func TestGameSettingsRoundPhases(t *testing.T) {
	var c ww.Config
	err := applyGameSettings(&c, map[string]any{"roundsPerDay": 2.0, "nightMin": 60.0, "dawnMin": 300.0, "dayMin": 300.0, "trialMin": 60.0,
		"roundPhases": []any{[]any{60.0, 300.0, 300.0, 60.0}, []any{120.0, 240.0, 240.0, 120.0}}})
	if err != nil {
		t.Fatal(err)
	}
	want := ww.Schedule{StartHour: 22, RoundHours: 12, Rounds: 2, Phases: []int{60, 300, 300, 60},
		RoundPhases: [][]int{{60, 300, 300, 60}, {120, 240, 240, 120}}}
	if !reflect.DeepEqual(*c.Schedule, want) {
		t.Fatalf("lịch = %+v", c.Schedule)
	}
	if err := c.Validate(); err != nil {
		t.Fatal(err)
	}

	for name, v := range map[string]any{
		"không phải danh sách": 60.0,
		"thiếu pha":            []any{[]any{60.0, 300.0, 360.0}},
		"lệch bước":            []any{[]any{75.0, 285.0, 300.0, 60.0}},
		"quá 4 vòng":           []any{[]any{360.0}, []any{360.0}, []any{360.0}, []any{360.0}, []any{360.0}},
	} {
		var bad ww.Config
		if err := applyGameSettings(&bad, map[string]any{"roundPhases": v}); err == nil {
			t.Fatalf("%s: không bị từ chối", name)
		}
	}
}

// Top tắt thì bỏ qua số phiếu gửi kèm; bật mà không gửi thì x2. Hai luật phiếu
// cũ vẫn nhận dù không còn hiện trên màn tạo ván.
func TestGameSettingsTopAndLegacyVote(t *testing.T) {
	cases := []struct {
		in   map[string]any
		vote ww.VoteRule
		top  int
	}{
		{map[string]any{"topOn": false, "topWeight": 4.0}, ww.VoteCut, 0},
		{map[string]any{"topOn": true}, ww.VoteCut, 2},
		{map[string]any{"vote": "top"}, ww.VoteTop, 0},
		{map[string]any{"vote": "flat"}, ww.VoteFlat, 0},
	}
	for _, c := range cases {
		var gc ww.Config
		if err := applyGameSettings(&gc, c.in); err != nil {
			t.Fatalf("%v: %v", c.in, err)
		}
		if gc.Vote != c.vote || gc.TopWeight != c.top {
			t.Errorf("%v: vote %s, topWeight %d", c.in, gc.Vote, gc.TopWeight)
		}
	}
}

// Key lạ, sai kiểu, ngoài khoảng, số lẻ ở ô số nguyên, lựa chọn lạ: 422.
func TestGameSettingsRejected(t *testing.T) {
	for _, in := range []map[string]any{
		{"bogus": true},
		{"kmOff": "yes"},
		{"extraWolves": 3.0},
		{"extraWolves": 0.5},
		{"seerKm": -1.0},
		{"seerKm": 21.0},
		{"kmPerUnit": 0.0},
		{"vote": "double"},
		{"vote": 1.0},
		{"skillKm": 2.0},
		{"villageGate": true},
		{"maxHang": 4.0},
		{"topOn": true, "topWeight": 6.0},
		{"kmOff": true, "roundHours": 5.0},
		{"kmOff": true, "roundsPerDay": 7.0},
		{"kmOff": true, "startHour": 24.0},
	} {
		var gc ww.Config
		err := applyGameSettings(&gc, in)
		if he, ok := err.(*HTTPError); !ok || he.Status != 422 || he.Code != "invalid_setting" {
			t.Fatalf("%v: lỗi = %v, mong đợi 422 invalid_setting", in, err)
		}
	}
}

// Mỗi tuỳ chọn có tên và mô tả để người tạo ván biết nó làm gì; ô lựa chọn có
// mô tả từng lựa chọn; điều kiện bật chỉ trỏ tới key có thật.
func TestGameSettingsSchemaDescribed(t *testing.T) {
	keys := map[string]bool{}
	for _, s := range gameCreateSettings() {
		keys[s.Key] = true
	}
	seen, section := map[string]bool{}, map[string]string{}
	for _, s := range gameCreateSettings() {
		if s.Label == "" || s.Description == "" {
			t.Fatalf("%s thiếu tên hoặc mô tả", s.Key)
		}
		for _, c := range s.Choices {
			if c.Label == "" || c.Description == "" {
				t.Fatalf("%s/%v thiếu tên hoặc mô tả", s.Key, c.Value)
			}
		}
		for _, c := range s.EnabledIf {
			if !keys[c.Key] {
				t.Fatalf("%s phụ thuộc key lạ %s", s.Key, c.Key)
			}
		}
		// Thẻ cha phải cùng khối và đứng trước để app lồng dòng con vào được.
		if s.Parent != "" && (!seen[s.Parent] || section[s.Parent] != s.Section || s.Section == "") {
			t.Fatalf("%s có thẻ cha %s không đứng trước trong cùng khối", s.Key, s.Parent)
		}
		seen[s.Key], section[s.Key] = true, s.Section
		// Giá trị mặc định phải qua được chính bước kiểm của nó.
		var gc ww.Config
		if err := applyGameSettings(&gc, map[string]any{s.Key: s.Default}); err != nil {
			t.Fatalf("%s: mặc định %v bị từ chối: %v", s.Key, s.Default, err)
		}
	}
}
