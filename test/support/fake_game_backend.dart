import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Backend giả: trả state đang giữ, ghi lại các lời gọi.
class FakeGameBackend {
  FakeGameBackend(this.now);

  DateTime Function() now;
  final calls = <String>[];
  Map<String, dynamic> game = {};
  Map<String, dynamic> me = {'status': 'running', 'alive': true};
  Map<String, Map<String, dynamic>> feedPages = {};

  /// Chặn trả lời `/me` cho tới khi complete, để dựng ca chạy chồng.
  Future<void>? holdMe;

  /// Có thì GET detail trả lỗi này (status, body).
  (int, Map<String, dynamic>)? failGame;

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.5.0+12',
    appPlatform: 'ios',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      calls.add('${request.method} $path');
      Object body;
      if (path.endsWith('/me')) {
        // Trả state lúc server đọc, dù câu trả lời tới muộn.
        body = me;
        final hold = holdMe;
        if (hold != null) await hold;
      } else if (path.endsWith('/actions')) {
        // Server ghi action: các lần đọc /me sau đó thấy state mới.
        me = {
          ...me,
          'notes': [
            {'round': 1, 'text': 'từ action'},
          ],
        };
        body = me;
      } else if (path.endsWith('/feed')) {
        body = feedPages[request.url.queryParameters['cursor']]!;
      } else if (failGame case (final status, final error)?) {
        return http.Response.bytes(
          utf8.encode(jsonEncode(error)),
          status,
          headers: {'content-type': 'application/json'},
        );
      } else {
        body = {'serverNow': now().toUtc().toIso8601String(), ...game};
      }
      return http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}
