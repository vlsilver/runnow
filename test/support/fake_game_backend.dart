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

  /// GET /v1/games/telegram; null trả 404 như backend chưa có bot ván.
  Map<String, dynamic>? gameTelegram;
  String gameBotCreateUrl = 'https://t.me/newbot/Run3IBot/van_boss_bot';

  /// POST /v1/games/telegram/check: backend có hẹn kiểm không.
  bool gameTelegramCheckQueued = false;

  /// GET /v1/agents/me. Rỗng thì `enabled` là false, màn ván ẩn nút MyBot.
  Map<String, dynamic> agentMe = {};

  /// Trả cho `start?dryRun=true`.
  Map<String, dynamic> startPreview = {};

  /// Mọi request đã gửi, để xem body và query.
  final requests = <http.Request>[];

  /// Trang chat theo cursor; khoá '' là trang mới nhất. POST thêm tin của
  /// [chatSender] lên đầu trang ''. `after=n` trả tối đa [chatAfterLimit] tin
  /// sau seq n lấy từ trang '', kèm hasNewer.
  Map<String, Map<String, dynamic>> chatPages = {};
  String chatSender = 'me';
  int chatAfterLimit = 30;

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
      if (path == '/v1/games/telegram') {
        // null: backend chưa có bot ván.
        final status = gameTelegram;
        if (status == null) return _json({'error': 'not_found'}, 404);
        body = status;
      } else if (path == '/v1/games/telegram/check') {
        body = {'queued': gameTelegramCheckQueued};
      } else if (path == '/v1/games/telegram/bot') {
        body = {'createUrl': gameBotCreateUrl};
      } else if (path == '/v1/games') {
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
      } else if (path == '/v1/agents/me') {
        body = agentMe;
      } else if (path.endsWith('/me/stand-in')) {
        final on = (jsonDecode(request.body) as Map)['on'] == true;
        me = {...me, 'standIn': on};
        body = {'standIn': on};
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
      } else if (path.endsWith('/reports')) {
        body = {'ok': true};
      } else if (path.contains('/chats/')) {
        final after = int.tryParse(request.url.queryParameters['after'] ?? '');
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
        } else if (after != null) {
          final page = chatPages['']!;
          final newer = [
            for (final m in page['messages'] as List)
              if ((m as Map<String, dynamic>)['seq'] as int > after) m,
          ]..sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
          body = {
            ...page,
            'cursor': null,
            'messages': newer.take(chatAfterLimit).toList().reversed.toList(),
            'hasNewer': newer.length > chatAfterLimit,
          };
        } else {
          body = chatPages[request.url.queryParameters['cursor'] ?? '']!;
        }
      } else if (path.endsWith('/admin/fake-players')) {
        // Đặt tổng người giả về đúng count, giữ người thật.
        final count = (jsonDecode(request.body) as Map)['count'] as int;
        final real = [
          for (final p in game['players'] as List? ?? const [])
            if ((p as Map)['fake'] != true) p,
        ];
        final players = [
          ...real,
          for (var i = 0; i < count; i++)
            {'uid': 'fake-$i', 'name': 'Giả $i', 'fake': true},
        ];
        game = {...game, 'players': players, 'playerCount': players.length};
        body = {'count': count};
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
