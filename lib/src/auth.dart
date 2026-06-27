import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:myrun/src/config.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:myrun/src/strava_client.dart';

class GoogleAuthController extends ChangeNotifier {
  GoogleAuthController(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  bool loading = false;
  String? errorMessage;

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
    final effectiveName = displayName ?? 'RunNow member';
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
      await _markStravaDisconnectedForCurrentUser();
      await StravaClient.instance.signOut();
      await GoogleSignIn.instance.signOut();
      await _auth.signOut();
      await _clearFirestoreCache();
    });
  }

  Future<void> _markStravaDisconnectedForCurrentUser() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final batch = _firestore.batch();
    batch.set(_firestore.collection('users').doc(user.uid), {
      'stravaConnected': false,
      'stravaDisconnectedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    batch.set(
      _firestore.collection('publicProfiles').doc(user.uid),
      {'stravaConnected': false, 'updatedAt': FieldValue.serverTimestamp()},
      SetOptions(merge: true),
    );
    await batch.commit();
  }

  Future<void> _clearFirestoreCache() async {
    try {
      await _firestore.terminate();
      await _firestore.clearPersistence();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Could not clear Firestore cache on logout: $error');
      }
    }
  }

  Future<void> _run(Future<void> Function() operation) async {
    loading = true;
    errorMessage = null;
    notifyListeners();
    try {
      await operation();
    } on FirebaseAuthException catch (error) {
      errorMessage = 'Google login thất bại: ${error.message ?? error.code}';
    } catch (error) {
      errorMessage = '$error';
    } finally {
      loading = false;
      notifyListeners();
    }
  }
}

class StravaAuthController extends ChangeNotifier {
  StravaAuthController(this._auth, this._firestore, {AppLinks? appLinks})
    : _appLinks = kIsWeb ? null : appLinks ?? AppLinks() {
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
  final FirebaseFirestore _firestore;
  final AppLinks? _appLinks;
  StreamSubscription<Uri>? _subscription;
  String? errorMessage;
  bool loading = false;
  bool get connected => StravaClient.instance.isSignedIn;

  Future<void> connect() async {
    await _run(() async {
      if (_auth.currentUser == null) {
        throw StateError('Bạn cần đăng nhập Google trước khi kết nối Strava.');
      }
      if (!StravaClient.instance.isConfigured) {
        throw StateError('STRAVA_CLIENT_ID chưa được cấu hình.');
      }
      if (StravaClient.instance.isSignedIn) {
        await _linkCurrentStravaAthlete();
        return;
      }
      final uri = await StravaClient.instance.beginAuthorization();
      final mode = kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication;
      if (!await launchUrl(uri, mode: mode)) {
        throw StateError('Không thể mở trang kết nối Strava.');
      }
    });
  }

  Future<void> disconnect() async {
    await _run(() async {
      final user = _auth.currentUser;
      final athleteId = StravaClient.instance.athleteId;
      if (user != null && athleteId != null && athleteId.isNotEmpty) {
        await _firestore.runTransaction((transaction) async {
          final linkRef = _firestore.collection('stravaLinks').doc(athleteId);
          final link = await transaction.get(linkRef);
          if (link.data()?['uid'] == user.uid) {
            transaction.delete(linkRef);
          }
          transaction.set(_firestore.collection('users').doc(user.uid), {
            'stravaConnected': false,
            'stravaAthleteId': FieldValue.delete(),
            'athleteId': FieldValue.delete(),
            'stravaDisconnectedAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          transaction.set(
            _firestore.collection('publicProfiles').doc(user.uid),
            {
              'stravaConnected': false,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        });
      }
      await StravaClient.instance.signOut();
    });
  }

  // Strava returns the short-lived authorization `code` in query params.
  Future<void> handleOAuthCallback(Uri uri) async {
    if (!_isStravaCallback(uri)) {
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
        // Dev-only web flow: this exchanges Strava OAuth code directly from
        // the browser because RunNow is currently an internal demo.
        // Production must move this exchange to a backend service.
        await StravaClient.instance.exchangeCode(code);
        try {
          await _linkCurrentStravaAthlete();
        } catch (error) {
          throw StateError(
            'Không lưu được liên kết Strava vào Firestore: $error',
          );
        }
      });
    }
  }

  bool _isStravaCallback(Uri uri) {
    if (kIsWeb) {
      final hasOAuthResult =
          uri.queryParameters.containsKey('code') ||
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

  Future<void> _linkCurrentStravaAthlete() async {
    final user = _auth.currentUser;
    final athleteId = StravaClient.instance.athleteId;
    if (user == null) {
      await StravaClient.instance.signOut();
      throw StateError('Bạn cần đăng nhập Google trước khi kết nối Strava.');
    }
    if (athleteId == null || athleteId.isEmpty) {
      throw StateError('Không lấy được Strava athlete ID.');
    }
    try {
      await _firestore.runTransaction((transaction) async {
        final linkRef = _firestore.collection('stravaLinks').doc(athleteId);
        final userRef = _firestore.collection('users').doc(user.uid);
        final userSnapshot = await transaction.get(userRef);
        final userData = userSnapshot.data() ?? const <String, dynamic>{};
        final lockedAthleteId =
            userData['lockedStravaAthleteId'] as String? ??
            userData['stravaAthleteId'] as String? ??
            userData['athleteId'] as String?;
        if (lockedAthleteId != null &&
            lockedAthleteId.isNotEmpty &&
            lockedAthleteId != athleteId) {
          throw StateError(
            'Tài khoản Google này đã được liên kết với một tài khoản Strava khác.',
          );
        }
        final link = await transaction.get(linkRef);
        final existingUid = link.data()?['uid'] as String?;
        if (existingUid != null && existingUid != user.uid) {
          throw StateError(
            'Tài khoản Strava này đã được liên kết với một tài khoản Google khác.',
          );
        }
        transaction.set(
          linkRef,
          {
            'uid': user.uid,
            'email': user.email,
            'linkedAt': FieldValue.serverTimestamp(),
          }..removeWhere((key, value) => value == null),
          SetOptions(merge: true),
        );
        transaction.set(userRef, {
          'stravaConnected': true,
          'lockedStravaAthleteId': lockedAthleteId ?? athleteId,
          'stravaAthleteId': athleteId,
          'athleteId': athleteId,
          'stravaLinkedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        transaction.set(
          _firestore.collection('publicProfiles').doc(user.uid),
          {'stravaConnected': true, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      });
    } catch (_) {
      await StravaClient.instance.signOut();
      rethrow;
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
      if (kIsWeb) {
        errorMessage =
            'Strava đã redirect về RunNow, nhưng browser không đổi được code '
            'sang token trực tiếp. Lưu client secret trong app hoặc Firestore '
            'không xử lý được lỗi này nếu Strava chặn CORS. Cần backend/proxy '
            'token exchange để web connect Strava ổn định. Chi tiết: $error';
      } else {
        errorMessage = '$error';
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  String _firebaseErrorMessage(FirebaseAuthException error) {
    if (error.code == 'internal-error' ||
        error.code == 'operation-not-allowed') {
      return 'Firebase Authentication chưa được bật đúng provider. '
          'Hãy bật Google trong Firebase Console.';
    }
    return 'Firebase Authentication thất bại: ${error.message ?? error.code}';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
