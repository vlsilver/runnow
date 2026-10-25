package backend

import (
	"slices"
	"strings"
)

// Thư viện phong cách vẽ dùng chung cho mọi loại thẻ có tranh AI (thẻ buổi
// chạy trước, Ma Sói và bot sau). Danh sách nằm ở backend chứ không ở app:
// thêm, tắt hay sửa prompt một phong cách chỉ cần deploy backend, app vẽ theo
// danh sách GET /v1/art-styles trả.
//
// Prompt ráp từ bốn khối: việc cần vẽ (dựng từ dữ liệu thẻ), khối phong cách,
// khối bố cục cố định theo loại thẻ, khối ràng buộc dùng chung. Tranh chỉ là
// nền bên trong thẻ; khung, bậc, chữ và số app tự vẽ đè lên, nên khối ràng buộc
// cấm chữ, số và khung.
//
// Sửa Medium hay Traits của một phong cách thì tăng Version: thẻ lưu
// key@version cùng prompt đã dùng, để biết tranh cũ vẽ bằng bản prompt nào.
// Không ghi tên studio hay hoạ sĩ vào prompt.

type artKind string

const (
	artKindRun      artKind = "run"
	artKindWerewolf artKind = "werewolf"
	artKindBot      artKind = "bot"
)

type artStyle struct {
	Key     string
	Version int
	// Name là tên hiện trên app.
	Name   string
	Family string
	// Medium và Traits là tiếng Anh, ráp thành "Render it as {Medium}: {Traits}."
	Medium string
	Traits string
	// Fits là các loại thẻ phong cách này hợp; loại khác không thấy nó.
	Fits []artKind
	// Swatch là ba màu cho ô chọn trên app khi chưa có ảnh mẫu, và làm nền
	// lúc ảnh mẫu đang tải.
	Swatch []string
	// Example là đường dẫn Storage của ảnh mẫu dưới artExampleDir; rỗng thì
	// app chỉ vẽ Swatch.
	Example string
	// Off tắt phong cách: không hiện trên app, không nhận lượt vẽ mới. Thẻ đã
	// vẽ bằng nó vẫn giữ tranh.
	Off bool
}

// artExampleDir chứa ảnh mẫu của các phong cách. 3i tự upload, mọi user đã
// đăng nhập đọc được (storage.rules).
const artExampleDir = "artStyles/examples/"

func (s artStyle) fits(kind artKind) bool { return slices.Contains(s.Fits, kind) }

type artFamily struct {
	Key   string `json:"key"`
	Label string `json:"label"`
}

var artFamilies = []artFamily{
	{"anime", "Anime & manga"}, {"paint", "Hội hoạ"}, {"vn", "Việt Nam & Á Đông"},
	{"print", "In ấn & đồ hoạ"}, {"game", "Digital & game"}, {"craft", "Thủ công & 3D"}, {"photo", "Ảnh chụp"},
}

var artStyles = []artStyle{
	{Key: "anime_cel", Version: 1, Name: "Anime cel", Family: "anime", Medium: "a cel-shaded anime illustration", Traits: "flat cel shading, crisp clean ink outlines, saturated colors, hard-edged shadows and a bright gradient sky", Fits: []artKind{artKindRun, artKindWerewolf, artKindBot}, Swatch: []string{"#7cc8ff", "#ffd6f0", "#2b3a67"}},
	{Key: "anime_scenic_light", Version: 1, Name: "Anime phong cảnh", Family: "anime", Medium: "a scenic anime background painting", Traits: "lush richly painted scenery, luminous towering clouds, soft lens glow and light shafts, a vivid blue-to-gold dusk", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#3a7bd5", "#ffd27a", "#f39c6b"}},
	{Key: "watercolor_anime_pastoral", Version: 1, Name: "Anime đồng quê", Family: "anime", Medium: "a hand-painted pastoral anime illustration", Traits: "soft watercolor backgrounds in pastel greens and sky blues, thin character outlines with simple two-tone shading, towering cumulus clouds and warm nostalgic light", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#9fd8b0", "#bfe3ff", "#fff1c9"}},
	{Key: "manga_ink", Version: 1, Name: "Manga đen trắng", Family: "anime", Medium: "a black-and-white manga panel drawing", Traits: "black ink linework, screentone dot shading, speed lines and stark white highlights", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#f4f2ec", "#8a8a8a", "#111111"}},
	{Key: "action_anime", Version: 1, Name: "Anime hành động", Family: "anime", Medium: "a dynamic action anime illustration", Traits: "dramatic foreshortening, bold motion lines, high-contrast rim light and a glowing energy aura", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#ff5a36", "#ffd23f", "#1b1f3b"}},
	{Key: "chibi", Version: 1, Name: "Chibi", Family: "anime", Medium: "a cute chibi illustration", Traits: "super-deformed two-to-three-head proportions, huge sparkling eyes, thick rounded outlines and a candy pastel palette", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#ffb3d1", "#b8f2e6", "#fff3b0"}, Example: artExampleDir + "chibi.jpg"},
	{Key: "shoujo_sparkle", Version: 1, Name: "Shoujo lấp lánh", Family: "anime", Medium: "a romantic shoujo illustration", Traits: "delicate thin lines, pastel pinks and lilacs, floral bokeh, soft sparkles and glow", Fits: []artKind{artKindBot}, Swatch: []string{"#f7c6e0", "#d4c1ff", "#ffffff"}},
	{Key: "oil_impasto", Version: 1, Name: "Sơn dầu impasto", Family: "paint", Medium: "a thick impasto oil painting", Traits: "heavy palette-knife strokes, rich saturated pigment, visible canvas texture and warm directional light", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#a8532a", "#e9b84f", "#2f4858"}, Example: artExampleDir + "oil_impasto.jpg"},
	{Key: "impressionist", Version: 1, Name: "Ấn tượng", Family: "paint", Medium: "an impressionist plein-air painting", Traits: "short broken brushstrokes, dappled outdoor sunlight, soft edges and vibrating complementary colors", Fits: []artKind{artKindRun}, Swatch: []string{"#9bc4e2", "#f6d186", "#7fb069"}, Example: artExampleDir + "impressionist.jpg"},
	{Key: "swirl_post_impressionist", Version: 1, Name: "Hậu ấn tượng xoáy", Family: "paint", Medium: "a post-impressionist painting with swirling strokes", Traits: "rhythmic swirling brushstrokes, deep cobalt and chrome yellow, outlined forms and a glowing starry sky", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#1f3c88", "#f4c430", "#5d8aa8"}, Example: artExampleDir + "swirl_post_impressionist.jpg"},
	{Key: "watercolor_loose", Version: 1, Name: "Màu nước", Family: "paint", Medium: "a loose watercolor painting", Traits: "wet-on-wet blooms, transparent washes, white paper showing through and soft bleeding edges", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#c9e4f0", "#f4d3c4", "#ffffff"}, Example: artExampleDir + "watercolor_loose.jpg"},
	{Key: "gouache_storybook", Version: 1, Name: "Gouache sách thiếu nhi", Family: "paint", Medium: "a gouache children's storybook illustration", Traits: "opaque matte flat shapes, chalky texture, a limited five-to-six color palette and cozy soft light", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#e07a5f", "#81b29a", "#f2cc8f"}, Example: artExampleDir + "gouache_storybook.jpg"},
	{Key: "classical_baroque", Version: 1, Name: "Cổ điển Baroque", Family: "paint", Medium: "a classical baroque oil painting", Traits: "dramatic chiaroscuro from a single light source, deep velvety shadows, glazed oil layers with fine craquelure", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#3b2a1a", "#c9a227", "#0d0d0d"}},
	{Key: "art_nouveau", Version: 1, Name: "Art Nouveau", Family: "paint", Medium: "an art nouveau decorative illustration", Traits: "flowing organic whiplash lines, muted gold, sage and cream, ornamental floral motifs", Fits: []artKind{artKindWerewolf, artKindBot}, Swatch: []string{"#c9b37e", "#9caf88", "#f3ead3"}},
	{Key: "chalk_pastel", Version: 1, Name: "Phấn tiên", Family: "paint", Medium: "a soft chalk pastel drawing", Traits: "powdery soft blending on toned paper, visible paper tooth and gentle hazy light", Fits: []artKind{artKindRun}, Swatch: []string{"#e8c7a0", "#a7c5eb", "#6d6875"}, Example: artExampleDir + "chalk_pastel.jpg"},
	{Key: "fauvist", Version: 1, Name: "Dã thú", Family: "paint", Medium: "a fauvist painting", Traits: "wild non-natural colors, bold flat color areas and loose expressive brushwork", Fits: []artKind{artKindRun}, Swatch: []string{"#ff006e", "#ffbe0b", "#3a86ff"}, Example: artExampleDir + "fauvist.jpg"},
	{Key: "pointillist", Version: 1, Name: "Chấm điểm", Family: "paint", Medium: "a pointillist painting", Traits: "tiny dots of pure color optically mixing and a bright sunlit palette", Fits: []artKind{artKindRun}, Swatch: []string{"#ffd166", "#06d6a0", "#118ab2"}, Example: artExampleDir + "pointillist.jpg"},
	{Key: "dong_ho_woodblock", Version: 1, Name: "Tranh Đông Hồ", Family: "vn", Medium: "a Vietnamese Dong Ho folk woodblock print", Traits: "printed on do paper with a shimmering seashell ground, flat earthy natural pigments of cinnabar red, ochre yellow and charcoal black, bold black outlines and naive folk figures", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#c0392b", "#e1b12c", "#f5ecd7"}, Example: artExampleDir + "dong_ho_woodblock.jpg"},
	{Key: "hang_trong", Version: 1, Name: "Tranh Hàng Trống", Family: "vn", Medium: "a Vietnamese Hang Trong folk painting", Traits: "fine woodblock outlines hand-colored with soft gradients in bright pinks, blues and greens, elegant decorative folk figures", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#e84393", "#0984e3", "#00b894"}},
	{Key: "kim_hoang", Version: 1, Name: "Tranh Kim Hoàng", Family: "vn", Medium: "a Vietnamese Kim Hoang folk print", Traits: "woodblock linework on bright vermilion paper, black ink with green and yellow accents, festive folk motifs", Fits: []artKind{artKindRun}, Swatch: []string{"#e63946", "#2a9d8f", "#ffd166"}},
	{Key: "son_mai_lacquer", Version: 1, Name: "Sơn mài", Family: "vn", Medium: "a Vietnamese lacquer painting", Traits: "deep black and cinnabar-red lacquer layers, gold and silver leaf highlights, crushed eggshell inlay and a glossy polished depth", Fits: []artKind{artKindRun, artKindWerewolf, artKindBot}, Swatch: []string{"#0b0b0b", "#b22222", "#d4af37"}},
	{Key: "tranh_lua_silk", Version: 1, Name: "Tranh lụa", Family: "vn", Medium: "a Vietnamese silk painting", Traits: "ink and translucent watercolor on silk, muted soft tones, visible silk weave and serene elongated figures", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#d8cbb3", "#9fb8ad", "#6b705c"}},
	{Key: "ink_wash", Version: 1, Name: "Thuỷ mặc", Family: "vn", Medium: "an East Asian ink wash painting", Traits: "monochrome ink with varied tonality, expressive single brushstrokes and vast misty empty space", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#f4f1ea", "#7d7d7d", "#1a1a1a"}, Example: artExampleDir + "ink_wash.jpg"},
	{Key: "ukiyo_e", Version: 1, Name: "Ukiyo-e", Family: "vn", Medium: "an Edo-era Japanese woodblock print", Traits: "flat color fields, bold contours, Prussian blue, stylized waves and clouds and visible paper grain", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#1d3557", "#f1faee", "#e76f51"}, Example: artExampleDir + "ukiyo_e.jpg"},
	{Key: "gongbi", Version: 1, Name: "Công bút", Family: "vn", Medium: "a meticulous gongbi court painting", Traits: "fine-line detail, mineral azurite and malachite pigments on silk", Fits: []artKind{artKindBot}, Swatch: []string{"#2a6f97", "#52b788", "#efe6d2"}},
	{Key: "cham_relief", Version: 1, Name: "Phù điêu Chăm", Family: "vn", Medium: "a carved Cham temple relief", Traits: "red brick and sandstone carving, warm terracotta, weathered surface and raking sunlight", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#b5651d", "#d9a066", "#5c3d2e"}},
	{Key: "dinh_wood_carving", Version: 1, Name: "Chạm gỗ đình làng", Family: "vn", Medium: "a carved Vietnamese village temple wood relief", Traits: "jackfruit wood in warm honey browns, folk figures and dragons, soft temple light", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#8b5a2b", "#d4a373", "#3e2723"}},
	{Key: "brocade_textile", Version: 1, Name: "Hoa văn thổ cẩm", Family: "vn", Medium: "a woven highland brocade textile", Traits: "indigo, red and saffron geometric motifs and tactile thread texture", Fits: []artKind{artKindBot}, Swatch: []string{"#283c86", "#c0392b", "#f39c12"}},
	{Key: "risograph", Version: 1, Name: "In Riso", Family: "print", Medium: "a risograph print", Traits: "two to three spot inks of fluorescent pink, teal and yellow, slight misregistration and grainy halftone", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#ff48b0", "#00a5a8", "#ffe800"}},
	{Key: "linocut", Version: 1, Name: "Khắc lino", Family: "print", Medium: "a linocut print", Traits: "bold carved black lines, white gouge marks, high contrast and one accent color", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#111111", "#f4f2ec", "#d62828"}, Example: artExampleDir + "linocut.jpg"},
	{Key: "pop_art_dots", Version: 1, Name: "Pop art chấm", Family: "print", Medium: "a pop art print", Traits: "Ben-Day dots, flat primary colors, thick black outlines and punchy contrast", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#ffd60a", "#e63946", "#1d4ed8"}},
	{Key: "vintage_travel_poster", Version: 1, Name: "Poster du lịch cổ", Family: "print", Medium: "a vintage travel poster illustration", Traits: "flat gradients, a simplified geometric landscape, a warm sunset palette and lithograph texture", Fits: []artKind{artKindRun}, Swatch: []string{"#f4a261", "#e76f51", "#264653"}, Example: artExampleDir + "vintage_travel_poster.jpg"},
	{Key: "flat_vector", Version: 1, Name: "Vector phẳng", Family: "print", Medium: "a flat vector illustration", Traits: "clean geometric shapes with no outlines, a limited harmonious palette and subtle gradients", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#4cc9f0", "#f72585", "#3a0ca3"}, Example: artExampleDir + "flat_vector.jpg"},
	{Key: "art_deco", Version: 1, Name: "Art Deco", Family: "print", Medium: "an art deco illustration", Traits: "symmetric geometric forms, gold on black, sunburst rays and streamlined elegance", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#0b0b0b", "#d4af37", "#1f3b4d"}},
	{Key: "western_comic", Version: 1, Name: "Truyện tranh Âu Mỹ", Family: "print", Medium: "a western comic book illustration", Traits: "bold inks, flat colors, halftone shading and dramatic low angles", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#ffd23f", "#e8443a", "#1d3557"}, Example: artExampleDir + "western_comic.jpg"},
	{Key: "noir_ink", Version: 1, Name: "Noir đen trắng", Family: "print", Medium: "a noir ink illustration", Traits: "high-contrast black and white, heavy cast shadows, rain and a single red accent", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#000000", "#f4f2ec", "#c1121f"}},
	{Key: "stained_glass", Version: 1, Name: "Kính màu", Family: "print", Medium: "a stained glass window artwork", Traits: "thick dark lead lines, jewel-tone translucent glass and a backlit glow", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#1d3557", "#e63946", "#ffb703"}},
	{Key: "sticker_diecut", Version: 1, Name: "Sticker", Family: "print", Medium: "a die-cut sticker illustration", Traits: "a thick white outline around the subject, bold clean lines, simple cel shading and vibrant colors", Fits: []artKind{artKindBot}, Swatch: []string{"#ffffff", "#ff6b6b", "#4ecdc4"}},
	{Key: "one_line", Version: 1, Name: "Nét liền tối giản", Family: "print", Medium: "a minimalist single-line drawing", Traits: "one continuous line, a single accent color wash and generous empty space", Fits: []artKind{artKindBot}, Swatch: []string{"#f4f2ec", "#111111", "#e76f51"}},
	{Key: "pixel_16bit", Version: 1, Name: "Pixel art 16-bit", Family: "game", Medium: "a 16-bit pixel art scene", Traits: "visible square pixels, a limited palette, dithering and a side-view retro game look", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#2b2d42", "#ef233c", "#8ecae6"}, Example: artExampleDir + "pixel_16bit.jpg"},
	{Key: "isometric_diorama", Version: 1, Name: "Sa bàn isometric", Family: "game", Medium: "an isometric miniature diorama", Traits: "a 45-degree isometric cartoon 3D scene, soft materials, gentle shadows and a solid-color backdrop", Fits: []artKind{artKindRun}, Swatch: []string{"#a8dadc", "#f1faee", "#457b9d"}},
	{Key: "low_poly", Version: 1, Name: "Low poly", Family: "game", Medium: "a low-poly 3D illustration", Traits: "faceted triangle geometry, flat shading and a smooth gradient sky", Fits: []artKind{artKindRun}, Swatch: []string{"#ff9f1c", "#2ec4b6", "#011627"}},
	{Key: "synthwave", Version: 1, Name: "Synthwave", Family: "game", Medium: "a synthwave illustration", Traits: "neon magenta and cyan, a glowing grid horizon, a chrome sunset and night haze", Fits: []artKind{artKindRun}, Swatch: []string{"#ff00c8", "#00e5ff", "#1a0033"}},
	{Key: "neon_cyber_city", Version: 1, Name: "Thành phố neon", Family: "game", Medium: "a neon-lit futuristic city scene", Traits: "rain-slick streets, teal and orange neon glow, reflections and a dense skyline", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#00b4d8", "#ff7b00", "#03045e"}},
	{Key: "fantasy_concept", Version: 1, Name: "Concept art fantasy", Family: "game", Medium: "a painterly fantasy concept art piece", Traits: "epic scale, volumetric god rays and deep atmospheric perspective", Fits: []artKind{artKindWerewolf}, Swatch: []string{"#2d3a4a", "#e9c46a", "#6a994e"}},
	{Key: "toon_3d_game", Version: 2, Name: "Game 3D cel-shade", Family: "game", Medium: "a screenshot from a cel-shaded 3D open-world video game", Traits: "stylized chunky 3D character and terrain models rendered in real time, soft toon lighting with thin outlines, a bright open-world palette and a clean sky", Fits: []artKind{artKindRun, artKindWerewolf}, Swatch: []string{"#80ed99", "#57cc99", "#38a3a5"}},
	{Key: "holo_foil", Version: 1, Name: "Hologram", Family: "game", Medium: "an iridescent holographic foil artwork", Traits: "prismatic rainbow sheen, metallic depth and shifting highlights", Fits: []artKind{artKindRun, artKindWerewolf, artKindBot}, Swatch: []string{"#ff9ad5", "#8ef0c9", "#7cc8ff"}},
	{Key: "claymation", Version: 1, Name: "Đất sét", Family: "craft", Medium: "a claymation scene", Traits: "handmade clay figures, fingerprint texture, soft rounded forms and studio softbox light", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#f4a261", "#e9c46a", "#2a9d8f"}, Example: artExampleDir + "claymation.jpg"},
	{Key: "animated_3d_feature", Version: 1, Name: "Hoạt hình 3D", Family: "craft", Medium: "a stylized 3D animated film still", Traits: "soft subsurface skin, big expressive eyes and warm bounce light", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#ffb4a2", "#6d6875", "#b5838d"}},
	{Key: "papercut_layers", Version: 1, Name: "Cắt giấy nhiều lớp", Family: "craft", Medium: "a layered papercut artwork", Traits: "stacked cut paper with soft drop shadows between layers and craft paper texture", Fits: []artKind{artKindRun}, Swatch: []string{"#ffcdb2", "#e5989b", "#6d6875"}},
	{Key: "needle_felt", Version: 1, Name: "Len chọc", Family: "craft", Medium: "a needle-felted wool miniature", Traits: "fuzzy wool fibers, soft miniature forms and cozy diffuse light", Fits: []artKind{artKindBot}, Swatch: []string{"#ddbea9", "#a5a58d", "#6b705c"}},
	{Key: "embroidery", Version: 1, Name: "Thêu tay", Family: "craft", Medium: "a hand embroidery artwork", Traits: "satin and cross stitches on linen with visible thread sheen", Fits: []artKind{artKindBot}, Swatch: []string{"#f1e3d3", "#d62828", "#003049"}},
	{Key: "tiltshift_miniature", Version: 1, Name: "Mô hình thu nhỏ", Family: "craft", Medium: "a tilt-shift miniature photograph", Traits: "a toy-town look, very shallow depth of field, saturated colors and bright sun", Fits: []artKind{artKindRun}, Swatch: []string{"#90be6d", "#f9c74f", "#577590"}, Example: artExampleDir + "tiltshift_miniature.jpg"},
	{Key: "ceramic_mosaic", Version: 1, Name: "Khảm gốm", Family: "craft", Medium: "a ceramic mosaic artwork", Traits: "glazed ceramic shards, white grout lines, bright tile colors and a sunlit sheen", Fits: []artKind{artKindRun}, Swatch: []string{"#277da1", "#f9844a", "#f8f9fa"}, Example: artExampleDir + "ceramic_mosaic.jpg"},
	{Key: "cinematic_photo", Version: 1, Name: "Điện ảnh", Family: "photo", Medium: "a cinematic film still", Traits: "an anamorphic widescreen feel, a teal and orange grade, shallow depth of field and rim light", Fits: []artKind{artKindRun}, Swatch: []string{"#1b4965", "#ff9f68", "#0b1320"}},
	{Key: "analog_film", Version: 1, Name: "Film analog", Family: "photo", Medium: "an analog 35mm film photograph", Traits: "film grain, faded warm tones, soft light leaks and natural light", Fits: []artKind{artKindRun, artKindBot}, Swatch: []string{"#e9c46a", "#f4a261", "#8d99ae"}, Example: artExampleDir + "analog_film.jpg"},
}

// artStyleFor là phong cách đang bật, hợp với kind; ok false khi không có.
func artStyleFor(key string, kind artKind) (artStyle, bool) {
	i := slices.IndexFunc(artStyles, func(s artStyle) bool { return s.Key == key })
	if i < 0 || artStyles[i].Off || !artStyles[i].fits(kind) {
		return artStyle{}, false
	}
	return artStyles[i], true
}

// ArtStyleView là một phong cách trên màn chọn của app.
type ArtStyleView struct {
	Key     string   `json:"key"`
	Version int      `json:"version"`
	Name    string   `json:"name"`
	Family  string   `json:"family"`
	Swatch  []string `json:"swatch"`
	Example string   `json:"example,omitempty"`
}

type ArtStyleList struct {
	Families []artFamily    `json:"families"`
	Styles   []ArtStyleView `json:"styles"`
}

// ArtStyles là các phong cách đang bật cho kind, theo thứ tự nhóm rồi thứ tự
// trong danh sách. Nhóm không còn phong cách nào thì bỏ.
func ArtStyles(kind artKind) ArtStyleList {
	out := ArtStyleList{Families: []artFamily{}, Styles: []ArtStyleView{}}
	for _, f := range artFamilies {
		n := len(out.Styles)
		for _, s := range artStyles {
			if s.Family == f.Key && !s.Off && s.fits(kind) {
				out.Styles = append(out.Styles, ArtStyleView{Key: s.Key, Version: s.Version, Name: s.Name, Family: s.Family, Swatch: s.Swatch, Example: s.Example})
			}
		}
		if len(out.Styles) > n {
			out.Families = append(out.Families, f)
		}
	}
	return out
}

// parseArtKind nhận loại thẻ từ query. Hiện chỉ thẻ buổi chạy có tranh AI.
func parseArtKind(v string) (artKind, bool) {
	if artKind(v) == artKindRun {
		return artKindRun, true
	}
	return "", false
}

const artConstraintsBlock = "The artwork fills the whole canvas edge to edge as one continuous scene with no border, frame or panels. " +
	"Every surface, including signs, shirts, bibs and banners, is plain and unmarked, free of letters, numbers, logos and watermarks."

// artPrompt ráp prompt từ phần việc cần vẽ (task), phong cách, bố cục.
func artPrompt(task string, s artStyle, composition string) string {
	return strings.Join([]string{task, "Render it as " + s.Medium + ": " + s.Traits + ".", composition, artConstraintsBlock}, " ")
}
