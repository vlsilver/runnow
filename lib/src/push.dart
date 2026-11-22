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
  final gameId = data['gameId'];
  if (kind is String &&
      kind.startsWith('game_') &&
      gameId is String &&
      gameId.isNotEmpty) {
    return '/games/${Uri.encodeComponent(gameId)}';
  }
  final sessionId = data['sessionId'];
  if (kind == 'live_start' && sessionId is String && sessionId.isNotEmpty) {
    return '/live/${Uri.encodeComponent(sessionId)}';
  }
  // Quà BXH, top 3 và quà BXH đã trao đều mở thẻ hạng của bảng đó.
  final boardId = data['boardId'];
  if ((kind == 'rank_reward' || kind == 'rank_top' || kind == 'gift_given') &&
      boardId is String &&
      boardId.isNotEmpty) {
    return Uri(path: '/club', queryParameters: {'board': boardId}).toString();
  }
  final contractId = data['contractId'];
  if ((kind == 'contract_gift' || kind == 'gift_given') &&
      contractId is String &&
      contractId.isNotEmpty) {
    return '/contracts/${Uri.encodeComponent(contractId)}';
  }
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
/// app: hỏi lúc người dùng vào phòng chạy hay ván ([askAfterJoining]), khi họ hiểu
/// vì sao app cần báo. Lỗi đăng ký chỉ log: không có push thì app vẫn dùng
/// được, lần mở app hay vào phòng sau sẽ đăng ký lại.
class PushController {
  PushController(
    this._auth,
    this._api,
    this._messaging,
    this._platform, {
    this._tokenRetryDelay = const Duration(seconds: 2),
  }) {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _registered = null;
        return;
      }
      unawaited(_guard(refresh));
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
  final Duration _tokenRetryDelay;
  static const _tokenAttempts = 5;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _refreshSubscription;
  StreamSubscription<Map<String, dynamic>>? _tapSubscription;

  /// Token đã ghi lên backend cho người đang đăng nhập.
  String? _registered;

  /// Đọc lại quyền mà không hỏi, có quyền thì đăng ký token; trả quyền đọc được.
  /// Màn cài đặt thông báo gọi khi người dùng bật ở Cài đặt của máy rồi quay về.
  Future<PushPermission> refresh() async {
    final permission = await _messaging.permission();
    if (permission == PushPermission.granted) await _registerCurrent();
    return permission;
  }

  /// iOS chưa có APNs token thì chưa lấy được token FCM, và lần đó không báo lại
  /// nếu token FCM không đổi. Thử thêm vài lần, hết lượt thì chờ lần mở app sau.
  Future<void> _registerCurrent() async {
    for (var attempt = 1; attempt <= _tokenAttempts; attempt++) {
      if (_auth.currentUser == null) return;
      final token = await _messaging.token();
      if (token != null) return _register(token);
      if (attempt < _tokenAttempts) {
        await Future<void>.delayed(_tokenRetryDelay);
      }
    }
  }

  Future<void> _register(String token) async {
    if (token == _registered) return;
    await _api.registerPushToken(token, _platform);
    _registered = token;
  }

  /// Gọi sau khi người dùng tạo hay vào phòng chạy, ván. Chỉ hỏi quyền nếu chưa hỏi
  /// lần nào; đã từ chối thì thôi, hệ điều hành cũng không hiện hỏi lại.
  Future<void> askAfterJoining() => _guard(ask);

  /// Quyền thông báo hiện tại của máy.
  Future<PushPermission> permission() => _messaging.permission();

  /// Hỏi quyền nếu chưa hỏi lần nào, có quyền thì đăng ký token; trả quyền sau
  /// cùng. Màn cài đặt thông báo gọi thẳng để biết kết quả mà vẽ lại.
  Future<PushPermission> ask() async {
    var permission = await _messaging.permission();
    if (permission == PushPermission.notAsked) {
      permission = await _messaging.requestPermission();
    }
    if (permission == PushPermission.granted) await _registerCurrent();
    return permission;
  }

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
