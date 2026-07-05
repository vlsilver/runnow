import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/activity_eligibility.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';

void main() {
  test('counts RunNow sessions from exactly 500 meters', () {
    expect(isRunNowActivityDistanceEligible(_runNow('ok', 500)), isTrue);
    expect(isRunNowActivityDistanceEligible(_runNow('short', 499.9)), isFalse);
  });

  test(
    'journal keeps overlapping RunNow session and links preferred Strava',
    () {
      final startedAt = DateTime.utc(2026, 7, 5, 1);
      final runNow = _runNow(
        'runnow',
        5000,
        startedAt: startedAt,
        elapsedSeconds: 1800,
      );
      final strava = ActivitySummary(
        id: 'strava',
        name: 'Strava Run',
        kind: ActivityKind.run,
        startedAt: startedAt.add(const Duration(minutes: 2)),
        distanceMeters: 5100,
        movingTimeSeconds: 1700,
        elapsedTimeSeconds: 1800,
      );

      final entries = buildJournalActivityEntries([runNow, strava]);

      expect(entries, hasLength(2));
      expect(
        entries
            .singleWhere((entry) => entry.activity.id == 'runnow')
            .preferredStravaActivityId,
        'strava',
      );
    },
  );

  test('prefers Strava when overlap exceeds 30 percent of RunNow time', () {
    final runNow = _runNow('runnow', 5000, elapsedSeconds: 1800);
    final strava = _strava(
      'strava',
      runNow.startedAt.add(const Duration(minutes: 10)),
      elapsedSeconds: 1800,
    );

    expect(activityOverlapRatio(runNow, strava), closeTo(2 / 3, 0.001));
    expect(selectOfficialActivities([runNow, strava]), [strava]);
  });

  test('keeps both recordings when overlap is exactly 30 percent', () {
    final runNow = _runNow('runnow', 5000, elapsedSeconds: 1000);
    final strava = _strava(
      'strava',
      runNow.startedAt.add(const Duration(seconds: 700)),
      elapsedSeconds: 300,
    );

    expect(activityOverlapRatio(runNow, strava), 0.3);
    expect(
      selectOfficialActivities([runNow, strava]),
      containsAll([runNow, strava]),
    );
  });

  test('does not let a Strava walk suppress a RunNow run', () {
    final runNow = _runNow('runnow', 5000);
    final walk = _strava('walk', runNow.startedAt, kind: ActivityKind.walk);

    expect(
      selectOfficialActivities([runNow, walk]),
      containsAll([runNow, walk]),
    );
  });

  test('never treats a Strava activity itself as a RunNow duplicate', () {
    final stravaA = _strava('strava-a', DateTime.utc(2026, 7, 4, 6));
    final stravaB = _strava('strava-b', DateTime.utc(2026, 7, 4, 6));

    expect(preferredStravaDuplicate(stravaA, [stravaB]), isNull);
  });
}

ActivitySummary _runNow(
  String id,
  double distanceMeters, {
  int elapsedSeconds = 1800,
  DateTime? startedAt,
}) => ActivitySummary(
  id: id,
  name: id,
  kind: ActivityKind.run,
  startedAt: startedAt ?? DateTime.utc(2026, 7, 4, 6),
  distanceMeters: distanceMeters,
  movingTimeSeconds: elapsedSeconds,
  elapsedTimeSeconds: elapsedSeconds,
  source: ActivitySource.runnow,
);

ActivitySummary _strava(
  String id,
  DateTime startedAt, {
  int elapsedSeconds = 1800,
  ActivityKind kind = ActivityKind.run,
}) => ActivitySummary(
  id: id,
  name: id,
  kind: kind,
  startedAt: startedAt,
  distanceMeters: 5000,
  movingTimeSeconds: elapsedSeconds,
  elapsedTimeSeconds: elapsedSeconds,
  source: ActivitySource.strava,
);
