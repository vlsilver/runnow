import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';

void main() {
  final now = DateTime.utc(2026, 10, 31, 6);

  LiveTrackingSession session(
    String id,
    LiveTrackingStatus status, {
    required Duration ago,
    double meters = 3000,
  }) => LiveTrackingSession(
    id: id,
    ownerUid: 'u-$id',
    ownerName: id,
    visibility: LiveTrackingVisibility.club,
    status: status,
    startedAt: now.subtract(ago + const Duration(minutes: 30)),
    updatedAt: now.subtract(ago),
    distanceMeters: meters,
    movingTimeSeconds: 1800,
  );

  test(
    'buổi live gần đây: chỉ buổi đã xong hoặc mất tín hiệu, bỏ buổi 0 km',
    () {
      // Thứ tự như truy vấn trả về: cập nhật mới trước.
      final sessions = [
        session(
          'dang-chay',
          LiveTrackingStatus.running,
          ago: const Duration(seconds: 20),
        ),
        session(
          'tam-dung',
          LiveTrackingStatus.paused,
          ago: const Duration(minutes: 2),
        ),
        session(
          'vua-xong',
          LiveTrackingStatus.finished,
          ago: const Duration(minutes: 5),
        ),
        // App bị tắt giữa chừng: vẫn "running" nhưng 6 phút không cập nhật.
        session(
          'mat-song',
          LiveTrackingStatus.running,
          ago: const Duration(minutes: 6),
        ),
        session(
          'khong-km',
          LiveTrackingStatus.finished,
          ago: const Duration(minutes: 40),
          meters: 0,
        ),
        session(
          'het-han',
          LiveTrackingStatus.expired,
          ago: const Duration(hours: 3),
        ),
      ];
      expect(
        [for (final s in recentLiveSessions(sessions, now)) s.id],
        ['vua-xong', 'mat-song', 'het-han'],
      );
    },
  );
}
