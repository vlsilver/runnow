# Hướng dẫn tích hợp Vertex AI (Gemini) — Google Gen AI SDK

Guide này dựa trên pattern **đã chạy production** ở backend 3i Run (Go +
`google.golang.org/genai`, `Backend: genai.BackendVertexAI`, model
`gemini-2.5-pro`). Dùng lại được cho project khác. Code chính bằng **Go**, kèm
bản **Python** tương đương.

> SDK "Google Gen AI" (`genai`) là SDK hợp nhất mới — CÙNG một đoạn code chạy
> được cho cả **Gemini Developer API** (dùng API key) lẫn **Vertex AI** (dùng
> ADC + project/location). Chỉ khác ở lúc tạo client. Guide này đi hướng
> **Vertex AI** (khuyên dùng cho production trên GCP: auth bằng service account,
> không phát tán API key).

---

## 1. Chuẩn bị GCP (một lần)

```bash
# 1) Chọn project + bật billing
gcloud config set project YOUR_PROJECT_ID

# 2) Bật Vertex AI API
gcloud services enable aiplatform.googleapis.com

# 3) Chọn REGION có model bạn cần (KHÔNG phải region nào cũng có mọi model)
#    Gemini 2.5 phổ biến ở us-central1. Một số tính năng chỉ có ở "global".
#    (Ở 3i, asia-southeast1 KHÔNG có Gemini nên phải để us-central1.)
```

**Xác thực (Application Default Credentials — ADC):**

- **Chạy local / dev:**
  ```bash
  gcloud auth application-default login
  ```
- **Chạy trên GCP (Cloud Run / GCE / GKE):** dùng service account của service,
  cấp quyền:
  ```bash
  gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:YOUR_SA@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
    --role="roles/aiplatform.user"
  ```
  Không cần API key, không cần file key — ADC tự lấy từ metadata server.

---

## 2. Cài SDK

| Ngôn ngữ | Lệnh |
|---|---|
| Go | `go get google.golang.org/genai` |
| Python | `pip install google-genai` |
| Node.js | `npm install @google/genai` |

---

## 3. Khởi tạo client (Vertex mode)

### Go — đúng như 3i đang dùng

```go
import "google.golang.org/genai"

ctx := context.Background()
client, err := genai.NewClient(ctx, &genai.ClientConfig{
    Project:  projectID,       // vd os.Getenv("GOOGLE_CLOUD_PROJECT")
    Location: "us-central1",   // region có model
    Backend:  genai.BackendVertexAI,
})
if err != nil {
    log.Fatal(err)
}
```

> Client an toàn để **tái sử dụng** (thread-safe) — tạo MỘT lần lúc khởi động
> service, không tạo mỗi request.

### Python

```python
from google import genai

client = genai.Client(
    vertexai=True,
    project="YOUR_PROJECT_ID",
    location="us-central1",
)
```

### Cách gọn hơn: cấu hình qua ENV (cả 2 ngôn ngữ)

Set các biến này rồi tạo client KHÔNG tham số (`genai.NewClient(ctx, nil)` /
`genai.Client()`):

```bash
export GOOGLE_GENAI_USE_VERTEXAI=true
export GOOGLE_CLOUD_PROJECT=YOUR_PROJECT_ID
export GOOGLE_CLOUD_LOCATION=us-central1
```

---

## 4. Sinh nội dung cơ bản (text)

### Go

```go
resp, err := client.Models.GenerateContent(
    ctx,
    "gemini-2.5-pro",
    genai.Text("Viết một câu chào bằng tiếng Việt."),
    nil, // config, có thể nil
)
if err != nil {
    log.Fatal(err)
}
fmt.Println(resp.Text()) // helper gộp text các part lại
```

### Python

```python
resp = client.models.generate_content(
    model="gemini-2.5-pro",
    contents="Viết một câu chào bằng tiếng Việt.",
)
print(resp.text)
```

---

## 5. System instruction + tham số sinh

### Go

```go
config := &genai.GenerateContentConfig{
    SystemInstruction: genai.NewContentFromText(
        "Bạn là trợ lý ngắn gọn, chỉ trả lời bằng tiếng Việt.",
        genai.RoleUser,
    ),
    Temperature:     genai.Ptr[float32](0.7),
    MaxOutputTokens: 1024,
    // TopP, TopK, StopSequences, ResponseMIMEType ("application/json") ...
}
resp, err := client.Models.GenerateContent(ctx, "gemini-2.5-pro",
    genai.Text("Tóm tắt lợi ích của chạy bộ."), config)
```

### Python

```python
from google.genai import types

resp = client.models.generate_content(
    model="gemini-2.5-pro",
    contents="Tóm tắt lợi ích của chạy bộ.",
    config=types.GenerateContentConfig(
        system_instruction="Bạn là trợ lý ngắn gọn, trả lời tiếng Việt.",
        temperature=0.7,
        max_output_tokens=1024,
        # response_mime_type="application/json"  # ép JSON
    ),
)
print(resp.text)
```

**Ép JSON có cấu trúc:** đặt `ResponseMIMEType: "application/json"` +
`ResponseSchema` (Go) / `response_schema` (Python) để model trả JSON đúng schema,
khỏi phải parse text lỏng lẻo.

---

## 6. Streaming (trả dần từng chunk)

### Go (iterator kiểu Go 1.23+)

```go
for chunk, err := range client.Models.GenerateContentStream(
    ctx, "gemini-2.5-pro", genai.Text("Kể một câu chuyện ngắn."), nil,
) {
    if err != nil {
        log.Fatal(err)
    }
    fmt.Print(chunk.Text())
}
```

### Python

```python
for chunk in client.models.generate_content_stream(
    model="gemini-2.5-pro", contents="Kể một câu chuyện ngắn.",
):
    print(chunk.text, end="")
```

---

## 7. Hội thoại nhiều lượt (chat, giữ history)

### Go

```go
chat, _ := client.Chats.Create(ctx, "gemini-2.5-pro", nil, nil)
r1, _ := chat.SendMessage(ctx, genai.Part{Text: "Tên tôi là Linh."})
fmt.Println(r1.Text())
r2, _ := chat.SendMessage(ctx, genai.Part{Text: "Tôi tên gì?"})
fmt.Println(r2.Text()) // nhớ "Linh" nhờ history
```

### Python

```python
chat = client.chats.create(model="gemini-2.5-pro")
print(chat.send_message("Tên tôi là Linh.").text)
print(chat.send_message("Tôi tên gì?").text)
```

> Muốn tự quản history (vd lưu DB, cắt bớt tin cũ): tự dựng slice
> `[]*genai.Content` với `Role: "user"` / `Role: "model"` rồi truyền vào
> `GenerateContent`. (3i làm cách này để trim + kiểm soát context.)

---

## 8. Function calling / tool use (model gọi hàm của bạn)

Đây là phần 3i dùng nhiều: cho model một tập tool đọc dữ liệu, model tự quyết
gọi tool nào, bạn thực thi rồi đưa kết quả lại cho model.

### Go (rút gọn)

```go
weatherTool := &genai.Tool{
    FunctionDeclarations: []*genai.FunctionDeclaration{{
        Name:        "get_weather",
        Description: "Lấy thời tiết theo thành phố",
        Parameters: &genai.Schema{
            Type: genai.TypeObject,
            Properties: map[string]*genai.Schema{
                "city": {Type: genai.TypeString},
            },
            Required: []string{"city"},
        },
    }},
}
config := &genai.GenerateContentConfig{Tools: []*genai.Tool{weatherTool}}

resp, _ := client.Models.GenerateContent(ctx, "gemini-2.5-pro",
    genai.Text("Thời tiết Hà Nội thế nào?"), config)

// Nếu model muốn gọi hàm:
for _, part := range resp.Candidates[0].Content.Parts {
    if fc := part.FunctionCall; fc != nil {
        result := runYourFunction(fc.Name, fc.Args) // BẠN tự chạy
        // Gửi kết quả lại cho model (FunctionResponse) để nó viết câu trả lời cuối
    }
}
```

> **Lưu ý an toàn (bài học từ 3i):** ĐỪNG cho model tự viết truy vấn DB tuỳ ý —
> chi phí/độ an toàn không kiểm soát. Chỉ mở các tool CÓ THAM SỐ CỐ ĐỊNH, tự
> mình chạy query, trả về data đã làm sạch. Model chỉ chọn tool + tham số.

---

## 9. Sinh ảnh (image generation)

3i dùng model ảnh riêng `gemini-2.5-flash-image`, và client ảnh đặt
`Location: "global"` (model ảnh phát hành ở global, không phải region thường):

```go
imageClient, _ := genai.NewClient(ctx, &genai.ClientConfig{
    Project:  projectID,
    Location: "global",           // model ảnh ở global
    Backend:  genai.BackendVertexAI,
})
resp, _ := imageClient.Models.GenerateContent(ctx, "gemini-2.5-flash-image",
    genai.Text("Một chú mèo phi hành gia, phong cách tối giản."), nil)
// Ảnh nằm trong part.InlineData (bytes) — tự lưu/đẩy lên storage.
```

---

## 10. Model IDs hiện dùng được

| Model | Dùng cho |
|---|---|
| `gemini-2.5-pro` | Suy luận mạnh, context dài (3i dùng cho bot) |
| `gemini-2.5-flash` | Nhanh + rẻ, tác vụ thường |
| `gemini-2.5-flash-lite` | Rẻ nhất, phân loại/trích xuất đơn giản |
| `gemini-2.5-flash-image` | Sinh/sửa ảnh (đặt Location "global") |

Chọn model qua ENV để đổi không cần build lại (3i: `GEMINI_MODEL`,
`GEMINI_LOCATION`).

---

## 11. Lưu ý production (đúc kết từ 3i)

- **Region ≠ model có sẵn:** kiểm tra model có ở region bạn chọn; nếu app chạy
  asia-southeast1 vẫn phải gọi Gemini ở us-central1/global (tách config region).
- **Timeout dài:** Gemini Pro với context lớn có thể chạy tới ~2–4 phút. Đặt
  `WriteTimeout`/HTTP timeout đủ lớn (3i để 300s cho service chạy bot).
- **Client tái dùng:** tạo 1 lần lúc khởi động, đừng tạo mỗi request.
- **Chi phí tính theo TOKEN:** context càng dài càng đắt — trim history, đừng
  nhồi dữ liệu thừa. Với tool-use, tự chạy query thay vì để model đọc cả bảng.
- **Chống bịa số:** nếu cần con số chính xác, TÍNH ở code rồi đưa cho model, đừng
  để model tự tính — kèm system prompt cấm bịa. Model rất sẵn lòng dựng số giả.
- **An toàn/safety settings:** chỉnh `SafetySettings` nếu bị chặn nhầm nội dung
  hợp lệ.
- **ADC trên Cloud Run:** cấp `roles/aiplatform.user` cho service account; không
  nhúng key vào image.

---

## 12. Tổng hợp ENV

```bash
GOOGLE_CLOUD_PROJECT=your-project-id
GOOGLE_CLOUD_LOCATION=us-central1     # region Gemini
GEMINI_MODEL=gemini-2.5-pro           # đổi model không cần build lại
# (tuỳ chọn) tạo client không tham số:
GOOGLE_GENAI_USE_VERTEXAI=true
```

---

## Tham khảo

- SDK Go: https://pkg.go.dev/google.golang.org/genai
- SDK Python: https://googleapis.github.io/python-genai/
- Vertex AI + Gemini docs: https://cloud.google.com/vertex-ai/generative-ai/docs
- Model list: https://cloud.google.com/vertex-ai/generative-ai/docs/models

> File này standalone (không thuộc app 3i) — copy sang project khác thoải mái.
> Nếu project khác dùng ngôn ngữ khác (Node/Java/…) hoặc muốn dùng
> **Claude trên Vertex** thay vì Gemini, báo mình bổ sung.
