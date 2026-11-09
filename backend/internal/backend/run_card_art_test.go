package backend

import (
	"bytes"
	"image"
	"image/jpeg"
	"image/png"
	"strings"
	"testing"
	"time"
)

func TestRunCardArtBudgetFieldDefaultsToTenUsd(t *testing.T) {
	f, ok := agentConfigFieldByKey("runCardArtDailyBudgetUsd")
	if !ok || f.Default != 10 || f.Kind != "number" {
		t.Fatalf("field trần vẽ thẻ = %+v", f)
	}
	if c := parseBudgetConfig(nil, runCardArtPool); c.dailyUsd != 10 {
		t.Fatalf("chưa đặt thì trần là %v, muốn 10", c.dailyUsd)
	}
	if c := parseBudgetConfig(map[string]any{"runCardArtDailyBudgetUsd": 0.0}, runCardArtPool); c.dailyUsd != 0 {
		t.Fatalf("đặt 0 là bỏ trần, được %v", c.dailyUsd)
	}
	// Trần của bot cá nhân không đọc nhầm field của thẻ.
	if c := parseAgentBudgetConfig(map[string]any{"runCardArtDailyBudgetUsd": 5.0}); c.dailyUsd != 0 {
		t.Fatalf("trần bot cá nhân = %v, muốn 0", c.dailyUsd)
	}
}

func TestRunCardArtPromptWithoutPhoto(t *testing.T) {
	s, _ := artStyleFor("linocut", artKindRun)
	got := runCardArtPrompt(map[string]any{"sportType": "TrailRun", "startedAt": "2026-10-24T11:30:00Z", "distanceMeters": 2500.0, "name": "Chạy với crush"}, s, false, "")
	want := "Create an image: a single full-bleed scene of a lone runner in mid-stride on a winding forest trail at dusk, capturing the feeling of a short, brisk run. " +
		"Render it as a linocut print: bold carved black lines, white gouge marks, high contrast and one accent color. " +
		"Vertical composition. The runner fills the middle of the frame; the top fifth is calm, open background and the bottom quarter is quiet, low-detail ground. " + artConstraintsBlock
	if got != want {
		t.Fatalf("prompt\n got %q\nwant %q", got, want)
	}
}

func TestRunCardArtPromptPutsTheRunnerNoteBeforeTheStyle(t *testing.T) {
	s, _ := artStyleFor("linocut", artKindRun)
	got := runCardArtPrompt(map[string]any{"sportType": "Run", "startedAt": "2026-10-24T23:00:00Z", "distanceMeters": 5000.0}, s, false, `mặc áo "đỏ", có chú chó chạy cùng`)
	want := "Create an image: a single full-bleed scene of a lone runner in mid-stride along a quiet open road in the early morning light, capturing the feeling of a steady run. " +
		"Extra details from the runner, used only where they fit the art style below: \"mặc áo 'đỏ', có chú chó chạy cùng\". " +
		"Render it as a linocut print: bold carved black lines, white gouge marks, high contrast and one accent color. "
	if !strings.HasPrefix(got, want) || !strings.HasSuffix(got, artConstraintsBlock) {
		t.Fatalf("prompt\n got %q\nwant prefix %q", got, want)
	}
	photo := runCardArtPrompt(map[string]any{}, s, true, "thêm cầu vồng")
	if !strings.Contains(photo, "if there is no person, keep the main subject and layout. Extra details from the runner, used only where they fit the art style below: \"thêm cầu vồng\". Render it as") {
		t.Fatalf("prompt có ảnh = %q", photo)
	}
}

func TestRunCardArtPromptWithPhotoKeepsPeopleRecognizable(t *testing.T) {
	s, _ := artStyleFor("linocut", artKindRun)
	got := runCardArtPrompt(map[string]any{"sportType": "Run", "startedAt": "2026-10-24T23:00:00Z", "distanceMeters": 42195.0}, s, true, "")
	if !strings.HasPrefix(got, "Transform the provided photograph") || !strings.Contains(got, "recognizable") || strings.Contains(got, "runner in mid-stride") {
		t.Fatalf("prompt = %q", got)
	}
}

func TestRunCardTimeOfDayUsesVietnamHour(t *testing.T) {
	cases := map[string]string{
		"2026-10-24T20:59:00Z": "at night under streetlights", // 3h59 VN
		"2026-10-24T21:00:00Z": "at dawn",                     // 4h VN
		"2026-10-24T23:00:00Z": "in the early morning light",  // 6h VN
		"2026-10-25T03:00:00Z": "in bright midday sun",        // 10h VN
		"2026-10-25T08:00:00Z": "in warm late-afternoon light",
		"2026-10-25T11:00:00Z": "at dusk",
		"2026-10-25T13:00:00Z": "at night under streetlights", // 20h VN
	}
	for at, want := range cases {
		started, _ := time.Parse(time.RFC3339, at)
		if got := runCardTimeOfDay(started); got != want {
			t.Errorf("%s: %q, muốn %q", at, got, want)
		}
	}
	if got := runCardTimeOfDay(time.Time{}); got != "in soft daylight" {
		t.Errorf("không có giờ: %q", got)
	}
}

func plainJPEG(t *testing.T, w, h int) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, w, h))
	for i := range img.Pix {
		img.Pix[i] = 200
	}
	var out bytes.Buffer
	if err := jpeg.Encode(&out, img, nil); err != nil {
		t.Fatal(err)
	}
	return out.Bytes()
}

// Tranh được khoe cho người khác nên không được mang theo EXIF của ảnh gốc.
func TestRunCardPlainImageDropsMetadata(t *testing.T) {
	src := plainJPEG(t, 6, 9)
	payload := []byte("Exif\x00\x00GPS-10.77,106.70")
	app1 := append([]byte{0xFF, 0xE1, 0, byte(len(payload) + 2)}, payload...)
	withExif := append(append(append([]byte{}, src[:2]...), app1...), src[2:]...)

	out, err := runCardPlainImage(withExif)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(out, []byte("GPS-10.77")) {
		t.Fatal("tranh còn giữ EXIF của ảnh gốc")
	}
	img, err := png.Decode(bytes.NewReader(out))
	if err != nil {
		t.Fatalf("tranh phải là PNG: %v", err)
	}
	if b := img.Bounds(); b.Dx() != 6 || b.Dy() != 9 {
		t.Fatalf("tranh %dx%d, muốn 6x9", b.Dx(), b.Dy())
	}
}

func TestRunCardPlainImageRejectsBadInput(t *testing.T) {
	if _, err := runCardPlainImage([]byte("không phải ảnh")); err == nil {
		t.Fatal("file không phải ảnh phải bị từ chối")
	}
	// 2049 x 1: nhỏ vài byte mà vượt cạnh tối đa 2048.
	var huge bytes.Buffer
	if err := png.Encode(&huge, image.NewGray(image.Rect(0, 0, 2049, 1))); err != nil {
		t.Fatal(err)
	}
	if _, err := runCardPlainImage(huge.Bytes()); err == nil {
		t.Fatal("ảnh quá cạnh tối đa phải bị từ chối")
	}
	var edge bytes.Buffer
	if err := png.Encode(&edge, image.NewGray(image.Rect(0, 0, 2048, 1))); err != nil {
		t.Fatal(err)
	}
	if _, err := runCardPlainImage(edge.Bytes()); err != nil {
		t.Fatalf("ảnh đúng cạnh tối đa phải qua: %v", err)
	}
}
