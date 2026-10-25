// Command art-style-examples vẽ ảnh mẫu cho các phong cách thẻ buổi chạy chưa
// có ảnh mẫu, ghi ra thư mục trên máy để duyệt tay; xem
// backend.ArtStyleExample. Không ghi gì lên Firestore hay Storage: ảnh duyệt
// xong thì upload vào artStyles/examples/ và khai Example trong art_styles.go.
//
// Mỗi phong cách là một lượt gọi model ảnh, tính tiền thật và không qua trần
// chi phí vẽ thẻ. Ảnh đã có trong -out thì bỏ qua, nên chạy lại chỉ vẽ phần
// còn thiếu hay phần đã xoá để vẽ lại. Model báo hết quota thì chờ -wait rồi
// vẽ lại phong cách đó.
//
// Cần Vertex AI (Application Default Credentials):
//
//	gcloud auth application-default login
//	go run ./migrations/art-style-examples -out /tmp/style-examples
//	go run ./migrations/art-style-examples -out /tmp/style-examples -keys anime_cel,chibi
package main

import (
	"context"
	"errors"
	"flag"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"google.golang.org/genai"

	"github.com/vlsilver/runnow/backend/internal/backend"
)

func main() {
	project := flag.String("project", "run-now-79767", "GCP project ID")
	model := flag.String("model", "gemini-2.5-flash-image", "model ảnh, cùng model vẽ tranh thẻ trên prod")
	out := flag.String("out", "", "thư mục ghi ảnh <key>.png")
	keys := flag.String("keys", "", "các key cách nhau dấu phẩy; bỏ trống là mọi phong cách chưa có ảnh mẫu")
	wait := flag.Duration("wait", time.Minute, "thời gian chờ trước khi vẽ lại khi model báo hết quota (429)")
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
		img, err := drawWithQuotaWait(ctx, client, *model, key, *wait)
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

// quotaRetries là số lần chờ thêm khi model ảnh báo hết quota (429). Quota ảnh
// của project tính theo phút nên vẽ liền vài ảnh là bị chặn; chờ rồi vẽ lại
// đúng phong cách đó thay vì bỏ qua để người chạy phải chạy lại tay.
const quotaRetries = 3

func drawWithQuotaWait(ctx context.Context, client *genai.Client, model, key string, wait time.Duration) ([]byte, error) {
	for retry := 0; ; retry++ {
		img, _, err := backend.ArtStyleExample(ctx, client, model, key)
		var apiErr genai.APIError
		if err == nil || !errors.As(err, &apiErr) || apiErr.Code != http.StatusTooManyRequests || retry == quotaRetries {
			return img, err
		}
		slog.Info("hết quota, chờ rồi vẽ lại", "style", key, "wait", wait, "retry", retry+1)
		time.Sleep(wait)
	}
}
