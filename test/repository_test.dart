import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';

void main() {
  test('uses hydrated Firestore detail even when streams are unavailable', () {
    expect(
      hasCachedActivityDetail({'hydrated': true, 'streamsHydrated': false}),
      isTrue,
    );
  });

  test('recognizes detail cached before the hydration flag sync fix', () {
    expect(
      hasCachedActivityDetail({
        'hydrated': false,
        'splits': <dynamic>[],
        'laps': <dynamic>[],
        'streams': <String, dynamic>{},
      }),
      isTrue,
    );
  });

  test('summary sync does not overwrite detail hydration state', () {
    final summary = ActivitySummary(
      id: '42',
      name: 'Morning run',
      kind: ActivityKind.run,
      startedAt: DateTime.utc(2026, 5, 30),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
      elapsedTimeSeconds: 1600,
    );

    expect(activitySummaryToSyncMap(summary), isNot(contains('hydrated')));
  });
}
