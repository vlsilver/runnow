import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Nối Garmin Connect. Backend lo OAuth với Garmin rồi trả kết quả về cùng deep
/// link với Strava, kèm `garmin=connected` hoặc `garminError=<mã>`.
class GarminController extends ChangeNotifier {
  GarminController(this._auth, this._api, {AppLinks? appLinks})
    : _appLinks = kIsWeb ? null : appLinks ?? AppLinks() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _status = _disconnected;
        statusLoading = false;
        notifyListeners();
      } else {
        unawaited(refreshStatus());
      }
    });
    if (kIsWeb) {
      unawaited(handleOAuthCallback(Uri.base));
      return;
    }
    final links = _appLinks;
    if (links == null) return;
    _subscription = links.uriLinkStream.listen(handleOAuthCallback);
    links.getInitialLink().then((uri) {
      if (uri != null) handleOAuthCallback(uri);
    });
  }

  static const _disconnected = GarminConnectionStatus(
    available: false,
    connected: false,
    status: 'disconnected',
  );

  final FirebaseAuth _auth;
  final RunNowApiClient _api;
  final AppLinks? _appLinks;
  StreamSubscription<Uri>? _subscription;
  StreamSubscription<User?>? _authSubscription;
  GarminConnectionStatus _status = _disconnected;
  String? errorMessage;
  bool loading = false;
  bool statusLoading = true;
  bool get connected => _status.connected;
  DateTime? get lastPushAt => _status.lastPushAt;

  Future<void> refreshStatus() async {
    if (_auth.currentUser == null) return;
    statusLoading = true;
    notifyListeners();
    try {
      _status = await _api.getGarminStatus();
      errorMessage = null;
    } catch (error) {
      debugPrint('Không kiểm tra được trạng thái Garmin: $error');
      errorMessage = 'Chưa kiểm tra được kết nối Garmin. Thử lại sau.';
    } finally {
      statusLoading = false;
      notifyListeners();
    }
  }

  Future<void> connect() async {
    await _run(() async {
      final uri = await _api.createGarminAuthorization(
        returnTarget: kIsWeb ? 'web' : 'mobile',
      );
      final launched = kIsWeb
          ? await launchUrl(
              uri,
              mode: LaunchMode.platformDefault,
              webOnlyWindowName: '_self',
            )
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        throw StateError('Không thể mở trang Garmin Connect.');
      }
    });
  }

  Future<void> disconnect() async {
    await _run(() async {
      await _api.disconnectGarmin();
      _status = GarminConnectionStatus(
        available: _status.available,
        connected: false,
        status: 'disconnected',
      );
    });
  }

  Future<void> handleOAuthCallback(Uri uri) async {
    if (!isGarminCallback(uri, webBase: kIsWeb ? Uri.base : null)) return;
    final error = uri.queryParameters['garminError'];
    if (error != null) {
      debugPrint('Garmin OAuth trả về lỗi: $error');
      errorMessage = garminErrorMessage(error);
      notifyListeners();
      return;
    }
    await _run(() async {
      _status = await _api.getGarminStatus();
    });
  }

  Future<void> _run(Future<void> Function() operation) async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } on RunNowApiException catch (error) {
      debugPrint('Garmin lỗi [${error.code}]: ${error.message}');
      errorMessage = garminErrorMessage(error.code);
    } catch (error) {
      debugPrint('Garmin lỗi: $error');
      errorMessage = garminErrorMessage('');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _authSubscription?.cancel();
    super.dispose();
  }
}

/// Deep link backend trả về sau khi nối Garmin. Trên web là đúng trang đang mở
/// ([webBase]) có `garmin` hoặc `garminError`.
bool isGarminCallback(Uri uri, {Uri? webBase}) {
  final hasResult =
      uri.queryParameters.containsKey('garmin') ||
      uri.queryParameters.containsKey('garminError');
  if (!hasResult) return false;
  if (webBase != null) {
    return uri.scheme == webBase.scheme &&
        uri.host == webBase.host &&
        uri.port == webBase.port &&
        uri.path == AppConfig.stravaRedirectPath;
  }
  return uri.scheme == AppConfig.stravaRedirectScheme &&
      uri.host == AppConfig.stravaRedirectHost &&
      uri.path == AppConfig.stravaRedirectPath;
}

/// Câu báo cho user theo mã lỗi backend. null là không cần báo: user tự bấm
/// không cho phép trên trang Garmin.
String? garminErrorMessage(String code) => switch (code) {
  'garmin_authorization_denied' => null,
  'garmin_user_already_linked' =>
    'Tài khoản Garmin này đang nối với một tài khoản 3i khác. '
        'Ngắt ở tài khoản kia trước rồi nối lại.',
  'garmin_not_configured' => 'Kết nối Garmin đang tạm đóng.',
  _ => 'Kết nối Garmin chưa xong. Vui lòng thử lại.',
};
