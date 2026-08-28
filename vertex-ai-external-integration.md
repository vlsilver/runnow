# Tích hợp Vertex AI (Gemini) từ service NGOÀI GCP bằng Service Account Key

Cho phép **một service khác** (chạy ngoài GCP: VPS, on-prem, CI, project khác…)
gọi **Vertex AI / Gemini** trong GCP project **`run-now-79767`** bằng một
**service account key JSON**.

```
[Service ngoài] --(key JSON = ADC)--> Vertex AI @ run-now-79767 (Gemini)
```

Giá trị dùng xuyên suốt guide (của project 3i):

| | Giá trị |
|---|---|
| GCP Project | `run-now-79767` |
| Location (region Gemini) | `us-central1` |
| Model | `gemini-2.5-pro` |

---

## PHẦN A — Làm trên project `run-now-79767` (một lần)

Cần quyền admin trên project. Chạy local có `gcloud` đã đăng nhập
(`gcloud auth login`).

```bash
PROJECT=run-now-79767

# 1) Bật Vertex AI API (nếu chưa)
gcloud services enable aiplatform.googleapis.com --project "$PROJECT"

# 2) Tạo service account RIÊNG cho việc gọi Vertex từ ngoài
#    (đừng dùng lại runnow-bot-runtime — nó có thêm quyền storage/datastore)
gcloud iam service-accounts create vertex-ext \
  --project "$PROJECT" \
  --display-name "Vertex external caller"

# 3) CHỈ cấp quyền gọi Vertex (nguyên tắc tối thiểu quyền)
gcloud projects add-iam-policy-binding "$PROJECT" \
  --member="serviceAccount:vertex-ext@${PROJECT}.iam.gserviceaccount.com" \
  --role="roles/aiplatform.user"

# 4) Xuất KEY JSON — đây là "secret key" đưa cho service ngoài
gcloud iam service-accounts keys create vertex-ext-key.json \
  --iam-account="vertex-ext@${PROJECT}.iam.gserviceaccount.com"
```

Sau bước 4 bạn có file `vertex-ext-key.json`. **Đây là credential dài hạn —
xem như mật khẩu** (mục Bảo mật ở dưới).

**Kiểm tra key hoạt động** (tuỳ chọn, chạy ngay tại máy vừa tạo):
```bash
gcloud auth activate-service-account \
  --key-file=vertex-ext-key.json --project run-now-79767
gcloud auth print-access-token >/dev/null && echo "KEY OK"
```

---

## PHẦN B — Dùng key ở service NGOÀI

### B1. Đặt key + trỏ ADC vào nó

Copy `vertex-ext-key.json` vào service (qua secret manager của service đó, KHÔNG
commit vào git), rồi set biến môi trường:

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/duong/dan/vertex-ext-key.json
```

SDK Google Gen AI tự động đọc biến này (ADC) — không phải nhét path vào code.

### B2. Cài SDK

| Ngôn ngữ | Lệnh |
|---|---|
| Go | `go get google.golang.org/genai` |
| Python | `pip install google-genai` |
| Node.js | `npm install @google/genai` |

### B3. Khởi tạo client (trỏ vào project `run-now-79767`)

**Go**
```go
import (
    "context"
    "log"
    "google.golang.org/genai"
)

ctx := context.Background()
client, err := genai.NewClient(ctx, &genai.ClientConfig{
    Project:  "run-now-79767",   // gọi Vertex TRONG project 3i
    Location: "us-central1",
    Backend:  genai.BackendVertexAI,
    // KHÔNG cần truyền credentials — SDK lấy từ GOOGLE_APPLICATION_CREDENTIALS
})
if err != nil {
    log.Fatal(err)
}
```

**Python**
```python
from google import genai
client = genai.Client(
    vertexai=True,
    project="run-now-79767",
    location="us-central1",
)
```

> Client tái sử dụng được (thread-safe) — tạo MỘT lần lúc khởi động, không tạo
> mỗi request.

### B4. Gọi Gemini

**Go**
```go
resp, err := client.Models.GenerateContent(
    ctx, "gemini-2.5-pro",
    genai.Text("Chào từ service ngoài."), nil,
)
if err != nil { log.Fatal(err) }
fmt.Println(resp.Text())
```

**Python**
```python
resp = client.models.generate_content(
    model="gemini-2.5-pro",
    contents="Chào từ service ngoài.",
)
print(resp.text)
```

### B5. System instruction + tham số (tuỳ chọn)

**Go**
```go
config := &genai.GenerateContentConfig{
    SystemInstruction: genai.NewContentFromText(
        "Trả lời ngắn gọn, tiếng Việt.", genai.RoleUser),
    Temperature:     genai.Ptr[float32](0.7),
    MaxOutputTokens: 1024,
    // ResponseMIMEType: "application/json", + ResponseSchema để ép JSON
}
resp, _ := client.Models.GenerateContent(ctx, "gemini-2.5-pro",
    genai.Text("Tóm tắt lợi ích chạy bộ."), config)
```

### B6. Streaming (tuỳ chọn)

**Go**
```go
for chunk, err := range client.Models.GenerateContentStream(
    ctx, "gemini-2.5-pro", genai.Text("Kể chuyện ngắn."), nil,
) {
    if err != nil { log.Fatal(err) }
    fmt.Print(chunk.Text())
}
```

**Python**
```python
for chunk in client.models.generate_content_stream(
    model="gemini-2.5-pro", contents="Kể chuyện ngắn."):
    print(chunk.text, end="")
```

> Function calling / chat nhiều lượt / sinh ảnh: xem file
> `vertex-ai-integration.md` (guide tổng quát) — code y hệt, chỉ khác client trỏ
> vào project `run-now-79767` với key ở trên.

---

## Bảo mật key JSON (BẮT BUỘC đọc)

- **KHÔNG commit** `vertex-ext-key.json` vào git. Thêm vào `.gitignore`.
- Cất trong **secret manager** của service ngoài (env secret / Vault / AWS
  Secrets Manager / GCP Secret Manager…), không để plaintext trên đĩa chung.
- Key này **chỉ có** `roles/aiplatform.user` → nếu lộ, kẻ xấu chỉ gọi được
  Vertex (tốn tiền Gemini), KHÔNG đụng được Firestore/Storage của 3i. Đó là lý do
  tách SA riêng thay vì dùng bot SA.
- **Xoay (rotate) định kỳ** hoặc khi nghi lộ:
  ```bash
  # liệt kê key
  gcloud iam service-accounts keys list \
    --iam-account=vertex-ext@run-now-79767.iam.gserviceaccount.com
  # tạo key mới, cập nhật service, rồi XOÁ key cũ
  gcloud iam service-accounts keys delete KEY_ID \
    --iam-account=vertex-ext@run-now-79767.iam.gserviceaccount.com
  ```
- Muốn **thu hồi toàn bộ** quyền của service ngoài: gỡ role hoặc xoá SA
  `vertex-ext` → mọi key của nó chết ngay.

---

## Chi phí & lưu ý

- **Billing tính vào project `run-now-79767`** (Gemini theo token). Service ngoài
  gọi = 3i trả tiền. Cân nhắc quota/giới hạn nếu service kia không do bạn kiểm
  soát hoàn toàn.
- **Region:** Gemini không có ở mọi region — giữ `us-central1` (hoặc `global`
  cho model ảnh). Đừng đổi bừa thành asia-* (sẽ 404 model).
- **Timeout:** Gemini Pro context lớn có thể chạy vài phút — đặt HTTP client
  timeout đủ lớn (≥120s) ở service ngoài.

---

## Troubleshooting

| Lỗi | Nguyên nhân / cách sửa |
|---|---|
| `403 PERMISSION_DENIED` | SA chưa có `roles/aiplatform.user`, hoặc IAM chưa propagate (đợi ~1 phút). Kiểm tra lại bước A3. |
| `401 / could not find default credentials` | `GOOGLE_APPLICATION_CREDENTIALS` chưa set hoặc sai path. |
| `404 model not found` | Model không có ở `Location` đang dùng → giữ `us-central1`. |
| `SERVICE_DISABLED aiplatform` | Chưa bật API → chạy lại bước A1. |
| `429 RESOURCE_EXHAUSTED` | Quota Gemini — xin tăng quota hoặc giảm nhịp gọi. |

---

## Tổng hợp ENV cho service ngoài

```bash
GOOGLE_APPLICATION_CREDENTIALS=/path/vertex-ext-key.json
# (code đã hardcode project/location/model, hoặc để chúng qua ENV:)
GCP_PROJECT=run-now-79767
GEMINI_LOCATION=us-central1
GEMINI_MODEL=gemini-2.5-pro
```

> File standalone. Nếu service ngoài dùng ngôn ngữ khác (Node/Java/…) báo mình
> bổ sung ví dụ.
