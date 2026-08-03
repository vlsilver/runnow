import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/activity_eligibility.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/tracking_draft_store.dart';
import 'package:myrun/src/tracking_session.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/route_map.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key, this.autoLock = true, this.contractId});

  final bool autoLock;
  final String? contractId;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

enum _GpsSignal { idle, locking, weak, fair, ready }

class _TrackingScreenState extends ConsumerState<TrackingScreen>
    with WidgetsBindingObserver {
  static const _gpsWarmupTimeout = Duration(seconds: 45);
  static const _gpsWarmupWindowSamples = 10;
  static const _gpsWarmupMinGoodSamples = 7;
  static const _gpsWarmupGoodAccuracyMeters = 25.0;
  static const _gpsWarmupFairAccuracyMeters = 40.0;
  static const _gpsWarmupMaxWindowDriftMeters = 45.0;
  static const _gpsWarmupMaxReportedSpeedMetersPerSecond = 3.0;
  static const _livePublishMinInterval = Duration(seconds: 5);
  static const _liveHeartbeatInterval = Duration(seconds: 30);
  static const _livePublishMinDistanceMeters = 20.0;
  static const _liveRoutePreviewStepMeters = 100.0;

  TrackingSession? _session;
  TrackingSessionSnapshot? _snapshot;
  TrackingLocationSample? _gpsReadyAnchor;
  StreamSubscription<TrackingLocationSample>? _positionSubscription;
  Timer? _ticker;
  var _checkingPermission = false;
  var _saving = false;
  var _capturingPhoto = false;
  String? _message;
  // Kèm theo _message khi cách khắc phục nằm ở Settings của máy. Null nghĩa
  // là không hiện nút, tránh mời user vào Settings khi chẳng có gì để sửa.
  VoidCallback? _settingsAction;
  Map<String, dynamic>? _lastWarmupDebug;
  var _gpsSignal = _GpsSignal.idle;
  var _gpsStableSamples = 0;
  var _gpsElapsedSeconds = 0;
  var _autoLockStarted = false;
  var _persistingDraft = false;
  var _backgroundLocationGranted = false;
  String? _contractId;
  Future<void> _livePublishQueue = Future<void>.value();
  Future<void> _photoUploadQueue = Future<void>.value();
  DateTime? _lastDraftSavedAt;
  DateTime? _lastLivePublishedAt;
  double _lastLivePublishedDistanceMeters = 0;
  // Sync route theo chunk (~10s/lần) để không mất buổi khi crash/hết pin.
  // `_trackChunkSeq` = seq chunk kế tiếp; `_flushedRoutePointCount` = số điểm
  // đã đẩy (đẩy tiếp từ đây). Serialize bằng queue để không đua ghi.
  int _trackChunkSeq = 0;
  int _flushedRoutePointCount = 0;
  DateTime? _lastTrackChunkAt;
  Future<void> _trackChunkQueue = Future<void>.value();
  bool _trackChunkResumed = false;
  static const _trackChunkInterval = Duration(seconds: 10);
  // Tường thuật LIVE lên group qua bot: báo start khi đủ ngưỡng, mốc mỗi 5km,
  // và finish. Gọi API fire-and-forget, không chặn tracking.
  // User bật/tắt "Live" trước khi chạy. BẬT = tự báo mốc km + ảnh lên group
  // trong lúc chạy. Mặc định TẮT (opt-in, riêng tư).
  bool _liveEnabled = false;
  bool _liveAnnouncedStart = false;
  int _liveAnnouncedKm = 0;
  Future<void> _liveAnnounceQueue = Future<void>.value();
  static const double _liveStartMinMeters = 500;
  static const double _liveMilestoneMeters = 5000;

  bool get _running => _snapshot?.status == TrackingSessionStatus.running;
  bool get _paused => _snapshot?.status == TrackingSessionStatus.paused;
  bool get _finished => _snapshot?.status == TrackingSessionStatus.finished;
  bool get _hasSession => _snapshot != null;
  bool get _gpsReady => _gpsReadyAnchor != null;
  String get _distanceSubtitle {
    if (_running) return 'ĐANG GHI HÀNH TRÌNH';
    if (_paused) return 'ĐÃ TẠM DỪNG';
    if (_finished) {
      if (_checkingPermission) return 'ĐANG DÒ GPS CHO BUỔI MỚI';
      if (_gpsReady) return 'SẴN SÀNG CHO BUỔI MỚI';
      return 'ĐÃ LƯU BUỔI CHẠY';
    }
    if (_gpsReady) return 'SẴN SÀNG · CHẠM START ĐỂ BẮT ĐẦU';
    if (_checkingPermission) return 'ĐANG DÒ TÍN HIỆU GPS';
    return 'ĐANG CHỜ GPS';
  }

  String get _screenTitle {
    if (_running) return 'Đang chạy';
    if (_paused) return 'Đã tạm dừng';
    return 'Chạy';
  }

  @override
  void initState() {
    super.initState();
    _contractId = widget.contractId;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoLockStarted) return;
      _autoLockStarted = true;
      _restoreDraftThenMaybeLock();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _positionSubscription?.cancel();
    _ticker?.cancel();
    _setWakelock(false);
    super.dispose();
  }

  void _setWakelock(bool enable) {
    unawaited(WakelockPlus.toggle(enable: enable));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_persistDraft());
      return;
    }
    if (state == AppLifecycleState.resumed && _running) {
      unawaited(_startRunningLocationStream());
      _startTicker();
      _setWakelock(true);
      unawaited(_publishLiveSnapshot(force: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_screenTitle),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_hasSession && !_finished) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: RunNowSemanticColors.info,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  'GHI HÀNH TRÌNH',
                  style: const TextStyle(
                    color: RunNowSemanticColors.info,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.6,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RunConsoleHeader(
                status: _statusLabel(snapshot),
                active: _running,
                signal: _gpsSignal,
              ),
              const SizedBox(height: 12),
              _TrackingCockpit(
                snapshot: snapshot,
                signal: _gpsSignal,
                elapsedSeconds: _gpsElapsedSeconds,
                stableSamples: _gpsStableSamples,
                minSeconds: 0,
                minSamples: _gpsWarmupMinGoodSamples,
                subtitle: _distanceSubtitle,
                onMap: snapshot == null || snapshot.routePoints.length < 2
                    ? null
                    : () => _openLiveMap(snapshot),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_running && !_paused && !_finished)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GlassPanel(
                borderRadius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  value: _liveEnabled,
                  onChanged: (value) => setState(() => _liveEnabled = value),
                  title: const Text('Live lên group'),
                  subtitle: const Text(
                    'Bot tự báo mốc km và ảnh bạn chụp lên group trong lúc chạy',
                  ),
                  secondary: Icon(
                    _liveEnabled ? Icons.sensors : Icons.sensors_off,
                  ),
                ),
              ),
            ),
          if (_message != null && !_checkingPermission && !_running)
            GlassPanel(
              borderRadius: 18,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _message!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  // Chỉ hiện lối tắt sang Settings, không tự mở. App Store
                  // guideline 5.1.1(iv) cấm đẩy user sang Settings sau khi
                  // họ đã bấm "Don't Allow" — quyết định đó phải được tôn
                  // trọng, mở Settings là do user chủ động bấm.
                  if (_settingsAction != null) ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _settingsAction,
                      child: const Text('Mở Cài đặt'),
                    ),
                  ],
                ],
              ),
            ),
          if (kDebugMode &&
              !_checkingPermission &&
              !_running &&
              _hasSession) ...[
            const SizedBox(height: 16),
            _TrialNoteCard(snapshot: snapshot),
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 16),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 14),
        child: _Controls(
          running: _running,
          paused: _paused,
          finished: _finished,
          hasSession: _hasSession,
          gpsReady: _gpsReady,
          busy: _checkingPermission || _saving,
          capturingPhoto: _capturingPhoto,
          canTakePhoto:
              (_running || _paused) &&
              (snapshot?.routePoints.isNotEmpty ?? false),
          onLockGps: _lockGps,
          onStart: _startFromLockedGps,
          onPause: _pause,
          onResume: _resume,
          onStop: _stopAndSave,
          onDiscard: _discard,
          onPhoto: _capturePhoto,
        ),
      ),
    );
  }

  Future<void> _restoreDraftThenMaybeLock() async {
    final draft = await ref.read(trackingDraftStoreProvider).load();
    if (!mounted) return;
    if (draft != null) {
      final session = draft.session;
      final wasRunning = session.status == TrackingSessionStatus.running;
      final snapshot = wasRunning
          ? session.continueAfterRestore(DateTime.now())
          : session.snapshot();
      setState(() {
        _session = session;
        _snapshot = snapshot;
        _lastWarmupDebug = draft.gpsWarmup;
        _contractId = draft.contractId ?? widget.contractId;
        _gpsSignal = wasRunning ? _GpsSignal.fair : _GpsSignal.idle;
        _message = snapshot.status == TrackingSessionStatus.finished
            ? 'Đang hoàn tất upload ảnh của buổi chạy.'
            : wasRunning
            ? 'Đã khôi phục phiên chạy và tiếp tục ghi. GPS point tiếp theo sẽ làm anchor mới.'
            : 'Đã khôi phục phiên chạy bị tạm dừng. Bấm TIẾP TỤC để chạy tiếp.';
      });
      await _persistDraft();
      if (wasRunning) {
        await _startRunningLocationStream();
        _startTicker();
        _setWakelock(true);
        unawaited(_publishLiveSnapshot(force: true));
      }
      if (snapshot.status == TrackingSessionStatus.finished) {
        final uploaded = await _uploadPendingPhotos();
        if (uploaded) await ref.read(trackingDraftStoreProvider).clear();
      }
      return;
    }
    if (widget.autoLock) {
      await _lockGps();
    }
  }

  Future<void> _lockGps() async {
    if (_running || _checkingPermission || _saving) return;
    if (_finished) {
      if (!await _uploadPendingPhotos()) return;
      await ref.read(trackingDraftStoreProvider).clear();
      await _resetSession(message: null);
    }
    if (!await _ensureContractWindowAllowsRun()) return;
    setState(() {
      _checkingPermission = true;
      _gpsReadyAnchor = null;
      _lastWarmupDebug = null;
      _gpsSignal = _GpsSignal.locking;
      _gpsStableSamples = 0;
      _gpsElapsedSeconds = 0;
      _message = null;
      _settingsAction = null;
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
      // Trên Android foreground service tự lo tracking nền nên không cần nhắc
      // "Luôn cho phép"; chỉ iOS mới gợi ý nâng quyền khi chưa có "Always".
      final backgroundHint =
          (_backgroundLocationGranted ||
              defaultTargetPlatform == TargetPlatform.android)
          ? ''
          : ' Bật "Luôn cho phép" vị trí để vẫn tracking khi khóa màn hình.';
      setState(() {
        _gpsReadyAnchor = anchor;
        _gpsSignal = _GpsSignal.ready;
        _message =
            'GPS READY (${(anchor.accuracyMeters ?? 0).toStringAsFixed(0)}m). Bấm START NOW để bắt đầu tính distance.$backgroundHint';
      });
      HapticFeedback.selectionClick();
    } finally {
      if (mounted) setState(() => _checkingPermission = false);
    }
  }

  Future<void> _startFromLockedGps() async {
    if (_running || _checkingPermission || _saving) return;
    if (!await _ensureContractWindowAllowsRun()) return;
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
      _resetTrackChunkState();
      setState(() {
        _session = session;
        _snapshot = session.snapshot();
        _gpsReadyAnchor = null;
        _gpsSignal = _GpsSignal.ready;
        _message =
            'Đã bắt đầu tracking. Điểm GPS đầu tiên sau START NOW sẽ làm anchor.';
      });
      await _startRunningLocationStream();
      _startTicker();
      _setWakelock(true);
      unawaited(_persistDraft());
      unawaited(_publishLiveSnapshot(force: true));
      HapticFeedback.mediumImpact();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Không bắt đầu được tracking: $error');
    }
  }

  void _pause() {
    final session = _session;
    if (session == null) return;
    final subscription = _positionSubscription;
    if (subscription != null) {
      unawaited(subscription.cancel());
    }
    _positionSubscription = null;
    _ticker?.cancel();
    _setWakelock(false);
    setState(() {
      _snapshot = session.pause(DateTime.now());
      _message = 'Đã pause. Route sau resume sẽ không nối qua đoạn nghỉ.';
    });
    unawaited(_persistDraft());
    unawaited(
      _publishLiveSnapshot(force: true, status: LiveTrackingStatus.paused),
    );
  }

  void _resume() {
    final session = _session;
    if (session == null) return;
    setState(() {
      _snapshot = session.resume(DateTime.now());
      _message = 'Đã resume. GPS point tiếp theo sẽ làm anchor mới.';
    });
    unawaited(_startRunningLocationStream());
    _startTicker();
    _setWakelock(true);
    unawaited(_persistDraft());
    unawaited(_publishLiveSnapshot(force: true));
  }

  Future<void> _capturePhoto() async {
    final session = _session;
    final snapshot = _snapshot;
    if (session == null ||
        snapshot == null ||
        _capturingPhoto ||
        (!_running && !_paused)) {
      return;
    }
    if (snapshot.routePoints.isEmpty) {
      setState(() => _message = 'Chờ GPS ghi được vị trí trước khi chụp ảnh.');
      return;
    }
    final anchor = snapshot.routePoints.last;
    final capturedAt = DateTime.now();
    final photoId = 'photo-${capturedAt.toUtc().millisecondsSinceEpoch}';
    setState(() => _capturingPhoto = true);
    try {
      final path = await ref
          .read(trackingPhotoCaptureProvider)
          .capture(sessionId: session.id, photoId: photoId);
      if (path == null || !mounted) return;
      final draft = TrackingPhotoDraft(
        id: photoId,
        capturedAt: capturedAt,
        latitude: anchor.latitude,
        longitude: anchor.longitude,
        distanceMeters: snapshot.distanceMeters,
        localPath: path,
      );
      final next = session.addPhoto(draft);
      setState(() {
        _snapshot = next;
        _message = 'Đã neo ảnh tại ${formatDistance(snapshot.distanceMeters)}.';
      });
      await _persistDraft();
      HapticFeedback.selectionClick();
      unawaited(_uploadPhotoLive(draft));
    } catch (error) {
      if (mounted) setState(() => _message = 'Không chụp được ảnh: $error');
    } finally {
      if (mounted) setState(() => _capturingPhoto = false);
    }
  }

  Future<bool> _uploadPendingPhotos() async {
    final session = _session;
    if (session == null) return true;
    final pending = session
        .snapshot()
        .photos
        .where((photo) => !photo.isUploaded)
        .toList();
    if (pending.isEmpty) return true;
    for (final photo in pending) {
      try {
        final uploaded = await ref
            .read(trackingPhotoRepositoryProvider)
            .upload(activityId: session.id, draft: photo);
        final next = session.markPhotoUploaded(photo.id, uploaded.storagePath);
        if (mounted) setState(() => _snapshot = next);
        await _persistDraft();
        await ref
            .read(trackingPhotoCaptureProvider)
            .deleteLocal(photo.localPath);
      } catch (error) {
        if (mounted) {
          setState(() {
            _message =
                'Buổi chạy đã lưu nhưng còn ảnh chưa upload. Mở lại màn Chạy để thử lại: $error';
          });
        }
        return false;
      }
    }
    return true;
  }

  Future<void> _uploadPhotoLive(TrackingPhotoDraft draft) {
    final operation = _photoUploadQueue.then((_) => _uploadPhotoLiveNow(draft));
    _photoUploadQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _uploadPhotoLiveNow(TrackingPhotoDraft draft) async {
    final session = _session;
    if (session == null) return;
    try {
      final uploaded = await ref
          .read(trackingPhotoRepositoryProvider)
          .upload(activityId: session.id, draft: draft);
      final next = session.markPhotoUploaded(draft.id, uploaded.storagePath);
      if (mounted) setState(() => _snapshot = next);
      await _persistDraft();
      await ref.read(trackingPhotoCaptureProvider).deleteLocal(draft.localPath);
      final contractId = _contractId;
      if (contractId != null) {
        await ref
            .read(liveTrackingRepositoryProvider)
            .publishPhoto(sessionId: session.id, photo: uploaded);
      }
      if (_liveEnabled) {
        // Live bật → khoe tấm ảnh vừa chụp lên group qua bot. Fire-and-forget.
        unawaited(
          ref
              .read(runNowApiClientProvider)
              .announceLive(
                activityId: session.id,
                event: 'photo',
                distanceMeters: next.distanceMeters,
                movingTimeSeconds: next.movingTimeSeconds.toDouble(),
                photoPath: uploaded.storagePath,
              )
              .catchError((_) {}),
        );
      }
    } catch (_) {
      // Bỏ qua — `_uploadPendingPhotos()` lúc dừng buổi chạy sẽ tự thử lại
      // (photo vẫn `!isUploaded` nên không mất dữ liệu, chỉ mất tính "live").
    }
  }

  Future<void> _stopAndSave() async {
    final session = _session;
    if (session == null || _saving) return;
    final current = _snapshot ?? session.snapshot();
    if (current.distanceMeters < minimumOfficialRunNowDistanceMeters) {
      final shouldStop = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Buổi chạy chưa đủ 500 m'),
          content: Text(
            'Bạn mới chạy ${formatDistance(current.distanceMeters)}. '
            'Session vẫn được lưu để xem lại nhưng sẽ không tính vào thành tích.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Tiếp tục chạy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Dừng và lưu'),
            ),
          ],
        ),
      );
      if (shouldStop != true || !mounted) return;
    }
    setState(() => _saving = true);
    try {
      await _positionSubscription?.cancel();
      _positionSubscription = null;
      _ticker?.cancel();
      _setWakelock(false);
      final snapshot = session.finish(DateTime.now());
      setState(() => _snapshot = snapshot);
      await _persistDraft();
      await _publishLiveSnapshot(
        force: true,
        status: LiveTrackingStatus.finished,
      );
      final photosUploaded = await _uploadPendingPhotos();
      final finalSnapshot = session.snapshot();
      final detail = finalSnapshot.toActivityDetail(
        name: '3I Run',
        recordingDevice: '3I app',
      );
      // Route đã được sync DẦN theo chunk (~10s/lần) trong lúc chạy. Đẩy nốt
      // đoạn cuối kể từ lần flush trước, rồi finalize chỉ gửi SUMMARY nhẹ
      // (stats/splits/streams, KHÔNG routePoints) — backend ghép chunk thành
      // route đầy đủ. Không còn "cú dump khổng lồ" ở cuối buổi (đúng ca buổi
      // race 10.4km từng vượt trần decode 2MB → mất buổi). trackingDebug cũng
      // đã bỏ hẳn (bản NHÂN ĐÔI ~695KB/buổi, backend không lưu).
      await _flushTrackChunk();
      final repository = ref.read(activityRepositoryProvider);
      // An toàn: chỉ finalize (nhẹ) khi TẤT CẢ điểm đã nằm trong chunk. Nếu lần
      // flush cuối lỗi mạng (chunk còn thiếu đuôi), degrade về full-save cũ để
      // KHÔNG mất phần route cuối — buổi vẫn đầy đủ như trước.
      final allChunked =
          _trackChunkResumed &&
          _flushedRoutePointCount >= finalSnapshot.routePoints.length;
      final result = allChunked
          ? await repository.finalizeTrackedActivity(detail)
          : await repository.saveTrackedActivity(detail);
      if (_liveEnabled && _liveAnnouncedStart) {
        // Buổi đã tường thuật live → chốt bằng tin "về đích". Fire-and-forget.
        unawaited(
          ref
              .read(runNowApiClientProvider)
              .announceLive(
                activityId: session.id,
                event: 'finish',
                distanceMeters: finalSnapshot.distanceMeters,
                movingTimeSeconds: finalSnapshot.movingTimeSeconds.toDouble(),
              )
              .catchError((_) {}),
        );
      }
      if (photosUploaded) await ref.read(trackingDraftStoreProvider).clear();
      if (!mounted) return;
      setState(() {
        _snapshot = finalSnapshot;
        _message = !photosUploaded
            ? _message
            : switch (result.status) {
                TrackedActivitySaveStatus.counted =>
                  'Đã lưu và tính buổi chạy vào thành tích.',
                TrackedActivitySaveStatus.belowMinimumDistance =>
                  'Đã lưu để xem lại nhưng không tính vì chưa đủ 500 m.',
                TrackedActivitySaveStatus.duplicateOfStrava =>
                  'Đã lưu route 3I nhưng thành tích ưu tiên buổi Strava trùng thời gian.',
              };
      });
      HapticFeedback.heavyImpact();
    } catch (error) {
      if (!mounted) return;
      setState(() => _message = 'Không lưu được buổi chạy: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _discard() async {
    final sessionId = _session?.id;
    final localPhotos = _session?.snapshot().photos ?? const [];
    if (sessionId != null) {
      unawaited(
        ref
            .read(liveTrackingRepositoryProvider)
            .finishSession(sessionId, LiveTrackingStatus.expired),
      );
    }
    await ref.read(trackingDraftStoreProvider).clear();
    for (final photo in localPhotos) {
      await ref.read(trackingPhotoCaptureProvider).deleteLocal(photo.localPath);
    }
    await _resetSession(message: 'Đã bỏ phiên tracking.');
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
                  Icon(
                    Icons.map_outlined,
                    color: context.runNowPalette.secondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'LIVE ROUTE',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: context.runNowPalette.secondary,
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
    _setWakelock(false);
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
      _lastLivePublishedAt = null;
      _lastLivePublishedDistanceMeters = 0;
      _contractId = widget.contractId;
      _message = message;
    });
  }

  Future<void> _startRunningLocationStream() async {
    await _positionSubscription?.cancel();
    _positionSubscription = ref
        .read(trackingLocationProvider)
        .runningSamples()
        .listen(_onPosition, onError: _onLocationError);
  }

  Future<void> _persistDraft() async {
    final session = _session;
    if (session == null || _persistingDraft) return;
    _persistingDraft = true;
    try {
      await ref
          .read(trackingDraftStoreProvider)
          .save(
            TrackingDraft(
              session: session,
              gpsWarmup: _lastWarmupDebug,
              contractId: _contractId,
            ),
          );
      _lastDraftSavedAt = DateTime.now();
    } finally {
      _persistingDraft = false;
    }
  }

  Future<bool> _ensureContractWindowAllowsRun() async {
    final contractId = _contractId;
    if (contractId == null) return true;
    try {
      final contract = await ref
          .read(runContractRepositoryProvider)
          .watchContract(contractId)
          .first;
      if (contract == null) {
        if (mounted) setState(() => _message = 'Không tìm thấy kèo tuyến.');
        return false;
      }
      final lifecycle = contractLifecycle(contract, DateTime.now());
      if (lifecycle == RunContractLifecycle.running) return true;
      final message = switch (lifecycle) {
        RunContractLifecycle.scheduled =>
          'Kèo này chưa tới giờ chạy. Chỉ bắt đầu được từ ${DateFormat('dd/MM · HH:mm').format(contract.startAt)}.',
        RunContractLifecycle.syncGrace ||
        RunContractLifecycle.awaitingFinalize ||
        RunContractLifecycle.completed ||
        RunContractLifecycle.failed => 'Kèo này đã hết thời gian chạy.',
        RunContractLifecycle.cancelled => 'Kèo này đã bị hủy.',
        RunContractLifecycle.running => '',
      };
      if (mounted) setState(() => _message = message);
      return false;
    } catch (error) {
      if (mounted) setState(() => _message = 'Không kiểm tra được kèo: $error');
      return false;
    }
  }

  Future<void> _persistDraftThrottled({
    Duration minInterval = const Duration(seconds: 10),
  }) async {
    final lastSavedAt = _lastDraftSavedAt;
    if (lastSavedAt != null &&
        DateTime.now().difference(lastSavedAt) < minInterval) {
      return;
    }
    await _persistDraft();
  }

  void _onPosition(TrackingLocationSample sample) {
    final session = _session;
    if (session == null || !_running) return;
    final snapshot = session.addLocation(sample);
    final latestLog = snapshot.pointLogs.isEmpty
        ? null
        : snapshot.pointLogs.last;
    setState(() {
      _snapshot = snapshot;
      _gpsSignal = _runningGpsSignal(sample, latestLog);
    });
    unawaited(_persistDraftThrottled());
    unawaited(_publishLiveSnapshot());
  }

  Future<void> _publishLiveSnapshot({
    bool force = false,
    LiveTrackingStatus? status,
  }) {
    final operation = _livePublishQueue.then(
      (_) => _publishLiveSnapshotNow(force: force, status: status),
    );
    _livePublishQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _publishLiveSnapshotNow({
    required bool force,
    LiveTrackingStatus? status,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final now = DateTime.now();
    final lastPublishedAt = _lastLivePublishedAt;
    final movedEnough =
        (snapshot.distanceMeters - _lastLivePublishedDistanceMeters).abs() >=
        _livePublishMinDistanceMeters;
    final waitedEnough =
        lastPublishedAt == null ||
        now.difference(lastPublishedAt) >= _livePublishMinInterval;
    if (!force && !movedEnough && !waitedEnough) return;
    try {
      await ref
          .read(liveTrackingRepositoryProvider)
          .publishSnapshot(
            snapshot: snapshot,
            status: status ?? _liveStatusForSnapshot(snapshot),
            routePreview: _downsampleLiveRoute(snapshot.routePoints),
            contractId: _contractId,
          );
      _lastLivePublishedAt = now;
      _lastLivePublishedDistanceMeters = snapshot.distanceMeters;
    } catch (_) {
      // Bỏ qua — lần publish tiếp theo (throttle ~10s/50m) sẽ tự thử lại.
    }
  }

  LiveTrackingStatus _liveStatusForSnapshot(TrackingSessionSnapshot snapshot) {
    return switch (snapshot.status) {
      TrackingSessionStatus.running => LiveTrackingStatus.running,
      TrackingSessionStatus.paused => LiveTrackingStatus.paused,
      TrackingSessionStatus.finished => LiveTrackingStatus.finished,
      TrackingSessionStatus.idle => LiveTrackingStatus.expired,
    };
  }

  List<RoutePoint> _downsampleLiveRoute(List<RoutePoint> points) {
    if (points.length <= 2) return points;
    final preview = <RoutePoint>[points.first];
    var lastAccepted = points.first;
    for (final point in points.skip(1)) {
      final distance = Geolocator.distanceBetween(
        lastAccepted.latitude,
        lastAccepted.longitude,
        point.latitude,
        point.longitude,
      );
      if (distance >= _liveRoutePreviewStepMeters || point == points.last) {
        preview.add(point);
        lastAccepted = point;
      }
    }
    return preview;
  }

  _GpsSignal _runningGpsSignal(
    TrackingLocationSample sample,
    TrackingPointLog? log,
  ) {
    final accuracy = sample.accuracyMeters ?? double.infinity;
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

    final sampleSpeed = sample.speedMetersPerSecond ?? 0.0;
    final reportedSpeed = sampleSpeed.isFinite ? sampleSpeed : 0.0;
    if (accuracy <= 12 && reportedSpeed <= 7.5) return _GpsSignal.ready;
    if (accuracy <= 25 && reportedSpeed <= 9) return _GpsSignal.fair;
    return _GpsSignal.weak;
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final session = _session;
      if (!mounted || session == null || !_running) return;
      final now = DateTime.now();
      setState(() => _snapshot = session.tick(now));
      unawaited(_persistDraftThrottled());
      final lastPublishedAt = _lastLivePublishedAt;
      if (lastPublishedAt == null ||
          now.difference(lastPublishedAt) >= _liveHeartbeatInterval) {
        unawaited(_publishLiveSnapshot());
      }
      final lastChunkAt = _lastTrackChunkAt;
      if (lastChunkAt == null ||
          now.difference(lastChunkAt) >= _trackChunkInterval) {
        unawaited(_flushTrackChunk());
      }
      _maybeAnnounceLive(session);
    });
  }

  /// Kiểm mốc live trong lúc chạy: báo start khi vượt ngưỡng, và mỗi khi qua
  /// bội số 5km mới. Bắn API fire-and-forget (không chặn tracking).
  void _maybeAnnounceLive(TrackingSession session) {
    if (!_liveEnabled) return;
    final distance = session.snapshot().distanceMeters;
    if (!_liveAnnouncedStart) {
      if (distance >= _liveStartMinMeters) {
        _liveAnnouncedStart = true;
        _liveAnnounceQueue = _liveAnnounceQueue
            .then((_) => _announceLive(session, 'start'))
            .catchError((_) {});
      }
      return;
    }
    final milestoneKm = (distance / _liveMilestoneMeters).floor() * 5;
    if (milestoneKm > _liveAnnouncedKm) {
      _liveAnnouncedKm = milestoneKm;
      _liveAnnounceQueue = _liveAnnounceQueue
          .then((_) => _announceLive(session, 'milestone', milestoneKm: milestoneKm))
          .catchError((_) {});
    }
  }

  Future<void> _announceLive(
    TrackingSession session,
    String event, {
    int milestoneKm = 0,
  }) async {
    final snapshot = session.snapshot();
    await ref
        .read(runNowApiClientProvider)
        .announceLive(
          activityId: session.id,
          event: event,
          distanceMeters: snapshot.distanceMeters,
          movingTimeSeconds: snapshot.movingTimeSeconds.toDouble(),
          milestoneKm: milestoneKm,
        );
  }

  /// Đẩy đoạn điểm route MỚI (kể từ lần đẩy trước) thành 1 chunk append-only.
  /// Serialize qua queue để 2 lần tick không đua ghi cùng seq. Lỗi mạng nuốt
  /// êm — tick sau tự thử lại (seq/điểm chưa đổi vì chỉ nhích khi ghi thành
  /// công), Stop vẫn chốt bằng finalize.
  Future<void> _flushTrackChunk() {
    _trackChunkQueue = _trackChunkQueue
        .then((_) => _flushTrackChunkNow())
        .catchError((_) {});
    return _trackChunkQueue;
  }

  Future<void> _flushTrackChunkNow() async {
    final session = _session;
    if (session == null) return;
    // Buổi khôi phục sau khi app bị kill: dò chunk đã ghi để đẩy tiếp không đè.
    if (!_trackChunkResumed) {
      final state = await ref
          .read(activityRepositoryProvider)
          .trackChunkState(session.id);
      _trackChunkSeq = state.nextSeq;
      _flushedRoutePointCount = state.flushedPoints;
      _trackChunkResumed = true;
    }
    final points = session.snapshot().routePoints;
    if (_flushedRoutePointCount >= points.length) {
      _lastTrackChunkAt = DateTime.now();
      return;
    }
    final segment = points.sublist(_flushedRoutePointCount);
    final lean = segment
        .map(
          (point) => <String, dynamic>{
            'latitude': point.latitude,
            'longitude': point.longitude,
            'timestamp': point.timestamp.toUtc().toIso8601String(),
          },
        )
        .toList();
    final seq = _trackChunkSeq;
    await ref
        .read(activityRepositoryProvider)
        .appendTrackChunk(activityId: session.id, seq: seq, points: lean);
    _trackChunkSeq = seq + 1;
    _flushedRoutePointCount = points.length;
    _lastTrackChunkAt = DateTime.now();
  }

  void _resetTrackChunkState() {
    _trackChunkSeq = 0;
    _flushedRoutePointCount = 0;
    _lastTrackChunkAt = null;
    _trackChunkResumed = true; // buổi mới: bắt đầu sạch từ seq 0, khỏi dò.
    _liveAnnouncedStart = false;
    _liveAnnouncedKm = 0;
  }

  Future<TrackingLocationSample?> _waitForStableGps() async {
    final completer = Completer<TrackingLocationSample?>();
    StreamSubscription<TrackingLocationSample>? subscription;
    Timer? timeout;
    var sampleCount = 0;
    var goodSamples = 0;
    var fairSamples = 0;
    var averageAccuracy = double.infinity;
    var windowDriftMeters = 0.0;
    TrackingLocationSample? best;
    final window = <TrackingLocationSample>[];
    final startedAt = DateTime.now();

    void complete(TrackingLocationSample? position) {
      if (completer.isCompleted) return;
      timeout?.cancel();
      subscription?.cancel();
      _lastWarmupDebug = {
        'startedAt': startedAt.toUtc().toIso8601String(),
        'endedAt': DateTime.now().toUtc().toIso8601String(),
        'sampleCount': sampleCount,
        'windowSamples': window.length,
        'goodSamples': goodSamples,
        'fairSamples': fairSamples,
        'windowSize': _gpsWarmupWindowSamples,
        'minGoodSamples': _gpsWarmupMinGoodSamples,
        'goodAccuracyMeters': _gpsWarmupGoodAccuracyMeters,
        'fairAccuracyMeters': _gpsWarmupFairAccuracyMeters,
        'maxWindowDriftMeters': _gpsWarmupMaxWindowDriftMeters,
        'actualWindowDriftMeters': windowDriftMeters,
        'averageAccuracyMeters': averageAccuracy.isFinite
            ? averageAccuracy
            : null,
        'maxReportedSpeedMetersPerSecond':
            _gpsWarmupMaxReportedSpeedMetersPerSecond,
        'bestAccuracyMeters': best?.accuracyMeters,
        'lockedAccuracyMeters': position?.accuracyMeters,
      }..removeWhere((key, value) => value == null);
      completer.complete(position);
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

    subscription = ref
        .read(trackingLocationProvider)
        .warmupSamples()
        .listen(
          (position) {
            sampleCount += 1;
            final accuracy = position.accuracyMeters ?? double.infinity;
            if (best == null ||
                accuracy < (best!.accuracyMeters ?? double.infinity)) {
              best = position;
            }
            window.add(position);
            if (window.length > _gpsWarmupWindowSamples) {
              window.removeAt(0);
            }
            goodSamples = 0;
            fairSamples = 0;
            var accuracySum = 0.0;
            var finiteAccuracyCount = 0;
            for (final sample in window) {
              final sampleAccuracy = sample.accuracyMeters ?? double.infinity;
              final speed = sample.speedMetersPerSecond ?? 0;
              final cleanSpeed = speed.isFinite ? speed : 0;
              if (sampleAccuracy.isFinite) {
                accuracySum += sampleAccuracy;
                finiteAccuracyCount += 1;
              }
              final speedOk =
                  cleanSpeed <= _gpsWarmupMaxReportedSpeedMetersPerSecond;
              if (sampleAccuracy <= _gpsWarmupGoodAccuracyMeters && speedOk) {
                goodSamples += 1;
              }
              if (sampleAccuracy <= _gpsWarmupFairAccuracyMeters && speedOk) {
                fairSamples += 1;
              }
            }
            averageAccuracy = finiteAccuracyCount == 0
                ? double.infinity
                : accuracySum / finiteAccuracyCount;
            windowDriftMeters = _windowDriftMeters(window);
            final elapsed = DateTime.now().difference(startedAt);
            final hasEnoughSamples = window.length >= _gpsWarmupWindowSamples;
            final hasEnoughGoodSamples =
                goodSamples >= _gpsWarmupMinGoodSamples;
            final hasAcceptableDrift =
                windowDriftMeters <= _gpsWarmupMaxWindowDriftMeters;
            final ready =
                hasEnoughSamples && hasEnoughGoodSamples && hasAcceptableDrift;
            if (mounted) {
              setState(() {
                _gpsElapsedSeconds = elapsed.inSeconds;
                _gpsStableSamples = goodSamples;
                _gpsSignal = ready
                    ? _GpsSignal.ready
                    : fairSamples >= _gpsWarmupMinGoodSamples &&
                          windowDriftMeters <= _gpsWarmupMaxWindowDriftMeters
                    ? _GpsSignal.fair
                    : _GpsSignal.weak;
                _message =
                    'Đang khóa GPS... good $goodSamples/$_gpsWarmupWindowSamples · acc ${accuracy.toStringAsFixed(0)}m';
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

  double _windowDriftMeters(List<TrackingLocationSample> samples) {
    if (samples.length < 2) return 0;
    final first = samples.first;
    var maxDrift = 0.0;
    for (final sample in samples.skip(1)) {
      maxDrift = math.max(
        maxDrift,
        haversineDistanceMeters(
          first.latitude,
          first.longitude,
          sample.latitude,
          sample.longitude,
        ),
      );
    }
    return maxDrift;
  }

  void _onLocationError(Object error) {
    if (!mounted) return;
    setState(() => _message = 'Lỗi GPS: $error');
  }

  Future<bool> _ensureLocationReady() async {
    final locationProvider = ref.read(trackingLocationProvider);
    final serviceEnabled = await locationProvider.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _message =
            'Dịch vụ vị trí đang tắt. Bật GPS để ghi lại tuyến đường và pace '
            'của buổi chạy.';
        _settingsAction = locationProvider.openLocationSettings;
      });
      return false;
    }

    var permission = await locationProvider.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await locationProvider.requestPermission();
    }

    // denied và deniedForever đều là "user đã từ chối" — trên iOS lần bấm
    // "Don't Allow" đầu tiên đã cho ra deniedForever vì hệ thống không hỏi
    // lại. Cả hai trường hợp chỉ giải thích tính năng cần gì rồi dừng; mở
    // Settings hay không là quyền của user.
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _message =
            'Ghi buổi chạy cần quyền vị trí để vẽ tuyến đường và tính '
            'quãng đường, pace. Các phần khác của app vẫn dùng bình thường.';
        _settingsAction = permission == LocationPermission.deniedForever
            ? locationProvider.openAppSettings
            : null;
      });
      return false;
    }

    // Foreground đã được cấp (whileInUse hoặc always).
    //
    // Android: foreground service (loại location, có notification) đã đủ để
    // tracking tiếp tục khi khóa màn hình / chuyển app khác, nên KHÔNG cần quyền
    // nền "Always" — app cũng không khai ACCESS_BACKGROUND_LOCATION nữa.
    //
    // iOS: giữ nguyên hành vi bản đang chạy trên App Store — thử nâng lên
    // "Always" để tracking nền mượt hơn.
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        permission == LocationPermission.whileInUse) {
      permission = await locationProvider.requestPermission();
    }
    _backgroundLocationGranted = permission == LocationPermission.always;
    return true;
  }

  String _statusLabel(TrackingSessionSnapshot? snapshot) {
    return switch (snapshot?.status) {
      TrackingSessionStatus.running => 'Đang bám vị trí',
      TrackingSessionStatus.paused => 'Tạm dừng ghi',
      TrackingSessionStatus.finished =>
        _checkingPermission
            ? 'Đang chuẩn bị buổi mới'
            : _gpsReady
            ? 'Sẵn sàng buổi mới'
            : 'Đã lưu buổi chạy',
      TrackingSessionStatus.idle ||
      null => _gpsReady ? 'Đã khóa vị trí' : 'Sẵn sàng',
    };
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
    required this.capturingPhoto,
    required this.canTakePhoto,
    required this.onLockGps,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStop,
    required this.onDiscard,
    required this.onPhoto,
  });

  final bool running;
  final bool paused;
  final bool finished;
  final bool hasSession;
  final bool gpsReady;
  final bool busy;
  final bool capturingPhoto;
  final bool canTakePhoto;
  final VoidCallback onLockGps;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStop;
  final VoidCallback onDiscard;
  final VoidCallback onPhoto;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    if (!hasSession || finished) {
      final label = switch ((finished, gpsReady)) {
        (true, true) => 'BẮT ĐẦU BUỔI MỚI',
        (true, false) => 'QUÉT GPS CHO BUỔI MỚI',
        (false, true) => 'BẮT ĐẦU CHẠY',
        (false, false) => 'QUÉT GPS',
      };
      final icon = switch ((finished, gpsReady)) {
        (true, true) => Icons.play_arrow_rounded,
        (true, false) => Icons.gps_fixed_rounded,
        (false, true) => Icons.play_arrow_rounded,
        (false, false) => Icons.gps_not_fixed_rounded,
      };
      final enabledColor = gpsReady ? palette.accent : palette.accentDeep;
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: enabledColor.withValues(alpha: 0.25),
              blurRadius: 24,
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 66,
          child: FilledButton.icon(
            onPressed: busy ? null : (gpsReady ? onStart : onLockGps),
            style: FilledButton.styleFrom(
              backgroundColor: enabledColor,
              foregroundColor: gpsReady ? Colors.black : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            icon: busy
                ? SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: gpsReady ? Colors.black : Colors.white,
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
    if (running) {
      return SizedBox(
        height: 66,
        child: Row(
          children: [
            _PhotoButton(
              enabled: canTakePhoto && !busy,
              loading: capturingPhoto,
              onPressed: onPhoto,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : onPause,
                style: FilledButton.styleFrom(
                  backgroundColor: RunNowSemanticColors.danger,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                icon: const Icon(Icons.pause_rounded, size: 28),
                label: const Text(
                  'TẠM DỪNG',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 66,
      child: Row(
        children: [
          _PhotoButton(
            enabled: canTakePhoto && !busy,
            loading: capturingPhoto,
            onPressed: onPhoto,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: busy ? null : onResume,
              style: FilledButton.styleFrom(
                backgroundColor: palette.accent,
                foregroundColor: palette.ink,
                minimumSize: const Size.fromHeight(58),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('TIẾP TỤC'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: busy ? null : onStop,
              style: OutlinedButton.styleFrom(
                foregroundColor: RunNowSemanticColors.danger,
                minimumSize: const Size.fromHeight(58),
                side: const BorderSide(color: RunNowSemanticColors.danger),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: const Text('KẾT THÚC'),
            ),
          ),
          const SizedBox(width: 6),
          IconButton.outlined(
            tooltip: 'Bỏ phiên',
            onPressed: busy ? null : onDiscard,
            style: IconButton.styleFrom(
              foregroundColor: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.62),
              minimumSize: const Size.square(48),
            ),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _PhotoButton extends StatelessWidget {
  const _PhotoButton({
    required this.enabled,
    required this.loading,
    required this.onPressed,
  });

  final bool enabled;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: 'Chụp ảnh và neo lên route',
      onPressed: enabled && !loading ? onPressed : null,
      style: IconButton.styleFrom(minimumSize: const Size.square(58)),
      icon: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_a_photo_outlined, size: 25),
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
    final routePoints = snapshot?.routePoints ?? const <RoutePoint>[];
    return Column(
      children: [
        SizedBox(
          height: 330,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                top: 4,
                child: Semantics(
                  button: onMap != null,
                  enabled: onMap != null,
                  label: 'Xem bản đồ hành trình',
                  child: Material(
                    color: Colors.transparent,
                    child: InkResponse(
                      onTap: onMap,
                      customBorder: const CircleBorder(),
                      radius: 119,
                      child: _RoutePreview(
                        signal: signal,
                        elapsedSeconds: elapsedSeconds,
                        stableSamples: stableSamples,
                        minSeconds: minSeconds,
                        minSamples: minSamples,
                        routePoints: routePoints,
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DistanceReadout(distance: distance),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.56),
                          fontSize: 11,
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
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 72,
                child: _MetricCard(label: 'THỜI GIAN', value: time),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 72,
                child: _MetricCard(label: 'PACE TB', value: pace),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SizedBox(
                height: 72,
                child: _MetricCard(label: 'PACE TỨC THỜI', value: livePace),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 22,
              child: Align(
                alignment: Alignment.topLeft,
                child: Text(
                  label,
                  maxLines: 2,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.54),
                    fontSize: 9,
                    height: 1.15,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistanceReadout extends StatelessWidget {
  const _DistanceReadout({required this.distance});

  final String distance;

  @override
  Widget build(BuildContext context) {
    final split = distance.lastIndexOf(' ');
    final value = split < 0 ? distance : distance.substring(0, split);
    final unit = split < 0 ? '' : distance.substring(split + 1);
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: TextStyle(
              color: textColor,
              fontSize: 64,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -2,
            ),
          ),
          if (unit.isNotEmpty)
            TextSpan(
              text: ' $unit',
              style: TextStyle(
                color: context.runNowPalette.accent,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10),
        ],
      ),
    );
  }
}

Color _gpsSignalColor(_GpsSignal signal) {
  return switch (signal) {
    // Thủy teal for a resolved lock — keeps the console on-brand instead of
    // clashing with the Mộc "success" green used elsewhere in the app.
    _GpsSignal.ready => RunNowSemanticColors.info,
    _GpsSignal.fair => RunNowSemanticColors.gpsFair,
    _GpsSignal.weak => RunNowSemanticColors.gpsWeak,
    _GpsSignal.locking => RunNowSemanticColors.gpsLocking,
    _GpsSignal.idle => RunNowSemanticColors.inactive,
  };
}

String _gpsSignalWord(_GpsSignal signal) {
  return switch (signal) {
    _GpsSignal.ready => 'tốt',
    _GpsSignal.fair => 'khá',
    _GpsSignal.weak => 'yếu',
    _GpsSignal.locking => 'đang dò',
    _GpsSignal.idle => 'chờ',
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
    final statusColor = active ? RunNowSemanticColors.info : signalColor;
    return Row(
      children: [
        Flexible(
          fit: FlexFit.loose,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: statusColor.withValues(alpha: 0.5)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatusDot(color: statusColor),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      status,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const Spacer(),
        const SizedBox(width: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.signal_cellular_alt_rounded,
              color: signalColor,
              size: 17,
            ),
            const SizedBox(width: 5),
            Text(
              'GPS ',
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.56),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              _gpsSignalWord(signal),
              style: TextStyle(
                color: signalColor,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _RoutePreview extends StatelessWidget {
  const _RoutePreview({
    required this.signal,
    required this.elapsedSeconds,
    required this.stableSamples,
    required this.minSeconds,
    required this.minSamples,
    required this.routePoints,
  });

  final _GpsSignal signal;
  final int elapsedSeconds;
  final int stableSamples;
  final int minSeconds;
  final int minSamples;
  final List<RoutePoint> routePoints;

  @override
  Widget build(BuildContext context) {
    final color = _gpsSignalColor(signal);
    final locking = signal == _GpsSignal.locking;
    final sampleProgress = minSamples <= 0
        ? 0.0
        : (stableSamples / minSamples).clamp(0.0, 1.0);
    final timeProgress = minSeconds <= 0
        ? null
        : (elapsedSeconds / minSeconds).clamp(0.0, 1.0);
    final progress = timeProgress == null
        ? sampleProgress
        : (timeProgress + sampleProgress) / 2;
    final hasRoute = routePoints.length >= 2;
    return SizedBox(
      width: 238,
      height: 238,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(238),
            painter: _RoutePreviewPainter(
              color: color,
              backgroundColor: context.runNowPalette.glassStart,
              roadColor: context.runNowPalette.foreground.withValues(
                alpha: 0.13,
              ),
              progress: locking ? progress : null,
              routePoints: routePoints,
            ),
          ),
          if (!hasRoute)
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: context.runNowPalette.background,
                  width: 4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.42),
                    blurRadius: 18,
                    spreadRadius: 7,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoutePreviewPainter extends CustomPainter {
  const _RoutePreviewPainter({
    required this.color,
    required this.backgroundColor,
    required this.roadColor,
    required this.progress,
    required this.routePoints,
  });

  final Color color;
  final Color backgroundColor;
  final Color roadColor;

  /// Warmup-lock progress (0..1). Null once the signal has resolved — the
  /// arc is only meaningful while actively scanning for a fix.
  final double? progress;
  final List<RoutePoint> routePoints;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final circle = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    canvas.save();
    canvas.clipPath(circle);
    canvas.drawCircle(center, radius, Paint()..color = backgroundColor);

    final areaPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withValues(alpha: 0.055);
    final area = Path()
      ..moveTo(-20, size.height * 0.58)
      ..cubicTo(
        size.width * 0.22,
        size.height * 0.44,
        size.width * 0.44,
        size.height * 0.72,
        size.width * 0.7,
        size.height * 0.55,
      )
      ..cubicTo(
        size.width * 0.86,
        size.height * 0.45,
        size.width * 1.05,
        size.height * 0.5,
        size.width + 20,
        size.height * 0.5,
      )
      ..lineTo(size.width + 20, size.height + 20)
      ..lineTo(-20, size.height + 20)
      ..close();
    canvas.drawPath(area, areaPaint);

    final roadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = roadColor;
    final minorRoadPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = roadColor.withValues(alpha: 0.65);

    final verticalRoads = [0.23, 0.5, 0.77];
    for (final x in verticalRoads) {
      final path = Path()
        ..moveTo(size.width * x, -12)
        ..cubicTo(
          size.width * (x - 0.04),
          size.height * 0.3,
          size.width * (x + 0.05),
          size.height * 0.68,
          size.width * (x - 0.02),
          size.height + 12,
        );
      canvas.drawPath(path, x == 0.5 ? roadPaint : minorRoadPaint);
    }
    final horizontalRoads = [0.26, 0.52, 0.78];
    for (final y in horizontalRoads) {
      final path = Path()
        ..moveTo(-12, size.height * y)
        ..cubicTo(
          size.width * 0.3,
          size.height * (y + 0.05),
          size.width * 0.68,
          size.height * (y - 0.04),
          size.width + 12,
          size.height * (y + 0.02),
        );
      canvas.drawPath(path, y == 0.52 ? roadPaint : minorRoadPaint);
    }

    final progress = this.progress;
    if (progress != null) {
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

    if (routePoints.length >= 2) {
      final points = _fitRoutePoints(routePoints, radius * 0.78, center);
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      final routePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color;
      canvas.drawPath(path, routePaint);
      canvas.drawCircle(
        points.last,
        9,
        Paint()..color = color.withValues(alpha: 0.25),
      );
      canvas.drawCircle(points.last, 5, Paint()..color = color);
    }
    canvas.restore();
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = roadColor,
    );
  }

  @override
  bool shouldRepaint(covariant _RoutePreviewPainter oldDelegate) {
    // `routePoints` được bọc lại bằng `List.unmodifiable(...)` mỗi lần lấy
    // snapshot (kể cả khi tick mỗi giây, không có điểm GPS mới), nên so theo
    // tham chiếu (`!=`) sẽ luôn coi là "đổi" và vẽ lại toàn bộ route dù không
    // cần thiết. Route chỉ được append, không bao giờ sửa nội dung mà giữ
    // nguyên độ dài, nên so độ dài là đủ và rẻ hơn nhiều so với việc project
    // lại toàn bộ điểm mỗi giây.
    return oldDelegate.color != color ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.roadColor != roadColor ||
        oldDelegate.progress != progress ||
        oldDelegate.routePoints.length != routePoints.length;
  }
}

/// Projects [points] onto a square inscribed in the radar circle, centered
/// on their own bounding box — a lightweight preview, not a real map.
List<Offset> _fitRoutePoints(
  List<RoutePoint> points,
  double maxRadius,
  Offset center,
) {
  var minLat = points.first.latitude;
  var maxLat = points.first.latitude;
  var minLng = points.first.longitude;
  var maxLng = points.first.longitude;
  for (final point in points) {
    minLat = math.min(minLat, point.latitude);
    maxLat = math.max(maxLat, point.latitude);
    minLng = math.min(minLng, point.longitude);
    maxLng = math.max(maxLng, point.longitude);
  }
  final span = math.max(maxLat - minLat, maxLng - minLng);
  if (span <= 0) {
    return points.map((_) => center).toList();
  }
  final midLat = (minLat + maxLat) / 2;
  final midLng = (minLng + maxLng) / 2;
  return points.map((point) {
    final dx = (point.longitude - midLng) / span * maxRadius * 2;
    // Latitude increases northward but screen y increases downward.
    final dy = -(point.latitude - midLat) / span * maxRadius * 2;
    return Offset(center.dx + dx, center.dy + dy);
  }).toList();
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
            '3I TRACKING',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.secondary,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Session từ 500 m được tính vào thành tích. Nếu trùng trên 30% thời gian, dữ liệu Strava được ưu tiên.',
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
