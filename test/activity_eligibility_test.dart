import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/activity_eligibility.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';

void main() {
  test('counts RunNow sessions from exactly 500 meters', () {
    expect(isCountedNonStravaRun(_runNow('ok', 500)), isTrue);
    expect(isCountedNonStravaRun(_runNow('short', 499.9)), isFalse);
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

  test('journal page uses overlap context outside the visible page', () {
    final startedAt = DateTime.utc(2026, 7, 5, 1);
    final runNow = _runNow(
      'runnow-page-1',
      5000,
      startedAt: startedAt,
      elapsedSeconds: 1800,
    );
    final strava = _strava(
      'strava-page-2',
      startedAt.add(const Duration(minutes: 2)),
      elapsedSeconds: 1800,
    );

    final entries = buildJournalPageEntries([runNow], [runNow, strava]);

    expect(entries, hasLength(1));
    expect(entries.single.preferredStravaActivityId, strava.id);
  });

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

  test('indexed duplicate lookup detects an earlier long Strava interval', () {
    final runNow = _runNow(
      'runnow',
      5000,
      startedAt: DateTime.utc(2026, 7, 4, 8),
      elapsedSeconds: 1800,
    );
    final longStrava = _strava(
      'long-strava',
      DateTime.utc(2026, 7, 4, 6),
      elapsedSeconds: 3 * 60 * 60,
    );
    final unrelated = _strava(
      'unrelated',
      DateTime.utc(2026, 7, 4, 7),
      elapsedSeconds: 60,
    );

    expect(
      preferredStravaDuplicates([runNow, unrelated, longStrava])['runnow'],
      longStrava,
    );
  });

  test('indexed duplicate lookup preserves source-list preference', () {
    final runNow = _runNow('runnow', 5000);
    final preferred = _strava('preferred', runNow.startedAt);
    final other = _strava('other', runNow.startedAt);

    expect(
      preferredStravaDuplicates([runNow, preferred, other])['runnow'],
      preferred,
    );
  });

  test('apple_health run is eligible and dedups vs strava + native', () {
    final start = DateTime.utc(2026, 7, 6, 6);
    expect(isCountedNonStravaRun(_appleHealth('h', 5000)), isTrue);
    expect(isCountedNonStravaRun(_appleHealth('short', 499)), isFalse);

    // Health trùng Strava → Strava thắng.
    final health = _appleHealth(
      'health',
      5000,
      startedAt: start.add(const Duration(minutes: 2)),
    );
    final strava = _strava('strava', start);
    expect(selectOfficialActivities([health, strava]), [strava]);

    // Health trùng 3i native (không Strava) → giữ native, order-independent.
    final runNow = _runNow('runnow', 5000, startedAt: start);
    for (final input in [
      [health, runNow],
      [runNow, health],
    ]) {
      final got = selectOfficialActivities(input);
      expect(got, hasLength(1));
      expect(got.single.source, ActivitySource.runnow);
    }
  });

  test('two apple_health runs at different times both count', () {
    final base = DateTime.utc(2026, 7, 6, 6);
    final a = _appleHealth('h-a', 5000, startedAt: base);
    final b = _appleHealth(
      'h-b',
      3000,
      startedAt: base.add(const Duration(hours: 3)),
    );
    expect(selectOfficialActivities([a, b]), hasLength(2));
  });
}

ActivitySummary _appleHealth(
  String id,
  double distanceMeters, {
  int elapsedSeconds = 1800,
  DateTime? startedAt,
}) => ActivitySummary(
  id: id,
  name: id,
  kind: ActivityKind.run,
  startedAt: startedAt ?? DateTime.utc(2026, 7, 6, 6),
  distanceMeters: distanceMeters,
  movingTimeSeconds: elapsedSeconds,
  elapsedTimeSeconds: elapsedSeconds,
  source: ActivitySource.appleHealth,
);

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
