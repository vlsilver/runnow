import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/tracking_session.dart';

void main() {
  test('calculates route distance and pace from accepted GPS samples', () {
    final session = TrackingSession(
      id: 'trial-1',
      config: const TrackingConfig(minSegmentDistanceMeters: 0.5),
    )..start(DateTime.utc(2026, 6, 1, 6));

    session.addLocation(_sample(0, latitude: 10, longitude: 106));
    final snapshot = session.addLocation(
      _sample(300, latitude: 10, longitude: 106.0137),
    );

    expect(snapshot.status, TrackingSessionStatus.running);
    expect(snapshot.distanceMeters, closeTo(1500, 60));
    expect(snapshot.movingTimeSeconds, 300);
    expect(snapshot.averagePaceSecondsPerKm, closeTo(200, 8));
    expect(snapshot.currentPaceSecondsPerKm, closeTo(200, 8));
    expect(snapshot.routePoints, hasLength(2));
  });

  test('running timer ticks independently from GPS samples', () {
    final session = TrackingSession(id: 'trial-timer')
      ..start(DateTime.utc(2026, 6, 1, 6));

    final snapshot = session.tick(DateTime.utc(2026, 6, 1, 6, 0, 5));

    expect(snapshot.distanceMeters, 0);
    expect(snapshot.movingTimeSeconds, 5);
  });

  test('rejects noisy GPS points without moving the route anchor', () {
    final session = TrackingSession(
      id: 'trial-2',
      config: const TrackingConfig(
        maxAccuracyMeters: 20,
        minSegmentDistanceMeters: 2,
      ),
    )..start(DateTime.utc(2026, 6, 1, 6));

    session.addLocation(_sample(0, latitude: 10, longitude: 106));
    session.addLocation(
      _sample(10, latitude: 10.0001, longitude: 106, accuracyMeters: 80),
    );
    final snapshot = session.addLocation(
      _sample(120, latitude: 10, longitude: 106.0055),
    );

    expect(snapshot.pointLogs, hasLength(3));
    expect(snapshot.pointLogs[1].decision, TrackingPointDecision.rejected);
    expect(
      snapshot.pointLogs[1].rejectReason,
      TrackingRejectReason.lowAccuracy,
    );
    expect(snapshot.distanceMeters, closeTo(600, 30));
    expect(snapshot.routePoints, hasLength(2));
  });

  test('does not connect route distance across manual pause and resume', () {
    final session = TrackingSession(
      id: 'trial-3',
      config: const TrackingConfig(minSegmentDistanceMeters: 0.5),
    )..start(DateTime.utc(2026, 6, 1, 6));

    session.addLocation(_sample(0, latitude: 10, longitude: 106));
    session.addLocation(_sample(120, latitude: 10, longitude: 106.0055));
    session.pause(DateTime.utc(2026, 6, 1, 6, 3));
    session.addLocation(_sample(150, latitude: 10, longitude: 106.02));
    session.resume(DateTime.utc(2026, 6, 1, 6, 5));
    session.addLocation(_sample(320, latitude: 10, longitude: 106.02));
    final snapshot = session.addLocation(
      _sample(440, latitude: 10, longitude: 106.0255),
    );

    expect(
      snapshot.pointLogs.any(
        (log) => log.rejectReason == TrackingRejectReason.paused,
      ),
      isTrue,
    );
    expect(snapshot.distanceMeters, closeTo(1200, 60));
    expect(snapshot.movingTimeSeconds, 320);
    expect(snapshot.routePoints, hasLength(4));
  });

  test(
    'creates kilometer splits and converts a finished run to activity summary',
    () {
      final session = TrackingSession(
        id: 'trial-4',
        config: const TrackingConfig(
          minSegmentDistanceMeters: 0.5,
          splitDistanceMeters: 1000,
        ),
      )..start(DateTime.utc(2026, 6, 1, 6));

      session.addLocation(_sample(0, latitude: 10, longitude: 106));
      session.addLocation(_sample(300, latitude: 10, longitude: 106.00913));
      session.addLocation(_sample(600, latitude: 10, longitude: 106.0195));
      final snapshot = session.finish(DateTime.utc(2026, 6, 1, 6, 10));
      final summary = snapshot.toActivitySummary(recordingDevice: 'Simulator');
      final detail = snapshot.toActivityDetail(recordingDevice: 'Simulator');

      expect(snapshot.status, TrackingSessionStatus.finished);
      expect(snapshot.splits, hasLength(2));
      expect(snapshot.splits.first.movingTimeSeconds, closeTo(300, 12));
      expect(summary.source, ActivitySource.runnow);
      expect(summary.sourceActivityId, 'trial-4');
      expect(summary.recordingDevice, 'Simulator');
      expect(summary.hydrated, isTrue);
      expect(summary.routePoints, hasLength(3));
      expect(detail.splits, hasLength(2));
      expect(detail.streams['distance'], hasLength(3));
      expect(detail.streams['velocity_smooth'], hasLength(3));
    },
  );

  test('keeps multi-kilometer split timing stable across pace changes', () {
    final session = TrackingSession(
      id: 'trial-4b',
      config: const TrackingConfig(
        minSegmentDistanceMeters: 0.5,
        splitDistanceMeters: 1000,
      ),
    )..start(DateTime.utc(2026, 6, 1, 6));

    session.addLocation(_sample(0, latitude: 10, longitude: 106));
    session.addLocation(_sample(300, latitude: 10, longitude: 106.00913));
    session.addLocation(_sample(580, latitude: 10, longitude: 106.01826));
    session.addLocation(_sample(920, latitude: 10, longitude: 106.02739));
    session.addLocation(_sample(1180, latitude: 10, longitude: 106.03652));
    session.addLocation(_sample(1520, latitude: 10, longitude: 106.0462));
    final snapshot = session.finish(DateTime.utc(2026, 6, 1, 6, 26));

    expect(snapshot.splits, hasLength(5));
    expect(snapshot.splits[0].movingTimeSeconds, closeTo(300, 12));
    expect(snapshot.splits[1].movingTimeSeconds, closeTo(280, 12));
    expect(snapshot.splits[2].movingTimeSeconds, closeTo(340, 12));
    expect(snapshot.splits[3].movingTimeSeconds, closeTo(260, 12));
    expect(snapshot.splits[4].movingTimeSeconds, closeTo(321, 12));
  });

  test('exports full trial debug log for algorithm tuning', () {
    final session = TrackingSession(id: 'trial-5')
      ..start(DateTime.utc(2026, 6, 1, 6));

    session.addLocation(_sample(0, latitude: 10, longitude: 106));
    session.addLocation(_sample(1, latitude: 10, longitude: 107));
    final debug = session.snapshot().toDebugMap();

    expect(debug['pointLogs'], isA<List<dynamic>>());
    expect(debug['routePoints'], isA<List<dynamic>>());
    expect(
      (debug['pointLogs'] as List<dynamic>).last['rejectReason'],
      'unrealisticSpeed',
    );
  });
}

TrackingLocationSample _sample(
  int seconds, {
  required double latitude,
  required double longitude,
  double accuracyMeters = 8,
}) {
  return TrackingLocationSample(
    latitude: latitude,
    longitude: longitude,
    timestamp: DateTime.utc(2026, 6, 1, 6).add(Duration(seconds: seconds)),
    accuracyMeters: accuracyMeters,
    speedMetersPerSecond: 3,
    headingDegrees: 90,
  );
}
