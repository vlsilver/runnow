# 3i

3i là không gian luyện tập và cộng đồng chạy bộ đa nền tảng. Sản phẩm kết
nối dữ liệu Strava, biến lịch sử chạy thành các chỉ số dễ hiểu, tạo động lực
qua Club và đang thử nghiệm khả năng tự ghi lại buổi chạy bằng điện thoại.

> Trạng thái hiện tại: **internal beta**. Thành tích nhận activity Strava và
> 3i từ 500 m. 3i session trùng trên 30% thời lượng với Strava bị loại
> khỏi phép tính để không nhân đôi thành tích.

## Product Snapshot

### Giá trị cốt lõi

3i tập trung vào ba câu hỏi của một runner:

1. **Tôi đã hứa sẽ chạy gì?** Kèo Chạy biến mục tiêu thành cam kết có deadline,
   tiến độ, kết quả và tái kèo.
2. **Tôi đang tiến bộ thế nào?** Tổng hợp tiến độ, consistency, personal power,
   kỷ luật, kỷ lục và khối lượng chạy từ dữ liệu thật.
3. **Nhóm của tôi đang hoạt động ra sao?** Club có bảng xếp hạng, tổng kết,
   nhật ký chung, hồ sơ thành viên và live tracking.
4. **Buổi chạy này diễn ra thế nào?** Activity detail có route và các biểu đồ
   pace, nhịp tim, cao độ, cadence, năng lượng khi nguồn dữ liệu cung cấp.

### Đối tượng sử dụng

- Runner cá nhân muốn theo dõi tiến độ rõ hơn giao diện nhật ký thông thường.
- Nhóm chạy nhỏ muốn tạo động lực bằng số liệu minh bạch và hoạt động chung.
- Nhóm thử nghiệm thuật toán GPS, background tracking và live location trước
  khi đưa dữ liệu 3i vào thành tích chính thức.

## Tính Năng Hiện Có

### Kèo Chạy

- Kèo là tab chính: 10km tuần, 3 buổi tuần, 2km hôm nay hoặc mục tiêu tùy chỉnh.
- Tiến độ tính Strava Run và 3i Run hợp lệ; loại manual, session 3i
  dưới 500 m, activity ngoài kỳ và bản 3i trùng trên 30% thời gian với Strava.
- Mỗi user có tối đa một kèo active do mình tạo; user vẫn có thể tham gia nhiều
  kèo Club khác.
- Tab Kèo là feed chung của mọi kèo Club đang active; kèo của user dùng màu nhấn
  riêng và kèo private chỉ xuất hiện với chính chủ.
- Card hiển thị số người tham gia và tổng phần trăm hoàn thành; detail hiển thị
  tiến trình riêng của từng thành viên.
- Có sync-grace sau deadline, forced Strava sync trước finalize, recap và tái kèo.
- Tổng quan cá nhân chuyển vào `Cài đặt > Hồ sơ & thành tích`.

### Tài khoản và dữ liệu

- Đăng nhập bằng Google qua Firebase Authentication.
- Kết nối một tài khoản Strava với một tài khoản 3i.
- Đồng bộ activity Strava phân trang và cache trong Firestore.
- Làm mới access token Strava và lưu token trong secure storage trên thiết bị.
- Xem dữ liệu đã đồng bộ từ Firestore khi offline; sync và hydrate detail cần
  mạng.

### Tổng quan cá nhân

- Tiến độ tuần hoặc 7 ngày gần nhất: km, thời gian, số buổi và pace trung bình.
- Mục tiêu km theo tuần/tháng, lưu trạng thái hiện tại và lịch sử chỉnh sửa.
- Personal Power theo tuần, 7 ngày hoặc tháng.
- Consistency 8 tuần và kỷ luật cá nhân 30 ngày.
- Kỷ lục cự ly, long run, pace và nhịp tim hợp lệ.
- Phân bổ quãng đường theo tháng, quý hoặc năm bằng line/bar chart.
- Nhấn giữ card để xuất ảnh và chia sẻ.

### Nhật ký và activity detail

- Nhật ký dạng timeline, tối ưu riêng cho mobile.
- Route dùng `flutter_map` với tile sáng CARTO/OpenStreetMap trên mọi nền tảng,
  không cần Google Maps API key.
- Session 3I có thể chụp ảnh khi chạy, neo ảnh theo GPS point hợp lệ gần nhất
  và hiển thị marker/gallery trong chi tiết hoạt động.
- Detail được đọc từ Firestore trước; chỉ gọi Strava khi cache chưa đủ.
- Chart pace, heart rate, heart-rate zones, elevation, cadence và energy khi có
  stream tương ứng.
- Chọn line/bar chart và khoảng lấy mẫu theo distance.
- Poster recap có route, pace chart và native share sheet.

### Club

- Hồ sơ nickname/avatar URL và chế độ Public/Private.
- Thành viên Public có trang tổng quan và nhật ký riêng để người khác xem.
- Bảng xếp hạng theo km, thời gian, consistency, pace, long run và số buổi.
- Khoảng xếp hạng: tuần hiện tại, 7 ngày gần nhất và tháng hiện tại.
- Aggregate leaderboard lưu riêng để không tải toàn bộ activity của mọi thành
  viên mỗi lần mở Club.
- Tổng kết Club, power chart, đóng góp theo thành viên và nhật ký chung.
- Các card tổng kết và leaderboard hỗ trợ nhấn giữ để chia sẻ.

### Tracking và live tracking (Beta)

- Tự động xin quyền location và warm-up GPS trước khi cho phép Start.
- Start, Pause, Resume, Finish; tính distance, elapsed/moving time, pace và split.
- Lọc point GPS có accuracy thấp, timestamp sai, tốc độ phi thực tế hoặc nhiễu
  khi đứng yên.
- Lưu local draft để khôi phục session bị gián đoạn.
- Android foreground service và iOS background location cho trường hợp khóa màn
  hình hoặc chuyển sang app khác. Force-close app không được hỗ trợ.
- Lưu raw decision/debug log cho các buổi chạy thử để tuning thuật toán.
- Live snapshot lên Firestore theo cadence khoảng 10 giây hoặc 50 m; heartbeat
  30 giây và route preview lấy mẫu khoảng 100 m.
- Thành viên xem tại `Club > Đang chạy`, gồm trạng thái, km, thời gian, pace và
  bản đồ route gần realtime.
- Session không cập nhật quá 30 giây được đánh dấu stale; quá 3 phút bị ẩn.

Tracking 3i dùng `source=runnow`. Session từ 500 m được tính vào thành tích;
session ngắn hơn vẫn được lưu để xem route/debug nhưng không cộng. Khi một 3i
session overlap trên 30% thời lượng với Strava Run, Strava là bản chính thức.

### Nền tảng

- iOS và Android: đầy đủ navigation chính; tracking chỉ có trên mobile.
- Web: dashboard nhiều cột, Club, nhật ký, thành viên và viewer live tracking.
- Dark/light/system theme.

## Trạng Thái Sản Phẩm

| Phạm vi | Trạng thái | Ghi chú |
| --- | --- | --- |
| Google login và hồ sơ | Beta ổn định | Cần theo dõi lỗi OAuth trên từng platform |
| Strava sync và activity detail | Beta ổn định | Direct client integration, chưa phù hợp public production |
| Dashboard và nhật ký | Beta ổn định | Strava ưu tiên khi trùng 3i |
| Club và leaderboard | Beta | Một Club chung; aggregate do client cập nhật |
| Tracking bằng điện thoại | Trial | Cần thêm dữ liệu chạy thật và so sánh Garmin/Strava |
| Background tracking | Trial | Cần acceptance test nhiều thiết bị và trạng thái pin/mạng |
| Live tracking trong Club | MVP | Chỉ profile Public; chưa có consent riêng cho từng session |
| Web | Beta | Viewer tốt hơn recorder; Strava OAuth web vẫn là dev-only |

## Product Risks

1. **Live-location consent:** hiện profile Public đồng nghĩa session tracking được
   publish cho Club. Trước khi mở rộng tester, cần toggle `Chia sẻ live với Club`
   theo từng buổi chạy và mặc định Off.
2. **Strava credential:** client secret hiện nằm trong Flutter config theo quyết
   định demo nội bộ. Trước public launch phải chuyển OAuth exchange/refresh sang
   backend service.
3. **Tracking accuracy:** core GPS chưa đủ bằng chứng để trở thành nguồn thành
   tích. Cần test route thoáng, đô thị, dừng đèn đỏ, mất mạng, khóa màn hình và
   pin yếu trên nhiều thiết bị.
4. **Client-owned aggregate:** leaderboard phù hợp nhóm nhỏ nhưng cần backend
   aggregation hoặc trusted job nếu quy mô tăng hoặc dữ liệu trở thành cạnh
   tranh chính thức.
5. **No crash recovery guarantee:** local draft giảm mất dữ liệu, nhưng app bị
   force-close không thể tiếp tục tracking như đồng hồ chuyên dụng.

## Roadmap Đề Xuất

### P0 - Đưa tracking/live tracking tới beta có kiểm soát

- Consent live theo từng session, hiển thị rõ ai đang được xem vị trí.
- Test matrix iOS/Android: foreground, lock screen, chuyển app, mất mạng, reconnect,
  low-power mode, permission While Using/Always và app restart.
- Báo chất lượng GPS, last update và trạng thái mạng rõ ràng cho runner/viewer.
- Dashboard nội bộ cho sai số 3i so với Garmin/Strava và reject reasons.
- Quy tắc retention/xóa `liveSessions` và dữ liệu debug cũ.

### P1 - Club Challenge

- Challenge tuần/tháng theo tổng km, số ngày active, elevation hoặc số buổi.
- Mục tiêu cá nhân và mục tiêu cộng dồn toàn Club.
- Progress chart, contribution chart, badge hoàn thành và recap để share.
- Eligibility dùng chung cho activity Strava và 3i hợp lệ.

Đây là bước tiếp theo có giá trị cao nhất: 3i đã có members, aggregate,
leaderboard và share card nên chi phí bổ sung vừa phải nhưng tạo lý do quay lại
hàng tuần. Strava cũng dùng challenge theo distance, time, elevation và active
days để tạo động lực cộng đồng.

### P2 - Lịch chạy và workout có cấu trúc

- Lên lịch ngày/giờ, distance, target pace và loại buổi chạy.
- Template Easy, Long Run, Tempo và Interval; reminder local notification.
- So sánh `planned vs completed`, streak hoàn thành kế hoạch và tổng kết tuần.
- Pacer trong lúc tracking: ahead/behind target pace, không cần AI.

Nike Run Club tập trung vào plan 5K/10K/Half/Marathon và guided runs; Apple
Workout dùng Pacer và custom intervals. 3i nên bắt đầu bằng rule/template
đơn giản thay vì AI coaching.

### P3 - Safety Link cho live tracking

- Tạo URL có token hết hạn để người thân xem mà không cần tài khoản 3i.
- Hiển thị current/last location, start point, last updated, trạng thái và pin.
- Runner chủ động gửi link mỗi session; Finish thu hồi quyền xem vị trí hiện tại.
- Không công khai link trong profile hoặc Club.

Strava Beacon cập nhật vị trí khoảng 15 giây và cho người nhận xem qua browser;
đây là mẫu sản phẩm phù hợp hơn việc buộc người thân tham gia Club.

### P4 - Race Route và Personal Best theo route

- Nhận diện route lặp lại từ polyline đã chuẩn hóa.
- So sánh buổi hiện tại với lần gần nhất hoặc tốt nhất trên cùng route.
- Hiển thị ahead/behind theo distance và ghost progress trên map.

Apple hỗ trợ Race Route sau khi người dùng lặp lại cùng route; tính năng này hợp
với dữ liệu route 3i đã có và tạo giá trị cá nhân rõ hơn segment công khai.

### P5 - Coaching có kiểm soát

- Bắt đầu bằng insight deterministic: tăng volume, long-run ratio, consistency,
  pace trend và cảnh báo tăng tải quá nhanh.
- Chỉ thêm AI để giải thích insight hoặc tạo nội dung sau khi có backend, consent,
  budget và cách đánh giá chất lượng.
- Chưa xây daily suggested workout kiểu Garmin vì 3i chưa có sleep, recovery,
  stress, VO2 max và sensor history cần thiết để đưa khuyến nghị an toàn.

## Product Metrics

- Activation: Google login -> kết nối Strava -> sync đầu tiên thành công.
- Weekly active runners và số ngày có activity mỗi thành viên.
- Tỷ lệ user đặt goal và hoàn thành goal tuần/tháng.
- Challenge join/completion rate và contribution distribution.
- Live tracking success rate, stale rate, thời gian reconnect và session hoàn tất.
- Tracking accuracy: chênh lệch distance/time so với Garmin/Strava, GPS reject
  rate và tỷ lệ session phải bỏ.
- Retention D7/D30 theo cohort đã kết nối Strava.

## Kiến Trúc

- Flutter + Riverpod + GoRouter.
- Firebase Authentication (Google) và Cloud Firestore.
- Strava OAuth/API gọi trực tiếp từ client trong bản demo nội bộ.
- `flutter_map` + CARTO/OpenStreetMap cho route map.
- Firestore persistence cho dữ liệu đã tải; secure storage cho Strava token.
- Tracking core thuần Dart tách khỏi UI và repository để unit test/tuning.

Data ownership chính:

```text
users/{uid}
users/{uid}/activities/{activityId}
users/{uid}/trainingGoalHistory/{historyId}
users/{uid}/runContractState/current
runContracts/{contractId}
publicProfiles/{uid}
leaderboardEntries/{uid}
liveSessions/{sessionId}
```

## Thiết Lập Phát Triển

### Yêu cầu

- Flutter stable.
- Xcode và CocoaPods cho iOS.
- Android SDK/NDK cho Android.
- Firebase CLI cho rules và web hosting.
- Firebase project có Google Authentication, Firestore và Cloud Storage.
- Strava API application.

Bundle/application IDs hiện tại:

- iOS: `com.runnow.3aeidiot`
- Android: `com.threeaeidiot.runnow`

### Firebase

Các file Firebase native không commit vào Git:

- `ios/Runner/GoogleService-Info.plist`
- `android/app/google-services.json`

Project Firebase mặc định đã được khai báo trong `.firebaserc`. Đăng nhập và
deploy rules:

```sh
firebase login
firebase deploy --only firestore:rules,firestore:indexes,storage
```

### Chạy và kiểm tra

```sh
flutter pub get
flutter analyze
flutter test
npx firebase-tools emulators:exec --only firestore "npm --prefix firebase-tests test" --project demo-runnow
flutter run
```

Build Android APK:

```sh
flutter build apk --release
```

Build và deploy web:

```sh
flutter build web --release
firebase deploy --only firestore:rules,firestore:indexes,storage,hosting
```

Kiểm tra iOS trước acceptance test:

```sh
scripts/check_ios_readiness.sh
```

## Tài Liệu

- [Tracking MVP và thuật toán GPS](docs/tracking_running_mvp.md)
- [Kèo Chạy v4 Product Plan](features/runnow_keo_chay_v4_final_implementation_plan.md)
- [Kèo Chạy v4 Technical Plan](features/runnow_keo_chay_v4_technical_plan.md)
- [Strava Authentication](https://developers.strava.com/docs/authentication/)
- [Strava Beacon](https://support.strava.com/hc/en-us/articles/224357527-Strava-Beacon)
- [Strava Challenges](https://support.strava.com/en-us/articles/15401916-strava-challenges)
- [Strava Goals](https://support.strava.com/en-us/articles/15401694-goals-on-the-strava-app)
- [Nike Run Club Training Plans](https://www.nike.com/help/a/nrc-plan/add-run-nrc)
- [Apple Watch Running](https://support.apple.com/guide/watch/run-with-apple-watch-apd73a43493f/watchos)
- [Garmin Daily Suggested Workouts](https://support.garmin.com/en-US/?faq=oYknGZ910l1pfBNzkDHX6A)
