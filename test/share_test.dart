import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/share.dart';

void main() {
  test('builds a readable Vietnamese recap caption', () {
    final activity = ActivitySummary(
      id: '42',
      name: 'Chạy buổi sáng',
      kind: ActivityKind.run,
      startedAt: DateTime(2026, 5, 31),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
      elapsedTimeSeconds: 1600,
    );
    expect(
      buildShareCaption(activity),
      'Chạy buổi sáng\n5.00 km • 25:00 • 5:00 /km\nChia sẻ từ RunNow',
    );
  });
}
