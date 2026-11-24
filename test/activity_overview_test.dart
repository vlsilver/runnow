import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/activity_overview.dart';
import 'package:myrun/src/widgets/split_pace_chart.dart';

void main() {
  group('sessionWhenLabel', () {
    final now = DateTime(2026, 10, 30, 21);

    test('hôm nay, hôm qua, rồi ngày tháng', () {
      expect(
        sessionWhenLabel(DateTime(2026, 10, 30, 4, 10), now),
        'Hôm nay 04:10',
      );
      expect(
        sessionWhenLabel(DateTime(2026, 10, 29, 23, 5), now),
        'Hôm qua 23:05',
      );
      expect(sessionWhenLabel(DateTime(2026, 10, 25, 6), now), '25/10 06:00');
    });
  });

  group('kmSplitRows', () {
    test('pace mỗi km, thanh dài theo tốc độ so với km nhanh nhất', () {
      final rows = kmSplitRows([
        {'split': 1, 'distanceMeters': 1000, 'movingTimeSeconds': 341},
        {'split': 2, 'distanceMeters': 1000, 'movingTimeSeconds': 312},
        {'split': 3, 'distanceMeters': 200, 'movingTimeSeconds': 50},
      ]);
      expect(rows.map((r) => r.label), ['1', '2', '0.2']);
      // 341 s/km; 312 s/km; 50 s cho 200 m = 250 s/km.
      expect(rows.map((r) => r.pace), [341, 312, 250]);
      expect(rows.map((r) => r.fastest), [false, true, false]);
      // 312/341 = 0.915; km lẻ nhanh hơn km nhanh nhất thì thanh kịch 1.
      expect(rows[0].widthFactor, closeTo(0.915, 0.001));
      expect(rows[1].widthFactor, 1);
      expect(rows[2].widthFactor, 1);
    });

    test('bỏ split hỏng; không có km trọn nào thì rỗng', () {
      expect(
        kmSplitRows([
          {'split': 1, 'distanceMeters': 0, 'movingTimeSeconds': 300},
          {'split': 2, 'distanceMeters': 400, 'movingTimeSeconds': 150},
        ]),
        isEmpty,
      );
    });
  });
}
