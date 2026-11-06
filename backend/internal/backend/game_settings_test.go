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
