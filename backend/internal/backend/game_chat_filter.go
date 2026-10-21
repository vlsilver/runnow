package backend

import (
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"
)

// Từ tục bị che khi ghi tin chat (App Store 1.2 đòi có lọc nội dung). Chỉ so
// nguyên từ, viết thường, có dấu: bản không dấu như "lon", "cac", "dit" là từ
// thường nên không che. Danh sách cố ý ngắn; tin lọt lưới thì người chơi báo
// cáo, admin xử lý.
var profanity = map[string]bool{
	"địt": true, "đụ": true, "đéo": true, "lồn": true, "buồi": true, "cặc": true, "đĩ": true,
	"đm": true, "dm": true, "đmm": true, "dmm": true, "đcm": true, "dcm": true, "đkm": true,
	"vcl": true, "vkl": true, "vl": true, "clm": true, "cl": true, "cc": true,
	"fuck": true, "fucking": true, "shit": true, "bitch": true,
}

// maskProfanity thay mỗi từ tục bằng số dấu * bằng số ký tự của nó. Chữ được
// đưa về NFC trước, vì bàn phím có thể gửi dấu tách rời (NFD).
func maskProfanity(text string) string {
	text = norm.NFC.String(text)
	var b strings.Builder
	word := []rune{}
	flush := func() {
		if profanity[strings.ToLower(string(word))] {
			b.WriteString(strings.Repeat("*", len(word)))
		} else {
			b.WriteString(string(word))
		}
		word = word[:0]
	}
	for _, r := range text {
		if unicode.IsLetter(r) || unicode.IsDigit(r) || unicode.Is(unicode.Mn, r) {
			word = append(word, r)
			continue
		}
		flush()
		b.WriteRune(r)
	}
	flush()
	return b.String()
}
