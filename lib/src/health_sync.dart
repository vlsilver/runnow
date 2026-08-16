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

  bool _connected = false;
  bool _busy = false;
  String? _error;
  bool _loaded = false;

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
    if (_connected) unawaited(sync());
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
        [HealthDataType.WORKOUT],
        permissions: [HealthDataAccess.READ],
      );
      if (!granted) {
        _error = 'Bạn chưa cấp quyền đọc Sức khoẻ cho 3i Run.';
      } else {
        _connected = true;
        await _store.write(key: _kConnected, value: '1');
        await _syncInternal();
      }
    } catch (e) {
      _error = 'Không kết nối được Apple Health: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Ngừng đồng bộ (không xoá dữ liệu đã nhập; muốn thu hồi quyền hẳn thì vào
  /// Cài đặt iOS > Sức khoẻ).
  Future<void> disconnect() async {
    _connected = false;
    await _store.delete(key: _kConnected);
    await _store.delete(key: _kLastSync);
    notifyListeners();
  }

  Future<void> sync() async {
    if (!available || !_connected || _busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await _syncInternal();
    } catch (e) {
      _error = 'Đồng bộ Apple Health lỗi: $e';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _syncInternal() async {
    final now = DateTime.now();
    final lastStr = await _store.read(key: _kLastSync);
    // Lần đầu lấy 90 ngày; sau đó từ mốc sync trước trừ 1 ngày (đề phòng lệch giờ).
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
      await _api.importHealthWorkouts(workouts);
    }
    await _store.write(key: _kLastSync, value: now.toUtc().toIso8601String());
  }
}
