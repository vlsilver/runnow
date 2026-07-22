# 3I Backend

Backend Strava cho 3I viết bằng Go, gồm cùng một image nhưng hai Cloud Run service:

- `runnow-api`: public OAuth callback, webhook và endpoint có Firebase ID token.
- `runnow-worker`: private, chỉ Cloud Tasks/Cloud Scheduler được invoke qua OIDC.

Health endpoint public của API là `GET /health`.

Thiết kế đầy đủ và kế hoạch cutover nằm tại
[`docs/backend_architecture.md`](../docs/backend_architecture.md).

## Phạm vi đã triển khai

- OAuth state dùng một lần, TTL 10 phút.
- Mapping 1 Firebase UID - 1 Strava athlete và chặn athlete trùng UID.
- Token Strava server-only, refresh rotation có transaction chống ghi đè token mới.
- Webhook nhận nhanh, lưu event idempotent rồi đẩy Cloud Tasks.
- Import/backfill phân trang, tombstone cho delete/out-of-order event.
- Lazy hydrate detail/streams bằng credentials của chủ activity.
- Aggregate tuần, 7 ngày, tháng và leaderboard do backend ghi.
- Reconcile 10 ngày gần nhất mỗi 6 giờ để bù webhook bị lỡ.

Flutter chưa được cutover trong commit này. App hiện tại vẫn gọi Strava trực tiếp;
không bật backend cho user thật cho đến khi Flutter chuyển OAuth/sync sang API và
mọi beta user reconnect một lần. Hai phía cùng refresh một token là trạng thái
không được hỗ trợ.

## Local checks

```bash
cd backend
go test ./...
go vet ./...
go build ./cmd/...
```

Local runtime dùng Application Default Credentials hoặc
`FIRESTORE_EMULATOR_HOST`. Sao chép `.env.example` thành `.env` ở máy cá nhân;
không commit file đó.

Credential chuyển tiếp cho Flutter và webhook operator nằm trong file local
`.secret/runnow.env`, đã bị Git ignore. Flutter local phải chạy bằng:

```bash
flutter run --dart-define-from-file=.secret/runnow.env
```

Source được chia theo ownership:

- `cmd/api`: binary public API.
- `cmd/worker`: binary private worker.
- `internal/backend`: domain/service, Strava gateway, Firestore và Cloud Tasks.

## Secret Manager

Tạo hai secret từ file local trước khi deploy:

```bash
./scripts/setup-secrets.sh
```

Script không ghi đè secret đã có version hoạt động. Nếu secret resource đã tồn
tại nhưng chưa có version, script tự thêm initial version từ file local. Khi
rotate, thêm version bằng `gcloud secrets versions add ...`.

## Deploy

```bash
cd backend
./scripts/setup-secrets.sh
./scripts/deploy.sh
```

Hai script tự đọc `.secret/runnow.env` từ root repository. Các URI deploy có
giá trị mặc định cho project hiện tại; chỉ export biến tương ứng khi cần override.
Sau khi thành công, deploy script cập nhật URL vào `.secret/config.json`.

Script tạo Artifact Registry, service accounts, IAM, ba queues, hai Cloud Run
services, Firestore TTL policies và Scheduler reconciliation. Nó không tạo nội
dung secret và không đăng ký webhook thay operator.

Sau deploy:

1. Cập nhật **Authorization Callback Domain** trong Strava bằng hostname của
   `API URL` mà script in ra.
2. Chạy `scripts/register-strava-webhook.sh` đúng một lần. Script tự đọc
   credential từ `.secret/runnow.env` và API URL từ `.secret/config.json`;
   Strava chỉ cho một subscription trên mỗi app.

`deploy.sh` mặc định để API ở `min-instances=0` nhằm tiết kiệm chi phí. Khi mở
public và cần webhook không chịu cold start, đổi API sang `min-instances=1`.
3. Lưu subscription ID trả về thành env `STRAVA_SUBSCRIPTION_ID` trên cả hai
   services sau khi cutover ổn định.
4. Deploy Firestore Rules/Indexes từ root repo.

## Rollback

Cloud Run giữ revisions. Rollback bằng cách chuyển traffic về revision trước;
không xóa collections/token trong rollback. Khi Flutter chưa cutover, backend
deploy không thay đổi hành vi app.
