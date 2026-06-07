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

  test('builds route points from Strava latlng stream fallback', () {
    final points = stravaRoutePointsFromStreams({
      'time': {
        'data': [0, 12, 25],
      },
      'latlng': {
        'data': [
          [10.1, 106.1],
          [10.2, 106.2],
          [10.3, 106.3],
        ],
      },
    }, startedAt: DateTime.utc(2026, 6, 6, 14, 25, 47));

    expect(points, hasLength(3));
    expect(points.first.latitude, 10.1);
    expect(points.first.longitude, 106.1);
    expect(points.last.timestamp.toUtc(), DateTime.utc(2026, 6, 6, 14, 26, 12));
  });

  test('backfills missing Strava streams without touching RunNow trials', () {
    expect(
      shouldBackfillStravaStreams({
        'source': 'runnow',
        'streamsVersion': 3,
      }, currentStreamsVersion: 4),
      isFalse,
    );
    expect(
      shouldBackfillStravaStreams({
        'source': 'strava',
        'streamsVersion': 3,
        'streams': <String, dynamic>{},
      }, currentStreamsVersion: 4),
      isTrue,
    );
    expect(
      shouldBackfillStravaStreams({
        'source': 'strava',
        'streamsVersion': 3,
      }, currentStreamsVersion: 4),
      isTrue,
    );
    expect(
      shouldBackfillStravaStreams({
        'source': 'strava',
        'streamsVersion': 4,
      }, currentStreamsVersion: 4),
      isTrue,
    );
    expect(
      shouldBackfillStravaStreams({
        'source': 'strava',
        'streamsHydrated': false,
        'streamsVersion': 4,
      }, currentStreamsVersion: 4),
      isTrue,
    );
    expect(
      shouldBackfillStravaStreams({
        'source': 'strava',
        'streamsHydrated': true,
        'streamsVersion': 4,
      }, currentStreamsVersion: 4),
      isFalse,
    );
  });

  test('downsamples long Strava streams before Firestore caching', () {
    final streams = {
      'distance': [for (var index = 0; index < 14169; index++) index * 10.0],
      'heartrate': [for (var index = 0; index < 14169; index++) 120.0 + index],
      'velocity_smooth': [
        for (var index = 0; index < 14169; index++) 2.5 + index / 1000,
      ],
    };

    final sampled = downsampleStreams(streams, maxSamples: 300);

    expect(sampled['distance'], hasLength(300));
    expect(sampled['heartrate'], hasLength(300));
    expect(sampled['velocity_smooth'], hasLength(300));
    expect(sampled['distance']!.first, streams['distance']!.first);
    expect(sampled['distance']!.last, streams['distance']!.last);
  });

  test('removes empty and non-finite stream values before caching', () {
    final sampled = downsampleStreams({
      'distance': [0, double.nan, 1000, double.infinity],
      'latlng': const [],
    }, maxSamples: 300);

    expect(sampled.keys, ['distance']);
    expect(sampled['distance'], [0, 1000]);
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
