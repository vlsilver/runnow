package backend

import (
	"fmt"
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

// Kiểu Cổ điển tắt km; Chạy bung thêm Già làng, km Riêng, Top x2 phiếu và 2 km kỹ năng.
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
	if !slices.Contains(hard.Extended, ww.Elder) || hard.Vote != ww.VoteSolo || hard.TopWeight != 2 || hard.SkillKm[ww.Seer] != 2 || hard.SkillKm[ww.Hunter] != 2 {
		t.Fatalf("Chạy bung = %+v", hard)
	}
}

// App bản tab chỉ vẽ tuỳ chọn theo nhóm, nên tuỳ chọn nào cũng phải có nhóm và
// nhóm đó phải có; mỗi tab có ít nhất một tuỳ chọn, trừ tab Vòng chơi chỉ cần
// lịch vòng.
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
			t.Errorf("%s không có nhóm nên app không hiện", s.Key)
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
	// App kéo được từng pha qua ô setting của nó; giờ nhắc nằm ở 4/5 pha Ngày
	// và giữa pha Biểu quyết, nên chia lại pha thì giờ nhắc dời theo.
	var keys []string
	for _, p := range round.Phases {
		keys = append(keys, p.SettingKey)
	}
	if want := []string{"nightMin", "dawnMin", "dayMin", "trialMin"}; !reflect.DeepEqual(keys, want) {
		t.Fatalf("ô setting của pha = %v", keys)
	}
	var in []string
	for _, m := range round.Reminders {
		in = append(in, fmt.Sprintf("%s@%g", m.Phase, m.Frac))
	}
	if want := []string{"day@0.8", "trial@0.5"}; !reflect.DeepEqual(in, want) {
		t.Fatalf("giờ nhắc trong pha = %v", in)
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

// Tab Vai hiện bảng chia chuẩn theo số người (bảng 1.2) và tuỳ chọn số sói
// của bộ bài tự chỉnh.
func TestGameCreateDeck(t *testing.T) {
	deck := gameCreateOptions().Deck
	want := []GameDeckTier{{10, 10, 2, 2}, {11, 11, 3, 3}, {12, 12, 3, 4}, {13, 16, 3, 5}, {17, 20, 4, 5}, {21, 24, 5, 5}}
	if !reflect.DeepEqual(deck.Tiers, want) {
		t.Fatalf("bảng chia = %v, mong đợi %v", deck.Tiers, want)
	}
	if deck.Note == "" || deck.FixedNote == "" || deck.Preview != 12 {
		t.Fatalf("thiếu ghi chú hoặc số người xem trước: %+v", deck)
	}
	var gc ww.Config
	if err := applyGameSettings(&gc, map[string]any{deck.WolvesKey: 4.0}); err != nil || gc.Wolves != 4 {
		t.Fatalf("%s=4 → Wolves %d, %v", deck.WolvesKey, gc.Wolves, err)
	}
	gc = ww.Config{}
	if err := applyGameSettings(&gc, nil); err != nil || gc.Wolves != 0 {
		t.Fatalf("không gửi thì vẫn chia theo số người: Wolves %d, %v", gc.Wolves, err)
	}
}
