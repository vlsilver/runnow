import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/models.dart';

void main() {
  test('compares rolling seven day distance with the previous seven days', () {
    final comparison = rollingSevenDayComparison([
      _activity(DateTime(2026, 6, 3, 8), 5000),
      _activity(DateTime(2026, 5, 28, 8), 3000),
      _activity(DateTime(2026, 5, 27, 8), 4000),
      _activity(DateTime(2026, 5, 20, 8), 9000),
    ], DateTime(2026, 6, 3, 20));

    expect(comparison.current.distanceMeters, 8000);
    expect(comparison.current.activityCount, 2);
    expect(comparison.previous.distanceMeters, 4000);
    expect(comparison.distanceChangeRatio, 1);
  });

  test('groups seven day distance by activity kind', () {
    final distribution = distanceByActivityKind(
      [
        _activity(DateTime(2026, 6, 3), 5000),
        _activity(DateTime(2026, 6, 2), 2000, kind: ActivityKind.walk),
        _activity(DateTime(2026, 5, 20), 9000),
      ],
      start: DateTime(2026, 5, 28),
      end: DateTime(2026, 6, 4),
    );

    expect(distribution.map((item) => item.kind), [
      ActivityKind.run,
      ActivityKind.walk,
    ]);
    expect(distribution.map((item) => item.distanceMeters), [5000, 2000]);
  });
}

ActivitySummary _activity(
  DateTime startedAt,
  double distanceMeters, {
  ActivityKind kind = ActivityKind.run,
}) {
  return ActivitySummary(
    id: startedAt.toIso8601String(),
    name: 'Run',
    kind: kind,
    startedAt: startedAt,
    distanceMeters: distanceMeters,
    movingTimeSeconds: 1800,
    elapsedTimeSeconds: 1900,
  );
}
