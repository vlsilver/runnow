# RunNow Tracking MVP

## Verdict

Tracking nên bắt đầu bằng một core thuần Dart nhận điểm GPS, tính toán metric, lưu log đầy đủ, rồi mới gắn UI và plugin location sau. Đây là đúng boundary cho RunNow hiện tại: thuật toán sẽ phải tuning nhiều khi chạy thật, nên không nên trộn logic này vào màn hình hoặc Firestore repository quá sớm.

## Invariant

- Dữ liệu Strava cũ vẫn đọc được và không bị migrate phá vỡ.
- Activity do RunNow tự record dùng chung model với Strava qua `ActivitySummary.source = runnow`.
- Trong giai đoạn thử nghiệm, lưu đủ raw sample/debug decision để phân tích sai số sau mỗi buổi chạy.
- UI có thể đổi nhanh, nhưng thuật toán distance/pace/split phải test được bằng unit test.
- MVP ưu tiên đúng và ổn định khi chạy foreground; background tracking và auto-pause để phase sau.

## Kiến Trúc

- `lib/src/models.dart`
  - Model chung `ActivitySource`, `RoutePoint`, `ActivitySummary`.
  - Strava activity mặc định `source = strava` để tương thích dữ liệu cũ.
  - RunNow tracking sẽ tạo `ActivitySummary` với `source = runnow`, `routePoints`, `hydrated = true`.

- `lib/src/tracking_session.dart`
  - Core tracking thuần Dart.
  - Không phụ thuộc Flutter UI, location plugin, Firebase.
  - Nhận `TrackingLocationSample`, trả về `TrackingSessionSnapshot`.
  - Chịu trách nhiệm filter GPS, tính distance, moving time, pace, split, debug log.

- UI phase sau
  - Màn hình Start/Pause/Resume/Finish.
  - Xin quyền foreground location trước khi start.
  - Hiển thị distance, time, pace hiện tại, pace trung bình, map polyline.
  - Khi finish mới lưu activity lên Firestore.

- Repository phase sau
  - Thêm `saveTrackedActivity(detail)`.
  - Lưu document vào `users/{uid}/activities/{activityId}`.
  - Giai đoạn thử nghiệm giữ `trackingDebug` để audit thuật toán.

## Kỹ Thuật Tính Toán

### GPS Sampling

MVP dùng foreground high-accuracy location:

- iOS: Core Location qua plugin Flutter location/geolocator.
- Android: Fused Location Provider qua plugin Flutter.
- Yêu cầu iOS Precise Location; nếu reduced accuracy thì cảnh báo user.
- Warm-up dùng `distanceFilter = 0` để đọc tín hiệu liên tục.
- Tracking sau `START RUN` dùng `distanceFilter = 5m` để giảm jitter và giảm số point.

Chưa làm:

- background tracking.
- auto-pause.
- barometer/elevation smoothing.
- dual-frequency GNSS/raw GNSS.

### GPS Warm-up

Tracking không được bắt đầu ngay khi user bấm nút đầu tiên.

Flow đúng cho giai đoạn MVP:

1. User bấm `LOCK GPS`.
2. App xin quyền location và đọc GPS ở chế độ high accuracy.
3. User đứng yên vài giây để app kiểm tra GPS lock.
4. Chỉ khi có nhiều sample ổn định, app mới hiện `START NOW`.
5. Chỉ sau `START NOW` mới tính distance, time và pace.
6. GPS point trong giai đoạn `LOCK GPS` chỉ dùng để đánh giá chất lượng tín hiệu, không được dùng làm route anchor.

Không auto-start khi warm-up timeout. Nếu GPS chưa ổn định, app yêu cầu user ra nơi thoáng hơn và khóa lại.

Warm-up hiện kiểm tra:

- thời gian warm-up tối thiểu `10s`.
- ít nhất `6` sample ổn định liên tiếp.
- best accuracy phải `<= 12m`.
- average accuracy trong cửa sổ ổn định phải `<= 15m`.
- current accuracy phải `<= 15m`.
- mỗi bước nhảy khi đang đứng yên không được vượt ngưỡng drift.
- tổng drift trong cửa sổ warm-up không được vượt `16m`.
- nếu sample warm-up nhảy xa bất thường hoặc implied speed lớn khi đang đứng yên, reset chuỗi ổn định.
- timeout `45s` thì không unlock; user phải ra nơi thoáng hơn rồi lock lại.

Lý do: accuracy reported bởi OS có thể trông tốt nhưng vị trí vẫn drift. Garmin cũng tách bước chờ GPS tốt khỏi start thật, nên RunNow cần cùng invariant này.

### Distance

Tính quãng đường bằng Haversine giữa hai accepted GPS points.

Điểm GPS được reject nếu:

- accuracy lớn hơn ngưỡng cấu hình, mặc định `25m`.
- timestamp không tăng.
- implied speed vượt ngưỡng chạy người, mặc định `6 m/s`.
- distance quá nhỏ, mặc định dưới `2m`, coi như nhiễu đứng yên.
- session đang pause.

### Moving Time

MVP dùng manual pause/resume:

- `elapsedTimeSeconds`: thời gian wall-clock từ start tới now.
- `movingTimeSeconds`: tổng thời gian giữa các accepted GPS segment khi session đang running.
- Sau resume, điểm GPS đầu tiên chỉ làm anchor, không nối quãng pause vào route.

### Pace

- Average pace = `movingTimeSeconds / distanceKm`.
- Current pace = rolling window gần nhất, mặc định `12s`.
- Không dùng raw instantaneous GPS speed làm pace chính vì dễ nhiễu.

### Splits

- MVP tạo split mỗi `1km`.
- Nếu một GPS segment vượt qua mốc split, nội suy thời gian theo tỷ lệ distance trong segment.
- Split lưu `distanceMeters`, `movingTimeSeconds`, `elapsedTimeSeconds`, `paceSecondsPerKm`.

### Debug Log

Trong giai đoạn thử nghiệm, mỗi sample có decision:

- accepted/rejected.
- reject reason.
- segment distance/time.
- total distance/moving time tại thời điểm đó.

Log này giúp trả lời: vì sao pace nhảy, vì sao thiếu distance, điểm nào bị reject quá mạnh.

## Data Shape MVP

Activity document cho RunNow tracking nên có:

- Summary fields hiện tại: `id`, `name`, `sportType`, `startedAt`, `distanceMeters`, `movingTimeSeconds`, `elapsedTimeSeconds`.
- Source fields: `source = runnow`, `sourceActivityId`, `recordingDevice`, `schemaVersion`.
- Route: `routePoints`.
- Detail fields: `hydrated = true`, `splits`, `streams`.
- Trial-only: `trackingDebug`.

Khi thuật toán ổn, có thể cắt bớt `trackingDebug` hoặc chỉ lưu khi bật developer mode.

Trong giai đoạn testing, RunNow tracking activity không được tính vào dashboard stats, leaderboard, club summary hoặc power score. Các stats chính vẫn lấy từ Strava trước để tránh làm nhiễu dữ liệu thật.

## Firestore Sync Policy

MVP không push realtime từng GPS point lên Firestore.

Lý do:

- GPS có thể emit 1 sample/giây; một buổi 45 phút có thể tạo hơn 2.700 writes nếu ghi trực tiếp từng điểm.
- Firestore free quota dễ bị đốt rất nhanh.
- Khi đang tuning thuật toán, source of truth tốt nhất là session in-memory + debug log, sau đó lưu một bản hoàn chỉnh khi `Finish`.
- Nếu app crash giữa buổi chạy, phase sau có thể thêm local draft persistence trước, không cần Firestore realtime ngay.

Flow sync được chọn:

1. Tracking chạy foreground, giữ state trong `TrackingSession`.
2. UI đọc `TrackingSessionSnapshot` để render realtime.
3. Khi user bấm `Finish`, app convert snapshot thành `ActivityDetail`.
4. Repository lưu một document activity hoàn chỉnh lên `users/{uid}/activities/{activityId}`.
5. Giai đoạn thử nghiệm lưu thêm `trackingDebug`.
6. Không refresh leaderboard trong giai đoạn testing; stats chính vẫn dùng Strava.

Realtime Firestore chỉ nên cân nhắc sau này nếu có live sharing/live tracking cho người khác xem.

## Trial Report Sau Mỗi Buổi Chạy

Mỗi buổi chạy thử cần ghi lại:

- `trialId`, thiết bị, OS, app build, ngày giờ.
- Môi trường: thoáng, đô thị, nhiều nhà cao tầng, công viên, cầu/hầm.
- So sánh distance RunNow với Strava/Garmin/Apple Workout nếu có.
- Tổng thời gian, moving time, average pace, current pace có bị lag/nhảy không.
- Số điểm GPS accepted/rejected theo từng reason.
- Accuracy P50/P95, accuracy tệ nhất.
- Max implied speed bị reject.
- Route map có drift, cắt góc, hoặc nhảy điểm không.
- Ghi chú cảm nhận: lúc đứng chờ đèn đỏ, pace có về chậm/dừng hợp lý không.

Sau mỗi trial, chỉ tuning một nhóm tham số chính:

- `maxAccuracyMeters`
- `maxRunningSpeedMetersPerSecond`
- `minSegmentDistanceMeters`
- `currentPaceWindow`

## Trial 001 Findings

Session đầu tiên đọc từ Firestore:

- Distance: `238.51m`
- Moving time cũ: `174s`; elapsed: `202s`
- GPS logs: `140`
- Accepted/rejected: `74/66`
- Reject reasons: `stationaryNoise=60`, `nonMonotonicTime=3`, `unrealisticSpeed=3`
- Accuracy P50/P95: khoảng `14.25m`
- Max accepted speed: `6.84m/s`

Điều chỉnh sau trial:

- Không dùng GPS point để làm timer UI; thêm `TrackingSession.tick()` mỗi giây.
- Current pace window giảm từ `15s` xuống `12s`.
- Max accepted speed giảm từ `7m/s` xuống `6m/s` để loại bớt spike pace quá nhanh đầu buổi.
- GPS warm-up cần nhiều sample ổn định hơn trước khi cho start.

## Trial 002 Findings

So sánh RunNow trial với Garmin sync qua Strava của user `vlsilver`:

- RunNow trial: `446.71m`, moving `335s`, pace khoảng `12:30/km`.
- Garmin/Strava: `376.7m`, moving `261s`, elapsed `300s`, pace khoảng `11:33/km`.
- RunNow start lúc `09:00:52`, Garmin start lúc `09:01:30`.
- Tại thời điểm Garmin start, RunNow đã cộng khoảng `43m`.
- Sau `30s`, RunNow đã nhảy lên khoảng `40m` dù user đang đứng đợi GPS.

Kết luận:

- Sai số chính không phải do Firestore hay sync.
- Sai số đến từ việc RunNow vừa warm-up vừa tính distance.
- Accuracy P50/P95 khoảng `14m`, nghĩa là accuracy đơn thuần không đủ để quyết định start.
- Cần đổi UI flow thành `LOCK GPS` trước, `START NOW` sau, và không tính warm-up point vào session distance.

## TODO

1. Core model
   - [x] Chuẩn hoá `ActivitySource` và `RoutePoint`.
   - [x] Thêm `TrackingSession` core thuần Dart.
   - [x] Unit test distance, filter, pause/resume, split, debug log.

2. Repository
   - [x] Thêm API lưu activity tự record.
   - [x] Lưu trial debug log trong giai đoạn MVP.
   - [x] Không tính tracking trial vào leaderboard/stats chính.
   - [ ] Không push realtime từng GPS point lên Firestore trong MVP.

3. UI
   - [x] Thêm tab `Chạy`.
   - [x] Màn hình Start/Pause/Resume/Finish.
   - [x] Xin quyền foreground location trước khi start.
   - [ ] Map realtime route.
   - [x] Save trial activity sau khi finish.

4. Real-world tuning
   - [ ] Chạy test 1-2km trong khu vực thoáng.
   - [ ] Chạy test đô thị/nhiều nhà cao tầng.
   - [ ] So sánh với Strava/Garmin/Apple Workout nếu có.
   - [ ] Ghi trial report sau mỗi buổi chạy.
   - [ ] Điều chỉnh accuracy threshold, max speed, min segment.
   - [ ] Xem lại pace rolling window.

5. Phase sau
   - [ ] Auto-pause.
   - [ ] Background tracking.
   - [ ] Audio cue.
   - [ ] Live activity trên iOS.
   - [ ] Sensor fusion nâng cao.
   - [ ] Export/share visual route replay.
