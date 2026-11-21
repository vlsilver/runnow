package backend

import (
	"slices"
	"testing"

	"google.golang.org/genai"
)

// BOT_IMAGES tắt thì 3i không có client ảnh, và model không được mời gọi
// generate_image ở cả group lẫn chat riêng.
func TestBotImageToolFollowsImageClient(t *testing.T) {
	has := func(s *BotService, private bool) bool {
		return slices.ContainsFunc(s.toolDeclarations(private)[0].FunctionDeclarations, func(d *genai.FunctionDeclaration) bool {
			return d.Name == "generate_image"
		})
	}
	for _, private := range []bool{false, true} {
		if has(&BotService{}, private) {
			t.Errorf("private=%v: không có client ảnh mà vẫn có generate_image", private)
		}
		if !has(&BotService{imageGenai: &genai.Client{}}, private) {
			t.Errorf("private=%v: có client ảnh mà mất generate_image", private)
		}
	}
}
