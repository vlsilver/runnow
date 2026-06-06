import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/tracking_session.dart';
import 'package:myrun/src/widgets/glass.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  TrackingSession? _session;
  TrackingSessionSnapshot? _snapshot;
  StreamSubscription<Position>? _positionSubscription;
  Timer? _ticker;
  var _checkingPermission = false;
  var _saving = false;
  String? _message;

  bool get _running => _snapshot?.status == TrackingSessionStatus.running;
  bool get _paused => _snapshot?.status == TrackingSessionStatus.paused;
  bool get _finished => _snapshot?.status == TrackingSessionStatus.finished;
  bool get _hasSession => _snapshot != null;

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
                Row(
                  children: [
                    _StatusDot(active: _running),
                    const SizedBox(width: 10),
                    Text(
                      _statusLabel(snapshot),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  formatDistance(snapshot?.distanceMeters ?? 0),
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    color: Colors.white,
                    fontSize: 54,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Quãng đường thử nghiệm',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.58),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCell(
                        label: 'TIME',
                        value: formatDuration(snapshot?.movingTimeSeconds ?? 0),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCell(
                        label: 'PACE TB',
                        value: formatPace(snapshot?.averagePaceSecondsPerKm),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _MetricCell(
                        label: 'PACE LIVE',
                        value: formatPace(snapshot?.currentPaceSecondsPerKm),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _MetricCell(
                        label: 'GPS POINTS',
                        value: '${snapshot?.routePoints.length ?? 0}',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _Controls(
                  running: _running,
                  paused: _paused,
                  finished: _finished,
                  hasSession: _hasSession,
                  busy: _checkingPermission || _saving,
                  onStart: _start,
                  onPause: _pause,
                  onResume: _resume,
                  onStop: _stopAndSave,
                  onDiscard: _discard,
                  onNewSession: _newSession,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_message != null)
            GlassPanel(
              borderRadius: 18,
              padding: const EdgeInsets.all(16),
              child: Text(
                _message!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          const SizedBox(height: 16),
          _TrialNoteCard(snapshot: snapshot),
          const SizedBox(height: 20),
          _TrialSessionList(
            activities: ref.watch(trackedTrialActivitiesProvider),
          ),
        ],
      ),
    );
  }

  Future<void> _start() async {
    if (_running || _checkingPermission) return;
    if (_finished) {
      await _resetSession(message: null);
    }
    setState(() {
      _checkingPermission = true;
      _message = null;
    });
    try {
      final ready = await _ensureLocationReady();
      if (!ready) return;
      setState(() {
        _message = 'Đang đợi GPS ổn định...';
      });
      final anchor = await _waitForStableGps();
      if (anchor == null) return;
      final now = DateTime.now();
      final session = TrackingSession(
        id: 'runnow-${now.toUtc().millisecondsSinceEpoch}',
      )..start(now);
      session.addLocation(_sampleFromPosition(anchor));
      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 1,
        ),
      ).listen(_onPosition, onError: _onLocationError);
      _startTicker();
      setState(() {
        _session = session;
        _snapshot = session.snapshot();
        _message =
            'GPS đã ổn định (${anchor.accuracy.toStringAsFixed(0)}m). Đang tracking local.';
      });
      HapticFeedback.mediumImpact();
    } finally {
      if (mounted) setState(() => _checkingPermission = false);
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
      await ref
          .read(activityRepositoryProvider)
          .saveTrackedActivity(detail, trackingDebug: snapshot.toDebugMap());
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

  Future<void> _newSession() async {
    await _resetSession(message: 'Sẵn sàng cho session chạy thử mới.');
  }

  Future<void> _resetSession({required String? message}) async {
    await _positionSubscription?.cancel();
    _ticker?.cancel();
    if (!mounted) return;
    setState(() {
      _positionSubscription = null;
      _session = null;
      _snapshot = null;
      _message = message;
    });
  }

  void _onPosition(Position position) {
    final session = _session;
    if (session == null || !_running) return;
    setState(() {
      _snapshot = session.addLocation(_sampleFromPosition(position));
    });
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
    var goodSamples = 0;
    var strongSamples = 0;
    Position? best;

    void complete(Position? position) {
      if (completer.isCompleted) return;
      timeout?.cancel();
      subscription?.cancel();
      completer.complete(position);
    }

    timeout = Timer(const Duration(seconds: 25), () {
      if (best != null) {
        setState(
          () => _message =
              'GPS chưa thật sự đẹp nhưng đủ để thử (${best!.accuracy.toStringAsFixed(0)}m).',
        );
        complete(best);
      } else {
        setState(
          () => _message =
              'Chưa lấy được GPS ổn định. Ra nơi thoáng hơn rồi thử lại.',
        );
        complete(null);
      }
    });

    subscription =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          ),
        ).listen(
          (position) {
            if (best == null || position.accuracy < best!.accuracy) {
              best = position;
            }
            if (position.accuracy <= 15) {
              strongSamples += 1;
              goodSamples += 1;
            } else if (position.accuracy <= 25) {
              goodSamples += 1;
            } else {
              strongSamples = 0;
              goodSamples = 0;
            }
            setState(
              () => _message =
                  'Đang khóa GPS... accuracy ${position.accuracy.toStringAsFixed(0)}m',
            );
            if (strongSamples >= 2 || goodSamples >= 3) complete(position);
          },
          onError: (Object error) {
            setState(() => _message = 'Không đọc được GPS: $error');
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
      TrackingSessionStatus.idle || null => 'READY',
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
    required this.busy,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onDiscard,
    required this.onNewSession,
  });

  final bool running;
  final bool paused;
  final bool finished;
  final bool hasSession;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onDiscard;
  final VoidCallback onNewSession;

  @override
  Widget build(BuildContext context) {
    if (!hasSession || finished) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: busy ? null : onStart,
          icon: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  finished
                      ? Icons.restart_alt_rounded
                      : Icons.play_arrow_rounded,
                ),
          label: Text(finished ? 'START NEW RUN' : 'START RUN'),
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

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
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
    return Padding(
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
        ],
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
