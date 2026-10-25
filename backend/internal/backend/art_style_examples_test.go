package backend

import (
	"context"
	"slices"
	"strings"
	"testing"

	"google.golang.org/genai"
)

// stubImageLLM trả resp cố định và ghi prompt từng lần gọi.
type stubImageLLM struct {
	resp    *genai.GenerateContentResponse
	prompts []string
}

func (s *stubImageLLM) Image(_ context.Context, parts []*genai.Part) (*genai.GenerateContentResponse, error) {
	s.prompts = append(s.prompts, parts[len(parts)-1].Text)
	return s.resp, nil
}

func TestArtStylesMissingExampleListsRunStylesWithoutImage(t *testing.T) {
	got := ArtStylesMissingExample()
	if !slices.Contains(got, "anime_cel") || !slices.Contains(got, "synthwave") {
		t.Fatalf("thiếu phong cách chưa có ảnh: %v", got)
	}
	if slices.Contains(got, "impressionist") {
		t.Fatal("impressionist đã có ảnh public domain mà vẫn bị vẽ")
	}
	if slices.Contains(got, "manga_ink") {
		t.Fatal("manga_ink không thuộc thẻ chạy mà vẫn bị vẽ")
	}
	// 39 phong cách thẻ chạy, 21 có ảnh public domain.
	if len(got) != 18 {
		t.Fatalf("có %d phong cách chưa có ảnh, muốn 18: %v", len(got), got)
	}
}

func TestDrawArtStyleExampleUsesTheRunCardPromptWithoutPhoto(t *testing.T) {
	gen := &stubImageLLM{resp: &genai.GenerateContentResponse{Candidates: []*genai.Candidate{{Content: &genai.Content{Parts: []*genai.Part{
		{InlineData: &genai.Blob{MIMEType: "image/png", Data: []byte("png")}},
	}}}}}}
	img, prompt, err := drawArtStyleExample(context.Background(), gen, "anime_cel")
	if err != nil {
		t.Fatal(err)
	}
	if string(img) != "png" {
		t.Fatalf("ảnh = %q", img)
	}
	// Buổi dựng sẵn: chạy đường vắng, 6h30 sáng giờ VN, 10 km.
	want := "Create an image: a single full-bleed illustration of a lone runner in mid-stride along a quiet open road in the early morning light, capturing the feeling of a long run."
	if !strings.HasPrefix(prompt, want) || !strings.Contains(prompt, "a cel-shaded anime illustration") {
		t.Fatalf("prompt = %q", prompt)
	}
	if len(gen.prompts) != 1 || gen.prompts[0] != prompt {
		t.Fatalf("model nhận %v, muốn đúng prompt trả về", gen.prompts)
	}
}

func TestDrawArtStyleExampleFailsWhenModelSendsNoImage(t *testing.T) {
	gen := &stubImageLLM{resp: &genai.GenerateContentResponse{Candidates: []*genai.Candidate{{FinishReason: genai.FinishReasonSafety}}}}
	if _, _, err := drawArtStyleExample(context.Background(), gen, "anime_cel"); err == nil || !strings.Contains(err.Error(), "SAFETY") {
		t.Fatalf("err = %v, muốn báo model không trả ảnh kèm lý do", err)
	}
	if _, _, err := drawArtStyleExample(context.Background(), gen, "manga_ink"); err == nil {
		t.Fatal("phong cách không thuộc thẻ chạy mà vẫn vẽ")
	}
}
