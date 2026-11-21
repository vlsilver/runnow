import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/screens/live_viewer_screen.dart';
import 'package:myrun/src/widgets/live_bits.dart';

void main() {
  group('routeKmMarks', () {
    // Dọc kinh tuyến, mỗi bước 0.004° vĩ độ ≈ 443 m. Cộng dồn: 443, 886,
    // 1329, 1772, 2215 m, nên mốc 1 km ở điểm thứ 3, mốc 2 km ở điểm thứ 5.
    final straight = [
      for (var i = 0; i < 6; i++) LatLng(21 + i * 0.004, 105.85),
    ];

    test('đặt mốc ở điểm đầu tiên chạm mỗi km', () {
      final marks = routeKmMarks(straight);
      expect(marks.map((m) => m.km), [1, 2]);
      expect(marks[0].point, straight[3]);
      expect(marks[1].point, straight[5]);
    });

    test('một bước dài vượt hai km thì hai mốc cùng một điểm', () {
      // 0.0225° ≈ 2.49 km.
      final jump = [const LatLng(21, 105.85), const LatLng(21.0225, 105.85)];
      final marks = routeKmMarks(jump);
      expect(marks.map((m) => m.km), [1, 2]);
      expect(marks.every((m) => m.point == jump[1]), isTrue);
    });

    test('rỗng hoặc một điểm thì không có mốc', () {
      expect(routeKmMarks(const []), isEmpty);
      expect(routeKmMarks(const [LatLng(21, 105.85)]), isEmpty);
    });
  });

  group('liveRoutePoints', () {
    final at = DateTime(2026, 10, 30, 6);
    RoutePoint point(double lat) =>
        RoutePoint(latitude: lat, longitude: 105.85, timestamp: at);
    LiveTrackingSession session({
      List<RoutePoint> preview = const [],
      RoutePoint? last,
    }) => LiveTrackingSession(
      id: 's',
      ownerUid: 'u',
      ownerName: 'A',
      visibility: LiveTrackingVisibility.club,
      status: LiveTrackingStatus.running,
      startedAt: at,
      updatedAt: at,
      distanceMeters: 0,
      movingTimeSeconds: 0,
      routePreview: preview,
      lastLocation: last,
    );

    test('mới bắt đầu, chưa có routePreview: vẫn có chỗ đang chạy', () {
      expect(liveRoutePoints(session(last: point(21))), [
        const LatLng(21, 105.85),
      ]);
    });

    test('nối điểm mới nhất vào sau routePreview', () {
      expect(
        liveRoutePoints(
          session(preview: [point(21), point(21.001)], last: point(21.002)),
        ),
        const [
          LatLng(21, 105.85),
          LatLng(21.001, 105.85),
          LatLng(21.002, 105.85),
        ],
      );
    });

    test('điểm mới nhất trùng điểm cuối routePreview thì không lặp', () {
      expect(
        liveRoutePoints(session(preview: [point(21)], last: point(21))),
        const [LatLng(21, 105.85)],
      );
    });

    test('chưa có GPS thì rỗng', () {
      expect(liveRoutePoints(session()), isEmpty);
    });
  });

  group('liveElapsedSeconds', () {
    final now = DateTime(2026, 10, 30, 6, 30);

    LiveTrackingSession session(
      DateTime updatedAt, {
      LiveTrackingStatus status = LiveTrackingStatus.running,
    }) => LiveTrackingSession(
      id: 's',
      ownerUid: 'u',
      ownerName: 'A',
      visibility: LiveTrackingVisibility.club,
      status: status,
      startedAt: DateTime(2026, 10, 30, 6),
      updatedAt: updatedAt,
      distanceMeters: 1000,
      movingTimeSeconds: 600,
    );

    test('đang chạy: cộng khoảng từ lần ghi cuối tới giờ', () {
      final s = session(now.subtract(const Duration(seconds: 10)));
      expect(liveElapsedSeconds(s, now), 610);
    });

    test('cộng thêm tối đa 3 phút', () {
      final s = session(now.subtract(const Duration(minutes: 10)));
      expect(liveElapsedSeconds(s, now), 780);
    });

    test('đồng hồ người xem chậm hơn server thì không trừ', () {
      final s = session(now.add(const Duration(seconds: 30)));
      expect(liveElapsedSeconds(s, now), 600);
    });

    test('tạm dừng thì đứng yên', () {
      final s = session(
        now.subtract(const Duration(seconds: 40)),
        status: LiveTrackingStatus.paused,
      );
      expect(liveElapsedSeconds(s, now), 600);
    });
  });
}
