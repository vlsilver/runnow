import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// One-release migration that removes credentials stored by the retired
/// direct-Strava client. Strava credentials now live only in the backend.
abstract final class LegacyStravaCredentials {
  static const _storage = FlutterSecureStorage();
  static const _keys = <String>[
    'strava_access_token',
    'strava_refresh_token',
    'strava_expires_at',
    'strava_athlete_id',
  ];

  static Future<void> clear() async {
    try {
      await Future.wait(_keys.map((key) => _storage.delete(key: key)));
    } catch (_) {
      // Best-effort cleanup — không có gì để làm nếu secure storage lỗi.
    }
  }
}
