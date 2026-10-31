import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Quyền thông báo của máy, gộp từ AuthorizationStatus.
enum PushPermission { notAsked, granted, denied }

/// Phần FCM app dùng; test thay bằng bản giả.
abstract class PushMessaging {
  Future<PushPermission> permission();
  Future<PushPermission> requestPermission();

  /// Token FCM của máy; null khi máy chưa có (iOS chưa nhận APNs token), lúc
  /// có thì token tới qua [tokenRefresh].
  Future<String?> token();
  Stream<String> get tokenRefresh;

  /// Data của thông báo người dùng chạm vào lúc app đã tắt hẳn.
  Future<Map<String, dynamic>?> launchTap();

  /// Data của thông báo người dùng chạm vào lúc app đang chạy nền.
  Stream<Map<String, dynamic>> get taps;
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging() {
    // iOS mặc định không hiện thông báo khi app đang mở; chủ phòng đang ở màn
    // khác vẫn cần thấy có người xin vào.
    unawaited(
      _fcm.setForegroundNotificationPresentationOptions(
        alert: true,
        sound: true,
      ),
    );
  }

  final _fcm = FirebaseMessaging.instance;

  static PushPermission _from(NotificationSettings settings) =>
      switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized ||
        AuthorizationStatus.provisional => PushPermission.granted,
        AuthorizationStatus.notDetermined => PushPermission.notAsked,
        _ => PushPermission.denied,
      };

  @override
  Future<PushPermission> permission() async =>
      _from(await _fcm.getNotificationSettings());

  @override
  Future<PushPermission> requestPermission() async =>
      _from(await _fcm.requestPermission());

  @override
  Future<String?> token() async {
    try {
      return await _fcm.getToken();
    } on FirebaseException catch (error) {
      if (error.code == 'apns-token-not-set') return null;
      rethrow;
    }
  }

  @override
  Stream<String> get tokenRefresh => _fcm.onTokenRefresh;

  @override
  Future<Map<String, dynamic>?> launchTap() async =>
      (await _fcm.getInitialMessage())?.data;

  @override
  Stream<Map<String, dynamic>> get taps =>
      FirebaseMessaging.onMessageOpenedApp.map((message) => message.data);
}

/// Màn cần mở khi chạm vào thông báo; null nếu thông báo không trỏ tới đâu.
String? pushLocation(Map<String, dynamic> data) {
  final kind = data['kind'];
  final roomId = data['roomId'];
  if (kind is String &&
      kind.startsWith('room_') &&
      roomId is String &&
      roomId.isNotEmpty) {
    return '/rooms/${Uri.encodeComponent(roomId)}';
  }
  return null;
}

/// Giữ token FCM của máy gắn với người đang đăng nhập. Không hỏi quyền lúc mở
/// app: hỏi lúc người dùng tạo hay vào phòng chạy ([askForRooms]), khi họ hiểu
/// vì sao app cần báo. Lỗi đăng ký chỉ log: không có push thì app vẫn dùng
/// được, lần mở app hay vào phòng sau sẽ đăng ký lại.
class PushController {
  PushController(this._auth, this._api, this._messaging, this._platform) {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _registered = null;
        return;
      }
      unawaited(_guard(_registerIfGranted));
    });
    _refreshSubscription = _messaging.tokenRefresh.listen((token) {
      if (_auth.currentUser == null) return;
      unawaited(_guard(() => _register(token)));
    });
  }

  final FirebaseAuth _auth;
  final RunNowApiClient _api;
  final PushMessaging _messaging;
  final String _platform;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<Map<String, dynamic>>? _tapSubscription;

  /// Token đã ghi lên backend cho người đang đăng nhập.
  String? _registered;

  Future<void> _registerIfGranted() async {
    if (await _messaging.permission() != PushPermission.granted) return;
    await _registerCurrent();
  }

  Future<void> _registerCurrent() async {
    final token = await _messaging.token();
    if (token != null) await _register(token);
  }

  Future<void> _register(String token) async {
    if (token == _registered) return;
    await _api.registerPushToken(token, _platform);
    _registered = token;
  }

  /// Gọi sau khi người dùng tạo hay vào phòng chạy. Chỉ hỏi quyền nếu chưa hỏi
  /// lần nào; đã từ chối thì thôi, hệ điều hành cũng không hiện hỏi lại.
  Future<void> askForRooms() => _guard(() async {
    var permission = await _messaging.permission();
    if (permission == PushPermission.notAsked) {
      permission = await _messaging.requestPermission();
    }
    if (permission == PushPermission.granted) await _registerCurrent();
  });

  /// Gỡ token trước khi đăng xuất, lúc còn ID token để gọi API. Gỡ hỏng thì
  /// máy này còn nhận push của người cũ tới khi có người đăng nhập lại.
  Future<void> beforeSignOut() async {
    final token = _registered;
    if (token == null) return;
    _registered = null;
    await _guard(() => _api.unregisterPushToken(token));
  }

  /// Chạm vào thông báo thì gọi [open] với màn cần mở. Gọi một lần.
  void handleTaps(void Function(String location) open) {
    if (_tapSubscription != null) return;
    void route(Map<String, dynamic>? data) {
      final location = data == null ? null : pushLocation(data);
      if (location != null) open(location);
    }

    _tapSubscription = _messaging.taps.listen(route);
    unawaited(_guard(() async => route(await _messaging.launchTap())));
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stack) {
      debugPrint('push: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 4);
    }
  }

  void dispose() {
    _authSubscription?.cancel();
    _refreshSubscription?.cancel();
    _tapSubscription?.cancel();
  }
}
