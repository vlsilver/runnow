import 'dart:math' as math;

import 'package:myrun/src/models.dart';

enum TrackingSessionStatus { idle, running, paused, finished }

enum TrackingPointDecision { accepted, rejected }

enum TrackingRejectReason {
  paused,
  lowAccuracy,
  nonMonotonicTime,
  unrealisticSpeed,
  stationaryNoise,
}

class TrackingConfig {
  const TrackingConfig({
    this.maxAccuracyMeters = 25,
    this.maxRunningSpeedMetersPerSecond = 6,
    this.minSegmentDistanceMeters = 2,
    this.splitDistanceMeters = 1000,
    this.currentPaceWindow = const Duration(seconds: 12),
  });

  final double maxAccuracyMeters;
  final double maxRunningSpeedMetersPerSecond;
  final double minSegmentDistanceMeters;
  final double splitDistanceMeters;
  final Duration currentPaceWindow;
}

class TrackingLocationSample {
  const TrackingLocationSample({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.altitudeMeters,
    this.accuracyMeters,
    this.speedMetersPerSecond,
    this.headingDegrees,
  });

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? altitudeMeters;
  final double? accuracyMeters;
  final double? speedMetersPerSecond;
  final double? headingDegrees;

  RoutePoint toRoutePoint() {
    return RoutePoint(
      latitude: latitude,
      longitude: longitude,
      timestamp: timestamp,
      altitudeMeters: altitudeMeters,
      accuracyMeters: accuracyMeters,
      speedMetersPerSecond: speedMetersPerSecond,
      headingDegrees: headingDegrees,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'altitudeMeters': altitudeMeters,
      'accuracyMeters': accuracyMeters,
      'speedMetersPerSecond': speedMetersPerSecond,
      'headingDegrees': headingDegrees,
    }..removeWhere((key, value) => value == null);
  }
}

class TrackingPointLog {
  const TrackingPointLog({
    required this.sample,
    required this.decision,
    this.rejectReason,
    this.segmentDistanceMeters = 0,
    this.segmentSeconds = 0,
    this.totalDistanceMeters = 0,
    this.movingTimeSeconds = 0,
  });

  final TrackingLocationSample sample;
  final TrackingPointDecision decision;
  final TrackingRejectReason? rejectReason;
  final double segmentDistanceMeters;
  final int segmentSeconds;
  final double totalDistanceMeters;
  final int movingTimeSeconds;

  Map<String, dynamic> toMap() {
    return {
      ...sample.toMap(),
      'decision': decision.name,
      'rejectReason': rejectReason?.name,
      'segmentDistanceMeters': segmentDistanceMeters,
      'segmentSeconds': segmentSeconds,
      'totalDistanceMeters': totalDistanceMeters,
      'movingTimeSeconds': movingTimeSeconds,
    }..removeWhere((key, value) => value == null);
  }
}

class TrackingSplit {
  const TrackingSplit({
    required this.index,
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.elapsedTimeSeconds,
    required this.completedAt,
  });

  final int index;
  final double distanceMeters;
  final int movingTimeSeconds;
  final int elapsedTimeSeconds;
  final DateTime completedAt;

  double? get paceSecondsPerKm =>
      distanceMeters <= 0 ? null : movingTimeSeconds / (distanceMeters / 1000);

  Map<String, dynamic> toMap() {
    return {
      'name': 'Km $index',
      'split': index,
      'distanceMeters': distanceMeters,
      'movingTimeSeconds': movingTimeSeconds,
      'elapsedTimeSeconds': elapsedTimeSeconds,
      'paceSecondsPerKm': paceSecondsPerKm,
      'completedAt': completedAt.toUtc().toIso8601String(),
    }..removeWhere((key, value) => value == null);
  }
}

class TrackingSessionSnapshot {
  const TrackingSessionSnapshot({
    required this.id,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.elapsedTimeSeconds,
    required this.routePoints,
    required this.pointLogs,
    required this.splits,
    this.currentPaceSecondsPerKm,
  });

  final String id;
  final TrackingSessionStatus status;
  final DateTime startedAt;
  final DateTime updatedAt;
  final double distanceMeters;
  final int movingTimeSeconds;
  final int elapsedTimeSeconds;
  final List<RoutePoint> routePoints;
  final List<TrackingPointLog> pointLogs;
  final List<TrackingSplit> splits;
  final double? currentPaceSecondsPerKm;

  double? get averagePaceSecondsPerKm =>
      distanceMeters <= 0 ? null : movingTimeSeconds / (distanceMeters / 1000);

  ActivitySummary toActivitySummary({
    String name = 'RunNow Run',
    ActivityKind kind = ActivityKind.run,
    String? recordingDevice,
  }) {
    return ActivitySummary(
      id: id,
      name: name,
      kind: kind,
      startedAt: startedAt,
      distanceMeters: distanceMeters,
      movingTimeSeconds: movingTimeSeconds,
      elapsedTimeSeconds: elapsedTimeSeconds,
      source: ActivitySource.runnow,
      sourceActivityId: id,
      recordingDevice: recordingDevice,
      routePoints: routePoints,
      hydrated: true,
    );
  }

  ActivityDetail toActivityDetail({
    String name = 'RunNow Run',
    ActivityKind kind = ActivityKind.run,
    String? recordingDevice,
  }) {
    return ActivityDetail(
      summary: toActivitySummary(
        name: name,
        kind: kind,
        recordingDevice: recordingDevice,
      ),
      splits: splits.map((split) => split.toMap()).toList(),
      streams: _streamsFromPointLogs(),
    );
  }

  Map<String, dynamic> toDebugMap() {
    return {
      'id': id,
      'status': status.name,
      'startedAt': startedAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'distanceMeters': distanceMeters,
      'movingTimeSeconds': movingTimeSeconds,
      'elapsedTimeSeconds': elapsedTimeSeconds,
      'averagePaceSecondsPerKm': averagePaceSecondsPerKm,
      'currentPaceSecondsPerKm': currentPaceSecondsPerKm,
      'routePoints': routePoints.map((point) => point.toMap()).toList(),
      'splits': splits.map((split) => split.toMap()).toList(),
      'pointLogs': pointLogs.map((log) => log.toMap()).toList(),
    }..removeWhere((key, value) => value == null);
  }

  Map<String, List<double>> _streamsFromPointLogs() {
    final accepted = pointLogs
        .where((log) => log.decision == TrackingPointDecision.accepted)
        .toList();
    final time = <double>[];
    final distance = <double>[];
    final speed = <double>[];
    final altitude = <double>[];
    var hasAltitude = false;

    for (final log in accepted) {
      time.add(log.sample.timestamp.difference(startedAt).inSeconds.toDouble());
      distance.add(log.totalDistanceMeters);
      speed.add(
        log.segmentSeconds <= 0
            ? log.sample.speedMetersPerSecond ?? 0
            : log.segmentDistanceMeters / log.segmentSeconds,
      );
      final sampleAltitude = log.sample.altitudeMeters;
      if (sampleAltitude != null) {
        hasAltitude = true;
        altitude.add(sampleAltitude);
      } else {
        altitude.add(0);
      }
    }

    return {
      'time': time,
      'distance': distance,
      'velocity_smooth': speed,
      if (hasAltitude) 'altitude': altitude,
    };
  }
}

class TrackingSession {
  TrackingSession({required this.id, this.config = const TrackingConfig()});

  final String id;
  final TrackingConfig config;

  TrackingSessionStatus _status = TrackingSessionStatus.idle;
  DateTime? _startedAt;
  DateTime? _updatedAt;
  TrackingLocationSample? _lastAccepted;
  DateTime? _movingStartedAt;
  var _needsAnchorAfterPause = false;
  var _distanceMeters = 0.0;
  var _accumulatedMovingTimeSeconds = 0;
  var _gpsMovingTimeSeconds = 0;
  final List<RoutePoint> _routePoints = [];
  final List<TrackingPointLog> _pointLogs = [];
  final List<_AcceptedSegment> _segments = [];
  final List<TrackingSplit> _splits = [];

  TrackingSessionStatus get status => _status;

  TrackingSessionSnapshot start(DateTime startedAt) {
    if (_status != TrackingSessionStatus.idle) {
      throw StateError('Tracking session đã bắt đầu.');
    }
    _startedAt = startedAt;
    _updatedAt = startedAt;
    _movingStartedAt = startedAt;
    _status = TrackingSessionStatus.running;
    return snapshot();
  }

  TrackingSessionSnapshot addLocation(TrackingLocationSample sample) {
    _ensureStarted();
    if (_status == TrackingSessionStatus.finished) {
      throw StateError('Tracking session đã kết thúc.');
    }
    _updatedAt = sample.timestamp;

    if (_status == TrackingSessionStatus.paused) {
      _pointLogs.add(_rejected(sample, TrackingRejectReason.paused));
      return snapshot();
    }

    final accuracy = sample.accuracyMeters;
    if (accuracy != null && accuracy > config.maxAccuracyMeters) {
      _pointLogs.add(_rejected(sample, TrackingRejectReason.lowAccuracy));
      return snapshot();
    }

    final previous = _lastAccepted;
    if (previous == null || _needsAnchorAfterPause) {
      _acceptAnchor(sample);
      return snapshot();
    }

    final deltaSeconds = sample.timestamp
        .difference(previous.timestamp)
        .inSeconds;
    if (deltaSeconds <= 0) {
      _pointLogs.add(_rejected(sample, TrackingRejectReason.nonMonotonicTime));
      return snapshot();
    }

    final segmentDistance = haversineDistanceMeters(
      previous.latitude,
      previous.longitude,
      sample.latitude,
      sample.longitude,
    );

    if (segmentDistance < config.minSegmentDistanceMeters) {
      _pointLogs.add(_rejected(sample, TrackingRejectReason.stationaryNoise));
      return snapshot();
    }

    final impliedSpeed = segmentDistance / deltaSeconds;
    if (impliedSpeed > config.maxRunningSpeedMetersPerSecond) {
      _pointLogs.add(_rejected(sample, TrackingRejectReason.unrealisticSpeed));
      return snapshot();
    }

    _acceptSegment(sample, segmentDistance, deltaSeconds);
    return snapshot();
  }

  TrackingSessionSnapshot tick(DateTime now) {
    _ensureStarted();
    if (_status == TrackingSessionStatus.finished) return snapshot();
    if (now.isAfter(_updatedAt ?? now)) {
      _updatedAt = now;
    }
    return snapshot();
  }

  TrackingSessionSnapshot pause(DateTime pausedAt) {
    _ensureStarted();
    if (_status != TrackingSessionStatus.running) return snapshot();
    _accumulatedMovingTimeSeconds = _currentMovingTimeSeconds(pausedAt);
    _movingStartedAt = null;
    _updatedAt = pausedAt;
    _status = TrackingSessionStatus.paused;
    _needsAnchorAfterPause = true;
    return snapshot();
  }

  TrackingSessionSnapshot resume(DateTime resumedAt) {
    _ensureStarted();
    if (_status != TrackingSessionStatus.paused) return snapshot();
    _updatedAt = resumedAt;
    _status = TrackingSessionStatus.running;
    _needsAnchorAfterPause = true;
    _movingStartedAt = resumedAt;
    return snapshot();
  }

  TrackingSessionSnapshot finish(DateTime finishedAt) {
    _ensureStarted();
    if (_status == TrackingSessionStatus.running) {
      _accumulatedMovingTimeSeconds = _currentMovingTimeSeconds(finishedAt);
    }
    _movingStartedAt = null;
    _updatedAt = finishedAt;
    _status = TrackingSessionStatus.finished;
    return snapshot();
  }

  TrackingSessionSnapshot snapshot() {
    final startedAt = _startedAt;
    final updatedAt = _updatedAt;
    if (startedAt == null || updatedAt == null) {
      throw StateError('Tracking session chưa bắt đầu.');
    }
    return TrackingSessionSnapshot(
      id: id,
      status: _status,
      startedAt: startedAt,
      updatedAt: updatedAt,
      distanceMeters: _distanceMeters,
      movingTimeSeconds: _currentMovingTimeSeconds(updatedAt),
      elapsedTimeSeconds: math.max(
        0,
        updatedAt.difference(startedAt).inSeconds,
      ),
      routePoints: List.unmodifiable(_routePoints),
      pointLogs: List.unmodifiable(_pointLogs),
      splits: List.unmodifiable(_splits),
      currentPaceSecondsPerKm: _currentPaceSecondsPerKm(updatedAt),
    );
  }

  void _acceptAnchor(TrackingLocationSample sample) {
    _lastAccepted = sample;
    _needsAnchorAfterPause = false;
    _routePoints.add(sample.toRoutePoint());
    _pointLogs.add(
      TrackingPointLog(
        sample: sample,
        decision: TrackingPointDecision.accepted,
        totalDistanceMeters: _distanceMeters,
        movingTimeSeconds: _currentMovingTimeSeconds(sample.timestamp),
      ),
    );
  }

  void _acceptSegment(
    TrackingLocationSample sample,
    double segmentDistanceMeters,
    int segmentSeconds,
  ) {
    final previousDistance = _distanceMeters;
    final previousMovingTime = _gpsMovingTimeSeconds;
    final previousUpdatedAt = _lastAccepted!.timestamp;

    _distanceMeters += segmentDistanceMeters;
    _gpsMovingTimeSeconds += segmentSeconds;
    _lastAccepted = sample;
    _routePoints.add(sample.toRoutePoint());
    _segments.add(
      _AcceptedSegment(
        distanceMeters: segmentDistanceMeters,
        seconds: segmentSeconds,
        completedAt: sample.timestamp,
      ),
    );
    _addCompletedSplits(
      previousDistance: previousDistance,
      previousMovingTimeSeconds: previousMovingTime,
      previousTimestamp: previousUpdatedAt,
      segmentDistanceMeters: segmentDistanceMeters,
      segmentSeconds: segmentSeconds,
    );
    _pointLogs.add(
      TrackingPointLog(
        sample: sample,
        decision: TrackingPointDecision.accepted,
        segmentDistanceMeters: segmentDistanceMeters,
        segmentSeconds: segmentSeconds,
        totalDistanceMeters: _distanceMeters,
        movingTimeSeconds: _currentMovingTimeSeconds(sample.timestamp),
      ),
    );
  }

  void _addCompletedSplits({
    required double previousDistance,
    required int previousMovingTimeSeconds,
    required DateTime previousTimestamp,
    required double segmentDistanceMeters,
    required int segmentSeconds,
  }) {
    var nextSplitDistance = (_splits.length + 1) * config.splitDistanceMeters;
    while (previousDistance < nextSplitDistance &&
        _distanceMeters >= nextSplitDistance) {
      final ratio =
          (nextSplitDistance - previousDistance) / segmentDistanceMeters;
      final splitMovingTime =
          previousMovingTimeSeconds + (segmentSeconds * ratio).round();
      final splitCompletedAt = previousTimestamp.add(
        Duration(seconds: (segmentSeconds * ratio).round()),
      );
      final previousSplitMovingTime = _splits.isEmpty
          ? 0
          : _splits.last.movingTimeSeconds + _previousSplitsMovingTime();
      final splitSeconds = splitMovingTime - previousSplitMovingTime;
      _splits.add(
        TrackingSplit(
          index: _splits.length + 1,
          distanceMeters: config.splitDistanceMeters,
          movingTimeSeconds: splitSeconds,
          elapsedTimeSeconds: splitCompletedAt
              .difference(_startedAt!)
              .inSeconds,
          completedAt: splitCompletedAt,
        ),
      );
      nextSplitDistance = (_splits.length + 1) * config.splitDistanceMeters;
    }
  }

  int _previousSplitsMovingTime() {
    if (_splits.length <= 1) return 0;
    return _splits
        .take(_splits.length - 1)
        .fold<int>(0, (sum, split) => sum + split.movingTimeSeconds);
  }

  TrackingPointLog _rejected(
    TrackingLocationSample sample,
    TrackingRejectReason reason,
  ) {
    return TrackingPointLog(
      sample: sample,
      decision: TrackingPointDecision.rejected,
      rejectReason: reason,
      totalDistanceMeters: _distanceMeters,
      movingTimeSeconds: _currentMovingTimeSeconds(sample.timestamp),
    );
  }

  int _currentMovingTimeSeconds(DateTime now) {
    final movingStartedAt = _movingStartedAt;
    if (_status != TrackingSessionStatus.running || movingStartedAt == null) {
      return _accumulatedMovingTimeSeconds;
    }
    return _accumulatedMovingTimeSeconds +
        math.max(0, now.difference(movingStartedAt).inSeconds);
  }

  double? _currentPaceSecondsPerKm(DateTime now) {
    var distance = 0.0;
    var seconds = 0;
    final windowSeconds = config.currentPaceWindow.inSeconds;
    for (final segment in _segments.reversed) {
      if (now.difference(segment.completedAt) > config.currentPaceWindow) {
        break;
      }
      if (seconds >= windowSeconds) break;
      distance += segment.distanceMeters;
      seconds += segment.seconds;
    }
    if (distance <= 0 || seconds <= 0) return null;
    return seconds / (distance / 1000);
  }

  void _ensureStarted() {
    if (_status == TrackingSessionStatus.idle || _startedAt == null) {
      throw StateError('Tracking session chưa bắt đầu.');
    }
  }
}

class _AcceptedSegment {
  const _AcceptedSegment({
    required this.distanceMeters,
    required this.seconds,
    required this.completedAt,
  });

  final double distanceMeters;
  final int seconds;
  final DateTime completedAt;
}

double haversineDistanceMeters(
  double latitudeA,
  double longitudeA,
  double latitudeB,
  double longitudeB,
) {
  const earthRadiusMeters = 6371008.8;
  final lat1 = _degreesToRadians(latitudeA);
  final lat2 = _degreesToRadians(latitudeB);
  final deltaLat = _degreesToRadians(latitudeB - latitudeA);
  final deltaLon = _degreesToRadians(longitudeB - longitudeA);
  final a =
      math.pow(math.sin(deltaLat / 2), 2) +
      math.cos(lat1) * math.cos(lat2) * math.pow(math.sin(deltaLon / 2), 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return earthRadiusMeters * c;
}

double _degreesToRadians(double value) => value * math.pi / 180;
