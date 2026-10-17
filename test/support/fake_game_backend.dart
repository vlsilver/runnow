import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/runnow_api_client.dart';

const unlinkedTelegram = {
  'linked': false,
  'tgUsername': '',
  'displayName': '',
  'inPsc': false,
};

/// Backend giả: trả state đang giữ, ghi lại các lời gọi.
class FakeGameBackend {
  FakeGameBackend(this.now);

  DateTime Function() now;
  final calls = <String>[];
  Map<String, dynamic> game = {};
  Map<String, dynamic> me = {'status': 'running', 'alive': true};
  Map<String, Map<String, dynamic>> feedPages = {};
  Map<String, dynamic> telegram = {...unlinkedTelegram};

  /// Chặn trả lời `/me` cho tới khi complete, để dựng ca chạy chồng.
  Future<void>? holdMe;

  /// Lỗi trả cho từng route, khoá là `METHOD path`: (status, body).
  final failures = <String, (int, Map<String, dynamic>)>{};

  /// Body của `GET /v1/games`.
  Map<String, dynamic> list = {'items': []};

  /// Trả cho `start?dryRun=true`.
  Map<String, dynamic> startPreview = {};

  /// Mọi request đã gửi, để xem body và query.
  final requests = <http.Request>[];

  /// Trang chat theo cursor; khoá '' là trang mới nhất. POST thêm tin của
  /// [chatSender] lên đầu trang ''.
  Map<String, Map<String, dynamic>> chatPages = {};
  String chatSender = 'me';

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.5.0+12',
    appPlatform: 'ios',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      final route = '${request.method} $path';
      calls.add(route);
      requests.add(request);
      if (failures[route] case (final status, final error)?) {
        return _json(error, status);
      }
      Object body;
      if (path == '/v1/games') {
        body = request.method == 'POST' ? {'id': 'g9'} : list;
      } else if (path.endsWith('/start')) {
        if (request.url.queryParameters['dryRun'] == 'true') {
          body = startPreview;
        } else {
          game = {
            ...game,
            'status': 'starting',
            'statusLabel': 'Đang chia bài',
          };
          body = {'attempt': 1};
        }
      } else if (path == '/v1/telegram/link-code') {
        body = {
          'code': 'K7Q2',
          'deepLink': 'https://t.me/runnow3i_bot?start=K7Q2',
          'expiresAt': now().add(const Duration(minutes: 10)).toIso8601String(),
        };
      } else if (path == '/v1/telegram/link') {
        if (request.method == 'DELETE') telegram = {...unlinkedTelegram};
        body = telegram;
      } else if (path.endsWith('/registration')) {
        final registered = request.method == 'POST';
        final count =
            (game['playerCount'] as int? ?? 0) + (registered ? 1 : -1);
        game = {...game, 'isRegistered': registered, 'playerCount': count};
        body = {'isRegistered': registered, 'playerCount': count};
      } else if (path.endsWith('/me')) {
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
      } else if (path.contains('/chats/')) {
        if (request.method == 'POST') {
          final page = chatPages['']!;
          final messages = (page['messages'] as List).cast<Object>();
          final top = messages.isEmpty
              ? 0
              : (messages.first as Map<String, dynamic>)['seq'] as int;
          final text = (jsonDecode(request.body) as Map)['text'];
          chatPages[''] = {
            ...page,
            'messages': [
              {
                'seq': top + 1,
                'uid': chatSender,
                'name': 'Tôi',
                'text': text,
                'system': false,
                'at': now().toUtc().toIso8601String(),
              },
              ...messages,
            ],
          };
          body = {'ok': true};
        } else {
          body = chatPages[request.url.queryParameters['cursor'] ?? '']!;
        }
      } else if (path.endsWith('/feed')) {
        body = feedPages[request.url.queryParameters['cursor']]!;
      } else {
        body = {'serverNow': now().toUtc().toIso8601String(), ...game};
      }
      return _json(body);
    }),
  );

  static http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json'},
      );
}
