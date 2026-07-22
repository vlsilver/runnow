import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

/// Quản lý đăng nhập Google + Apple. Bắt buộc phải có Sign in with Apple vì
/// App Store Guideline 4.8: app chỉ dùng đăng nhập bên thứ ba (Google) làm
/// cách đăng nhập duy nhất sẽ bị từ chối.
class AuthController extends ChangeNotifier {
  AuthController(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  bool loading = false;
  String? errorMessage;

  /// Chỉ hiện nút Sign in with Apple trên nền Apple, nơi hệ điều hành có sẵn
  /// hộp thoại đăng nhập. Web và Android cần thêm Service ID + redirect
  /// riêng bên Apple Developer — chưa cấu hình mà vẫn hiện nút thì bấm vào
  /// chỉ báo lỗi. Guideline 4.8 cũng chỉ áp cho App Store.
  static bool get appleSignInAvailable =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> signIn() async {
    await _run(() async {
      if (kIsWeb) {
        // Web: Firebase popup qua auth handler (firebaseapp.com). Chỉ cần
        // localhost nằm trong Firebase Authorized domains — KHÔNG cần cấu hình
        // JavaScript origins ở Google Cloud.
        final result = await _auth.signInWithPopup(GoogleAuthProvider());
        final user = result.user;
        if (user == null) throw StateError('Không thể đăng nhập Google.');
        await _upsertProfile(
          user: user,
          displayName: user.displayName,
          avatarUrl: user.photoURL,
          email: user.email,
        );
      } else {
        final account = await GoogleSignIn.instance.authenticate();
        await _handleAccount(account);
      }
    });
  }

  Future<void> signInWithApple() async {
    await _run(() async {
      final provider = AppleAuthProvider()
        ..addScope('email')
        ..addScope('name');
      final result = kIsWeb
          ? await _auth.signInWithPopup(provider)
          : await _auth.signInWithProvider(provider);
      final user = result.user;
      if (user == null) throw StateError('Không thể đăng nhập Apple.');
      // Apple chỉ trả tên đúng 1 lần ở lần cấp quyền đầu tiên, những lần sau
      // displayName sẽ null — lúc đó giữ nguyên tên đã lưu trong Firestore
      // thay vì ghi đè (xem `_upsertProfile`). Người dùng chọn "Ẩn email"
      // thì email là địa chỉ privaterelay.appleid.com của Apple.
      await _upsertProfile(
        user: user,
        displayName: user.displayName,
        avatarUrl: user.photoURL,
        email: user.email,
      );
    });
  }

  Future<void> _handleAccount(GoogleSignInAccount account) async {
    final authentication = account.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: authentication.idToken,
    );
    final result = await _auth.signInWithCredential(credential);
    final user = result.user;
    if (user == null) throw StateError('Không thể đăng nhập Google.');
    await _upsertProfile(
      user: user,
      displayName: user.displayName ?? account.displayName,
      avatarUrl: user.photoURL ?? account.photoUrl,
      email: user.email ?? account.email,
    );
  }

  Future<void> _upsertProfile({
    required User user,
    String? displayName,
    String? avatarUrl,
    String? email,
  }) async {
    final effectiveName = displayName ?? '3i member';
    await _firestore.runTransaction((transaction) async {
      final userRef = _firestore.collection('users').doc(user.uid);
      final publicRef = _firestore.collection('publicProfiles').doc(user.uid);
      final snapshot = await transaction.get(userRef);
      final data = snapshot.data() ?? const <String, dynamic>{};
      final nickname = (data['nickname'] as String?)?.trim().isNotEmpty == true
          ? (data['nickname'] as String).trim()
          : effectiveName;
      final visibility = data['profileVisibility'] as String? ?? 'private';
      final String? effectiveAvatar = data['avatarUrl'] as String? ?? avatarUrl;
      final stravaConnected = data['stravaConnected'] as bool? ?? false;
      final userUpdate = <String, dynamic>{
        'displayName': nickname,
        'email': email,
        'nickname': nickname,
        'profileVisibility': visibility,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (effectiveAvatar != null) userUpdate['avatarUrl'] = effectiveAvatar;
      if (!snapshot.exists) {
        userUpdate['createdAt'] = FieldValue.serverTimestamp();
      }
      final publicUpdate = <String, dynamic>{
        'uid': user.uid,
        'displayName': nickname,
        'nickname': nickname,
        'profileVisibility': visibility,
        'stravaConnected': stravaConnected,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (effectiveAvatar != null) {
        publicUpdate['avatarUrl'] = effectiveAvatar;
      }
      if (!snapshot.exists) {
        publicUpdate['createdAt'] = FieldValue.serverTimestamp();
      }
      transaction.set(userRef, userUpdate, SetOptions(merge: true));
      transaction.set(publicRef, publicUpdate, SetOptions(merge: true));
    });
  }

  Future<void> signOut() async {
    await _run(() async {
      try {
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Tài khoản đăng nhập bằng Apple chưa từng qua Google Sign-In —
        // bỏ qua, việc signOut Firebase bên dưới mới là phần bắt buộc.
      }
      await _auth.signOut();
      await _clearFirestoreCache();
    });
  }

  Future<void> _clearFirestoreCache() async {
    try {
      await _firestore.terminate();
      await _firestore.clearPersistence();
    } catch (_) {
      // Best-effort cleanup — logout vẫn tiếp tục dù xoá cache thất bại.
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } on FirebaseAuthException catch (error, stack) {
      // Chi tiết kỹ thuật chỉ đi vào log cho dev — người dùng nhận câu tiếng
      // Việt nói được họ nên làm gì tiếp theo.
      debugPrint('Đăng nhập lỗi [${error.code}]: ${error.message}');
      debugPrintStack(stackTrace: stack, maxFrames: 6);
      errorMessage = _friendlyAuthMessage(error);
    } catch (error, stack) {
      debugPrint('Đăng nhập lỗi ngoài Firebase: $error');
      debugPrintStack(stackTrace: stack, maxFrames: 6);
      errorMessage = 'Đăng nhập không thành công. Vui lòng thử lại.';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// Đổi mã lỗi Firebase sang câu người dùng hiểu được. Trả về null nghĩa là
  /// không hiện gì — dùng cho trường hợp chính người dùng bấm huỷ.
  String? _friendlyAuthMessage(FirebaseAuthException error) {
    return switch (error.code) {
      // Người dùng tự đóng hộp thoại — không phải lỗi.
      'canceled' ||
      'web-context-canceled' ||
      'popup-closed-by-user' ||
      'cancelled-popup-request' => null,

      'network-request-failed' =>
        'Không có kết nối mạng. Kiểm tra Wi-Fi hoặc 4G rồi thử lại.',

      'account-exists-with-different-credential' ||
      'credential-already-in-use' =>
        'Email này đã được đăng nhập bằng cách khác. '
            'Hãy thử nút đăng nhập còn lại.',

      'user-disabled' =>
        'Tài khoản này đã bị khoá. Liên hệ ban quản trị club để được mở lại.',

      'too-many-requests' =>
        'Bạn thử quá nhiều lần. Đợi vài phút rồi đăng nhập lại.',

      // Provider chưa bật trong Firebase Console — lỗi cấu hình phía mình,
      // không phải lỗi người dùng, nên đừng bảo họ "thử lại".
      'operation-not-allowed' =>
        'Cách đăng nhập này đang tạm ngưng. Vui lòng dùng cách khác.',

      _ => 'Đăng nhập không thành công. Vui lòng thử lại.',
    };
  }
}

class StravaAuthController extends ChangeNotifier {
  StravaAuthController(this._auth, this._api, {AppLinks? appLinks})
    : _appLinks = kIsWeb ? null : appLinks ?? AppLinks() {
    _authSubscription = _auth.authStateChanges().listen((user) {
      if (user == null) {
        _status = const StravaConnectionStatus(
          connected: false,
          status: 'disconnected',
        );
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

  final FirebaseAuth _auth;
  final RunNowApiClient _api;
  final AppLinks? _appLinks;
  StreamSubscription<Uri>? _subscription;
  StreamSubscription<User?>? _authSubscription;
  StravaConnectionStatus _status = const StravaConnectionStatus(
    connected: false,
    status: 'unknown',
  );
  String? errorMessage;
  bool loading = false;
  bool statusLoading = true;
  bool get connected => _status.connected;
  String get connectionStatus => _status.status;

  Future<void> refreshStatus() async {
    if (_auth.currentUser == null) return;
    statusLoading = true;
    notifyListeners();
    try {
      _status = await _api.getStravaStatus();
      errorMessage = null;
    } catch (error) {
      debugPrint('Không kiểm tra được trạng thái Strava: $error');
      errorMessage = 'Chưa kiểm tra được kết nối Strava. Kéo xuống để thử lại.';
    } finally {
      statusLoading = false;
      notifyListeners();
    }
  }

  Future<void> connect() async {
    await _run(() async {
      if (_auth.currentUser == null) {
        throw StateError('Bạn cần đăng nhập Google trước khi kết nối Strava.');
      }
      final uri = await _api.createStravaAuthorization(
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
        throw StateError('Không thể mở trang kết nối Strava.');
      }
    });
  }

  Future<void> disconnect() async {
    await _run(() async {
      await _api.disconnectStrava();
      _status = const StravaConnectionStatus(
        connected: false,
        status: 'disconnected',
      );
    });
  }

  // Backend exchanges the OAuth code and redirects only the final result here.
  Future<void> handleOAuthCallback(Uri uri) async {
    if (!_isStravaCallback(uri)) {
      return;
    }
    final error = uri.queryParameters['error'];
    if (error != null) {
      debugPrint('Strava OAuth trả về lỗi: $error');
      // Người dùng bấm "Không cho phép" ở trang Strava — không phải sự cố.
      errorMessage = error == 'access_denied'
          ? null
          : 'Kết nối Strava chưa xong. Vui lòng thử lại.';
      notifyListeners();
      return;
    }
    if (uri.queryParameters['strava'] == 'connected') {
      await _run(() async {
        _status = await _api.getStravaStatus();
      });
    }
  }

  bool _isStravaCallback(Uri uri) {
    if (kIsWeb) {
      final hasOAuthResult =
          uri.queryParameters.containsKey('strava') ||
          uri.queryParameters.containsKey('error');
      if (!hasOAuthResult) return false;
      return uri.scheme == Uri.base.scheme &&
          uri.host == Uri.base.host &&
          uri.port == Uri.base.port &&
          uri.path == AppConfig.stravaRedirectPath;
    }
    return uri.scheme == AppConfig.stravaRedirectScheme &&
        uri.host == AppConfig.stravaRedirectHost &&
        uri.path == AppConfig.stravaRedirectPath;
  }

  Future<void> _run(Future<void> Function() operation) async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } on FirebaseAuthException catch (error) {
      debugPrint('Strava/Firebase lỗi [${error.code}]: ${error.message}');
      errorMessage = 'Không kết nối được Strava. Vui lòng thử lại.';
    } catch (error) {
      debugPrint('Strava lỗi: $error');
      errorMessage = 'Không kết nối được Strava. Vui lòng thử lại.';
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
