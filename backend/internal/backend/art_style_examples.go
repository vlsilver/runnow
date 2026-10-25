package backend

import (
	"context"
	"fmt"

	"google.golang.org/genai"
)

// Ảnh mẫu do model vẽ cho các phong cách không có tranh public domain. Lệnh
// migrations/art-style-examples vẽ một lần trên máy người chạy; người đó duyệt
// tay rồi upload vào artExampleDir và khai Example như ảnh public domain. Không
// qua trần chi phí vẽ thẻ vì người chạy lệnh tự quyết vẽ bao nhiêu.

// artExampleSnapshot là buổi chạy dựng sẵn cho ảnh mẫu: đường vắng, 6h30 sáng,
// 10 km. Ảnh mẫu dùng đúng prompt vẽ thẻ không ảnh, để user thấy gần đúng cái
// mình sẽ nhận.
var artExampleSnapshot = map[string]any{
	"sportType":      "Run",
	"startedAt":      "2026-10-25T06:30:00+07:00",
	"distanceMeters": 10000.0,
}

// ArtStylesMissingExample là key các phong cách đang bật của thẻ buổi chạy mà
// chưa có ảnh mẫu, theo thứ tự trong danh sách.
func ArtStylesMissingExample() []string {
	var keys []string
	for _, s := range artStyles {
		if !s.Off && s.fits(artKindRun) && s.Example == "" {
			keys = append(keys, s.Key)
		}
	}
	return keys
}

// ArtStyleExample vẽ ảnh mẫu cho phong cách key bằng model ảnh model, khung
// 2:3 như tranh thẻ. Trả ảnh và prompt đã dùng.
func ArtStyleExample(ctx context.Context, client *genai.Client, model, key string) ([]byte, string, error) {
	return drawArtStyleExample(ctx, genaiImageLLM{client: client, model: model, aspect: runCardArtAspect}, key)
}

func drawArtStyleExample(ctx context.Context, gen agentImageLLM, key string) ([]byte, string, error) {
	style, ok := artStyleFor(key, artKindRun)
	if !ok {
		return nil, "", fmt.Errorf("thẻ chạy không có phong cách %q", key)
	}
	prompt := runCardArtPrompt(artExampleSnapshot, style, false)
	resp, err := gen.Image(withLLMLabel(ctx, "art_style_example", ""), []*genai.Part{genai.NewPartFromText(prompt)})
	if err != nil {
		return nil, prompt, err
	}
	img := imageFromResponse(resp)
	if len(img) == 0 {
		finish, block := imageRefusal(resp)
		return nil, prompt, fmt.Errorf("model không trả ảnh (finishReason %q, blockReason %q)", finish, block)
	}
	return img, prompt, nil
}
