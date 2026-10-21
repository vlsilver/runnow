# 3i Run

App chạy bộ cho nhóm nhỏ: lấy dữ liệu từ Strava, Apple Health và GPS của điện thoại,
rồi biến thành kèo, bảng xếp hạng, game và bot để cả nhóm có lý do chạy cùng nhau.

## Tính năng

- **Kèo Chạy:** tự đặt mục tiêu có hạn chót. Backend tính tiến độ và tự chốt kết quả khi hết hạn.
- **Club:** bảng xếp hạng, tổng kết, nhật ký chung và xem người khác đang chạy theo thời gian thực.
- **Hành Trình và giáo án:** thống kê cá nhân, kỷ lục và giáo án do coach AI soạn.
- **Tracking:** ghi buổi chạy bằng GPS, chạy được cả khi khoá màn hình. Buổi chạy trùng với Strava trên 30% thì không tính.
- **Ma Sói:** game theo số km chạy được, chơi trong app và trên Telegram.
- **Bot 3i:** bot Telegram trong group của club, có trí nhớ, tra Google và tự lên lịch đăng bài.
- **MyBot (beta):** mỗi người có một bot riêng trong app, chat riêng và vào chung phòng bot.
- **Admin:** tab cấp quyền admin, tester Ma Sói và quyền dùng MyBot.

## Kiến trúc

| Phần | Công nghệ |
| --- | --- |
| App | Flutter (iOS, Android, web), Riverpod, GoRouter |
| Dữ liệu | Firebase Auth (Google), Firestore, Storage, Hosting |
| Backend | Go, một image chạy 3 service Cloud Run ở `asia-southeast1` |
| AI | Gemini trên Vertex AI |

Ba service backend:

- `runnow-api`: public. Lo OAuth Strava, webhook Strava và Telegram, và API cho app.
- `runnow-worker`: private. Chạy các job của Cloud Tasks và Cloud Scheduler: sync, tính aggregate, chốt kèo.
- `runnow-bot`: private. Chạy toàn bộ phần AI, gồm bot 3i và MyBot.

Chi tiết xem [docs/system_architecture.md](docs/system_architecture.md) và
[docs/backend_architecture.md](docs/backend_architecture.md).

## Phát triển

Cần Flutter stable, Go, Firebase CLI, và Xcode hoặc Android SDK.
Các file secret không commit: `.secret/runnow.env`, `GoogleService-Info.plist`, `google-services.json`.

```sh
# App
flutter pub get
flutter analyze && flutter test
flutter run --dart-define-from-file=.secret/runnow.env

# Backend
cd backend && go vet ./... && go test ./...
backend/scripts/test_emulator.sh   # test cần Firestore và Auth emulator (project demo-runnow)

# Firestore rules
npx firebase-tools emulators:exec --only firestore "npm --prefix firebase-tests test" --project demo-runnow
```

## Deploy

```sh
backend/scripts/deploy.sh                  # build image, deploy api, worker, bot
scripts/deploy_web.sh                      # Flutter web lên Firebase Hosting
firebase deploy --only firestore:rules,firestore:indexes,storage
```

App iOS: chạy `flutter build ipa`, rồi upload qua Xcode Organizer.

## Tài liệu

- [Kiến trúc hệ thống](docs/system_architecture.md)
- [Backend](docs/backend_architecture.md) và [backend/README.md](backend/README.md)
- [Tracking và thuật toán GPS](docs/tracking_running_mvp.md)
- [Checklist phát hành lên store](docs/store_release_readiness.md)
