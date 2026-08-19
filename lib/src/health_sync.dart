import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';

import 'runnow_api_client.dart';

/// Đồng bộ buổi CHẠY từ Apple Health (HealthKit) — chỉ iOS.
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

  // Loại dữ liệu Health cần ĐỌC: buổi tập (km chạy), số bước, và quãng đường
  // đi bộ+chạy (chỉ hiển thị kèm bước, KHÔNG tính vào km chạy). Dùng chung cho
  // connect() lẫn _reauthorize() để danh sách không lệch nhau.
  static const _readTypes = <HealthDataType>[
    HealthDataType.WORKOUT,
    HealthDataType.STEPS,
    HealthDataType.DISTANCE_WALKING_RUNNING,
  ];
  static const _readAccess = <HealthDataAccess>[
    HealthDataAccess.READ,
    HealthDataAccess.READ,
    HealthDataAccess.READ,
  ];

  bool _connected = false;
  bool _busy = false;
  String? _error;
  bool _loaded = false;
  // Sync nền đã tự bung popup xin-quyền trong phiên này chưa (tránh dội hộp thoại
  // mỗi lần app resume nếu user cứ gạt bỏ). Reset khi đã đọc được lại.
  bool _autoReauthTried = false;

  /// HealthKit chỉ có trên iOS.
  bool get available => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
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
      final granted = await _health.requestAuthorization(
        _readTypes,
        permissions: _readAccess,
      );
      if (!granted) {
        _error = 'Bạn chưa cấp quyền đọc Sức khoẻ cho 3i Run.';
      } else {
        _connected = true;
        await _store.write(key: _kConnected, value: '1');
        await _store.write(key: _kPermVersion, value: _permVersion);
        // Kết nối = kéo TOÀN BỘ 90 ngày (bỏ mốc sync cũ còn sót — vd cài lại app
        // nhưng Keychain vẫn giữ lastSync → nếu không sẽ chỉ kéo 1 ngày).
        final found = await _syncInternal(full: true);
        // iOS trả "granted" kể cả khi user TỪ CHỐI đọc → đọc ra 0 buổi. Gợi ý
        // kiểm tra quyền thay vì để user tưởng đã kết nối mà chẳng có gì.
        if (found == 0) {
          _error =
              'Chưa thấy buổi chạy nào trong Sức khoẻ. Nếu bạn có chạy (Apple '
              'Watch/app khác), vào Cài đặt iOS > Sức khoẻ > Truy cập & Thiết bị '
              '> 3i Run và bật quyền đọc "Workouts".';
        }
      }
    } catch (e) {
      _error = _isAuthError(e)
          ? _authHint
          : 'Không kết nối được Apple Health: $e';
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

  /// Gợi ý khi quyền HealthKit chưa/không được cấp (không tự sửa bằng code được).
  static const _authHint =
      'Apple Health chưa cấp quyền đọc cho 3i Run. Mở Cài đặt iOS > Sức khoẻ > '
      'Truy cập & Thiết bị > 3i Run rồi bật quyền đọc "Bước" và "Workouts", sau '
      'đó bấm Đồng bộ lại.';

  /// Lỗi HealthKit kiểu "Authorization not determined" — quyền đọc chưa được xác
  /// định (hay gặp khi cài lại app: Keychain giữ cờ đã-kết-nối nhưng iOS đã reset
  /// quyền) hoặc user từng từ chối (iOS vẫn trả granted=true cho READ).
  bool _isAuthError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('not determined') || s.contains('authorization');
  }

  /// Xin lại quyền đọc HealthKit. Trên iOS: đã cấp → trả true NGAY, không hiện
  /// hộp thoại; chưa xác định (notDetermined) → hiện hộp thoại để user cấp; đã
  /// từ chối trước đó → trả về ngay, không hiện lại. Nhờ vậy gọi được cả lúc sync
  /// nền mà không nhây (xem guard _autoReauthTried ở [sync]).
  Future<bool> _reauthorize() async {
    try {
      await _health.configure();
      return await _health.requestAuthorization(
        _readTypes,
        permissions: _readAccess,
      );
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
        _error = 'Đồng bộ Apple Health lỗi: $e';
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

    final workouts = <Map<String, dynamic>>[];
    for (final p in points) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      if (v.workoutActivityType != HealthWorkoutActivityType.RUNNING) continue;
      // totalDistance của WORKOUT do plugin trả về theo MÉT.
      final dist = (v.totalDistance ?? 0).toDouble();
      if (dist <= 0) continue;
      final moving = p.dateTo.difference(p.dateFrom).inSeconds;
      if (moving <= 0) continue;
      workouts.add({
        'sourceId': p.uuid,
        'startedAt': p.dateFrom.toUtc().toIso8601String(),
        'distanceMeters': dist,
        'movingTimeSeconds': moving,
      });
    }

    if (workouts.isNotEmpty) {
      // Gửi khoảng [from, now] để backend dọn buổi đã xoá trong Health — CHỈ khi
      // đọc trọn (≤500, không bị cap cắt) để không xoá nhầm.
      final canReconcile = workouts.length <= 500;
      await _api.importHealthWorkouts(
        workouts,
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
        days.add({
          'date': _dateKey(start),
          'steps': steps,
          'distanceMeters': meters,
        });
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
        types: [HealthDataType.DISTANCE_WALKING_RUNNING],
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
      types: [HealthDataType.DISTANCE_WALKING_RUNNING],
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
