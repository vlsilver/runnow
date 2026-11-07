package backend

import (
	"reflect"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Không gửi settings (app cũ) thì ván mới theo luật cũ, trừ sói cắn không cần
// km; km các vai vẫn theo KmPerUnit.
func TestGameSettingsDefaults(t *testing.T) {
	gc := ww.Config{KmPerUnit: 2}
	if err := applyGameSettings(&gc, nil); err != nil {
		t.Fatal(err)
	}
	want := ww.Config{KmPerUnit: 2, Vote: ww.VoteCut, SkillKm: map[ww.Role]float64{ww.Wolf: 0}}
	if !reflect.DeepEqual(gc, want) {
		t.Fatalf("config = %+v, mong đợi %+v", gc, want)
	}
}

func TestGameSettingsApplied(t *testing.T) {
	var gc ww.Config
	err := applyGameSettings(&gc, map[string]any{
		"extraWolves": 1.0, "wolfKm": 2.0, "seerKm": 0.0, "guardKm": 1.5, "witchKm": 3.0, "hunterKm": 1.0,
		"villageGate": true, "vote": "top", "kmPerUnit": 2.5, "topVoters": 4.0,
	})
	if err != nil {
		t.Fatal(err)
	}
	want := ww.Config{
		ExtraWolves: 1, KmPerUnit: 2.5, VillageGate: true, Vote: ww.VoteTop, TopVoters: 4,
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

// skillKm đặt một mức km cho cả bốn vai có kỹ năng; km riêng của vai gửi kèm
// thì thắng. Sói không theo skillKm.
func TestGameSettingsSkillKm(t *testing.T) {
	var gc ww.Config
	if err := applyGameSettings(&gc, map[string]any{"skillKm": 2.0, "witchKm": 0.5}); err != nil {
		t.Fatal(err)
	}
	want := map[ww.Role]float64{ww.Wolf: 0, ww.Seer: 2, ww.Guard: 2, ww.Witch: 0.5, ww.Hunter: 2}
	if !reflect.DeepEqual(gc.SkillKm, want) {
		t.Fatalf("SkillKm = %v, mong đợi %v", gc.SkillKm, want)
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
		// Giá trị mặc định phải qua được chính bước kiểm của nó.
		var gc ww.Config
		if err := applyGameSettings(&gc, map[string]any{s.Key: s.Default}); err != nil {
			t.Fatalf("%s: mặc định %v bị từ chối: %v", s.Key, s.Default, err)
		}
	}
}
