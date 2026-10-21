# 3i Store Release Readiness

Tài liệu này theo dõi các lỗi và rủi ro cần xử lý trước khi gửi 3i lên App
Store/Play Store. Chỉ đánh dấu hoàn thành khi code, test tự động và kiểm tra trên
thiết bị thật đều đạt.

## Release Gate

- [x] `flutter analyze` không có lỗi.
- [x] Toàn bộ `flutter test` đạt.
- [ ] Worktree sạch và release được build từ một commit/tag xác định.
- [ ] Test tracking khi khóa màn hình, chuyển app và khôi phục sau khi app bị hệ
      điều hành thu hồi.
- [ ] Test OAuth, sync, journal, kèo và live tracking bằng tài khoản reviewer.

## P0 - Bắt buộc trước khi submit

### Authentication và tài khoản

- [ ] Thêm phương thức đăng nhập tương đương đáp ứng App Store Guideline 4.8;
      với iOS, lựa chọn chuẩn là Sign in with Apple.
- [ ] Thêm luồng xóa tài khoản trong app, gồm xác nhận, re-authentication và xóa
      dữ liệu liên quan. Không chỉ yêu cầu người dùng gửi email.

### Strava OAuth

- [ ] Rotate Strava client secret hiện đã nằm trong source/Git history.
- [ ] Chuyển authorization-code exchange và refresh-token rotation sang backend.
- [ ] Không đóng gói client secret hoặc refresh token dùng chung trong app/web.
- [ ] Sinh OAuth `state` ngẫu nhiên, lưu tạm và bắt buộc validate callback.

### Live location và quyền riêng tư

- [ ] Thêm consent riêng cho từng session live; mặc định không chia sẻ.
- [ ] Không suy ra quyền chia sẻ vị trí live chỉ từ trạng thái public của profile.
- [ ] Đồng bộ privacy policy với hành vi thật của app.

## P1 - Performance và độ ổn định

### Đợt 1: Giảm tải trực tiếp trên client

- [x] Journal dùng cursor pagination, chỉ tải trang đầu 30 activity và dùng
      context thời gian để không mất liên kết overlap ở ranh giới trang.
- [x] Bỏ listener "prewarm" Nhật ký vì màn hình pagination không sử dụng cache
      của listener đó.
- [x] Dashboard cá nhân giới hạn stream activity thay vì tải vô hạn.
- [x] Giới hạn stream dashboard của member và tự hủy subscription khi rời màn.
- [x] Thay duplicate detection `O(n²)` bằng interval index dùng chung.
- [x] Live tracking query chỉ lấy trạng thái `running`/`paused`, có limit và
      Firestore composite indexes.
- [x] Danh sách kèo query theo trạng thái, dùng cursor pagination 20 mục và
      lazy list trên mobile; không tăng limit rồi đọc lại các trang cũ.
- [ ] Verify chuyển tab Club/Member và mở activity bằng profile có trên 500
      activities trên iPhone thật.

### Đợt 2: Aggregate và khả năng mở rộng

- [ ] Tách recent activity stream khỏi all-time analytics.
- [ ] Lưu aggregate dashboard/member theo tuần, tháng và all-time records để UI
      không cần parse hàng trăm activity.
- [x] Bỏ mô hình một Firestore listener cho mỗi member trong Club Journal;
      hiện dùng one-shot query giới hạn 20 activity/member, tối đa 4 query đồng
      thời và cache kết quả 2 phút.
- [ ] Hợp nhất các one-shot query Club Journal thành collection feed có
      pagination khi số member tăng.
- [ ] Thiết lập TTL hoặc job xóa/archive `liveSessions` cũ.
- [x] Cache analytics tóm tắt của member và chỉ tính lại khi activity/ngày đổi.
- [x] Cache comparison/tháng/kỷ luật/sort gần đây trên dashboard cá nhân; không
      tính lại khi chỉ filter hoặc widget khác rebuild.
- [x] Memoize `PersonalPowerCard` và volume chart độc lập với rebuild do
      filter/scroll.
- [ ] Chuyển all-time records sang aggregate thay vì quét danh sách activity.
- [ ] Đo frame timing bằng Flutter DevTools profile mode trên thiết bị thật.

### Hoãn để chốt flow sync activity

- [ ] Không dừng Strava pagination chỉ vì một page không phát sinh Firestore
      write; cần chốt lại incremental/full-resync semantics trước khi sửa.
- [ ] Không rebuild leaderboard từ toàn bộ lịch sử sau mọi sync; chuyển sang
      aggregate theo period sau khi chốt cách xử lý activity mới/xóa/overlap.

### Reliability

- [x] Chỉ recalculate kèo chứa activity vừa thay đổi; một kèo lỗi không làm hỏng
      các kèo còn lại hoặc tạo unhandled async exception.
- [ ] Coalesce draft persistence để trạng thái mới nhất không bị bỏ qua khi một
      lần ghi trước đó vẫn đang chạy.

## P1 - Firestore và Storage Rules

- [ ] `stravaLinks` chỉ owner/backend được đọc; không lộ UID/email cho mọi user.
- [ ] Ảnh activity private không được mở cho toàn bộ user đăng nhập.
- [ ] Xác định trust model leaderboard; không để client tùy biến tự ghi thành tích
      nếu bảng xếp hạng được dùng cạnh tranh công khai.
- [ ] Thêm rules tests chạy bằng Firebase Emulator cho các trường hợp owner,
      member public/private, contract participant và user ngoài contract.

## P1 - App Store Privacy

- [ ] Thêm và kiểm tra `PrivacyInfo.xcprivacy` trong app bundle.
- [ ] Hoàn tất App Privacy answers cho account, location, fitness/heart rate,
      photos, identifiers và analytics.
- [ ] Cập nhật permission descriptions từ tên cũ `RunNow`/`chạy thử nghiệm`
      sang hành vi chính thức của 3i.
- [ ] Review notes mô tả rõ background location chỉ hoạt động trong session chạy.

## P2 - Release Hygiene

- [x] Di chuyển raw UI color còn lại sang theme tokens.
- [ ] Cấu hình Android release keystore; release build không được fallback sang
      debug signing.
- [ ] Tăng build number cho mỗi lần upload Store.
- [ ] Kiểm tra icon, splash, deep link và URL privacy/support từ archive cuối.

## Verification Log

### 2026-07-16

- `flutter analyze`: đạt.
- `flutter test`: 141 test đạt.
- Targeted performance/repository/widget tests: đạt.
- Live query indexes đã thêm vào source nhưng chưa deploy lên Firebase.
- Chưa chạy full iOS archive hoặc test background trên thiết bị thật.
