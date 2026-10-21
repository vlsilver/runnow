import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';

import 'runnow_api_client.dart';

/// Đồng bộ buổi CHẠY từ kho sức khoẻ máy: iOS = Apple Health (HealthKit),
/// Android = Health Connect. Cùng một luồng đọc → đẩy backend (source khác nhau).
///
/// Khác Strava: "kết nối" ở đây là QUYỀN hệ điều hành (không OAuth/token/server).
/// Cờ đã-kết-nối lưu CỤC BỘ trên máy (HealthKit là dữ liệu thiết bị). Ngắt kết
/// nối = ngừng đồng bộ + xoá cờ (HealthKit không cho thu hồi quyền bằng code).
class HealthSyncController extends ChangeNotifier {
  HealthSyncController(this._api) {
    unawaited(load());
  }

  final RunNowApiClient _api;
  final Health _health = Health();
  final FlutterSecureStorage _store = const FlutterSecureStorage();

  static const _kConnected = 'apple_health_connected';
  static const _kLastSync = 'apple_health_last_sync';
  static const _kPermVersion = 'apple_health_perm_version';
  // Tăng mỗi khi THÊM loại quyền mới vào _readTypes → user đã kết nối được xin
  // lại quyền đúng 1 lần cho loại mới. v2: thêm DISTANCE_WALKING_RUNNING.
  static const _permVersion = '2';

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _isIOS => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Nguồn kho gửi cho backend: iOS=apple_health, Android=health_connect.
  String get _healthSource => _isAndroid ? 'health_connect' : 'apple_health';

  /// Quãng đường: iOS dùng DISTANCE_WALKING_RUNNING; Android (Health Connect) dùng
  /// DISTANCE_DELTA (DistanceRecord) — WORKOUT trên HC KHÔNG kèm quãng đường nên
  /// phải đọc record distance riêng rồi cộng vào từng buổi.
  HealthDataType get _distanceType => _isAndroid
      ? HealthDataType.DISTANCE_DELTA
      : HealthDataType.DISTANCE_WALKING_RUNNING;

  // Loại dữ liệu Health cần ĐỌC: buổi tập (km chạy), số bước, quãng đường. Getter
  // theo platform để iOS/Android không lệch type; dùng chung connect()/_reauthorize().
  List<HealthDataType> get _readTypes =>
      [HealthDataType.WORKOUT, HealthDataType.STEPS, _distanceType];
  List<HealthDataAccess> get _readAccess =>
      List<HealthDataAccess>.filled(_readTypes.length, HealthDataAccess.READ);

  bool _connected = false;
  bool _busy = false;
  String? _error;
  bool _loaded = false;
  // Sync nền đã tự bung popup xin-quyền trong phiên này chưa (tránh dội hộp thoại
  // mỗi lần app resume nếu user cứ gạt bỏ). Reset khi đã đọc được lại.
  bool _autoReauthTried = false;

  /// Kho sức khoẻ máy: iOS (Apple Health) hoặc Android (Health Connect). Riêng
  /// Android còn phải kiểm Health Connect đã cài chưa — làm trong connect().
  bool get available => _isIOS || _isAndroid;

  /// Tên kho để hiển thị trên UI (Settings…): iOS=Apple Health, Android=Health Connect.
  String get providerName => _isAndroid ? 'Health Connect' : 'Apple Health';
  bool get connected => _connected;
  bool get busy => _busy;
  String? get error => _error;

  /// Đọc cờ đã lưu; nếu đang kết nối thì đồng bộ nền các buổi mới.
  Future<void> load() async {
    if (_loaded || !available) return;
    _loaded = true;
    _connected = (await _store.read(key: _kConnected)) == '1';
    notifyListeners();
    // Auto-sync nền lúc mở app: KHÔNG hiện banner lỗi (đỡ dội lỗi vào mặt user
    // khi vừa mở app). Lỗi chỉ hiện khi user chủ động bấm Kết nối/Đồng bộ.
    if (_connected) unawaited(sync(silent: true));
  }

  /// Xin quyền đọc Workout từ Apple Health. Được cấp → bật đồng bộ + kéo lịch sử.
  Future<void> connect() async {
    if (!available || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _health.configure();
      // Android: Health Connect có thể CHƯA CÀI / cần cập nhật → đẩy user ra store
      // cài rồi thử lại (không có nó thì mọi thao tác đọc đều vô nghĩa).
      if (_isAndroid) {
        final status = await _health.getHealthConnectSdkStatus();
        if (status != HealthConnectSdkStatus.sdkAvailable) {
          _error =
              'Máy chưa có Health Connect (hoặc cần cập nhật). Cài/cập nhật Health '
              'Connect từ Google Play rồi bấm Kết nối lại.';
          try {
            await _health.installHealthConnect();
          } catch (_) {}
          return; // finally vẫn set _busy=false
        }
      }
      final granted = await _health.requestAuthorization(
        _readTypes,
        permissions: _readAccess,
      );
      // iOS: bool `granted` tin cậy. Android/Health Connect: KHÔNG cho kiểm tra
      // chắc chắn quyền READ (HC ẩn vì privacy) → `granted` có thể = false DÙ user
      // đã cấp (OS hiện "Allowed"). Nên KHÔNG chặn ở đây trên Android — để phần
      // THỬ ĐỌC bên dưới quyết định: đọc được = đã kết nối; chưa cấp thật thì
      // _syncInternal ném auth error → nhảy catch → gợi ý cấp quyền.
      if (!granted && !_isAndroid) {
        _error = 'Bạn chưa cấp quyền đọc Sức khoẻ cho 3i Run.';
      } else {
        // Android: Health Connect mặc định chỉ cho đọc 30 ngày gần nhất — xin thêm
        // quyền đọc LỊCH SỬ để backfill 90 ngày được (best-effort, hỏng thì bỏ qua).
        if (_isAndroid) {
          try {
            await _health.requestHealthDataHistoryAuthorization();
          } catch (_) {}
        }
        // Kết nối = kéo TOÀN BỘ 90 ngày (bỏ mốc sync cũ còn sót — vd cài lại app
        // nhưng Keychain vẫn giữ lastSync → nếu không sẽ chỉ kéo 1 ngày). ĐỌC TRƯỚC
        // khi bật cờ: chưa cấp quyền thật thì ném auth error ở đây → catch xử, KHÔNG
        // đánh dấu đã kết nối (tránh "connected nhưng đọc rỗng vì thiếu quyền").
        final found = await _syncInternal(full: true);
        _connected = true;
        await _store.write(key: _kConnected, value: '1');
        await _store.write(key: _kPermVersion, value: _permVersion);
        // Đọc được nhưng 0 buổi → đã kết nối, chỉ là chưa có dữ liệu. Gợi ý kiểm tra.
        if (found == 0) {
          _error = _isAndroid
              ? 'Chưa thấy buổi chạy nào trong Health Connect. Nếu bạn có chạy '
                    '(Garmin/COROS…), mở app đó bật đồng bộ sang Health Connect, hoặc '
                    'kiểm tra quyền đọc "Bài tập/Quãng đường" cho 3i Run rồi thử lại.'
              : 'Chưa thấy buổi chạy nào trong Sức khoẻ. Nếu bạn có chạy (Apple '
                    'Watch/app khác), vào Cài đặt iOS > Sức khoẻ > Truy cập & Thiết bị '
                    '> 3i Run và bật quyền đọc "Workouts".';
        }
      }
    } catch (e) {
      _error = _isAuthError(e)
          ? _authHint
          : 'Không kết nối được Sức khoẻ: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Ngừng đồng bộ (không xoá dữ liệu đã nhập; muốn thu hồi quyền hẳn thì vào
  /// Cài đặt iOS > Sức khoẻ). Chỉ đụng cờ cục bộ nên không được phép "báo lỗi" —
  /// xoá luôn cả thông báo lỗi cũ (vd lỗi sync trước đó).
  Future<void> disconnect() async {
    _connected = false;
    _error = null;
    try {
      await _store.delete(key: _kConnected);
      await _store.delete(key: _kLastSync);
    } catch (_) {
      // Cờ cục bộ; xoá keychain lỗi cũng coi như đã ngắt.
    }
    notifyListeners();
  }

  /// Gợi ý khi quyền kho sức khoẻ chưa/không được cấp (không tự sửa bằng code).
  String get _authHint => _isAndroid
      ? 'Health Connect chưa cấp quyền đọc cho 3i Run. Mở Health Connect > Quyền '
            'ứng dụng > 3i Run rồi bật đọc "Bài tập", "Bước", "Quãng đường", sau đó '
            'bấm Đồng bộ lại.'
      : 'Apple Health chưa cấp quyền đọc cho 3i Run. Mở Cài đặt iOS > Sức khoẻ > '
            'Truy cập & Thiết bị > 3i Run rồi bật quyền đọc "Bước" và "Workouts", '
            'sau đó bấm Đồng bộ lại.';

  /// Lỗi HealthKit kiểu "Authorization not determined" — quyền đọc chưa được xác
  /// định (hay gặp khi cài lại app: Keychain giữ cờ đã-kết-nối nhưng iOS đã reset
  /// quyền) hoặc user từng từ chối (iOS vẫn trả granted=true cho READ).
  bool _isAuthError(Object e) {
    final s = e.toString().toLowerCase();
    // iOS: "not determined"/"authorization". Android/Health Connect: đọc khi thiếu
    // quyền ném SecurityException / "permission denied".
    return s.contains('not determined') ||
        s.contains('authorization') ||
        s.contains('permission') ||
        s.contains('securityexception') ||
        s.contains('denied');
  }

  /// Xin lại quyền đọc HealthKit. Trên iOS: đã cấp → trả true NGAY, không hiện
  /// hộp thoại; chưa xác định (notDetermined) → hiện hộp thoại để user cấp; đã
  /// từ chối trước đó → trả về ngay, không hiện lại. Nhờ vậy gọi được cả lúc sync
  /// nền mà không nhây (xem guard _autoReauthTried ở [sync]).
  Future<bool> _reauthorize() async {
    try {
      await _health.configure();
      final ok = await _health.requestAuthorization(
        _readTypes,
        permissions: _readAccess,
      );
      // Android/Health Connect: bool không tin cậy cho quyền READ → luôn cho THỬ
      // đọc lại (true); lần _syncInternal kế mới thực sự quyết định. iOS tin bool.
      return _isAndroid ? true : ok;
    } catch (_) {
      return false;
    }
  }

  /// User đã kết nối từ trước nhưng app vừa THÊM loại quyền mới (vd DISTANCE) →
  /// xin lại quyền đúng 1 lần. iOS chỉ hiện hộp thoại nếu có loại chưa xác định;
  /// đã cấp đủ thì no-op. Gắn cờ version để không hỏi lại mỗi lần sync.
  Future<void> _ensureLatestPermissions() async {
    try {
      if (await _store.read(key: _kPermVersion) == _permVersion) return;
      await _health.requestAuthorization(_readTypes, permissions: _readAccess);
      await _store.write(key: _kPermVersion, value: _permVersion);
    } catch (_) {}
  }

  Future<void> sync({bool silent = false}) async {
    if (!available || !_connected || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _syncInternal();
    } catch (e) {
      if (_isAuthError(e)) {
        // Quyền chưa được cấp → CHỦ ĐỘNG xin lại quyền (kể cả lúc sync nền lúc mở
        // app). Nếu 'notDetermined' (hay gặp sau khi cài lại app) iOS sẽ HIỆN hộp
        // thoại cho user bật — đây là cách DUY NHẤT user biết cần cấp, không thể
        // bắt user tự mò bấm Đồng bộ. Không sợ nhây: iOS chỉ hiện hộp thoại khi
        // notDetermined; đã trả lời rồi thì requestAuthorization trả về ngay,
        // không hiện lại. Sync nền chỉ tự bung 1 lần/phiên (user chủ động bấm
        // Đồng bộ thì luôn thử) để phòng user gạt bỏ hộp thoại + app resume liên tục.
        var recovered = false;
        if (!silent || !_autoReauthTried) {
          if (silent) _autoReauthTried = true;
          if (await _reauthorize()) {
            try {
              await _syncInternal();
              recovered = true;
              _autoReauthTried =
                  false; // đọc được lại → cho phép tự bung sau này
            } catch (_) {
              // Vẫn hỏng sau khi xin lại = user từng từ chối (iOS không hiện lại).
            }
          }
        }
        // Chỉ hỏng thật (đã bung popup mà vẫn không đọc được) mới hướng dẫn vào
        // Cài đặt iOS — và chỉ khi user đang chủ động (không dội lỗi lúc mở app).
        if (!recovered && !silent) _error = _authHint;
      } else if (!silent) {
        _error = 'Đồng bộ Sức khoẻ lỗi: $e';
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Trả về số buổi ĐỌC ĐƯỢC từ Health trong lần này (để connect biết có dữ liệu
  /// không mà gợi ý kiểm tra quyền).
  Future<int> _syncInternal({bool full = false}) async {
    // Plugin PHẢI được configure trước mọi thao tác đọc. connect() có gọi, nhưng
    // load()/sync() lúc mở lại app thì chưa — thiếu là getHealthDataFromTypes
    // throw → banner lỗi. Gọi ở đây cho mọi đường (idempotent).
    await _health.configure();
    await _ensureLatestPermissions();
    final now = DateTime.now();
    final lastStr = full ? null : await _store.read(key: _kLastSync);
    // Lần đầu / full: lấy 90 ngày; sau đó từ mốc sync trước trừ 1 ngày (đề phòng lệch giờ).
    final from = lastStr != null
        ? (DateTime.tryParse(lastStr)?.subtract(const Duration(days: 1)) ??
              now.subtract(const Duration(days: 90)))
        : now.subtract(const Duration(days: 90));

    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WORKOUT],
      startTime: from,
      endTime: now,
    );
    // Android (Health Connect): WORKOUT KHÔNG kèm quãng đường (plugin trả null) →
    // đọc DISTANCE_DELTA cùng cửa sổ rồi cộng vào từng buổi theo thời gian. iOS đã
    // có totalDistance trong WORKOUT nên bỏ qua query này.
    final distancePoints = _isAndroid
        ? await _health.getHealthDataFromTypes(
            types: [HealthDataType.DISTANCE_DELTA],
            startTime: from,
            endTime: now,
          )
        : const <HealthDataPoint>[];

    final sessions = <_HealthWorkout>[];
    for (final p in points) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      final sport = _sportTypeFor(v.workoutActivityType);
      if (sport == null) continue; // loại không hỗ trợ → bỏ
      final moving = p.dateTo.difference(p.dateFrom).inSeconds;
      if (moving <= 0) continue;
      // iOS: totalDistance (MÉT) có sẵn. Android: cộng DISTANCE_DELTA rơi trong buổi.
      final dist = _isAndroid
          ? _sumDistanceInWindow(distancePoints, p.dateFrom, p.dateTo)
          : (v.totalDistance ?? 0).toDouble();
      // Gym KHÔNG có quãng đường (đo bằng thời lượng/calo) → chấp nhận dist=0.
      // Môn có quãng đường (chạy/đi/đạp/bơi) mà dist<=0 = thiếu dữ liệu → bỏ.
      if (dist <= 0 && sport != 'Gym') continue;
      final calories = (v.totalEnergyBurned ?? 0).toDouble();
      // uuid = metadata.id (thường có), nhưng plugin gán "" nếu native thiếu → id
      // TẤT ĐỊNH theo MỐC BẮT ĐẦU (giây) để idempotent giữa các lần sync (không mất
      // buổi, không nhân bản). KHÔNG kèm quãng đường: dist có thể đổi nhẹ khi delta
      // về trễ → id đổi → nhân bản. Start của buổi là bất biến. Không chứa "/ ".
      final sourceId = p.uuid.isNotEmpty
          ? p.uuid
          : 'gen-${p.dateFrom.toUtc().millisecondsSinceEpoch ~/ 1000}';
      sessions.add(
        _HealthWorkout(
          sourceId: sourceId,
          sportType: sport,
          start: p.dateFrom,
          end: p.dateTo,
          distanceMeters: dist,
          movingSeconds: moving,
          caloriesKcal: calories,
        ),
      );
    }

    // DEDUP tầng "trong-kho": HealthKit tự gộp iPhone+Watch, nhưng Health Connect
    // KHÔNG — nhiều app (Garmin + Google Fit…) cùng ghi 1 buổi → nhiều record chồng
    // thời gian. Gộp nhóm chồng nhau, giữ bản QUÃNG ĐƯỜNG DÀI NHẤT (giàu nhất).
    final deduped = _isAndroid ? _dedupOverlapping(sessions) : sessions;
    final workouts = [for (final s in deduped) s.toPayload()];

    if (workouts.isNotEmpty) {
      // Gửi khoảng [from, now] để backend dọn buổi đã xoá trong Health — CHỈ khi
      // đọc trọn (≤500, không bị cap cắt) để không xoá nhầm.
      final canReconcile = workouts.length <= 500;
      await _api.importHealthWorkouts(
        workouts,
        source: _healthSource,
        reconcileFrom: canReconcile ? from.toUtc().toIso8601String() : null,
        reconcileTo: canReconcile ? now.toUtc().toIso8601String() : null,
      );
    }
    // Số bước (bảng xếp hạng RIÊNG) — lỗi ở đây không được phá phần workout.
    try {
      await _syncSteps(full: full, now: now);
    } catch (_) {}
    await _store.write(key: _kLastSync, value: now.toUtc().toIso8601String());
    return workouts.length;
  }

  /// Map loại workout Health → sportType 3i. null = loại KHÔNG hỗ trợ (gym, bơi,
  /// yoga…) → bỏ qua. Run mới cộng km chạy/kèo; Walk/Hike/Ride chỉ HIỂN THỊ thành
  /// buổi riêng (backend + selectOfficialActivities lọc kind==run nên không lọt
  /// vào km chạy). Ride (đạp xe) sync để xem, chưa cộng leaderboard.
  String? _sportTypeFor(HealthWorkoutActivityType t) => switch (t) {
    HealthWorkoutActivityType.RUNNING ||
    HealthWorkoutActivityType.RUNNING_TREADMILL => 'Run',
    HealthWorkoutActivityType.WALKING => 'Walk',
    HealthWorkoutActivityType.HIKING => 'Hike',
    HealthWorkoutActivityType.BIKING ||
    HealthWorkoutActivityType.BIKING_STATIONARY => 'Ride',
    HealthWorkoutActivityType.SWIMMING ||
    HealthWorkoutActivityType.SWIMMING_POOL ||
    HealthWorkoutActivityType.SWIMMING_OPEN_WATER => 'Swim',
    // Gym: các buổi KHÔNG có quãng đường (đo bằng thời lượng/calo).
    HealthWorkoutActivityType.STRENGTH_TRAINING ||
    HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING ||
    HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING ||
    HealthWorkoutActivityType.HIGH_INTENSITY_INTERVAL_TRAINING ||
    HealthWorkoutActivityType.CROSS_TRAINING ||
    HealthWorkoutActivityType.CORE_TRAINING ||
    HealthWorkoutActivityType.WEIGHTLIFTING ||
    HealthWorkoutActivityType.YOGA ||
    HealthWorkoutActivityType.PILATES ||
    HealthWorkoutActivityType.GYMNASTICS => 'Gym',
    _ => null,
  };

  /// Cộng các mẩu DISTANCE_DELTA (mét) có thời điểm BẮT ĐẦU nằm trong [start,end)
  /// → tổng quãng đường 1 buổi (Health Connect tách distance khỏi WORKOUT). Dùng
  /// mốc bắt đầu để mỗi mẩu chỉ thuộc đúng 1 buổi, tránh đếm đôi khi 2 buổi kề.
  double _sumDistanceInWindow(
    List<HealthDataPoint> points,
    DateTime start,
    DateTime end,
  ) {
    var sum = 0.0;
    for (final p in points) {
      if (p.dateFrom.isBefore(start) || !p.dateFrom.isBefore(end)) continue;
      final v = p.value;
      if (v is NumericHealthValue) sum += v.numericValue.toDouble();
    }
    return sum;
  }

  /// Gộp các buổi CÙNG 1 LẦN CHẠY (nhiều app ghi vào Health Connect thành nhiều
  /// record chồng thời gian) thành 1 — giữ bản quãng đường DÀI NHẤT. So bằng TỶ LỆ
  /// CHỒNG với bản đại diện (>0.3, khớp overlapRatio backend) thay vì chồng-bất-kỳ,
  /// để KHÔNG gộp nhầm 2 buổi RIÊNG gần nhau bị 1 record rác bắc cầu.
  List<_HealthWorkout> _dedupOverlapping(List<_HealthWorkout> items) {
    if (items.length <= 1) return items;
    final sorted = [...items]..sort((a, b) => a.start.compareTo(b.start));
    final result = <_HealthWorkout>[];
    var best = sorted.first;
    for (var i = 1; i < sorted.length; i++) {
      final cur = sorted[i];
      if (_overlapRatio(cur, best) > 0.3) {
        if (cur.distanceMeters > best.distanceMeters) best = cur;
      } else {
        result.add(best);
        best = cur;
      }
    }
    result.add(best);
    return result;
  }

  /// Tỷ lệ chồng thời gian = (giao) / (buổi NGẮN hơn). 0 nếu không chồng.
  double _overlapRatio(_HealthWorkout a, _HealthWorkout b) {
    final start = a.start.isAfter(b.start) ? a.start : b.start;
    final end = a.end.isBefore(b.end) ? a.end : b.end;
    final overlap = end.difference(start).inSeconds;
    if (overlap <= 0) return 0;
    final da = a.end.difference(a.start).inSeconds;
    final db = b.end.difference(b.start).inSeconds;
    final minDur = da < db ? da : db;
    if (minDur <= 0) return 0;
    return overlap / minDur;
  }

  /// Đọc TỔNG số bước theo từng NGÀY (lịch máy) rồi đẩy lên. full = backfill 35
  /// ngày (đủ cho 7 ngày/tuần/tháng); thường chỉ hôm nay + hôm qua (bước hôm nay
  /// còn tăng, hôm qua đề phòng dữ liệu về trễ). HealthKit tự dedup iPhone+Watch.
  Future<void> _syncSteps({required bool full, required DateTime now}) async {
    final dayCount = full ? 35 : 2;
    final today = DateTime(now.year, now.month, now.day);
    final days = <Map<String, dynamic>>[];
    for (var i = 0; i < dayCount; i++) {
      final start = today.subtract(Duration(days: i));
      final end = i == 0 ? now : start.add(const Duration(days: 1));
      final total = await _health.getTotalStepsInInterval(start, end);
      // Quãng đường đi bộ+chạy của ngày (chỉ hiển thị kèm bước). Lỗi/thiếu quyền
      // distance → 0, không chặn phần bước.
      final meters = await _dayDistanceMeters(start, end);
      final steps = total ?? 0;
      if (steps > 0 || meters > 0) {
        final day = <String, dynamic>{
          'date': _dateKey(start),
          'steps': steps,
          'distanceMeters': meters,
        };
        // LƯU chi tiết theo giờ cho 14 ngày GẦN NHẤT (đủ cho phần lớn lượt xem;
        // giới hạn để full-sync không phải đọc 35×2 query hourly). Màn detail đọc
        // từ Firestore → xem được cả simulator/offline/user khác. Lỗi hourly KHÔNG
        // chặn phần ngày.
        if (i < 14) {
          try {
            final hSteps = await hourlySteps(start);
            if (hSteps.any((h) => h > 0)) day['hourlySteps'] = hSteps;
          } catch (_) {}
          try {
            final hDist = await hourlyDistance(start);
            if (hDist.any((d) => d > 0)) day['hourlyDistance'] = hDist;
          } catch (_) {}
        }
        days.add(day);
      }
    }
    if (days.isNotEmpty) await _api.importHealthSteps(days);
  }

  /// TỔNG quãng đường đi bộ+chạy (mét) của một ngày — dùng HKStatisticsCollection
  /// (interval query) nên đã dedup iPhone+Watch, khớp số Apple hiển thị.
  Future<double> _dayDistanceMeters(DateTime start, DateTime end) async {
    if (!end.isAfter(start)) return 0;
    try {
      final points = await _health.getHealthIntervalDataFromTypes(
        startDate: start,
        endDate: end,
        types: [_distanceType],
        interval: 86400, // 1 bucket/ngày → tổng ngày
      );
      return points.fold<double>(0, (a, p) => a + _numericValue(p));
    } catch (_) {
      return 0;
    }
  }

  double _numericValue(HealthDataPoint p) {
    final v = p.value;
    return v is NumericHealthValue ? v.numericValue.toDouble() : 0;
  }

  /// Số bước theo TỪNG GIỜ (24 phần tử, 0h→23h) của MỘT ngày. Dùng
  /// getHealthDataFromTypes (đọc mẫu thô) — hàm này ĐÃ chạy được trên máy (buổi
  /// chạy sync bằng chính nó), khác 2 cách trước (getTotalStepsInInterval bucket
  /// theo ngày; getHealthIntervalDataFromTypes) đều trả rỗng cho khoảng 1-giờ.
  /// Tự gom mẫu vào bucket theo giờ khởi phát. (Total ngày vẫn lấy số đã dedup ở
  /// Firestore, nên đây chỉ dùng cho HÌNH DẠNG phân bố.)
  Future<List<int>> hourlySteps(DateTime day) async {
    final buckets = List<int>.filled(24, 0);
    if (!available) return buckets;
    await _health.configure();
    final base = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    var end = base.add(const Duration(days: 1));
    if (end.isAfter(now)) end = now;
    if (!end.isAfter(base)) return buckets;
    final points = await _health.getHealthDataFromTypes(
      types: [HealthDataType.STEPS],
      startTime: base,
      endTime: end,
    );
    for (final p in points) {
      final h = p.dateFrom.toLocal().hour;
      if (h >= 0 && h < 24) buckets[h] += _numericValue(p).round();
    }
    return buckets;
  }

  /// Quãng đường đi bộ+chạy theo TỪNG GIỜ (24 phần tử, mét, 0h→23h) của một ngày
  /// — cho biểu đồ ở trang chi tiết. Cùng cách với [hourlySteps]
  /// (getHealthDataFromTypes + gom theo giờ) cho chắc chạy trên máy.
  Future<List<double>> hourlyDistance(DateTime day) async {
    final buckets = List<double>.filled(24, 0);
    if (!available) return buckets;
    await _health.configure();
    final base = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    var end = base.add(const Duration(days: 1));
    if (end.isAfter(now)) end = now;
    if (!end.isAfter(base)) return buckets;
    final points = await _health.getHealthDataFromTypes(
      types: [_distanceType],
      startTime: base,
      endTime: end,
    );
    for (final p in points) {
      final h = p.dateFrom.toLocal().hour;
      if (h >= 0 && h < 24) buckets[h] += _numericValue(p);
    }
    return buckets;
  }

  String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

/// Một buổi chạy đọc từ kho sức khoẻ (Apple Health / Health Connect), trước khi
/// gộp trùng + đẩy lên backend.
class _HealthWorkout {
  _HealthWorkout({
    required this.sourceId,
    required this.sportType,
    required this.start,
    required this.end,
    required this.distanceMeters,
    required this.movingSeconds,
    this.caloriesKcal = 0,
  });

  final String sourceId;
  final String sportType; // Run / Walk / Hike / Ride / Swim / Gym
  final DateTime start;
  final DateTime end;
  final double distanceMeters;
  final int movingSeconds;
  final double caloriesKcal; // calo tiêu hao (chủ yếu cho Gym/Swim, có thể 0)

  Map<String, dynamic> toPayload() => {
    'sourceId': sourceId,
    'sportType': sportType,
    'startedAt': start.toUtc().toIso8601String(),
    'distanceMeters': distanceMeters,
    'movingTimeSeconds': movingSeconds,
    if (caloriesKcal > 0) 'caloriesKcal': caloriesKcal,
  };
}
