import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:myrun/src/config.dart';

typedef IdTokenProvider = Future<String> Function({required bool forceRefresh});

class StravaConnectionStatus {
  const StravaConnectionStatus({
    required this.connected,
    required this.status,
    this.athleteId,
  });

  factory StravaConnectionStatus.fromJson(Map<String, dynamic> json) {
    return StravaConnectionStatus(
      connected: json['connected'] == true,
      status: json['status'] as String? ?? 'disconnected',
      athleteId: json['athleteId'] as String?,
    );
  }

  final bool connected;
  final String status;
  final String? athleteId;
}

class TrackedActivityBackendResult {
  const TrackedActivityBackendResult({
    required this.status,
    this.stravaActivityId,
  });

  factory TrackedActivityBackendResult.fromJson(Map<String, dynamic> json) {
    return TrackedActivityBackendResult(
      status: json['status'] as String? ?? 'counted',
      stravaActivityId: json['stravaActivityId'] as String?,
    );
  }

  final String status;
  final String? stravaActivityId;
}

class RunNowApiException implements Exception {
  const RunNowApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  final int statusCode;
  final String code;
  final String message;

  @override
  String toString() => message;
}

class RunNowApiClient {
  RunNowApiClient({
    required this.tokenProvider,
    http.Client? httpClient,
    Uri? baseUri,
  }) : _http = httpClient ?? http.Client(),
       _baseUri = baseUri ?? Uri.parse(AppConfig.runNowApiBaseUrl);

  factory RunNowApiClient.firebase(FirebaseAuth auth) {
    return RunNowApiClient(
      tokenProvider: ({required forceRefresh}) async {
        final user = auth.currentUser;
        if (user == null) throw StateError('Bạn chưa đăng nhập Google.');
        final token = await user.getIdToken(forceRefresh);
        if (token == null || token.isEmpty) {
          throw StateError('Không lấy được phiên đăng nhập Firebase.');
        }
        return token;
      },
    );
  }

  static const _timeout = Duration(seconds: 25);

  final IdTokenProvider tokenProvider;
  final http.Client _http;
  final Uri _baseUri;

  Future<StravaConnectionStatus> getStravaStatus() async {
    final response = await _send('GET', '/v1/strava/status');
    return StravaConnectionStatus.fromJson(_jsonObject(response));
  }

  Future<Uri> createStravaAuthorization({required String returnTarget}) async {
    final response = await _send(
      'POST',
      '/v1/strava/authorization',
      body: {'returnTarget': returnTarget},
    );
    final value = _jsonObject(response)['authorizationUrl'] as String?;
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null) {
      throw const FormatException(
        'Backend trả về authorization URL không hợp lệ.',
      );
    }
    return uri;
  }

  Future<void> disconnectStrava() async {
    await _send('POST', '/v1/strava/disconnect');
  }

  Future<void> requestStravaRepair({bool full = false}) async {
    await _send('POST', '/v1/strava/repair', body: {'full': full});
  }

  Future<void> hydrateActivity(String activityId) async {
    await _send(
      'POST',
      '/v1/activities/${Uri.encodeComponent(activityId)}/hydrate',
    );
  }

  Future<TrackedActivityBackendResult> saveTrackedActivity(
    Map<String, dynamic> activity,
  ) async {
    final response = await _send(
      'POST',
      '/v1/activities/tracked',
      body: {'activity': activity},
    );
    return TrackedActivityBackendResult.fromJson(_jsonObject(response));
  }

  Future<void> updateProfile({
    required String nickname,
    required String? avatarUrl,
    required String visibility,
  }) async {
    await _send(
      'POST',
      '/v1/profile',
      body: {
        'nickname': nickname,
        'avatarUrl': avatarUrl,
        'visibility': visibility,
      },
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    var response = await _sendOnce(method, path, body: body);
    if (response.statusCode == 401) {
      response = await _sendOnce(
        method,
        path,
        body: body,
        forceRefreshToken: true,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _apiException(response);
    }
    return response;
  }

  Future<http.Response> _sendOnce(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool forceRefreshToken = false,
  }) async {
    final token = await tokenProvider(forceRefresh: forceRefreshToken);
    final request = http.Request(method, _baseUri.resolve(path))
      ..headers.addAll({
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _http.send(request).timeout(_timeout);
    return http.Response.fromStream(streamed);
  }

  Map<String, dynamic> _jsonObject(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backend trả về dữ liệu không hợp lệ.');
    }
    return decoded;
  }

  RunNowApiException _apiException(http.Response response) {
    try {
      final data = _jsonObject(response);
      return RunNowApiException(
        statusCode: response.statusCode,
        code: data['code'] as String? ?? 'request_failed',
        message: data['message'] as String? ?? 'Backend từ chối yêu cầu.',
      );
    } catch (_) {
      return RunNowApiException(
        statusCode: response.statusCode,
        code: 'request_failed',
        message: 'Backend trả về lỗi HTTP ${response.statusCode}.',
      );
    }
  }

  void close() => _http.close();
}
