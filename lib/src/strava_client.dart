import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:myrun/src/config.dart';

class StravaToken {
  StravaToken({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.athleteId,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresAt;
  final String athleteId;
}

class StravaClient {
  StravaClient._();

  static final StravaClient instance = StravaClient._();
  static const _storage = FlutterSecureStorage();

  static const clientId = AppConfig.stravaClientId;
  static const clientSecret = AppConfig.stravaClientSecret;
  static const redirectUri = AppConfig.stravaRedirectUri;
  static const scope = AppConfig.stravaScope;

  String? _accessToken;
  String? _refreshToken;
  int? _expiresAt;
  String? athleteId;

  bool get isConfigured => clientId.isNotEmpty && clientSecret.isNotEmpty;
  bool get isSignedIn => _accessToken != null && athleteId != null;

  Future<void> initialize() async {
    final map = await _storage.readAll();
    _accessToken = map['strava_access_token'];
    _refreshToken = map['strava_refresh_token'];
    _expiresAt = map['strava_expires_at'] != null
        ? int.tryParse(map['strava_expires_at']!)
        : null;
    athleteId = map['strava_athlete_id'];
  }

  /// Start the direct Strava OAuth flow used by the local-only demo build.
  Future<Uri> beginAuthorization() async {
    if (!isConfigured) throw StateError('Strava credentials not configured.');
    final state = base64UrlEncode(
      utf8.encode(DateTime.now().toIso8601String()),
    ).replaceAll('=', '');

    final params = {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'approval_prompt': 'auto',
      'scope': scope,
      'state': state,
    };
    final uri = Uri.https('www.strava.com', '/oauth/mobile/authorize', params);
    return uri;
  }

  /// TODO: Move OAuth exchange and refresh to a backend before distribution.
  Future<void> exchangeCode(String code) async {
    final body = {
      'client_id': clientId,
      'client_secret': clientSecret,
      'code': code,
      'grant_type': 'authorization_code',
    };
    final response = await http.post(
      Uri.parse('https://www.strava.com/oauth/token'),
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Strava token exchange failed: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    await _storeTokenFromResponse(data);
  }

  Future<void> _storeTokenFromResponse(Map<String, dynamic> data) async {
    _accessToken = data['access_token'] as String;
    _refreshToken = data['refresh_token'] as String;
    _expiresAt = (data['expires_at'] as num).toInt();
    athleteId = '${data['athlete']?['id'] ?? data['athlete_id'] ?? ''}';
    await _storage.write(key: 'strava_access_token', value: _accessToken);
    await _storage.write(key: 'strava_refresh_token', value: _refreshToken);
    await _storage.write(key: 'strava_expires_at', value: '$_expiresAt');
    await _storage.write(key: 'strava_athlete_id', value: athleteId ?? '');
  }

  Future<void> signOut() async {
    _accessToken = null;
    _refreshToken = null;
    _expiresAt = null;
    athleteId = null;
    await _storage.delete(key: 'strava_access_token');
    await _storage.delete(key: 'strava_refresh_token');
    await _storage.delete(key: 'strava_expires_at');
    await _storage.delete(key: 'strava_athlete_id');
  }

  Future<void> _refreshIfNeeded() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_accessToken == null || _expiresAt == null) return;
    if (_expiresAt! > now + 60) return; // still valid
    if (_refreshToken == null) throw StateError('Refresh token missing');
    final body = {
      'client_id': clientId,
      'client_secret': clientSecret,
      'grant_type': 'refresh_token',
      'refresh_token': _refreshToken!,
    };
    final response = await http.post(
      Uri.parse('https://www.strava.com/oauth/token'),
      body: body,
    );
    if (response.statusCode != 200) {
      throw Exception('Strava token refresh failed: ${response.statusCode}');
    }
    final data = json.decode(response.body) as Map<String, dynamic>;
    await _storeTokenFromResponse(data);
  }

  Future<List<dynamic>> listActivities({int? after, required int page}) async {
    await _refreshIfNeeded();
    final uri = Uri.https('www.strava.com', '/api/v3/athlete/activities', {
      if (after != null) 'after': '$after',
      'page': '$page',
      'per_page': '100',
    });
    _debugLog('GET $uri');
    final resp = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${_accessToken ?? ''}'},
    );
    _debugLog('GET ${uri.path} -> ${resp.statusCode}\n${resp.body}');
    if (resp.statusCode == 401) throw Exception('Strava unauthorized');
    if (resp.statusCode != 200) {
      throw Exception('Strava returned ${resp.statusCode}');
    }
    return json.decode(resp.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getActivityDetail(String activityId) async {
    await _refreshIfNeeded();
    final uri = Uri.https('www.strava.com', '/api/v3/activities/$activityId');
    _debugLog('GET $uri');
    final resp = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${_accessToken ?? ''}'},
    );
    _debugLog('GET ${uri.path} -> ${resp.statusCode}\n${resp.body}');
    if (resp.statusCode == 401) throw Exception('Strava unauthorized');
    if (resp.statusCode != 200) {
      throw Exception('Strava returned ${resp.statusCode}');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getActivityStreams(String activityId) async {
    await _refreshIfNeeded();
    final uri =
        Uri.https('www.strava.com', '/api/v3/activities/$activityId/streams', {
          'keys':
              'distance,time,velocity_smooth,heartrate,altitude,cadence,watts',
          'key_by_type': 'true',
        });
    _debugLog('GET $uri');
    final resp = await http.get(
      uri,
      headers: {'Authorization': 'Bearer ${_accessToken ?? ''}'},
    );
    _debugLog('GET ${uri.path} -> ${resp.statusCode}\n${resp.body}');
    if (resp.statusCode == 401) throw Exception('Strava unauthorized');
    if (resp.statusCode != 200) {
      throw Exception('Strava returned ${resp.statusCode}');
    }
    return json.decode(resp.body) as Map<String, dynamic>;
  }

  void _debugLog(String message) {
    if (kDebugMode) debugPrint('[StravaClient] $message');
  }
}
