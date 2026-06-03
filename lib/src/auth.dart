import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:myrun/src/config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:myrun/src/strava_client.dart';

class StravaAuthController extends ChangeNotifier {
  StravaAuthController(this._auth, {AppLinks? appLinks})
    : _appLinks = appLinks ?? AppLinks() {
    _subscription = _appLinks.uriLinkStream.listen(handleOAuthCallback);
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) handleOAuthCallback(uri);
    });
  }

  final FirebaseAuth _auth;
  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;
  String? errorMessage;
  bool loading = false;

  Future<void> connect() async {
    await _run(() async {
      if (!StravaClient.instance.isConfigured) {
        throw StateError('STRAVA_CLIENT_ID chưa được cấu hình.');
      }
      if (StravaClient.instance.isSignedIn) {
        await _ensureFirebaseSignIn();
        return;
      }
      final uri = await StravaClient.instance.beginAuthorization();
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('Không thể mở trang kết nối Strava.');
      }
    });
  }

  Future<void> disconnect() async {
    await _run(() async {
      await StravaClient.instance.signOut();
      await _auth.signOut();
    });
  }

  // Strava returns the short-lived authorization `code` in query params.
  Future<void> handleOAuthCallback(Uri uri) async {
    if (uri.scheme != AppConfig.stravaRedirectScheme ||
        uri.host != AppConfig.stravaRedirectHost ||
        uri.path != AppConfig.stravaRedirectPath) {
      return;
    }
    final error = uri.queryParameters['error'];
    if (error != null) {
      errorMessage = 'Kết nối Strava thất bại: $error';
      notifyListeners();
      return;
    }
    final code = uri.queryParameters['code'];
    if (code != null) {
      await _run(() async {
        await StravaClient.instance.exchangeCode(code);
        await _ensureFirebaseSignIn();
      });
    }
  }

  Future<void> _ensureFirebaseSignIn() async {
    // Firebase UID owns the user's Firestore documents.
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } on FirebaseAuthException catch (error) {
      errorMessage = _firebaseErrorMessage(error);
    } catch (error) {
      errorMessage = '$error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _firebaseErrorMessage(FirebaseAuthException error) {
    if (error.code == 'internal-error' ||
        error.code == 'operation-not-allowed') {
      return 'Firebase Authentication chưa được bật. Vào Firebase Console > '
          'Authentication > Get started > Sign-in method > Anonymous, bật '
          'provider rồi bấm Kết nối Strava lại.';
    }
    return 'Firebase Authentication thất bại: ${error.message ?? error.code}';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
