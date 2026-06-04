import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';

void main() {
  test('accepts only supported activity kinds', () {
    expect(parseActivityKind('Run'), ActivityKind.run);
    expect(parseActivityKind('Hike'), ActivityKind.hike);
    expect(parseActivityKind('Ride'), isNull);
  });

  test('calculates pace from moving time and distance', () {
    final activity = ActivitySummary(
      id: '42',
      name: 'Morning run',
      kind: ActivityKind.run,
      startedAt: DateTime(2026, 5, 30),
      distanceMeters: 5000,
      movingTimeSeconds: 1500,
      elapsedTimeSeconds: 1600,
    );
    expect(activity.paceSecondsPerKm, 300);
  });

  test('parses athlete profile and last sync timestamp', () {
    final lastSyncedAt = DateTime.utc(2026, 5, 31, 8);
    final profile = UserProfile.fromMap({
      'athleteId': '123',
      'athlete': {'firstname': 'Linh', 'lastname': 'Vang'},
      'lastSyncedAt': lastSyncedAt,
    });
    expect(profile.athleteId, '123');
    expect(profile.displayName, 'Linh Vang');
    expect(profile.lastSyncedAt, lastSyncedAt.toLocal());
  });

  test('parses detail laps and streams', () {
    final detail = ActivityDetail.fromMap({
      'id': '42',
      'name': 'Morning run',
      'sportType': 'Run',
      'startedAt': '2026-05-30T00:00:00Z',
      'distanceMeters': 5000,
      'movingTimeSeconds': 1500,
      'elapsedTimeSeconds': 1600,
      'laps': [
        {'name': 'Lap 1', 'distanceMeters': 1000},
      ],
      'streams': {
        'heartrate': [140, 145],
      },
    });
    expect(detail.laps, hasLength(1));
    expect(detail.streams['heartrate'], [140.0, 145.0]);
  });

  test(
    'detects activity summary changes without touching cached detail fields',
    () {
      final summary = ActivitySummary(
        id: '42',
        name: 'Morning run',
        kind: ActivityKind.run,
        startedAt: DateTime.utc(2026, 5, 30),
        distanceMeters: 5000,
        movingTimeSeconds: 1500,
        elapsedTimeSeconds: 1600,
        hydrated: true,
      );
      final next = activitySummaryToSyncMap(summary);
      final existing = {
        ...next,
        'hydrated': true,
        'streams': {
          'heartrate': [140, 145],
        },
      };
      expect(activitySummaryHasChanges(existing, next), isFalse);
      expect(
        activitySummaryHasChanges({...existing, 'distanceMeters': 5100}, next),
        isTrue,
      );
    },
  );

  test('builds leaderboard aggregate for common ranking windows', () {
    final now = DateTime(2026, 6, 4, 12);
    final entry = leaderboardEntryToMap(
      uid: 'runner-1',
      profile: {
        'nickname': 'Linh',
        'profileVisibility': 'public',
        'avatarUrl': 'https://example.com/a.png',
      },
      activities: [
        ActivitySummary(
          id: 'recent',
          name: 'Recent run',
          kind: ActivityKind.run,
          startedAt: DateTime(2026, 6, 3, 6),
          distanceMeters: 5000,
          movingTimeSeconds: 1800,
          elapsedTimeSeconds: 1900,
        ),
        ActivitySummary(
          id: 'old',
          name: 'Old run',
          kind: ActivityKind.run,
          startedAt: DateTime(2026, 5, 1, 6),
          distanceMeters: 10000,
          movingTimeSeconds: 3600,
          elapsedTimeSeconds: 3700,
        ),
      ],
      now: now,
    );
    expect(entry['uid'], 'runner-1');
    expect(entry['displayName'], 'Linh');
    expect(entry['profileVisibility'], 'public');
    expect(
      (entry['rollingSevenDays'] as Map<String, dynamic>)['distanceMeters'],
      5000,
    );
    expect((entry['currentMonth'] as Map<String, dynamic>)['activeDays'], 1);
  });
}
