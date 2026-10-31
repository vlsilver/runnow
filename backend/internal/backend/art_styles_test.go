package backend

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestArtStylesRegistryIsConsistent(t *testing.T) {
	families := map[string]bool{}
	for _, f := range artFamilies {
		families[f.Key] = true
	}
	keys := map[string]bool{}
	for _, s := range artStyles {
		if keys[s.Key] {
			t.Errorf("trùng key %q", s.Key)
		}
		keys[s.Key] = true
		if !families[s.Family] {
			t.Errorf("%s: nhóm %q không có trong artFamilies", s.Key, s.Family)
		}
		if s.Version < 1 || s.Name == "" || s.Medium == "" || s.Traits == "" || len(s.Fits) == 0 || len(s.Swatch) != 3 {
			t.Errorf("%s: thiếu dữ liệu", s.Key)
		}
		// Rules Storage chỉ mở cho user đọc ảnh mẫu dưới thư mục này.
		if s.Example != "" && !strings.HasPrefix(s.Example, artExampleDir) {
			t.Errorf("%s: ảnh mẫu %q nằm ngoài %s", s.Key, s.Example, artExampleDir)
		}
		// Khối phong cách tự thêm dấu chấm cuối câu.
		if strings.HasSuffix(s.Traits, ".") {
			t.Errorf("%s: Traits không được kết bằng dấu chấm", s.Key)
		}
	}
	if len(artStyles) != 56 {
		t.Fatalf("có %d phong cách, muốn 56", len(artStyles))
	}
}

func TestArtStylesForRunListsOnlyFittingStylesByFamily(t *testing.T) {
	got := ArtStyles(artKindRun)
	// 39 phong cách có cờ R trong bảng nghiên cứu.
	if len(got.Styles) != 39 {
		t.Fatalf("thẻ chạy có %d phong cách, muốn 39", len(got.Styles))
	}
	if got.Styles[0].Key != "anime_cel" || got.Styles[len(got.Styles)-1].Key != "analog_film" {
		t.Fatalf("thứ tự sai: đầu %s, cuối %s", got.Styles[0].Key, got.Styles[len(got.Styles)-1].Key)
	}
	for _, s := range got.Styles {
		if s.Key == "manga_ink" || s.Key == "shoujo_sparkle" {
			t.Fatalf("%s không hợp thẻ chạy mà vẫn hiện", s.Key)
		}
	}
	if len(got.Families) != 7 {
		t.Fatalf("có %d nhóm, muốn 7", len(got.Families))
	}
}

func TestArtStylesHidesStyleThatIsOff(t *testing.T) {
	saved := artStyles
	t.Cleanup(func() { artStyles = saved })
	artStyles = []artStyle{
		{Key: "a", Version: 1, Family: "photo", Fits: []artKind{artKindRun}, Off: true},
		{Key: "b", Version: 1, Family: "photo", Fits: []artKind{artKindRun}},
	}
	got := ArtStyles(artKindRun)
	if len(got.Styles) != 1 || got.Styles[0].Key != "b" {
		t.Fatalf("styles = %+v, muốn chỉ b", got.Styles)
	}
	if _, ok := artStyleFor("a", artKindRun); ok {
		t.Fatal("phong cách đã tắt vẫn nhận lượt vẽ")
	}
	if _, ok := artStyleFor("b", artKindWerewolf); ok {
		t.Fatal("phong cách không hợp loại thẻ vẫn nhận lượt vẽ")
	}
}

func TestArtStylesSendExampleOnlyWhenThereIsOne(t *testing.T) {
	saved := artStyles
	t.Cleanup(func() { artStyles = saved })
	artStyles = []artStyle{
		{Key: "a", Version: 1, Family: "photo", Fits: []artKind{artKindRun}, Example: "artStyles/examples/a.jpg"},
		{Key: "b", Version: 1, Family: "photo", Fits: []artKind{artKindRun}},
	}
	b, err := json.Marshal(ArtStyles(artKindRun).Styles)
	if err != nil {
		t.Fatal(err)
	}
	want := `[{"key":"a","version":1,"name":"","family":"photo","swatch":null,"example":"artStyles/examples/a.jpg"},` +
		`{"key":"b","version":1,"name":"","family":"photo","swatch":null}]`
	if string(b) != want {
		t.Fatalf("view\n got %s\nwant %s", b, want)
	}
}

func TestArtPromptJoinsFourBlocks(t *testing.T) {
	s, ok := artStyleFor("linocut", artKindRun)
	if !ok {
		t.Fatal("thiếu linocut")
	}
	got := artPrompt("Create an image: a runner.", s, "Vertical composition.")
	want := "Create an image: a runner. Render it as a linocut print: bold carved black lines, white gouge marks, high contrast and one accent color. Vertical composition. " +
		"The artwork fills the whole canvas edge to edge as one continuous scene with no border, frame or panels. " +
		"Every surface, including signs, shirts, bibs and banners, is plain and unmarked, free of letters, numbers, logos and watermarks."
	if got != want {
		t.Fatalf("prompt\n got %q\nwant %q", got, want)
	}
}
