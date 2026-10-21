import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/agents/agent_chat_screen.dart';
import 'package:myrun/src/agents/agent_group_facts_screen.dart';
import 'package:myrun/src/agents/agent_screen.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

class _FakeUser implements User {
  @override
  String get uid => 'me';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Backend giả cho /v1/agents*: giữ state, ghi lại request.
class _AgentBackend {
  Map<String, dynamic> agent = {
    'name': 'Bot của Tôi',
    'persona': '',
    'created': false,
  };
  final memories = <Map<String, dynamic>>[];
  final learned = <Map<String, dynamic>>[];
  final groupFacts = <Map<String, dynamic>>[];
  var admin = false;
  Map<String, dynamic> dm = {'messages': [], 'waiting': false};
  Map<String, dynamic> room = {'messages': [], 'members': []};
  final requests = <http.Request>[];
  var _ids = 0;

  List<String> get calls => [
    for (final r in requests) '${r.method} ${r.url.path}',
  ];

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.5.0+12',
    appPlatform: 'ios',
    httpClient: MockClient((request) async {
      requests.add(request);
      final path = request.url.path;
      final body = request.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(request.body) as Map<String, dynamic>;
      Object out = {'ok': true};
      switch ((request.method, path)) {
        case ('GET', '/v1/agents/me'):
          out = {
            'enabled': true,
            'agent': agent,
            'memories': memories,
            'memoryLimit': 50,
            'learned': learned,
          };
        case ('DELETE', final p) when p.startsWith('/v1/agents/me/learned/'):
          learned.removeWhere((f) => p.endsWith('/${f['id']}'));
        case ('GET', '/v1/agents/group-facts'):
          out = {'facts': groupFacts, 'canDelete': admin};
        case ('DELETE', final p) when p.startsWith('/v1/agents/group-facts/'):
          groupFacts.removeWhere((f) => p.endsWith('/${f['id']}'));
        case ('POST', '/v1/agents/me'):
          agent = {...body, 'created': true};
          out = agent;
        case ('POST', '/v1/agents/me/memories'):
          final m = {
            'id': 'm${++_ids}',
            'text': body['text'],
            'source': 'manual',
          };
          memories.add(m);
          out = m;
        case ('DELETE', final p) when p.startsWith('/v1/agents/me/memories/'):
          memories.removeWhere((m) => p.endsWith('/${m['id']}'));
        case ('GET', '/v1/agents/me/dm'):
          out = request.url.queryParameters.containsKey('after')
              ? {'messages': [], 'waiting': dm['waiting']}
              : dm;
        case ('GET', '/v1/agents/room'):
          out = request.url.queryParameters.containsKey('after')
              ? {'messages': [], 'members': []}
              : room;
        case ('POST', '/v1/agents/me/dm' || '/v1/agents/room'):
          break;
        default:
          return http.Response('{"error":"not_found"}', 404);
      }
      return http.Response(
        jsonEncode(out),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

void main() {
  late _AgentBackend backend;

  Future<void> pump(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
        ],
        child: MaterialApp(home: home),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Gỡ màn để dừng timer poll trước khi test kết thúc.
  Future<void> close(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  setUp(() => backend = _AgentBackend());

  testWidgets('creates the bot, then adds and deletes a memory', (
    tester,
  ) async {
    await pump(tester, const AgentScreen());
    // Chưa tạo: chưa có nút vào chat, chưa có bộ nhớ.
    expect(find.text('Chat riêng'), findsNothing);
    expect(find.textContaining('Bộ nhớ'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Tính cách'),
      'Hay đùa',
    );
    await tester.tap(find.text('Tạo bot'));
    await tester.pumpAndSettle();
    final create = backend.requests.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/v1/agents/me',
    );
    expect(jsonDecode(create.body), {
      'name': 'Bot của Tôi',
      'persona': 'Hay đùa',
    });
    expect(find.text('Chat riêng'), findsOneWidget);
    expect(find.text('Bộ nhớ (0/50)'), findsOneWidget);
    // Bộ nhớ được dùng trong phòng: phải nói rõ cho chủ.
    expect(find.textContaining('các thành viên khác cùng đọc'), findsOneWidget);

    await tester.tap(find.text('Thêm'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '  Chạy sáng thứ 7  ');
    await tester.tap(find.text('Lưu').last);
    await tester.pumpAndSettle();
    expect(backend.memories.single['text'], 'Chạy sáng thứ 7');
    expect(find.text('Chạy sáng thứ 7'), findsOneWidget);
    expect(find.text('Bộ nhớ (1/50)'), findsOneWidget);

    await tester.tap(find.byTooltip('Xoá'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xoá').last);
    await tester.pumpAndSettle();
    expect(backend.calls, contains('DELETE /v1/agents/me/memories/m1'));
    expect(find.text('Bộ nhớ (0/50)'), findsOneWidget);
  });

  testWidgets('shows what the bot learned and forgets on request', (
    tester,
  ) async {
    backend.learned.addAll([
      {'id': 'f1', 'text': 'Mê chạy trail', 'source': 'learned'},
      {'id': 'tg-f2', 'text': 'Đi giày Pegasus', 'source': 'migrated'},
    ]);
    // Chưa tạo bot vẫn thấy điều bot học được từ group Telegram.
    await pump(tester, const AgentScreen());
    await tester.scrollUntilVisible(
      find.text('Bot biết gì về nhóm'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Bot tự học về bạn (2)'), findsOneWidget);
    expect(find.text('Từ trí nhớ cũ của 3i'), findsOneWidget);

    await tester.tap(find.byTooltip('Quên').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quên').last);
    await tester.pumpAndSettle();
    expect(backend.calls, contains('DELETE /v1/agents/me/learned/tg-f2'));
    expect(find.text('Đi giày Pegasus'), findsNothing);
    expect(find.text('Bot tự học về bạn (1)'), findsOneWidget);
  });

  testWidgets('only admins can make the bot forget group facts', (
    tester,
  ) async {
    backend.groupFacts.add({'id': 'f1', 'text': 'Nhóm chạy 6h thứ 7'});
    await pump(tester, const AgentGroupFactsScreen());
    expect(find.text('Nhóm chạy 6h thứ 7'), findsOneWidget);
    expect(find.byTooltip('Quên'), findsNothing);
    await close(tester);

    backend.admin = true;
    await pump(tester, const AgentGroupFactsScreen());
    await tester.tap(find.byTooltip('Quên'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quên').last);
    await tester.pumpAndSettle();
    expect(backend.calls, contains('DELETE /v1/agents/group-facts/f1'));
    expect(find.text('Bot chưa học được gì về nhóm.'), findsOneWidget);
  });

  testWidgets('DM shows typing only while a recent message waits', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 20, 8);
    backend.agent = {'name': 'Sóc', 'persona': '', 'created': true};
    backend.dm = {
      'messages': [
        {
          'seq': 2,
          'role': 'user',
          'text': 'còn đó không',
          'at': now.toIso8601String(),
        },
        {
          'seq': 1,
          'role': 'agent',
          'text': 'chào chủ',
          'at': now.toIso8601String(),
        },
      ],
      'waiting': true,
    };
    await pump(tester, AgentDMScreen(now: () => now));
    expect(find.text('chào chủ'), findsOneWidget);
    expect(find.text('Bot đang trả lời…'), findsOneWidget);
    expect(find.text('Sóc'), findsWidgets); // tên bot ở tiêu đề và trên tin
    await close(tester);

    // Quá 2 phút: task trả lời đã bỏ cuộc, thôi hiện "đang trả lời".
    await pump(tester, AgentDMScreen(now: () => now.add(agentReplyTimeout)));
    expect(find.text('chào chủ'), findsOneWidget);
    expect(find.text('Bot đang trả lời…'), findsNothing);

    await tester.enterText(find.byType(TextField), '  nhớ giúp mình  ');
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pump();
    await tester.pump();
    final post = backend.requests.lastWhere((r) => r.method == 'POST');
    expect(post.url.path, '/v1/agents/me/dm');
    expect(jsonDecode(post.body), {'text': 'nhớ giúp mình'});
    await close(tester);
  });

  testWidgets('room labels bots by owner and my own bot as mine', (
    tester,
  ) async {
    final at = DateTime.utc(2026, 10, 20, 8).toIso8601String();
    backend.room = {
      'messages': [
        {
          'seq': 3,
          'kind': 'agent',
          'uid': 'me',
          'name': 'Cú',
          'owner': 'Tôi',
          'text': 'ok luôn',
          'at': at,
        },
        {
          'seq': 2,
          'kind': 'agent',
          'uid': 'an',
          'name': 'Sóc',
          'owner': 'An',
          'text': 'chạy không',
          'at': at,
        },
        {
          'seq': 1,
          'kind': 'human',
          'uid': 'me',
          'name': 'Tôi',
          'text': 'chào',
          'at': at,
        },
      ],
      'members': [
        {'uid': 'an', 'name': 'An', 'botName': 'Sóc'},
        {'uid': 'me', 'name': 'Tôi', 'botName': 'Cú'},
        {'uid': 'dung', 'name': 'Dũng'},
      ],
    };
    await pump(tester, const AgentRoomScreen());
    expect(find.text('Sóc · bot của An'), findsOneWidget);
    expect(find.text('Cú · bot của bạn'), findsOneWidget);
    // Tin của chính mình không hiện tên.
    expect(find.text('Tôi'), findsNothing);

    await tester.tap(find.byTooltip('Thành viên'));
    await tester.pumpAndSettle();
    expect(find.text('Bot: Sóc'), findsOneWidget);
    expect(find.text('Chưa tạo bot'), findsOneWidget);
    await close(tester);
  });
}
