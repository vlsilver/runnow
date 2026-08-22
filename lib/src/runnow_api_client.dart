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

  /// Hoàn tất buổi chạy đã sync DẦN theo chunk: chỉ gửi phần summary NHẸ
  /// (stats/splits/streams, KHÔNG kèm routePoints — route đã đẩy sẵn qua các
  /// chunk `activities/{id}/track/{seq}`). Backend ghép chunk lại thành route
  /// đầy đủ rồi lưu như buổi thường. Tránh "cú dump khổng lồ" ở cuối buổi.
  Future<TrackedActivityBackendResult> finalizeTrackedActivity(
    Map<String, dynamic> summary,
  ) async {
    final response = await _send(
      'POST',
      '/v1/activities/tracked/finalize',
      body: {'activity': summary},
    );
    return TrackedActivityBackendResult.fromJson(_jsonObject(response));
  }

  /// Tường thuật LIVE 1 sự kiện buổi tập (start / milestone / finish). Backend
  /// enqueue task cho bot viết + gửi group. Gọi fire-and-forget từ vòng tracking
  /// — lỗi mạng bỏ qua, không chặn buổi chạy.
  Future<void> announceLive({
    required String activityId,
    required String event,
    required double distanceMeters,
    required double movingTimeSeconds,
    int milestoneKm = 0,
    String photoPath = '',
  }) async {
    await _send(
      'POST',
      '/v1/live/announce',
      body: {
        'activityId': activityId,
        'event': event,
        'distanceMeters': distanceMeters,
        'movingTimeSeconds': movingTimeSeconds,
        'milestoneKm': milestoneKm,
        'photoPath': photoPath,
      },
    );
  }

  /// Sau khi CHỦ kèo chốt kết quả: nhờ backend cho 3i "bôi tro trét trấu" những
  /// người đăng ký mà không hoàn thành, lên group. Fire-and-forget, chỉ kèo
  /// public mới nên gọi. Lỗi mạng bỏ qua (không chặn luồng chốt kèo).
  Future<void> announceContractResult({required String contractId}) async {
    await _send(
      'POST',
      '/v1/contracts/announce-result',
      body: {'contractId': contractId},
    );
  }

  /// Báo group qua 3i bot khi vừa TẠO một kèo công khai — rủ mọi người tham gia.
  /// Fire-and-forget, chỉ kèo public mới nên gọi. Lỗi mạng bỏ qua.
  Future<void> announceNewContract({required String contractId}) async {
    await _send(
      'POST',
      '/v1/contracts/announce-new',
      body: {'contractId': contractId},
    );
  }

  /// Báo group khi chủ GỠ một giáo án công khai (kèm goal vì doc sắp bị xoá).
  /// Fire-and-forget, chỉ giáo án public mới nên gọi.
  Future<void> announceCoachRemoved({required String goal}) async {
    await _send('POST', '/v1/coach/announce-removed', body: {'goal': goal});
  }

  /// Nhập buổi CHẠY từ kho sức khoẻ máy. Backend upsert theo sourceId + dedup thời
  /// gian với Strava/native để không đếm đôi km. [source]: "apple_health" (iOS) |
  /// "health_connect" (Android); bỏ trống = backend mặc định apple_health.
  Future<void> importHealthWorkouts(
    List<Map<String, dynamic>> workouts, {
    String? source,
    String? reconcileFrom,
    String? reconcileTo,
  }) async {
    await _send(
      'POST',
      '/v1/activities/health-import',
      body: {
        'workouts': workouts,
        'source': ?source,
        // Có mốc → backend dọn buổi ĐÚNG nguồn này đã xoá trong Health ở khoảng đó.
        'reconcileFrom': ?reconcileFrom,
        'reconcileTo': ?reconcileTo,
      },
    );
  }

  /// Nhập số bước theo NGÀY từ Apple Health (bảng xếp hạng bước riêng). Backend
  /// upsert theo ngày + dựng lại BXH bước.
  Future<void> importHealthSteps(List<Map<String, dynamic>> days) async {
    await _send(
      'POST',
      '/v1/health/steps-import',
      body: {'days': days},
    );
  }

  /// AI Coach: nhờ backend sinh ĐỀ XUẤT giáo án theo mục tiêu + lịch sử chạy
  /// thật. Chạy bất đồng bộ (Gemini) — backend ghi users/{uid}/coach/draft xong
  /// app tự nhận qua stream Firestore. Giáo án đang chạy không bị đụng tới.
  Future<void> generateTrainingPlan({
    required String goal,
    String visibility = 'private',
  }) async {
    await _send(
      'POST',
      '/v1/training-plan/generate',
      body: {'goal': goal, 'visibility': visibility},
    );
  }

  /// Xác nhận bản nháp → giáo án đang chạy.
  Future<void> confirmTrainingPlan() async {
    await _send('POST', '/v1/training-plan/confirm');
  }

  /// Bỏ bản nháp, giữ nguyên giáo án đang chạy.
  Future<void> discardTrainingPlan() async {
    await _send('POST', '/v1/training-plan/discard');
  }

  /// Hỏi coach một câu trong ngữ cảnh giáo án của chính user. Đồng bộ vì màn
  /// chat đang đợi câu trả lời. Hạn 70s — backend cho Gemini 60s, chừa biên để
  /// lỗi hiện ra là lỗi thật chứ không phải client bỏ cuộc sớm.
  Future<String> askCoach({
    required String planId,
    required String question,
  }) async {
    final res = await _send(
      'POST',
      '/v1/coach/ask',
      body: {'planId': planId, 'question': question},
      timeout: const Duration(seconds: 70),
    );
    return _jsonObject(res)['answer'] as String? ?? '';
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

  /// Xoá vĩnh viễn tài khoản và toàn bộ dữ liệu gắn với nó.
  ///
  /// Backend phải làm việc này vì client không xoá được subcollection của
  /// Firestore, không gỡ được chính mình khỏi Firebase Auth, và không thu
  /// hồi được token Strava. Tài khoản nhiều dữ liệu có thể mất khá lâu nên
  /// dùng timeout dài hơn mặc định.
  Future<void> deleteAccount() async {
    await _send(
      'POST',
      '/v1/account/delete',
      timeout: const Duration(minutes: 2),
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Duration? timeout,
  }) async {
    var response = await _sendOnce(method, path, body: body, timeout: timeout);
    if (response.statusCode == 401) {
      response = await _sendOnce(
        method,
        path,
        body: body,
        timeout: timeout,
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
    Duration? timeout,
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
    final streamed = await _http.send(request).timeout(timeout ?? _timeout);
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
