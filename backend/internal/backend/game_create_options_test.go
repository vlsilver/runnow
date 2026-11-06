package backend

import (
	"reflect"
	"slices"
	"strings"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Kiểu ván dựng sẵn nào cũng tạo được ván hợp lệ, và đúng một kiểu là mặc định.
func TestGameCreatePresetsValid(t *testing.T) {
	opts := gameCreateOptions()
	if len(opts.Presets) == 0 {
		t.Fatal("không có kiểu ván dựng sẵn")
	}
	defaults := 0
	for _, p := range opts.Presets {
		if p.Default {
			defaults++
		}
		if p.Key == "" || p.Label == "" || p.Summary == "" || len(p.Details) == 0 {
			t.Fatalf("kiểu %q thiếu tên, mô tả hay chi tiết", p.Key)
		}
		gc := ww.Config{}
		for role, on := range p.Roles {
			if !slices.Contains(toggleRoles, ww.Role(role)) {
				t.Fatalf("kiểu %q bật tắt vai lạ %q", p.Key, role)
			}
			if !on {
				gc.Disabled = append(gc.Disabled, ww.Role(role))
			}
		}
		if err := applyGameSettings(&gc, p.Settings); err != nil {
			t.Fatalf("kiểu %q: %v", p.Key, err)
		}
		if err := gc.Validate(); err != nil {
			t.Fatalf("kiểu %q: %v", p.Key, err)
		}
	}
	if defaults != 1 {
		t.Fatalf("có %d kiểu mặc định, mong đợi 1", defaults)
	}
}

// Kiểu Cổ điển tắt km; Chạy bung thêm Già làng, x2 phiếu và 2 km kỹ năng.
func TestGameCreatePresetValues(t *testing.T) {
	byKey := map[string]GamePreset{}
	for _, p := range gameCreateOptions().Presets {
		byKey[p.Key] = p
	}
	var classic ww.Config
	if err := applyGameSettings(&classic, byKey["classic"].Settings); err != nil || !classic.KmOff {
		t.Fatalf("Cổ điển = %+v, %v", classic, err)
	}
	var hard ww.Config
	if err := applyGameSettings(&hard, byKey["hard"].Settings); err != nil {
		t.Fatal(err)
	}
	if !slices.Contains(hard.Extended, ww.Elder) || hard.Vote != ww.VoteTop || hard.SkillKm[ww.Seer] != 2 || hard.SkillKm[ww.Hunter] != 2 {
		t.Fatalf("Chạy bung = %+v", hard)
	}
}

// Tuỳ chọn có nhóm thì nhóm đó phải có; mỗi tab có ít nhất một tuỳ chọn, trừ
// tab Vòng chơi chỉ cần lịch vòng.
func TestGameCreateGroups(t *testing.T) {
	opts := gameCreateOptions()
	groups := map[string]int{}
	for _, g := range opts.Groups {
		if g.Key == "" || g.Label == "" {
			t.Fatalf("nhóm thiếu key hoặc tên: %+v", g)
		}
		groups[g.Key] = 0
	}
	for _, s := range opts.Settings {
		if s.Group == "" {
			continue
		}
		if _, ok := groups[s.Group]; !ok {
			t.Fatalf("%s ở nhóm lạ %q", s.Key, s.Group)
		}
		groups[s.Group]++
	}
	for k, n := range groups {
		if n == 0 && k != "round" {
			t.Fatalf("nhóm %q không có tuỳ chọn nào", k)
		}
	}
}

// Lịch một vòng gốc (bảng 1.3): đêm 22h–0h, rạng sáng 0h–10h, ngày 10h–20h,
// biểu quyết 20h–22h; nhắc đề cử 18h, nhắc biểu quyết 21h. Tính theo giờ kể từ
// 22h mở đêm.
func TestGameCreateRoundPlan(t *testing.T) {
	round := gameCreateOptions().Round
	var bounds [][2]float64
	for _, p := range round.Phases {
		if p.Label == "" || p.Description == "" {
			t.Fatalf("pha %q thiếu tên hoặc mô tả", p.Key)
		}
		bounds = append(bounds, [2]float64{p.From, p.To})
	}
	if want := [][2]float64{{0, 2}, {2, 12}, {12, 22}, {22, 24}}; !reflect.DeepEqual(bounds, want) {
		t.Fatalf("pha = %v, mong đợi %v", bounds, want)
	}
	var marks []float64
	for _, m := range round.Reminders {
		marks = append(marks, m.At)
	}
	if want := []float64{20, 23}; !reflect.DeepEqual(marks, want) {
		t.Fatalf("giờ nhắc = %v, mong đợi %v", marks, want)
	}
	if round.Start == "" {
		t.Fatal("thiếu câu ván bắt đầu thế nào")
	}
}

// Vai bật tắt được có mô tả, đã thay hết chữ giờ.
func TestGameCreateRoleDescriptions(t *testing.T) {
	for _, r := range gameCreateOptions().Roles {
		if r.Description == "" || strings.Contains(r.Description, "{") {
			t.Fatalf("vai %s: mô tả %q", r.Key, r.Description)
		}
	}
}
