import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/tracking_session.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/route_map.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, this.autoLock = true});

  final bool autoLock;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

enum _GpsSignal { idle, locking, weak, fair, ready }

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  static const _gpsWarmupTimeout = Duration(seconds: 45);
  static const _gpsWarmupMinDuration = Duration(seconds: 16);
  static const _gpsWarmupMinStableSamples = 8;
  static const _gpsWarmupMaxBestAccuracyMeters = 8.0;
  static const _gpsWarmupMaxAverageAccuracyMeters = 10.0;
  static const _gpsWarmupMaxCurrentAccuracyMeters = 12.0;
  static const _gpsWarmupMaxStepMeters = 4.0;
  static const _gpsWarmupMaxDriftMeters = 8.0;
  static const _gpsWarmupMaxStandingSpeedMetersPerSecond = 0.9;
  static const _gpsWarmupMaxReportedSpeedMetersPerSecond = 1.2;

  TrackingSession? _session;
  TrackingSessionSnapshot? _snapshot;
  Position? _gpsReadyAnchor;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _ticker;
  var _checkingPermission = false;
  var _saving = false;
  String? _message;
  Map<String, dynamic>? _lastWarmupDebug;
  var _gpsSignal = _GpsSignal.idle;
  var _gpsStableSamples = 0;
  var _gpsElapsedSeconds = 0;
  var _autoLockStarted = false;

  bool get _running => _snapshot?.status == TrackingSessionStatus.running;
  bool get _paused => _snapshot?.status == TrackingSessionStatus.paused;
  bool get _finished => _snapshot?.status == TrackingSessionStatus.finished;
  bool get _hasSession => _snapshot != null;
  bool get _gpsReady => _gpsReadyAnchor != null;
  String get _distanceSubtitle {
    if (_running) return 'TRACKING ACTIVE';
    if (_gpsReady) return 'GPS LOCKED · READY TO START';
    if (_checkingPermission) return 'SCANNING GPS SIGNAL';
    return '';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoLockStarted) return;
      _autoLockStarted = true;
      if (widget.autoLock) _lockGps();
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Chạy thử'),
            Text(
              'TRACKING LAB',
              style: TextStyle(
                color: AppColors.blueGlow,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassPanel(
            borderRadius: 28,
            padding: const EdgeInsets.all(22),
            gradient: const LinearGradient(
              colors: [Color(0xff06172b), Color(0xff03101d)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _RunConsoleHeader(
                  status: _statusLabel(snapshot),
                  active: _running,
                  signal: _gpsSignal,
                ),
                const SizedBox(height: 18),
                _TrackingCockpit(
                  snapshot: snapshot,
                  signal: _gpsSignal,
                  elapsedSeconds: _gpsElapsedSeconds,
                  stableSamples: _gpsStableSamples,
                  minSeconds: _gpsWarmupMinDuration.inSeconds,
                  minSamples: _gpsWarmupMinStableSamples,
                  subtitle: _distanceSubtitle,
                  onMap: snapshot == null || snapshot.routePoints.length < 2
                      ? null
                      : () => _openLiveMap(snapshot),
                ),
                const SizedBox(height: 24),
                _Controls(
                  running: _running,
                  paused: _paused,
                  finished: _finished,
                  hasSession: _hasSession,
                  gpsReady: _gpsReady,
                  busy: _checkingPermission || _saving,
                  onLockGps: _lockGps,
                  onStart: _startFromLockedGps,
                  onPause: _pause,
                  onResume: _resume,
                  onStop: _stopAndSave,
                  onDiscard: _discard,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_message != null && !_checkingPermission && !_running)
            GlassPanel(
              borderRadius: 18,
              padding: const EdgeInsets.all(16),
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          if (!_checkingPermission && !_running && _hasSession) ...[
            const SizedBox(height: 16),
            _TrialNoteCard(snapshot: snapshot),
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 16),
          _TrialSessionList(
            activities: ref.watch(trackedTrialActivitiesProvider),
          ),
        ],
      ),
    );
  }

  Future<void> _lockGps() async {
    if (_running || _checkingPermission || _saving) return;
    if (_finished) {
      await _resetSession(message: null);
    }
    setState(() {
      _checkingPermission = true;
      _gpsReadyAnchor = null;
      _lastWarmupDebug = null;
      _gpsSignal = _GpsSignal.locking;
      _gpsStableSamples = 0;
      _gpsElapsedSeconds = 0;
      _message = null;
    });
    try {
      final ready = await _ensureLocationReady();
      if (!ready) {
        if (mounted) setState(() => _gpsSignal = _GpsSignal.weak);
        return;
      }
      setState(() {
        _message = 'Đứng yên vài giây để khóa GPS...';
      });
      final anchor = await _waitForStableGps();
      if (anchor == null) return;
      if (!mounted) return;
      setState(() {
        _gpsReadyAnchor = anchor;
        _gpsSignal = _GpsSignal.ready;
        _message =
            'GPS READY (${anchor.accuracy.toStringAsFixed(0)}m). Bấm START NOW để bắt đầu tính distance.';
      });
      HapticFeedback.selectionClick();
    } finally {
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  Future<void> _startFromLockedGps() async {
    if (_running || _checkingPermission || _saving) return;
    final anchor = _gpsReadyAnchor;
    if (anchor == null) {
      await _lockGps();
      return;
    }
    try {
      final now = DateTime.now();
      final session = TrackingSession(
        id: 'runnow-${now.toUtc().millisecondsSinceEpoch}',
      )..start(now);
      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen(_onPosition, onError: _onLocationError);
      _startTicker();
      setState(() {
        _session = session;
        _snapshot = session.snapshot();
        _gpsReadyAnchor = null;
        _gpsSignal = _GpsSignal.ready;
        _message =
            'Đã bắt đầu tracking. Điểm GPS đầu tiên sau START NOW sẽ làm anchor.';
      });
      HapticFeedback.mediumImpact();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Không bắt đầu được tracking: $error');
    }
  }

  void _pause() {
    final session = _session;
    if (session == null) return;
    setState(() {
      _snapshot = session.pause(DateTime.now());
      _message = 'Đã pause. Route sau resume sẽ không nối qua đoạn nghỉ.';
    });
  }

  void _resume() {
    final session = _session;
    if (session == null) return;
    setState(() {
      _snapshot = session.resume(DateTime.now());
      _message = 'Đã resume. GPS point tiếp theo sẽ làm anchor mới.';
    });
  }

  Future<void> _stopAndSave() async {
    final session = _session;
    if (session == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _ticker?.cancel();
      final snapshot = session.finish(DateTime.now());
      final detail = snapshot.toActivityDetail(
        name: 'RunNow Trial',
        recordingDevice: 'RunNow app',
      );
      final debug = {
        ...snapshot.toDebugMap(),
        if (_lastWarmupDebug != null) 'gpsWarmup': _lastWarmupDebug,
      };
      await ref
          .read(activityRepositoryProvider)
          .saveTrackedActivity(detail, trackingDebug: debug);
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _message =
            'Đã lưu buổi chạy thử. Activity này chưa cộng vào stats/leaderboard.';
      });
      HapticFeedback.heavyImpact();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Không lưu được tracking trial: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    await _resetSession(message: 'Đã bỏ phiên tracking thử.');
  }

  Future<void> _openLiveMap(TrackingSessionSnapshot snapshot) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: GlassPanel(
          borderRadius: 26,
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.map_outlined, color: AppColors.blueGlow),
                  const SizedBox(width: 8),
                  Text(
                    'LIVE ROUTE',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: AppColors.blueGlow,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              RouteMap.fromRoutePoints(
                points: snapshot.routePoints,
                height: MediaQuery.sizeOf(context).height * 0.52,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetSession({required String? message}) async {
    await _positionSubscription?.cancel();
    _ticker?.cancel();
    if (!mounted) return;
    setState(() {
      _positionSubscription = null;
      _session = null;
      _snapshot = null;
      _gpsReadyAnchor = null;
      _lastWarmupDebug = null;
      _gpsSignal = _GpsSignal.idle;
      _gpsStableSamples = 0;
      _gpsElapsedSeconds = 0;
      _message = message;
    });
  }

  void _onPosition(Position position) {
    final session = _session;
    if (session == null || !_running) return;
    final snapshot = session.addLocation(_sampleFromPosition(position));
    final latestLog = snapshot.pointLogs.isEmpty
        ? null
        : snapshot.pointLogs.last;
    setState(() {
      _snapshot = snapshot;
      _gpsSignal = _runningGpsSignal(position, latestLog);
    });
  }

  _GpsSignal _runningGpsSignal(Position position, TrackingPointLog? log) {
    final accuracy = position.accuracy;
    if (log?.decision == TrackingPointDecision.rejected) {
      return switch (log?.rejectReason) {
        TrackingRejectReason.lowAccuracy ||
        TrackingRejectReason.unrealisticSpeed ||
        TrackingRejectReason.nonMonotonicTime => _GpsSignal.weak,
        TrackingRejectReason.paused => _GpsSignal.fair,
        TrackingRejectReason.stationaryNoise =>
          accuracy <= 12 ? _GpsSignal.ready : _GpsSignal.fair,
        null => _GpsSignal.fair,
      };
    }

    final reportedSpeed = position.speed.isFinite ? position.speed : 0.0;
    if (accuracy <= 12 && reportedSpeed <= 7.5) return _GpsSignal.ready;
    if (accuracy <= 25 && reportedSpeed <= 9) return _GpsSignal.fair;
    return _GpsSignal.weak;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final session = _session;
      if (!mounted || session == null || !_running) return;
      setState(() => _snapshot = session.tick(DateTime.now()));
    });
  }

  Future<Position?> _waitForStableGps() async {
    final completer = Completer<Position?>();
    StreamSubscription<Position>? subscription;
    Timer? timeout;
    var stableSamples = 0;
    var sampleCount = 0;
    var unstableJumps = 0;
    var accuracySum = 0.0;
    var bestAccuracy = double.infinity;
    var maxWindowStepMeters = 0.0;
    var maxWindowDriftMeters = 0.0;
    Position? best;
    Position? previous;
    Position? stableAnchor;
    final startedAt = DateTime.now();

    void complete(Position? position) {
      if (completer.isCompleted) return;
      timeout?.cancel();
      subscription?.cancel();
      _lastWarmupDebug = {
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': DateTime.now().toUtc().toIso8601String(),
        'sampleCount': sampleCount,
        'stableSamples': stableSamples,
        'unstableJumps': unstableJumps,
        'minWarmupSeconds': _gpsWarmupMinDuration.inSeconds,
        'minStableSamples': _gpsWarmupMinStableSamples,
        'maxBestAccuracyMeters': _gpsWarmupMaxBestAccuracyMeters,
        'maxAverageAccuracyMeters': _gpsWarmupMaxAverageAccuracyMeters,
        'maxCurrentAccuracyMeters': _gpsWarmupMaxCurrentAccuracyMeters,
        'maxStepMeters': _gpsWarmupMaxStepMeters,
        'maxDriftMeters': _gpsWarmupMaxDriftMeters,
        'maxWindowStepMeters': maxWindowStepMeters,
        'maxWindowDriftMeters': maxWindowDriftMeters,
        'maxReportedSpeedMetersPerSecond':
            _gpsWarmupMaxReportedSpeedMetersPerSecond,
        'bestAccuracyMeters': best?.accuracy,
        'lockedAccuracyMeters': position?.accuracy,
      }..removeWhere((key, value) => value == null);
      completer.complete(position);
    }

    void resetStableWindow() {
      stableSamples = 0;
      accuracySum = 0;
      bestAccuracy = double.infinity;
      maxWindowStepMeters = 0;
      maxWindowDriftMeters = 0;
      stableAnchor = null;
    }

    timeout = Timer(_gpsWarmupTimeout, () {
      if (!mounted) {
        complete(null);
        return;
      }
      setState(() {
        _gpsSignal = _GpsSignal.weak;
        _message =
            'GPS chưa ổn định. Đứng yên ở nơi thoáng hơn rồi bấm LOCK GPS lại.';
      });
      complete(null);
    });

    subscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen(
          (position) {
            sampleCount += 1;
            if (best == null || position.accuracy < best!.accuracy) {
              best = position;
            }
            final prior = previous;
            var unstable = false;
            var stepMeters = 0.0;
            var impliedSpeed = 0.0;
            if (prior != null) {
              final seconds =
                  position.timestamp
                      .difference(prior.timestamp)
                      .inMilliseconds /
                  1000;
              if (seconds > 0) {
                stepMeters = haversineDistanceMeters(
                  prior.latitude,
                  prior.longitude,
                  position.latitude,
                  position.longitude,
                );
                impliedSpeed = stepMeters / seconds;
                final allowedJump = math.min(
                  _gpsWarmupMaxStepMeters,
                  math.max(2.0, position.accuracy * 0.45),
                );
                unstable =
                    stepMeters > allowedJump ||
                    impliedSpeed > _gpsWarmupMaxStandingSpeedMetersPerSecond;
              }
            }
            previous = position;

            final reportedSpeed = position.speed.isFinite ? position.speed : 0;
            if (reportedSpeed > _gpsWarmupMaxReportedSpeedMetersPerSecond) {
              unstable = true;
            }

            if (unstable ||
                position.accuracy > _gpsWarmupMaxCurrentAccuracyMeters) {
              unstableJumps += 1;
              resetStableWindow();
            } else {
              stableAnchor ??= position;
              final anchor = stableAnchor!;
              final driftMeters = haversineDistanceMeters(
                anchor.latitude,
                anchor.longitude,
                position.latitude,
                position.longitude,
              );
              if (driftMeters > _gpsWarmupMaxDriftMeters) {
                unstableJumps += 1;
                resetStableWindow();
              } else {
                stableSamples += 1;
                accuracySum += position.accuracy;
                bestAccuracy = math.min(bestAccuracy, position.accuracy);
                maxWindowStepMeters = math.max(maxWindowStepMeters, stepMeters);
                maxWindowDriftMeters = math.max(
                  maxWindowDriftMeters,
                  driftMeters,
                );
              }
            }
            final elapsed = DateTime.now().difference(startedAt);
            final averageAccuracy = stableSamples == 0
                ? double.infinity
                : accuracySum / stableSamples;
            final hasEnoughTime = elapsed >= _gpsWarmupMinDuration;
            final hasEnoughSamples =
                stableSamples >= _gpsWarmupMinStableSamples;
            final hasStrongAccuracy =
                bestAccuracy <= _gpsWarmupMaxBestAccuracyMeters &&
                averageAccuracy <= _gpsWarmupMaxAverageAccuracyMeters &&
                position.accuracy <= _gpsWarmupMaxCurrentAccuracyMeters &&
                maxWindowStepMeters <= _gpsWarmupMaxStepMeters &&
                maxWindowDriftMeters <= _gpsWarmupMaxDriftMeters;
            final ready =
                hasEnoughTime && hasEnoughSamples && hasStrongAccuracy;
            if (mounted) {
              setState(() {
                _gpsElapsedSeconds = elapsed.inSeconds;
                _gpsStableSamples = stableSamples;
                _gpsSignal = ready
                    ? _GpsSignal.ready
                    : stableSamples >= 4 &&
                          averageAccuracy <= 14 &&
                          maxWindowDriftMeters <= 10
                    ? _GpsSignal.fair
                    : _GpsSignal.weak;
                _message =
                    'Đang khóa GPS... ${elapsed.inSeconds}/${_gpsWarmupMinDuration.inSeconds}s · stable $stableSamples/$_gpsWarmupMinStableSamples · acc ${position.accuracy.toStringAsFixed(0)}m';
              });
            }
            if (ready) {
              complete(position);
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _gpsSignal = _GpsSignal.weak;
                _message = 'Không đọc được GPS: $error';
              });
            }
            complete(null);
          },
        );

    return completer.future;
  }

  void _onLocationError(Object error) {
    if (!mounted) return;
    setState(() => _message = 'Lỗi GPS: $error');
  }

  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(
        () => _message = 'Location Service đang tắt. Hãy bật GPS để chạy thử.',
      );
      await Geolocator.openLocationSettings();
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      setState(
        () => _message = 'RunNow cần quyền vị trí để tracking route và pace.',
      );
      return false;
    }

    if (permission == LocationPermission.deniedForever) {
      setState(
        () => _message =
            'Quyền vị trí đang bị chặn. Mở Settings để cấp lại quyền.',
      );
      await Geolocator.openAppSettings();
      return false;
    }

    return true;
  }

  String _statusLabel(TrackingSessionSnapshot? snapshot) {
    return switch (snapshot?.status) {
      TrackingSessionStatus.running => 'RECORDING',
      TrackingSessionStatus.paused => 'PAUSED',
      TrackingSessionStatus.finished => 'SAVED TRIAL',
      TrackingSessionStatus.idle || null => _gpsReady ? 'GPS LOCKED' : 'READY',
    };
  }

  TrackingLocationSample _sampleFromPosition(Position position) {
    return TrackingLocationSample(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      altitudeMeters: position.altitude,
      accuracyMeters: position.accuracy,
      speedMetersPerSecond: position.speed,
      headingDegrees: position.heading,
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.running,
    required this.paused,
    required this.finished,
    required this.hasSession,
    required this.gpsReady,
    required this.busy,
    required this.onLockGps,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onDiscard,
  });

  final bool running;
  final bool paused;
  final bool finished;
  final bool hasSession;
  final bool gpsReady;
  final bool busy;
  final VoidCallback onLockGps;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    if (!hasSession || finished) {
      final label = switch ((finished, gpsReady)) {
        (true, _) => 'SCAN GPS AGAIN',
        (false, true) => 'START RUN',
        (false, false) => 'SCAN GPS',
      };
      final icon = switch ((finished, gpsReady)) {
        (true, _) => Icons.gps_fixed_rounded,
        (false, true) => Icons.play_arrow_rounded,
        (false, false) => Icons.gps_not_fixed_rounded,
      };
      final enabledColor = gpsReady ? const Color(0xff19f58a) : AppColors.red;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: enabledColor.withValues(alpha: 0.34),
              blurRadius: 30,
              spreadRadius: 1,
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 68,
          child: FilledButton.icon(
            onPressed: busy ? null : (gpsReady ? onStart : onLockGps),
            style: FilledButton.styleFrom(
              backgroundColor: enabledColor,
              foregroundColor: gpsReady ? AppColors.black : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            icon: busy
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: gpsReady ? AppColors.black : Colors.white,
                    ),
                  )
                : Icon(icon, size: 30),
            label: Text(
              label,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : (running ? onPause : onResume),
                icon: Icon(
                  running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
                label: Text(running ? 'PAUSE' : 'RESUME'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onStop,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('STOP & SAVE'),
              ),
            ),
          ],
        ),
        if (!running) ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: busy ? null : onDiscard,
            child: const Text('Bỏ phiên thử'),
          ),
        ],
      ],
    );
  }
}

class _TrackingCockpit extends StatelessWidget {
  const _TrackingCockpit({
    required this.snapshot,
    required this.signal,
    required this.elapsedSeconds,
    required this.stableSamples,
    required this.minSeconds,
    required this.minSamples,
    required this.subtitle,
    required this.onMap,
  });

  final TrackingSessionSnapshot? snapshot;
  final _GpsSignal signal;
  final int elapsedSeconds;
  final int stableSamples;
  final int minSeconds;
  final int minSamples;
  final String subtitle;
  final VoidCallback? onMap;

  @override
  Widget build(BuildContext context) {
    final distance = formatDistance(snapshot?.distanceMeters ?? 0);
    final time = formatDuration(snapshot?.movingTimeSeconds ?? 0);
    final pace = formatPace(snapshot?.averagePaceSecondsPerKm);
    final livePace = formatPace(snapshot?.currentPaceSecondsPerKm);
    return SizedBox(
      height: 405,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: _CornerMetric(label: 'TIME', value: time),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: _CornerMetric(label: 'PACE TB', value: pace, alignEnd: true),
          ),
          Positioned(
            bottom: 10,
            left: 0,
            child: _CornerMetric(label: 'PACE LIVE', value: livePace),
          ),
          Positioned(
            bottom: 10,
            right: 0,
            child: _CornerMapMetric(
              enabled: onMap != null,
              pointCount: snapshot?.routePoints.length ?? 0,
              onTap: onMap,
            ),
          ),
          Positioned(
            top: 62,
            child: _GpsRadar(
              signal: signal,
              elapsedSeconds: elapsedSeconds,
              stableSamples: stableSamples,
              minSeconds: minSeconds,
              minSamples: minSamples,
            ),
          ),
          Positioned(
            bottom: 96,
            child: Column(
              children: [
                Text(
                  distance,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.56),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CornerMetric extends StatelessWidget {
  const _CornerMetric({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: SizedBox(
        width: 126,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: alignEnd
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Text(
                label,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alignEnd ? TextAlign.end : TextAlign.start,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CornerMapMetric extends StatelessWidget {
  const _CornerMapMetric({
    required this.enabled,
    required this.pointCount,
    required this.onTap,
  });

  final bool enabled;
  final int pointCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? AppColors.blueGlow : Colors.white30;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: enabled ? onTap : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: SizedBox(
          width: 126,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'MAP',
                  style: TextStyle(
                    color: color.withValues(alpha: enabled ? 0.85 : 0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      enabled ? '$pointCount pts' : 'WAIT',
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.map_outlined, color: color, size: 22),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: active ? AppColors.red : AppColors.amber,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (active ? AppColors.red : AppColors.amber).withValues(
              alpha: 0.45,
            ),
            blurRadius: 16,
          ),
        ],
      ),
    );
  }
}

Color _gpsSignalColor(_GpsSignal signal) {
  return switch (signal) {
    _GpsSignal.ready => const Color(0xff19f58a),
    _GpsSignal.fair => AppColors.amber,
    _GpsSignal.weak => AppColors.red,
    _GpsSignal.locking => AppColors.blueGlow,
    _GpsSignal.idle => Colors.white38,
  };
}

String _gpsSignalLabel(_GpsSignal signal) {
  return switch (signal) {
    _GpsSignal.ready => 'GPS GOOD',
    _GpsSignal.fair => 'GPS FAIR',
    _GpsSignal.weak => 'GPS WEAK',
    _GpsSignal.locking => 'SCANNING',
    _GpsSignal.idle => 'STANDBY',
  };
}

class _RunConsoleHeader extends StatelessWidget {
  const _RunConsoleHeader({
    required this.status,
    required this.active,
    required this.signal,
  });

  final String status;
  final bool active;
  final _GpsSignal signal;

  @override
  Widget build(BuildContext context) {
    final signalColor = _gpsSignalColor(signal);
    return Row(
      children: [
        _StatusDot(active: active),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            status,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: signalColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: signalColor.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: signalColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: signalColor.withValues(alpha: 0.5),
                        blurRadius: 14,
                      ),
                    ],
                  ),
                  child: const SizedBox.square(dimension: 8),
                ),
                const SizedBox(width: 7),
                Text(
                  _gpsSignalLabel(signal),
                  style: TextStyle(
                    color: signalColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GpsRadar extends StatelessWidget {
  const _GpsRadar({
    required this.signal,
    required this.elapsedSeconds,
    required this.stableSamples,
    required this.minSeconds,
    required this.minSamples,
  });

  final _GpsSignal signal;
  final int elapsedSeconds;
  final int stableSamples;
  final int minSeconds;
  final int minSamples;

  @override
  Widget build(BuildContext context) {
    final color = _gpsSignalColor(signal);
    final progress = math.min(
      1.0,
      ((elapsedSeconds / minSeconds) + (stableSamples / minSamples)) / 2,
    );
    return SizedBox(
      width: 238,
      height: 238,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(238),
            painter: _GpsRadarPainter(color: color, progress: progress),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.58)),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 22),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(
                signal == _GpsSignal.ready
                    ? Icons.gps_fixed_rounded
                    : Icons.gps_not_fixed_rounded,
                color: color,
                size: 34,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GpsRadarPainter extends CustomPainter {
  const _GpsRadarPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.09);
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: 0.18);
    final activePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = color;

    for (final scale in [0.34, 0.56, 0.78, 1.0]) {
      canvas.drawCircle(center, radius * scale, gridPaint);
    }
    for (var i = 0; i < 8; i++) {
      final angle = math.pi * 2 * i / 8;
      final start = Offset(
        center.dx + math.cos(angle) * radius * 0.34,
        center.dy + math.sin(angle) * radius * 0.34,
      );
      final end = Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      canvas.drawLine(start, end, gridPaint);
    }
    final rect = Rect.fromCircle(center: center, radius: radius * 0.92);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      glowPaint,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      activePaint,
    );
    final dotAngle = -math.pi / 2 + math.pi * 2 * progress;
    final dot = Offset(
      center.dx + math.cos(dotAngle) * radius * 0.92,
      center.dy + math.sin(dotAngle) * radius * 0.92,
    );
    canvas.drawCircle(dot, 7, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GpsRadarPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.progress != progress;
  }
}

class _TrialNoteCard extends StatelessWidget {
  const _TrialNoteCard({required this.snapshot});

  final TrackingSessionSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final logs = snapshot?.pointLogs ?? const <TrackingPointLog>[];
    final rejected = logs
        .where((log) => log.decision == TrackingPointDecision.rejected)
        .length;
    return GlassPanel(
      borderRadius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TRIAL MODE',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Buổi chạy thử được lưu để tuning thuật toán. Chưa cộng vào Tổng quan, Club hoặc Leaderboard.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SmallStat(
                  label: 'Accepted',
                  value: '${logs.length - rejected}',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SmallStat(label: 'Rejected', value: '$rejected'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrialSessionList extends StatelessWidget {
  const _TrialSessionList({required this.activities});

  final AsyncValue<List<ActivitySummary>> activities;

  @override
  Widget build(BuildContext context) {
    return activities.when(
      data: (items) => GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SESSION ĐÃ TEST',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.secondary,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text(
                'Chưa có session thử nào được lưu.',
                style: Theme.of(context).textTheme.bodyMedium,
              )
            else
              for (final activity in items.take(8)) ...[
                _TrialSessionRow(activity: activity),
                if (activity != items.take(8).last)
                  Divider(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
              ],
          ],
        ),
      ),
      error: (error, stack) => GlassPanel(
        borderRadius: 18,
        padding: const EdgeInsets.all(16),
        child: Text('Không tải được session test: $error'),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _TrialSessionRow extends StatelessWidget {
  const _TrialSessionRow({required this.activity});

  final ActivitySummary activity;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/tracking/session/${activity.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.science_outlined, color: AppColors.red),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    formatDate(activity.startedAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDistance(activity.distanceMeters),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.secondary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  formatPace(activity.paceSecondsPerKm),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.map_outlined,
              size: 18,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  const _SmallStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: Theme.of(context).colorScheme.tertiary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
