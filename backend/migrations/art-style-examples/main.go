// Command art-style-examples vẽ ảnh mẫu cho các phong cách thẻ buổi chạy chưa
// có ảnh mẫu, ghi ra thư mục trên máy để duyệt tay; xem
// backend.ArtStyleExample. Không ghi gì lên Firestore hay Storage: ảnh duyệt
// xong thì upload vào artStyles/examples/ và khai Example trong art_styles.go.
//
// Mỗi phong cách là một lượt gọi model ảnh, tính tiền thật và không qua trần
// chi phí vẽ thẻ. Ảnh đã có trong -out thì bỏ qua, nên chạy lại chỉ vẽ phần
// còn thiếu hay phần đã xoá để vẽ lại.
//
// Cần Vertex AI (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/art-style-examples -out /tmp/style-examples
//	go run ./migrations/art-style-examples -out /tmp/style-examples -keys anime_cel,chibi
package main

import (
	"context"
	"flag"
	"log/slog"
	"os"
	"path/filepath"
	"strings"

	"google.golang.org/genai"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

func main() {
	project := flag.String("project", "run-now-79767", "GCP project ID")
	model := flag.String("model", "gemini-2.5-flash-image", "model ảnh, cùng model vẽ tranh thẻ trên prod")
	out := flag.String("out", "", "thư mục ghi ảnh <key>.png")
	keys := flag.String("keys", "", "các key cách nhau dấu phẩy; bỏ trống là mọi phong cách chưa có ảnh mẫu")
	flag.Parse()
	if *out == "" {
		slog.Error("thiếu -out")
		os.Exit(2)
	}
	todo := backend.ArtStylesMissingExample()
	if *keys != "" {
		todo = strings.Split(*keys, ",")
	}
	if err := os.MkdirAll(*out, 0o755); err != nil {
		slog.Error("không tạo được thư mục ra", "error", err)
		os.Exit(1)
	}

	ctx := context.Background()
	// Model ảnh chỉ có ở location global, như client vẽ ảnh của service bot.
	client, err := genai.NewClient(ctx, &genai.ClientConfig{Project: *project, Location: "global", Backend: genai.BackendVertexAI})
	if err != nil {
		slog.Error("kết nối Vertex AI lỗi, chạy `gcloud auth application-default login` trước", "error", err)
		os.Exit(1)
	}

	var drawn, skipped, failed []string
	for _, key := range todo {
		path := filepath.Join(*out, key+".png")
		if _, err := os.Stat(path); err == nil {
			skipped = append(skipped, key)
			continue
		}
		img, _, err := backend.ArtStyleExample(ctx, client, *model, key)
		if err != nil {
			slog.Warn("không vẽ được", "style", key, "error", err)
			failed = append(failed, key)
			continue
		}
		if err := os.WriteFile(path, img, 0o644); err != nil {
			slog.Error("không ghi được ảnh, dừng", "style", key, "error", err)
			os.Exit(1)
		}
		slog.Info("đã vẽ", "style", key, "file", path)
		drawn = append(drawn, key)
	}
	slog.Info("art-style-examples xong", "drawn", len(drawn), "skipped", len(skipped), "failed", failed)
	if len(failed) > 0 {
		os.Exit(1)
	}
}
