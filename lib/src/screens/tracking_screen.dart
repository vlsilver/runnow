import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/activity_eligibility.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/rooms/live_board.dart';
import 'package:myrun/src/rooms/run_room_actions.dart' show runRoomErrorText;
import 'package:myrun/src/rooms/run_room_create_sheet.dart'
    show runRoomMaxRunners;
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/rooms/run_room_run_panel.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/tracking_draft_store.dart';
import 'package:myrun/src/tracking_session.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/route_map.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({
    super.key,
    this.autoLock = true,
    this.contractId,
    this.roomId,
  });

  final bool autoLock;
  final String? contractId;

  /// Chạy trong phòng: buổi live gắn roomId để người trong phòng thấy nhau.
  final String? roomId;

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

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
  // Vị trí GPS mới nhất (kể cả lúc đang dò, chưa khoá) để map có tâm hiển thị
  // NGAY, không phải chờ khoá xong.
  TrackingLocationSample? _lastGpsSample;
  StreamSubscription<TrackingLocationSample>? _positionSubscription;
  Timer? _ticker;
  var _checkingPermission = false;
  var _saving = false;
  var _capturingPhoto = false;
  // Thông báo dưới đáy TỰ TẮT sau vài giây — không để dính panel "show mãi".
  // Mọi chỗ vẫn gán `_message = ...` như thường; setter tự hẹn giờ xoá.
  String? _messageValue;
  Timer? _messageTimer;
  String? get _message => _messageValue;
  set _message(String? value) {
    _messageValue = value;
    _messageTimer?.cancel();
    if (value != null) {
      _messageTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _messageValue = null);
      });
    }
  }

  // Kèm theo _message khi cách khắc phục nằm ở Settings của máy. Null nghĩa
  // là không hiện nút, tránh mời user vào Settings khi chẳng có gì để sửa.
  VoidCallback? _settingsAction;
  Map<String, dynamic>? _lastWarmupDebug;
  var _autoLockStarted = false;
  var _persistingDraft = false;
  String? _contractId;
  String? _roomId;
  // Đọc từ phòng ở build; null khi chưa tải xong phòng.
  RunRoomPrivacy? _roomPrivacy;
  RunRoomKind? _roomKind;
  String? _roomHostUid;
  bool _roomJoined = false;
  // Chạy riêng có nhận người chạy cùng không. Chọn trước khi bắt đầu; nhận
  // thì lúc bắt đầu mở một phòng solo. Chỉ giữ trong màn này, như các cài
  // đặt Live khác.
  LiveJoinPolicy _joinPolicy = LiveJoinPolicy.approve;
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
  // trong lúc chạy. Mặc định BẬT nếu hồ sơ công khai (private thì Live vô nghĩa
  // vì backend không khoe), áp dụng 1 lần khi biết visibility.
  bool _liveEnabled = false;
  bool _liveDefaultApplied = false;
  bool _liveAnnouncedStart = false;
  int _liveAnnouncedKm = 0;
  // User tự chỉnh trong nút cài đặt Live: báo mỗi mấy km, và có đăng ảnh không.
  int _liveMilestoneKm = 2;
  bool _livePhotoEnabled = true;
  static const List<int> _liveMilestoneOptions = [1, 2, 3, 5];

  // Môn của buổi đang ghi. Chọn TRƯỚC khi bắt đầu; chốt khi bấm Bắt đầu. Chạy
  // bộ là mặc định. Đạp xe/xe máy KHÔNG cộng vào km chạy/kèo — có BXH riêng.
  ActivityKind _selectedKind = ActivityKind.run;

  // Ngưỡng tốc độ chống-nhảy-GPS theo môn (m/s). Chạy giữ mặc định từ DB; đạp
  // ~90km/h, xe máy ~162km/h — nếu vẫn 36km/h như chạy sẽ cắt nhầm điểm thật.
  double? _maxSpeedOverrideFor(ActivityKind kind) => switch (kind) {
    ActivityKind.ride => 25, // ~90 km/h
    ActivityKind.motorbike => 45, // ~162 km/h
    _ => null, // chạy/khác: dùng cấu hình DB (mặc định 10 m/s)
  };

  // Bước báo mốc km khi Live. Chạy = user chọn; đạp = mỗi 10km; xe máy = mỗi
  // 20km (quãng đường đạp/xe máy dài, mốc nhỏ sẽ spam group).
  int get _effectiveMilestoneKm => switch (_selectedKind) {
    ActivityKind.ride => 10,
    ActivityKind.motorbike => 20,
    _ => _liveMilestoneKm,
  };

  String _activityNameFor(ActivityKind kind) => switch (kind) {
    ActivityKind.walk => '3I Walk',
    ActivityKind.ride => '3I Ride',
    ActivityKind.motorbike => '3I Moto',
    _ => '3I Run',
  };
  Future<void> _liveAnnounceQueue = Future<void>.value();
  static const double _liveStartMinMeters = 300;

  bool get _running => _snapshot?.status == TrackingSessionStatus.running;
  bool get _paused => _snapshot?.status == TrackingSessionStatus.paused;
  bool get _finished => _snapshot?.status == TrackingSessionStatus.finished;
  bool get _hasSession => _snapshot != null;
  bool get _gpsReady => _gpsReadyAnchor != null;

  bool get _roomOnly => runRoomLiveRoomOnly(
    roomId: _roomId,
    kind: _roomKind,
    privacy: _roomPrivacy,
  );

  bool get _canHostRunTogether => runRoomCanHostRunTogether(
    roomId: widget.roomId,
    isRun: _selectedKind == ActivityKind.run,
    liveEnabled: _liveEnabled,
  );

  /// Dòng phụ của Live: trước khi chạy là lựa chọn, đang chạy chỉ hiện khi
  /// phòng solo đã mở thật.
  bool get _showRunTogether =>
      _canHostRunTogether && (!_hasSession || _roomKind == RunRoomKind.solo);


  @override
  void initState() {
    super.initState();
    _contractId = widget.contractId;
    _roomId = widget.roomId;
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
    _messageTimer?.cancel();
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

  /// Báo người đang chạy khi có người xem live thả tim.
  void _toastNewHearts(Hearts? previous, AsyncValue<Hearts> next) {
    if (next.error case final error?) {
      debugPrint('Không đọc được tim buổi live: $error');
      return;
    }
    final hearts = next.value;
    final myUid = ref.read(firebaseUserProvider).value?.uid;
    if (hearts == null || myUid == null || !mounted) return;
    final uids = newHeartUids(previous, hearts, myUid: myUid);
    if (uids.isEmpty) return;
    final members = ref.read(membersProvider).value ?? const <MemberProfile>[];
    final first =
        members.where((member) => member.uid == uids.first).firstOrNull
            ?.displayName ??
        'Một người';
    final text = uids.length == 1
        ? '$first thả tim cho bạn'
        : '$first và ${uids.length - 1} người nữa thả tim cho bạn';
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          content: Row(
            children: [
              const Icon(Icons.favorite_rounded, color: RunNowDataColors.heart),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
            ],
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    // Giữ subscribe cấu hình tracking từ DB để lúc bấm Bắt đầu đã có giá trị mới
    // nhất (appConfig/tracking) thay vì mặc định.
    ref.watch(trackingConfigProvider);
    final roomId = _roomId;
    if (roomId != null) {
      // Giữ giá trị cũ lúc doc phòng đang tải: phòng solo vừa mở đã gán sẵn ở
      // _openSoloRoom, gán null thì buổi live bị giấu trong chốc lát.
      if (ref.watch(runRoomProvider(roomId)).value case final room?) {
        _roomPrivacy = room.privacy;
        _roomKind = room.kind;
        _roomHostUid = room.hostUid;
      }
      _roomJoined =
          ref.watch(myRunRoomMemberProvider(roomId)).value?.state ==
          RunRoomMemberState.joined;
      // Phòng kín thì không báo lên group Telegram: người ngoài phòng không
      // xem được buổi live mà tin trên group lại lộ ra là đang chạy. Chờ biết
      // kiểu phòng rồi mới tắt, để phòng công khai giữ mặc định Live.
      if (_roomPrivacy != null && _roomOnly) _liveEnabled = false;
    }
    final liveId = _liveEnabled ? _session?.id : null;
    if (liveId != null) {
      // Giữ danh sách thành viên để toast có tên, không rebuild màn này.
      ref.listen(membersProvider, (_, _) {});
      ref.listen(
        heartsProvider(liveHeartTarget(liveId)),
        (previous, next) => _toastNewHearts(previous?.value, next),
      );
    }
    final snapshot = _snapshot;
    final isPublic =
        ref.watch(userProfileProvider).value?.visibility ==
        ProfileVisibility.public;
    // Mặc định BẬT Live cho hồ sơ công khai — nhưng CHỈ với chạy bộ. Đạp xe/xe
    // máy mặc định TẮT Live (user bật tay nếu muốn). Áp 1 lần khi biết visibility.
    if (isPublic && !_liveDefaultApplied) {
      _liveDefaultApplied = true;
      _liveEnabled = _selectedKind == ActivityKind.run;
    }
    final distance = formatDistance(snapshot?.distanceMeters ?? 0);
    final time = formatDuration(snapshot?.movingTimeSeconds ?? 0);
    final pace = formatPace(snapshot?.averagePaceSecondsPerKm);
    final livePace = formatPace(snapshot?.currentPaceSecondsPerKm);
    final mapPoints = _liveMapPoints(snapshot);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Scaffold(
      // Map TRÀN VIỀN toàn màn; số liệu + điều khiển nổi lên trên (kiểu app dẫn
      // đường), không card/padding/bo góc bọc map nữa.
      body: Stack(
        children: [
          Positioned.fill(
            child: mapPoints.isNotEmpty
                ? LayoutBuilder(
                    builder: (context, c) => RouteMap.fromRoutePoints(
                      points: mapPoints,
                      follow: true,
                      height: c.maxHeight,
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Đang lấy vị trí GPS…',
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          if (!_running && !_paused)
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, left: 12),
                  child: Material(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.92),
                    elevation: 3,
                    shadowColor: Colors.black.withValues(alpha: 0.3),
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => context.go('/'),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (roomId == null && !_hasSession)
            const Positioned(
              top: 0,
              left: 64,
              right: 64,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: _LiveNearbyPill()),
                ),
              ),
            ),
          if (roomId != null)
            Positioned(
              top: 0,
              // Chừa chỗ nút đóng khi chưa chạy.
              left: !_running && !_paused ? 64 : 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: RunRoomRunPanel(roomId: roomId),
                ),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_message != null && !_checkingPermission && !_running)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: GlassPanel(
                        borderRadius: 18,
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _message!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (_settingsAction != null) ...[
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _settingsAction,
                                child: const Text('Mở Cài đặt'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  GlassPanel(
                    borderRadius: 24,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _DistanceReadout(distance: distance),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 74,
                                child: _MetricCard(
                                  label: 'THỜI GIAN',
                                  value: time,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 74,
                                child: _MetricCard(label: 'PACE TB', value: pace),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SizedBox(
                                height: 74,
                                child: _MetricCard(
                                  label: 'PACE TỨC THỜI',
                                  value: livePace,
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Live gom vào cùng card cho liền khối, không trôi nổi.
                        if (isPublic && !_finished && !_roomOnly) ...[
                          const SizedBox(height: 10),
                          Divider(
                            height: 1,
                            color: onSurface.withValues(alpha: 0.08),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                _liveEnabled
                                    ? Icons.sensors
                                    : Icons.sensors_off,
                                size: 19,
                                color: _liveEnabled
                                    ? RunNowSemanticColors.danger
                                    : onSurface.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'Live lên group',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (_liveEnabled || _showRunTogether)
                                      Text(
                                        [
                                          if (_liveEnabled)
                                            'Báo mỗi ${_effectiveMilestoneKm}km'
                                                '${_livePhotoEnabled ? ' · kèm ảnh' : ''}',
                                          if (_showRunTogether)
                                            'Chạy cùng: '
                                                '${_joinPolicy.label.toLowerCase()}',
                                        ].join(' · '),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: onSurface.withValues(
                                            alpha: 0.55,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Nút cài đặt: chỉ hiện khi có gì để chỉnh.
                              if (_liveEnabled || _canHostRunTogether)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.tune_rounded, size: 20),
                                  tooltip: 'Cài đặt Live',
                                  onPressed: _openLiveSettings,
                                ),
                              Switch(
                                value: _liveEnabled,
                                onChanged: (value) =>
                                    setState(() => _liveEnabled = value),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Chọn môn — chỉ trước khi bắt đầu (chưa có phiên). Khi đã ghi
                  // thì môn đã chốt, không đổi giữa chừng.
                  if (!_running && !_paused && !_finished && !_hasSession) ...[
                    const SizedBox(height: 10),
                    _SportPicker(
                      selected: _selectedKind,
                      onChanged: (kind) {
                        setState(() {
                          _selectedKind = kind;
                          // Đạp/xe máy: Live mặc định TẮT. Chạy: bật lại nếu công
                          // khai (đúng mặc định của chạy bộ).
                          _liveEnabled =
                              kind == ActivityKind.run ? isPublic : false;
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  _Controls(
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
                ],
              ),
            ),
          ),
        ],
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
        _roomId = draft.roomId ?? widget.roomId;
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
      _message = null;
      _settingsAction = null;
    });
    try {
      final ready = await _ensureLocationReady();
      if (!ready) {
        return;
      }
      final anchor = await _waitForStableGps();
      if (anchor == null) return;
      if (!mounted) return;
      // Sẵn sàng rồi: nút đổi thành START + map đã hiện vị trí — không cần báo
      // chữ "GPS READY" gây rối.
      setState(() => _gpsReadyAnchor = anchor);
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
      var config =
          ref.read(trackingConfigProvider).value ?? const TrackingConfig();
      // Đạp/xe máy đi nhanh hơn ngưỡng chống-nhảy-GPS của chạy (36km/h) → nâng
      // ngưỡng theo môn, không thì điểm thật bị cắt, quãng đường hụt.
      final maxSpeed = _maxSpeedOverrideFor(_selectedKind);
      if (maxSpeed != null) {
        config = config.copyWith(maxRunningSpeedMetersPerSecond: maxSpeed);
      }
      final session = TrackingSession(
        id: 'runnow-${now.toUtc().millisecondsSinceEpoch}',
        // Cấu hình từ DB (appConfig/tracking) — giãn mẫu chống zigzag GPS. Chưa
        // tải kịp thì dùng mặc định (đã có minSampleIntervalSeconds=15).
        config: config,
      )..start(now);
      _resetTrackChunkState();
      setState(() {
        _session = session;
        _snapshot = session.snapshot();
        _gpsReadyAnchor = null;
      });
      await _startRunningLocationStream();
      _startTicker();
      _setWakelock(true);
      unawaited(_persistDraft());
      unawaited(_publishLiveSnapshot(force: true));
      unawaited(_openSoloRoom(session.id));
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
      // Review trước khi giữ: xấu thì bỏ luôn — không lưu vào buổi, không đăng
      // group. Chỉ khi bấm "giữ" ảnh mới được neo + upload (+ share nếu Live).
      final keep = await _reviewPhoto(path);
      if (!keep) {
        await ref.read(trackingPhotoCaptureProvider).deleteLocal(path);
        if (mounted) setState(() => _message = 'Đã bỏ ảnh vừa chụp.');
        return;
      }
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

  /// Xem lại ảnh vừa chụp trước khi giữ. Trả true = giữ (lưu vào buổi, + đăng
  /// group nếu Live), false = bỏ hẳn.
  Future<bool> _reviewPhoto(String path) async {
    final willPost = _liveEnabled && _livePhotoEnabled;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ảnh giữ ĐÚNG tỉ lệ (contain) trên nền tối — không bóp méo, gọn.
            ColoredBox(
              color: Colors.black,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: Center(
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                    width: double.infinity,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    willPost ? 'Đăng ảnh này lên group?' : 'Dùng ảnh này?',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (willPost) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(
                          Icons.sensors,
                          size: 16,
                          color: RunNowSemanticColors.danger,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Live đang bật — ảnh sẽ lên group ngay.',
                            style: TextStyle(
                              fontSize: 12,
                              color: onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Bỏ'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => Navigator.pop(context, true),
                          icon: Icon(
                            willPost ? Icons.send_rounded : Icons.check_rounded,
                            size: 18,
                          ),
                          label: Text(willPost ? 'Đăng' : 'Lưu'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return confirmed == true;
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
      if (_liveEnabled && _livePhotoEnabled) {
        // Live + cho đăng ảnh → khoe tấm vừa chụp lên group. Fire-and-forget.
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
      unawaited(_endOwnSoloRoom());
      final photosUploaded = await _uploadPendingPhotos();
      final finalSnapshot = session.snapshot();
      final detail = finalSnapshot.toActivityDetail(
        name: _activityNameFor(_selectedKind),
        kind: _selectedKind,
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
    unawaited(_endOwnSoloRoom());
    await ref.read(trackingDraftStoreProvider).clear();
    for (final photo in localPhotos) {
      await ref.read(trackingPhotoCaptureProvider).deleteLocal(photo.localPath);
    }
    await _resetSession(message: 'Đã bỏ phiên tracking.');
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
      _lastLivePublishedAt = null;
      _lastLivePublishedDistanceMeters = 0;
      _contractId = widget.contractId;
      _roomId = widget.roomId;
      _roomPrivacy = null;
      _roomKind = null;
      _roomHostUid = null;
      _message = message;
    });
  }

  /// Mở phòng solo cho buổi chạy riêng vừa bắt đầu để người trong club xin
  /// chạy cùng. Không chặn việc ghi buổi chạy: lỗi chỉ báo snackbar.
  Future<void> _openSoloRoom(String sessionId) async {
    final privacy = _joinPolicy.roomPrivacy;
    final uid = ref.read(firebaseUserProvider).value?.uid;
    final isPublic =
        ref.read(userProfileProvider).value?.visibility ==
        ProfileVisibility.public;
    // Hồ sơ riêng tư thì club không thấy buổi live, chẳng ai xin chạy cùng.
    if (privacy == null || uid == null || !isPublic || !_canHostRunTogether) {
      return;
    }
    final api = ref.read(runNowApiClientProvider);
    final String roomId;
    try {
      roomId = await api.createRunRoom(
        privacy: privacy.value,
        maxRunners: runRoomMaxRunners,
        kind: RunRoomKind.solo.name,
      );
    } catch (error) {
      debugPrint('mở phòng chạy cùng: $error');
      _showSnack('Chưa mở được chạy cùng: ${runRoomErrorText(error)}');
      return;
    }
    // Buổi chạy đã xong hay bị bỏ trong lúc chờ: không ai còn chủ phòng này.
    if (!mounted || _session?.id != sessionId || _finished) {
      unawaited(_endRoom(api, roomId));
      return;
    }
    setState(() {
      _roomId = roomId;
      _roomPrivacy = privacy;
      _roomKind = RunRoomKind.solo;
      _roomHostUid = uid;
    });
    unawaited(_persistDraft());
  }

  /// Đóng phòng solo mình mở cho buổi này, để người chạy cùng thấy buổi đã
  /// xong thay vì phòng nằm mở tới hạn.
  Future<void> _endOwnSoloRoom() async {
    final roomId = _roomId;
    final uid = ref.read(firebaseUserProvider).value?.uid;
    if (roomId == null ||
        _roomKind != RunRoomKind.solo ||
        uid == null ||
        _roomHostUid != uid) {
      return;
    }
    await _endRoom(ref.read(runNowApiClientProvider), roomId);
  }

  Future<void> _endRoom(RunNowApiClient api, String roomId) async {
    try {
      await api.endRunRoom(roomId);
    } catch (error) {
      debugPrint('đóng phòng chạy cùng $roomId: $error');
      _showSnack('Chưa đóng được phòng chạy cùng: ${runRoomErrorText(error)}');
    }
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(text)),
      );
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
              roomId: _roomId,
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
    setState(() => _snapshot = snapshot);
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
            // Chỉ gắn phòng khi đã vào: rules từ chối roomId của người ngoài
            // phòng, gắn bừa thì mất luôn buổi live.
            roomId: _roomJoined ? _roomId : null,
            roomOnly: _roomOnly,
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

  /// Điểm để vẽ map trong cockpit: ưu tiên route đang chạy; chưa có thì lấy
  /// anchor GPS vừa khoá (1 điểm) để map center chỗ đó ngay khi vào màn.
  List<RoutePoint> _liveMapPoints(TrackingSessionSnapshot? snapshot) {
    final route = snapshot?.routePoints ?? const <RoutePoint>[];
    if (route.isNotEmpty) return route;
    final here = _gpsReadyAnchor ?? _lastGpsSample;
    if (here != null) {
      return [
        RoutePoint(
          latitude: here.latitude,
          longitude: here.longitude,
          timestamp: DateTime.now(),
        ),
      ];
    }
    return const <RoutePoint>[];
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
    final milestoneKm = _milestoneReachedKm(distance);
    if (milestoneKm > _liveAnnouncedKm) {
      _liveAnnouncedKm = milestoneKm;
      _liveAnnounceQueue = _liveAnnounceQueue
          .then(
            (_) => _announceLive(session, 'milestone', milestoneKm: milestoneKm),
          )
          .catchError((_) {});
    }
  }

  /// Mốc km đã đạt để thông báo, theo bước _liveMilestoneKm user chọn (vd mỗi
  /// 2km → 2,4,6…). Đã có tin start riêng ở 300m + tin finish lúc Stop.
  int _milestoneReachedKm(double distanceMeters) {
    final step = _effectiveMilestoneKm;
    return (distanceMeters / 1000 / step).floor() * step;
  }

  /// Sheet cài đặt Live: bật/tắt Live + (khi bật) chọn mốc km báo + có đăng ảnh
  /// không. update() ghi cả state màn (để logic + card đổi) lẫn state sheet.
  void _openLiveSettings() {
    // Theo đúng style sheet nhà: nền trong suốt + GlassPanel(22), tiêu đề section
    // UPPERCASE nhỏ, chọn bằng SegmentedButton (xem settings_screen).
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) {
          void update(VoidCallback fn) {
            setState(fn);
            setSheet(() {});
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              14,
              0,
              14,
              MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: GlassPanel(
              borderRadius: 22,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_canHostRunTogether) ...[
                    const Text(
                      'CHẠY CÙNG',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Phòng mở lúc bấm Bắt đầu với quyền vào đã chọn; đang chạy
                    // thì giữ nguyên tới hết buổi.
                    if (!_hasSession)
                      SegmentedButton<LiveJoinPolicy>(
                        showSelectedIcon: false,
                        segments: [
                          for (final policy in LiveJoinPolicy.values)
                            ButtonSegment(
                              value: policy,
                              label: Text(policy.label),
                            ),
                        ],
                        selected: {_joinPolicy},
                        onSelectionChanged: (s) =>
                            update(() => _joinPolicy = s.first),
                      )
                    else
                      Text(
                        _roomKind == RunRoomKind.solo
                            ? 'Đang nhận người chạy cùng · '
                                  '${_joinPolicy.label.toLowerCase()}'
                            : 'Buổi này không nhận người chạy cùng',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Bạn bè trong club thấy bạn ở trang Live và xin chạy cùng.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  const Text(
                    'CÀI ĐẶT LIVE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.4,
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _liveEnabled,
                    onChanged: (v) => update(() => _liveEnabled = v),
                    title: const Text('Live lên group'),
                    subtitle: const Text(
                      'Bot tự báo mốc km lên group khi bạn chạy',
                    ),
                  ),
                  if (_liveEnabled) ...[
                    const SizedBox(height: 6),
                    const Text(
                      'BÁO MỖI MỐC',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Chạy/đi bộ: user chọn mốc. Đạp/xe máy: mốc CỐ ĐỊNH (10/20km)
                    // vì quãng đường dài, mốc nhỏ sẽ spam group.
                    if (_selectedKind == ActivityKind.run ||
                        _selectedKind == ActivityKind.walk)
                      SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: [
                          for (final km in _liveMilestoneOptions)
                            ButtonSegment(value: km, label: Text('${km}km')),
                        ],
                        selected: {_liveMilestoneKm},
                        onSelectionChanged: (s) =>
                            update(() => _liveMilestoneKm = s.first),
                      )
                    else
                      Text(
                        'Cố định mỗi ${_effectiveMilestoneKm}km',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _livePhotoEnabled,
                      onChanged: (v) => update(() => _livePhotoEnabled = v),
                      title: const Text('Đăng ảnh lên group'),
                      subtitle: const Text(
                        'Ảnh bạn chụp lúc chạy sẽ được đăng vào group',
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
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
        _message = null;
      });
      // Báo 1 lần rồi tự tắt, không để dính panel liên tục. Trạng thái GPS yếu
      // vẫn hiện ở chỉ báo tín hiệu trên header.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
            content: Text(
              'GPS chưa ổn định. Đứng yên nơi thoáng hơn rồi bấm LOCK GPS lại.',
            ),
          ),
        );
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
            final hasEnoughSamples = window.length >= _gpsWarmupWindowSamples;
            final hasEnoughGoodSamples =
                goodSamples >= _gpsWarmupMinGoodSamples;
            final hasAcceptableDrift =
                windowDriftMeters <= _gpsWarmupMaxWindowDriftMeters;
            final ready =
                hasEnoughSamples && hasEnoughGoodSamples && hasAcceptableDrift;
            if (mounted) {
              setState(() {
                _lastGpsSample = position;
                // Không hiện chuỗi kỹ thuật lúc dò; map đã có "Đang lấy vị trí".
                _message = null;
              });
            }
            if (ready) {
              complete(position);
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
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
    return true;
  }

}

/// Chọn môn trước khi bắt đầu: Đi bộ / Chạy bộ / Đạp xe. Đi bộ chung BXH với
/// chạy; đạp xe có BXH riêng. Chỉ chạy bộ cộng vào km chạy của kèo.
class _SportPicker extends StatelessWidget {
  const _SportPicker({required this.selected, required this.onChanged});

  final ActivityKind selected;
  final ValueChanged<ActivityKind> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onAccent = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;

    Widget seg(ActivityKind kind, IconData icon, String label) {
      final on = selected == kind;
      return Expanded(
        child: GestureDetector(
          onTap: on ? null : () => onChanged(kind),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: on ? palette.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: on ? onAccent : onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: on ? onAccent : onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          seg(ActivityKind.walk, Icons.directions_walk_rounded, 'Đi bộ'),
          seg(ActivityKind.run, Icons.directions_run_rounded, 'Chạy bộ'),
          seg(ActivityKind.ride, Icons.directions_bike_rounded, 'Đạp xe'),
        ],
      ),
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

/// Rủ chạy cùng trước khi bắt đầu: có người đang live thì hiện số người, chạm
/// vào trang Live để xin chạy cùng.
class _LiveNearbyPill extends ConsumerWidget {
  const _LiveNearbyPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final board = ref.watch(liveBoardProvider).value;
    final count = board == null
        ? 0
        : board.liveRooms.length + board.solos.length;
    if (count == 0) return const SizedBox.shrink();
    final palette = context.runNowPalette;
    return Material(
      color: palette.ink,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () => context.push('/live'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            '$count đang Live · chạy cùng?',
            style: TextStyle(
              color: palette.accent,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
