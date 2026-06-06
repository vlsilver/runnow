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
    expect(activitySummaryToSyncMap(summary)['source'], 'strava');
    expect(activitySummaryToSyncMap(summary)['schemaVersion'], 1);
  });

  test('tracked activity map stores detail and trial debug payload', () {
    final detail = ActivityDetail(
      summary: ActivitySummary(
        id: 'trial-1',
        name: 'RunNow trial',
        kind: ActivityKind.run,
        startedAt: DateTime.utc(2026, 6, 1, 6),
        distanceMeters: 5000,
        movingTimeSeconds: 1500,
        elapsedTimeSeconds: 1600,
        source: ActivitySource.runnow,
        sourceActivityId: 'trial-1',
        hydrated: true,
      ),
      splits: [
        {'split': 1, 'distanceMeters': 1000, 'movingTimeSeconds': 300},
      ],
      streams: {
        'distance': [0, 1000],
        'velocity_smooth': [0, 3.3],
      },
    );

    final map = trackedActivityToFirestoreMap(
      detail,
      trackingDebug: {
        'pointLogs': [
          {'decision': 'accepted'},
        ],
      },
      savedAt: 'server-time',
    );

    expect(map['source'], 'runnow');
    expect(map['hydrated'], isTrue);
    expect(map['streamsHydrated'], isTrue);
    expect(map['trackingSavedAt'], 'server-time');
    expect((map['splits'] as List<dynamic>), hasLength(1));
    expect(
      (map['trackingDebug'] as Map<String, dynamic>)['pointLogs'],
      hasLength(1),
    );
  });

  test(
    'demo repository keeps tracked trials out of primary activity stream',
    () async {
      final repository = DemoActivityRepository();
      final detail = ActivityDetail(
        summary: ActivitySummary(
          id: 'trial-demo',
          name: 'RunNow Trial',
          kind: ActivityKind.run,
          startedAt: DateTime.utc(2026, 6, 1, 6),
          distanceMeters: 1000,
          movingTimeSeconds: 360,
          elapsedTimeSeconds: 370,
          source: ActivitySource.runnow,
          hydrated: true,
        ),
      );

      await repository.saveTrackedActivity(detail);

      final primary = await repository.watchActivities().first;
      final trials = await repository.watchTrackedTrialActivities().first;
      expect(primary.any((activity) => activity.id == 'trial-demo'), isFalse);
      expect(trials.single.id, 'trial-demo');
    },
  );
}
