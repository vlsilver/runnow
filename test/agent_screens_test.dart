import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:myrun/src/agents/agent_blocks_screen.dart';
import 'package:myrun/src/agents/agent_chat_controller.dart';
import 'package:myrun/src/agents/agent_chat_screen.dart';
import 'package:myrun/src/agents/agent_group_facts_screen.dart';
import 'package:myrun/src/agents/agent_screen.dart';
import 'package:myrun/src/agents/agent_setup_screen.dart';
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
  var noLearn = false;
  Map<String, dynamic> dm = {'messages': [], 'waiting': false};
  Map<String, dynamic> room = {'messages': [], 'members': []};

  /// Field today của GET me; null là backend cũ chưa có field.
  Map<String, dynamic>? today;

  /// Field telegram của GET me; null là backend cũ hoặc cờ tắt.
  Map<String, dynamic>? telegram;

  /// GET /v1/telegram/link: tài khoản 3i đã liên kết Telegram chưa.
  Map<String, dynamic> telegramLink = {'linked': false};

  /// Người mình đã chặn: tin của họ (và bot của họ) trả về hidden, text rỗng.
  final blocks = <Map<String, dynamic>>[];

  /// Còn phải đồng ý AI thì lưu bot, chat riêng, nhắn phòng trả 403.
  var consentRequired = false;
  var consentVersion = 1;
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
      http.Response error(int status, String code) => http.Response(
        jsonEncode({
          'error': code,
          'message': code,
          'consentVersion': consentVersion,
        }),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      const gated = {'/v1/agents/me', '/v1/agents/me/dm', '/v1/agents/room'};
      if (consentRequired && request.method == 'POST' && gated.contains(path)) {
        return error(403, 'consent_required');
      }
      switch ((request.method, path)) {
        case ('GET', '/v1/agents/me'):
          out = {
            'enabled': true,
            'agent': agent,
            'memories': memories,
            'memoryLimit': 50,
            'learned': learned,
            'noLearn': noLearn,
            'consentRequired': consentRequired,
            'consentVersion': consentVersion,
            'today': ?today,
            'telegram': ?telegram,
          };
        case ('GET', '/v1/telegram/link'):
          out = telegramLink;
        case ('POST', '/v1/telegram/link-code'):
          out = {
            'code': 'K7Q2',
            'deepLink': 'https://t.me/runnow3i_bot?start=K7Q2',
            'expiresAt': '2026-10-22T10:00:00Z',
          };
        case ('POST', '/v1/agents/me/consent'):
          if (body['version'] != consentVersion) {
            return error(409, 'consent_version_mismatch');
          }
          consentRequired = false;
          out = {'consentRequired': false, 'consentVersion': consentVersion};
        case ('DELETE', final p) when p.startsWith('/v1/agents/me/learned/'):
          learned.removeWhere((f) => p.endsWith('/${f['id']}'));
        case ('POST', '/v1/agents/me/no-learn'):
          noLearn = body['on'] == true;
          if (noLearn) learned.clear();
          out = {'noLearn': noLearn};
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
          final after = int.tryParse(
            request.url.queryParameters['after'] ?? '',
          );
          out = after == null
              ? dm
              : {
                  'messages': [
                    for (final m in dm['messages'] as List)
                      if ((m['seq'] as int) > after) m,
                  ],
                  'waiting': dm['waiting'],
                };
        case ('GET', '/v1/agents/room'):
          final blocked = {for (final b in blocks) b['uid']};
          out = request.url.queryParameters.containsKey('after')
              ? {'messages': [], 'members': []}
              : {
                  ...room,
                  'messages': [
                    for (final m in room['messages'] as List)
                      blocked.contains(m['uid'])
                          ? {...m, 'hidden': true, 'text': ''}
                          : m,
                  ],
                };
        case ('POST', final p)
            when p.startsWith('/v1/agents/room/messages/') &&
                p.endsWith('/report'):
          if (body['block'] == true) {
            final seq = int.parse(p.split('/')[5]);
            final m = (room['messages'] as List).firstWhere(
              (m) => m['seq'] == seq,
            );
            blocks.add({'uid': m['uid'], 'name': m['owner'] ?? m['name']});
          }
        case ('GET', '/v1/agents/blocks'):
          out = {'blocks': blocks};
        case ('DELETE', final p) when p.startsWith('/v1/agents/blocks/'):
          blocks.removeWhere((b) => p.endsWith('/${b['uid']}'));
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

  /// Link màn MyBot đã mở ra ngoài app.
  late List<Uri> opened;

  setUp(() {
    backend = _AgentBackend();
    opened = [];
  });

  /// Màn MyBot cùng màn tạo/sửa bot, đủ để đi qua lại bằng go_router.
  Future<void> pumpMyBot(WidgetTester tester) async {
    // Cao như điện thoại để ListView dựng hết các mục.
    tester.view.physicalSize = const Size(420, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => AgentScreen(
            openUrl: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
        GoRoute(
          path: '/agent/setup',
          builder: (_, _) => const AgentSetupScreen(),
        ),
        GoRoute(
          path: '/agent/memories',
          builder: (_, _) => const AgentScreen(list: AgentListView.memories),
        ),
        GoRoute(
          path: '/agent/blocks',
          builder: (_, _) => const AgentBlocksScreen(),
        ),
        GoRoute(path: '/agent/dm', builder: (_, _) => const AgentDMScreen()),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('creates the bot from a preset, then adds and deletes a memory', (
    tester,
  ) async {
    await pumpMyBot(tester);
    // Chưa tạo: chưa có nút vào chat, chưa có bộ nhớ.
    expect(find.text('Tạo bot của riêng bạn'), findsOneWidget);
    expect(find.text('Chat riêng'), findsNothing);
    expect(find.text('BOT BIẾT GÌ VỀ BẠN'), findsNothing);

    await tester.tap(find.text('Tạo bot'));
    await tester.pumpAndSettle();
    expect(find.text('Bot của bạn là ai?'), findsOneWidget);
    await tester.tap(find.text('Cây hài'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo bot'));
    await tester.pumpAndSettle();
    final create = backend.requests.firstWhere(
      (r) => r.method == 'POST' && r.url.path == '/v1/agents/me',
    );
    expect(jsonDecode(create.body), {
      'name': 'Bot của Tôi',
      'persona': 'Hay đùa, cà khịa vừa phải. Nói ngắn, xưng "tui".',
    });
    // Không bị đòi đồng ý AI (allowlist): không có bước xin phép.
    expect(backend.calls, isNot(contains('POST /v1/agents/me/consent')));

    // Lưu xong quay về MyBot, giờ đã có bot.
    expect(find.text('Chat riêng'), findsOneWidget);
    expect(find.text('BOT BIẾT GÌ VỀ BẠN'), findsOneWidget);
    expect(find.text('0/50'), findsOneWidget);

    await tester.tap(find.text('Thêm điều cần nhớ'));
    await tester.pumpAndSettle();
    // Bộ nhớ đi cả vào phòng: nói rõ lúc chủ đang gõ.
    expect(
      find.text('Mọi thành viên trong phòng bot đều đọc được.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, '  Chạy sáng thứ 7  ');
    await tester.tap(find.text('Lưu').last);
    await tester.pumpAndSettle();
    expect(backend.memories.single['text'], 'Chạy sáng thứ 7');
    expect(find.text('Chạy sáng thứ 7'), findsOneWidget);
    expect(find.text('1/50'), findsOneWidget);

    // Ở tab không có nút xoá từng mục: chạm vào mục để sửa hoặc xoá.
    expect(find.byTooltip('Xoá'), findsNothing);
    await tester.tap(find.text('Chạy sáng thứ 7'));
    await tester.pumpAndSettle();
    expect(find.text('Sửa mục nhớ'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Xoá'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('DELETE /v1/agents/me/memories/m1'));
    expect(find.text('0/50'), findsOneWidget);
  });

  testWidgets('tab shows the DM count of today, rereads it after chatting', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.today = {
      'dmUsed': 3,
      'dmMax': 100,
      'roomUsed': 12,
      'roomMax': 300,
      'resting': null,
    };
    await pumpMyBot(tester);
    expect(find.text('3/100'), findsOneWidget);
    expect(find.text('tin hôm nay'), findsOneWidget);
    expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);

    // Bot trả lời một câu trong lúc chủ ở màn chat: quay về thấy số mới.
    await tester.tap(find.text('Chat riêng'));
    await tester.pumpAndSettle();
    backend.today = {...?backend.today, 'dmUsed': 4};
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('4/100'), findsOneWidget);
  });

  testWidgets('budget resting puts the bot to sleep, chat still opens', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    // Cả hai cùng chạm thì backend báo budget; app chỉ báo nghỉ vì budget.
    backend.today = {
      'dmUsed': 100,
      'dmMax': 100,
      'roomUsed': 0,
      'roomMax': 300,
      'resting': 'budget',
    };
    await pumpMyBot(tester);
    expect(find.text('Cú đang nghỉ'), findsOneWidget);
    expect(find.text('MyBot chạm trần chi phí hôm nay.'), findsOneWidget);
    expect(find.text('QUAY LẠI LÚC 0H'), findsOneWidget);
    expect(find.byIcon(Icons.bedtime_outlined), findsOneWidget);
    expect(find.text('HẾT TIN · MỞ LẠI 0H'), findsNothing);

    await tester.tap(find.text('Chat riêng'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentDMScreen), findsOneWidget);
    await close(tester);
  });

  testWidgets('dm_limit resting says chat reopens at midnight', (tester) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.today = {
      'dmUsed': 30,
      'dmMax': 30,
      'roomUsed': 0,
      'roomMax': 300,
      'resting': 'dm_limit',
    };
    await pumpMyBot(tester);
    expect(find.text('30/30'), findsOneWidget);
    expect(find.text('HẾT TIN · MỞ LẠI 0H'), findsOneWidget);
    // Hết tin chat riêng thì bot vẫn nói trong phòng, nên không ngủ.
    expect(find.text('Cú'), findsOneWidget);
    expect(find.text('Cú đang nghỉ'), findsNothing);
  });

  // 4,1 km: 10 câu sẵn + 4 km × 10 = 50 tin; mốc 1 km = 3 ảnh. Mốc kế tiếp
  // của tin và ảnh cùng ở 5 km: 60 − 50 = 10 tin, 5 − 3 = 2 ảnh, 5 − 4,1 = 0,9.
  testWidgets(
    'km card: 4,1 km opens 50 messages and 3 images, says what is next',
    (tester) async {
      backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
      backend.today = {
        'dmUsed': 0,
        'dmMax': 50,
        'roomUsed': 0,
        'roomMax': 300,
        'resting': null,
        'dmByKm': {
          'base': 10,
          'perKm': 10,
          'runKm': 4.1,
          'nextKm': 5,
          'nextMax': 60,
        },
        'images': {
          'used': 1,
          'limit': 3,
          'runKm': 4.1,
          'nextKm': 5,
          'nextLimit': 5,
        },
      };
      await pumpMyBot(tester);
      expect(find.text('KM HÔM NAY'), findsOneWidget);
      expect(find.text('4,1'), findsOneWidget);
      expect(find.text('50 tin chat'), findsOneWidget);
      expect(find.text('10 sẵn + 40 từ 4 km'), findsOneWidget);
      expect(find.text('3 ảnh vẽ'), findsOneWidget);
      expect(find.text('đã vẽ 1'), findsOneWidget);
      expect(
        find.text(
          'Chạy hay đi bộ thêm 0,9 km để có thêm 10 tin và 2 ảnh.',
          findRichText: true,
        ),
        findsOneWidget,
      );
    },
  );

  // Số km còn thiếu tính tay: 5 − 2,6 = 2,4; 5 − 4,1 = 0,9; 1 − 0 = 1. Ảnh
  // thêm: 5 − 3 = 2, 3 − 0 = 3.
  for (final (runKm, nextKm, nextLimit, used, limit, progress) in [
    (2.6, 5, 5, 1, 3, 'Chạy hay đi bộ thêm 2,4 km để vẽ thêm 2 ảnh.'),
    (4.1, 5, 5, 3, 3, 'Chạy hay đi bộ thêm 0,9 km để vẽ thêm 2 ảnh.'),
    (0.0, 1, 3, 0, 0, 'Chạy hay đi bộ thêm 1 km để vẽ thêm 3 ảnh.'),
  ]) {
    testWidgets('ran $runKm km: shows $used/$limit images and "$progress"', (
      tester,
    ) async {
      backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
      backend.today = {
        'dmUsed': 0,
        'dmMax': 100,
        'roomUsed': 0,
        'roomMax': 300,
        'resting': null,
        'images': {
          'used': used,
          'limit': limit,
          'runKm': runKm,
          'nextKm': nextKm,
          'nextLimit': nextLimit,
        },
      };
      await pumpMyBot(tester);
      expect(find.text('$used/$limit'), findsOneWidget);
      expect(find.text('ảnh hôm nay'), findsOneWidget);
      expect(find.text(progress, findRichText: true), findsOneWidget);
      // Backend chưa trả dmByKm thì không đoán số tin theo km.
      expect(find.textContaining('tin chat'), findsNothing);
    });
  }

  // Số tính tay theo 10 câu sẵn + 10 câu mỗi km, mốc ảnh 1 km → 3, 5 → 5,
  // 10 → 10. 4,96 km hiện 4,9 (làm tròn xuống) mà còn thiếu 0,1 (làm tròn lên).
  for (final (name, today, texts) in [
    (
      '0 km',
      {
        'dmMax': 10,
        'dmByKm': {
          'base': 10,
          'perKm': 10,
          'runKm': 0,
          'nextKm': 1,
          'nextMax': 20,
        },
        'images': {
          'used': 0,
          'limit': 0,
          'runKm': 0,
          'nextKm': 1,
          'nextLimit': 3,
        },
      },
      [
        '10 tin chat',
        '10 sẵn mỗi ngày',
        '0 ảnh vẽ',
        'Chạy hay đi bộ đủ 1 km để mở',
        'Chạy hay đi bộ thêm 1 km để có thêm 10 tin và 3 ảnh.',
      ],
    ),
    (
      '9,5 km, tin chạm trần',
      {
        'dmMax': 100,
        'dmByKm': {
          'base': 10,
          'perKm': 10,
          'runKm': 9.5,
          'nextKm': null,
          'nextMax': null,
        },
        'images': {
          'used': 2,
          'limit': 5,
          'runKm': 9.5,
          'nextKm': 10,
          'nextLimit': 10,
        },
      },
      [
        '9,5',
        '100 tin chat',
        'Đã đủ tối đa 100 tin',
        '5 ảnh vẽ',
        'Chạy hay đi bộ thêm 0,5 km để vẽ thêm 5 ảnh.',
      ],
    ),
    (
      '12,3 km, hết mốc',
      {
        'dmMax': 100,
        'dmByKm': {
          'base': 10,
          'perKm': 10,
          'runKm': 12.3,
          'nextKm': null,
          'nextMax': null,
        },
        'images': {
          'used': 4,
          'limit': 10,
          'runKm': 12.3,
          'nextKm': null,
          'nextLimit': null,
        },
      },
      ['12,3', 'Mốc cao nhất', 'Đã mở hết tin và ảnh hôm nay.'],
    ),
    (
      'admin tắt thưởng km',
      {
        'dmMax': 10,
        'dmByKm': {
          'base': 10,
          'perKm': 0,
          'runKm': 3.0,
          'nextKm': null,
          'nextMax': null,
        },
        'images': {
          'used': 0,
          'limit': 3,
          'runKm': 3.0,
          'nextKm': 5,
          'nextLimit': 5,
        },
      },
      ['3', '3 ảnh vẽ', 'Chạy hay đi bộ thêm 2 km để vẽ thêm 2 ảnh.'],
    ),
    (
      '4,96 km, tắt vẽ ảnh',
      {
        'dmMax': 50,
        'dmByKm': {
          'base': 10,
          'perKm': 10,
          'runKm': 4.96,
          'nextKm': 5,
          'nextMax': 60,
        },
      },
      [
        '4,9',
        '50 tin chat',
        '10 sẵn + 40 từ 4 km',
        'Chạy hay đi bộ thêm 0,1 km để có thêm 10 tin.',
      ],
    ),
  ]) {
    testWidgets('km card $name', (tester) async {
      backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
      backend.today = {
        'dmUsed': 0,
        'roomUsed': 0,
        'roomMax': 300,
        'resting': null,
        ...today,
      };
      await pumpMyBot(tester);
      expect(find.text('KM HÔM NAY'), findsOneWidget);
      for (final text in texts) {
        expect(
          find.text(text, findRichText: true),
          findsOneWidget,
          reason: text,
        );
      }
      if (!today.containsKey('images')) {
        expect(find.textContaining('ảnh vẽ'), findsNothing);
      }
      if (name == 'admin tắt thưởng km') {
        expect(find.textContaining('tin chat'), findsNothing);
      }
      if (name == '9,5 km, tin chạm trần') {
        expect(find.textContaining('thêm 0,5 km để có thêm'), findsNothing);
      }
    });
  }

  testWidgets('top image tier: no km to go, old backend: no image stat', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    final today = {
      'dmUsed': 0,
      'dmMax': 100,
      'roomUsed': 0,
      'roomMax': 300,
      'resting': null,
    };
    backend.today = {
      ...today,
      'images': {
        'used': 4,
        'limit': 10,
        'runKm': 12.3,
        'nextKm': null,
        'nextLimit': null,
      },
    };
    await pumpMyBot(tester);
    expect(find.text('4/10'), findsOneWidget);
    expect(find.textContaining('đi bộ thêm'), findsNothing);
    expect(
      find.text('Đã mở hết ảnh hôm nay.', findRichText: true),
      findsOneWidget,
    );

    backend.today = today;
    await tester.tap(find.text('Chat riêng'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('ảnh hôm nay'), findsNothing);
    expect(find.text('0/100'), findsOneWidget);
    expect(find.text('KM HÔM NAY'), findsNothing);
  });

  testWidgets('old backend without today: no quota, no banner', (tester) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    await pumpMyBot(tester);
    expect(find.text('Chat riêng'), findsOneWidget);
    expect(find.text('tin hôm nay'), findsNothing);
    expect(find.byIcon(Icons.bedtime_outlined), findsNothing);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
  });

  const createUrl = 'https://t.me/newbot/Run3IBot/cu_42_bot?name=C%C3%BA';
  Map<String, dynamic> botOnTelegram() => {
    'createUrl': createUrl,
    'botUsername': 'cu_42_bot',
    'linked': true,
  };
  int meReads() => backend.calls.where((c) => c == 'GET /v1/agents/me').length;
  void resumeApp(WidgetTester tester) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  testWidgets('no telegram field: no Telegram section, no link lookup', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    await pumpMyBot(tester);
    expect(find.text('Chat riêng'), findsOneWidget);
    expect(find.textContaining('Telegram'), findsNothing);
    expect(backend.calls, isNot(contains('GET /v1/telegram/link')));

    // Quay về app: đọc lại hồ sơ một lần cho km và số tin, không hỏi liên
    // kết Telegram, không đọc lần hai.
    final reads = meReads();
    resumeApp(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(meReads(), reads + 1);
    expect(backend.calls, isNot(contains('GET /v1/telegram/link')));
  });

  testWidgets('bot running on Telegram opens t.me/<username>', (tester) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.telegram = botOnTelegram();
    await pumpMyBot(tester);
    expect(find.text('@cu_42_bot'), findsOneWidget);
    expect(find.text('Chat và vẽ ảnh trên Telegram'), findsOneWidget);

    await tester.tap(find.text('Mở'));
    await tester.pump();
    expect(opened, [Uri.parse('https://t.me/cu_42_bot')]);
  });

  testWidgets('broken bot offers to recreate it through createUrl', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.telegram = {
      ...botOnTelegram(),
      'setupError': 'Forbidden: bot was deleted',
    };
    await pumpMyBot(tester);
    expect(find.text('Bot Telegram bị lỗi'), findsOneWidget);
    expect(find.text('Mở'), findsNothing);

    await tester.tap(find.text('Tạo lại'));
    await tester.pump();
    expect(opened, [Uri.parse(createUrl)]);
  });

  testWidgets('no bot yet, Telegram linked: opens createUrl', (tester) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.telegram = {'createUrl': createUrl, 'linked': false};
    backend.telegramLink = {'linked': true, 'tgUsername': 'an'};
    await pumpMyBot(tester);
    expect(find.text('Chat và vẽ ảnh trên Telegram'), findsOneWidget);

    await tester.tap(find.text('Đưa bot lên Telegram'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(createUrl)]);
    expect(backend.calls, isNot(contains('POST /v1/telegram/link-code')));
  });

  testWidgets('no bot yet, Telegram not linked: links first, then creates', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.telegram = {'createUrl': createUrl, 'linked': false};
    await pumpMyBot(tester);
    expect(find.text('Liên kết Telegram trước, rồi bấm lại'), findsOneWidget);

    await tester.tap(find.text('Đưa bot lên Telegram'));
    await tester.pump();
    await tester.pump();
    expect(opened, [Uri.parse('https://t.me/runnow3i_bot?start=K7Q2')]);
    expect(find.text('Bấm Start trong Telegram rồi quay lại'), findsOneWidget);

    // Bấm Start bên Telegram rồi quay lại; bấm lần nữa thì mới tạo bot.
    backend.telegramLink = {'linked': true, 'tgUsername': 'an'};
    resumeApp(tester);
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Đưa bot lên Telegram'));
    await tester.pump();
    expect(opened.last, Uri.parse(createUrl));
    await close(tester);
  });

  // Chạy xong (Strava đồng bộ) rồi quay lại app: thẻ km và số tin theo kịp.
  testWidgets('back in the app, the km card is read again', (tester) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    Map<String, dynamic> today(double runKm, int dmMax, int nextMax) => {
      'dmUsed': 10,
      'dmMax': dmMax,
      'roomUsed': 0,
      'roomMax': 300,
      'resting': null,
      'dmByKm': {
        'base': 10,
        'perKm': 10,
        'runKm': runKm,
        'nextKm': runKm.floor() + 1,
        'nextMax': nextMax,
      },
    };
    backend.today = today(0, 10, 20);
    await pumpMyBot(tester);
    expect(find.text('10 tin chat'), findsOneWidget);

    backend.today = today(3.2, 40, 50);
    resumeApp(tester);
    await tester.pump();
    await tester.pump();
    expect(find.text('3,2'), findsOneWidget);
    expect(find.text('40 tin chat'), findsOneWidget);
    expect(find.text('10/40'), findsOneWidget);
  });

  testWidgets('returning from Telegram rereads me, once more after a delay', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.telegram = {'createUrl': createUrl, 'linked': false};
    backend.telegramLink = {'linked': true, 'tgUsername': 'an'};
    await pumpMyBot(tester);
    final reads = meReads();

    // Quay về lúc backend chưa nối xong bot: vẫn chưa có bot.
    resumeApp(tester);
    await tester.pump();
    await tester.pump();
    expect(meReads(), reads + 1);
    expect(find.text('Đưa bot lên Telegram'), findsOneWidget);

    backend.telegram = botOnTelegram();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(meReads(), reads + 2);
    expect(find.text('@cu_42_bot'), findsOneWidget);

    // Quay về lần nữa lúc bot đã chạy: đọc lại một lần vì km và số tin có thể
    // đã đổi, nhưng không đọc lần hai sau ít giây.
    resumeApp(tester);
    await tester.pump(const Duration(minutes: 1));
    expect(meReads(), reads + 3);
    expect(find.text('Đưa bot vào group PSC'), findsNothing);
  });

  testWidgets('Phòng bot on: adds the bot to PSC, rereads me on return', (
    tester,
  ) async {
    const join = 'https://t.me/cu_42_bot?startgroup=psc';
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.telegram = {...botOnTelegram(), 'pscJoinUrl': join, 'inPsc': false};
    await pumpMyBot(tester);
    final button = find.text('Đưa bot vào group PSC');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    expect(opened, [Uri.parse(join)]);

    // Thêm bot vào PSC bên Telegram rồi quay lại.
    final reads = meReads();
    backend.telegram = {...botOnTelegram(), 'pscJoinUrl': join, 'inPsc': true};
    resumeApp(tester);
    await tester.pump();
    await tester.pump();
    expect(meReads(), reads + 1);
    expect(find.text('Đưa bot vào group PSC'), findsNothing);
    expect(find.text('Ở GROUP PSC'), findsOneWidget);

    // Đã ở PSC: quay về chỉ đọc lại một lần, không đọc lần hai.
    await tester.pump(const Duration(seconds: 5));
    final after = meReads();
    resumeApp(tester);
    await tester.pump(const Duration(minutes: 1));
    expect(meReads(), after + 1);
  });

  testWidgets('tab shows three memories, the full list shows all', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    for (var i = 1; i <= 4; i++) {
      backend.memories.add({'id': 'm$i', 'text': 'Mục $i', 'source': 'manual'});
    }
    await pumpMyBot(tester);
    expect(find.text('Mục 3'), findsOneWidget);
    expect(find.text('Mục 4'), findsNothing);

    await tester.tap(find.text('Xem tất cả'));
    await tester.pumpAndSettle();
    expect(find.text('Mục 4'), findsOneWidget);
    expect(find.byTooltip('Xoá'), findsNWidgets(4));
    await tester.tap(find.byTooltip('Xoá').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xoá').last);
    await tester.pumpAndSettle();
    expect(backend.calls, contains('DELETE /v1/agents/me/memories/m4'));
    expect(find.text('Mục 4'), findsNothing);
  });

  testWidgets('edits the bot and previews the two newest room messages', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': 'Nói ngắn', 'created': true};
    final at = DateTime.utc(2026, 10, 20, 8).toIso8601String();
    // Phòng trả tin mới trước. Tin mới nhất là của người đã chặn: bỏ qua.
    backend.room = {
      'messages': [
        {
          'seq': 4,
          'kind': 'human',
          'uid': 'binh',
          'name': 'Bình',
          'text': '',
          'hidden': true,
          'at': at,
        },
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
          'uid': 'an',
          'name': 'An',
          'text': 'chào cả nhà',
          'at': at,
        },
      ],
      'members': [
        {'uid': 'an', 'name': 'An', 'botName': 'Sóc'},
        {'uid': 'me', 'name': 'Tôi', 'botName': 'Cú'},
        {'uid': 'dung', 'name': 'Dũng'},
      ],
    };
    await pumpMyBot(tester);
    expect(find.text('Nói ngắn'), findsOneWidget);
    expect(find.text('2 bot đang ở phòng'), findsOneWidget);
    expect(find.text('chào cả nhà'), findsNothing);
    final older = tester.getTopLeft(find.text('Sóc · bot của An'));
    final newer = tester.getTopLeft(find.text('Cú · bot của bạn'));
    expect(older.dy, lessThan(newer.dy));

    await tester.tap(find.byTooltip('Sửa bot'));
    await tester.pumpAndSettle();
    expect(find.text('Sửa bot'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Cú'), findsOneWidget);
    final name = find.byType(TextField).first;
    await tester.enterText(name, '   ');
    await tester.pump();
    // Tên trống thì không cho lưu, backend cũng từ chối.
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Lưu'))
          .onPressed,
      isNull,
    );
    await tester.enterText(name, 'Cú Mèo');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Lưu'));
    await tester.pumpAndSettle();
    final save = backend.requests.lastWhere((r) => r.method == 'POST');
    expect(jsonDecode(save.body), {'name': 'Cú Mèo', 'persona': 'Nói ngắn'});
    expect(find.text('Cú Mèo'), findsOneWidget);
  });

  testWidgets('shows what the bot learned and forgets on request', (
    tester,
  ) async {
    backend.learned.addAll([
      {'id': 'f1', 'text': 'Mê chạy trail', 'source': 'learned'},
      {'id': 'tg-f2', 'text': 'Đi giày Pegasus', 'source': 'migrated'},
    ]);
    // Chưa tạo bot vẫn thấy điều bot học được từ group Telegram.
    await pumpMyBot(tester);
    expect(find.text('BOT TỰ HỌC VỀ BẠN'), findsOneWidget);
    expect(find.text('Từ trí nhớ cũ của 3i'), findsOneWidget);
    expect(find.text('Bot biết gì về nhóm'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Quên').last);
    await tester.pumpAndSettle();
    expect(find.text('Cho bot quên điều này?'), findsOneWidget);
    await tester.tap(find.text('Quên').last);
    await tester.pumpAndSettle();
    expect(backend.calls, contains('DELETE /v1/agents/me/learned/tg-f2'));
    expect(find.text('Đi giày Pegasus'), findsNothing);
    expect(find.text('Mê chạy trail'), findsOneWidget);
  });

  testWidgets('turning learning off asks first, on again does not', (
    tester,
  ) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.learned.addAll([
      {'id': 'f1', 'text': 'Mê chạy trail', 'source': 'learned'},
      {'id': 'f2', 'text': 'Đi giày Pegasus', 'source': 'learned'},
    ]);
    await pumpMyBot(tester);
    bool switchOn() =>
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value;
    expect(switchOn(), isTrue);
    expect(find.text('ĐANG TỰ HỌC'), findsOneWidget);

    await tester.tap(find.text('Cho bot tự học về bạn'));
    await tester.pumpAndSettle();
    expect(
      find.text('Bot xoá 2 điều đã học về bạn và không học thêm.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Tắt'));
    await tester.pumpAndSettle();
    final off = backend.requests.lastWhere((r) => r.method == 'POST');
    expect(off.url.path, '/v1/agents/me/no-learn');
    expect(jsonDecode(off.body), {'on': true});
    expect(switchOn(), isFalse);
    expect(find.text('Mê chạy trail'), findsNothing);
    expect(find.text('Bot không tự học về bạn.'), findsOneWidget);
    expect(find.text('ĐANG TỰ HỌC'), findsNothing);

    await tester.tap(find.text('Cho bot tự học về bạn'));
    await tester.pumpAndSettle();
    expect(find.text('Tắt tự học?'), findsNothing);
    final on = backend.requests.lastWhere((r) => r.method == 'POST');
    expect(jsonDecode(on.body), {'on': false});
    expect(switchOn(), isTrue);
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

  testWidgets('DM shows messages left today, rereads it when the bot replies', (
    tester,
  ) async {
    final now = DateTime.utc(2026, 10, 20, 8);
    Map<String, dynamic> message(int seq, String role, String text) => {
      'seq': seq,
      'role': role,
      'text': text,
      'at': now.toIso8601String(),
    };
    backend.agent = {'name': 'Sóc', 'persona': '', 'created': true};
    backend.today = {
      'dmUsed': 82,
      'dmMax': 100,
      'roomUsed': 0,
      'roomMax': 300,
      'resting': null,
    };
    backend.dm = {
      'messages': [message(1, 'agent', 'chào chủ')],
      'waiting': false,
    };
    await pump(tester, AgentDMScreen(now: () => now));
    expect(find.text('Chat riêng · chỉ bạn thấy'), findsOneWidget);
    expect(find.text('Còn 18 tin'), findsOneWidget);

    // Bot trả lời một câu: backend đếm thêm một lượt.
    backend.dm = {
      'messages': [
        message(3, 'agent', 'nhớ rồi'),
        message(2, 'user', 'nhớ giúp mình'),
        message(1, 'agent', 'chào chủ'),
      ],
      'waiting': false,
    };
    backend.today = {...?backend.today, 'dmUsed': 83};
    await tester.pump(AgentChatController.pollEvery);
    await tester.pump();
    await tester.pump();
    expect(find.text('nhớ rồi'), findsOneWidget);
    expect(find.text('Còn 17 tin'), findsOneWidget);
    await close(tester);
  });

  // 5 − 4,1 = 0,9 km; 60 − 50 = 10 tin.
  for (final (name, dmByKm, title, detail) in [
    (
      'still a km milestone',
      {'base': 10, 'perKm': 10, 'runKm': 4.1, 'nextKm': 5, 'nextMax': 60},
      'Hết 50 tin hôm nay',
      'Chạy hay đi bộ thêm 0,9 km để có thêm 10 tin. Không thì 0h mở lại.',
    ),
    (
      'already at the cap',
      {'base': 10, 'perKm': 10, 'runKm': 12.0, 'nextKm': null, 'nextMax': null},
      'Hết 50 tin hôm nay',
      'Đã mở tối đa. Chat lại được lúc 0h, bot vẫn nói trong phòng bot.',
    ),
    (
      'old backend',
      null,
      'Hết 50 tin hôm nay',
      'Chat lại được lúc 0h. Bot vẫn nói trong phòng bot.',
    ),
  ]) {
    testWidgets('DM out of messages, $name: "$detail"', (tester) async {
      backend.agent = {'name': 'Sóc', 'persona': '', 'created': true};
      backend.today = {
        'dmUsed': 50,
        'dmMax': 50,
        'roomUsed': 0,
        'roomMax': 300,
        'resting': 'dm_limit',
        'dmByKm': ?dmByKm,
      };
      backend.dm = {'messages': [], 'waiting': false};
      await pump(tester, const AgentDMScreen());
      expect(find.text(title), findsOneWidget);
      expect(find.text(detail), findsOneWidget);
      expect(
        find.byIcon(Icons.trending_up_rounded),
        name == 'still a km milestone' ? findsOneWidget : findsNothing,
      );
      await close(tester);
    });
  }

  testWidgets('DM at the daily limit locks the composer until midnight', (
    tester,
  ) async {
    backend.agent = {'name': 'Sóc', 'persona': '', 'created': true};
    backend.today = {
      'dmUsed': 30,
      'dmMax': 30,
      'roomUsed': 0,
      'roomMax': 300,
      'resting': 'dm_limit',
    };
    backend.dm = {'messages': [], 'waiting': false};
    await pump(tester, const AgentDMScreen());
    expect(find.text('Hết 30 tin hôm nay'), findsOneWidget);
    expect(find.textContaining('Còn '), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pump();
    expect(backend.calls, isNot(contains('POST /v1/agents/me/dm')));
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

  testWidgets('room hides blocked senders and reports others, not mine', (
    tester,
  ) async {
    final at = DateTime.utc(2026, 10, 20, 8).toIso8601String();
    backend.room = {
      'messages': [
        {
          'seq': 5,
          'kind': 'human',
          'uid': 'binh',
          'name': 'Bình',
          'text': '',
          'hidden': true,
          'at': at,
        },
        {
          'seq': 4,
          'kind': 'agent',
          'uid': 'me',
          'name': 'Cú',
          'owner': 'Tôi',
          'text': 'ok luôn',
          'at': at,
        },
        {
          'seq': 3,
          'kind': 'agent',
          'uid': 'an',
          'name': 'Sóc',
          'owner': 'An',
          'text': 'chạy không',
          'at': at,
        },
        {
          'seq': 2,
          'kind': 'human',
          'uid': 'an',
          'name': 'An',
          'text': 'chào cả nhà',
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
      ],
    };
    await pump(tester, const AgentRoomScreen());
    // Tin ẩn vẫn nằm trong trang nhưng không vẽ.
    expect(find.text('Bình'), findsNothing);
    expect(find.text('ok luôn'), findsOneWidget);

    // Tin của mình và của bot mình: không có menu báo cáo.
    for (final mine in ['chào', 'ok luôn']) {
      await tester.longPress(find.text(mine));
      await tester.pumpAndSettle();
      expect(find.text('Báo cáo tin này'), findsNothing);
    }

    await tester.longPress(find.text('chạy không'));
    await tester.pumpAndSettle();
    // Tin của bot: chặn là chặn chủ bot.
    expect(find.text('Báo cáo và chặn An'), findsOneWidget);
    await tester.tap(find.text('Báo cáo tin này'));
    await tester.pumpAndSettle();
    var report = backend.requests.lastWhere((r) => r.method == 'POST');
    expect(report.url.path, '/v1/agents/room/messages/3/report');
    expect(jsonDecode(report.body), {'block': false});
    expect(find.text('Đã báo cáo'), findsOneWidget);
    expect(find.text('chạy không'), findsOneWidget);
    // Chờ snackbar trước tắt, snackbar sau mới hiện.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('chạy không'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Báo cáo và chặn An'));
    await tester.pumpAndSettle();
    report = backend.requests.lastWhere((r) => r.method == 'POST');
    expect(report.url.path, '/v1/agents/room/messages/3/report');
    expect(jsonDecode(report.body), {'block': true});
    expect(find.text('Đã báo cáo và chặn'), findsOneWidget);
    // Ẩn ngay cả tin của An lẫn bot của An, không chờ mở lại phòng.
    expect(find.text('chạy không'), findsNothing);
    expect(find.text('chào cả nhà'), findsNothing);
    expect(find.text('ok luôn'), findsOneWidget);
    await close(tester);
  });

  testWidgets('blocked list from the MyBot tab unblocks', (tester) async {
    backend.agent = {'name': 'Cú', 'persona': '', 'created': true};
    backend.blocks.add({'uid': 'an', 'name': 'An'});
    await pumpMyBot(tester);
    await tester.tap(find.text('Người đã chặn'));
    await tester.pumpAndSettle();
    expect(find.text('An'), findsOneWidget);

    await tester.tap(find.text('Bỏ chặn'));
    await tester.pumpAndSettle();
    expect(backend.calls, contains('DELETE /v1/agents/blocks/an'));
    expect(find.text('An'), findsNothing);
    expect(find.text('Bạn chưa chặn ai.'), findsOneWidget);
  });

  testWidgets('asks for AI consent with the server version before creating', (
    tester,
  ) async {
    backend.consentRequired = true;
    backend.consentVersion = 3;
    await pumpMyBot(tester);
    await tester.tap(find.text('Tạo bot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cây hài'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Tạo bot'));
    await tester.pumpAndSettle();
    expect(find.text('Trước khi bắt đầu'), findsOneWidget);
    expect(find.text('Bot của Tôi chạy bằng AI.'), findsOneWidget);

    // Để sau: về màn tạo bot, chưa tạo gì.
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(find.text('Bot của bạn là ai?'), findsOneWidget);
    expect(backend.calls, isNot(contains('POST /v1/agents/me')));
    expect(backend.calls, isNot(contains('POST /v1/agents/me/consent')));

    await tester.tap(find.widgetWithText(FilledButton, 'Tạo bot'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cho bot tự học về tôi'));
    await tester.pump();
    await tester.tap(find.text('Đồng ý và tạo bot'));
    await tester.pumpAndSettle();
    final posts = [
      for (final r in backend.requests)
        if (r.method == 'POST') [r.url.path, jsonDecode(r.body)],
    ];
    // Đồng ý trước rồi mới tạo bot, đúng thứ tự backend đòi.
    expect(posts, [
      [
        '/v1/agents/me/consent',
        {'version': 3},
      ],
      [
        '/v1/agents/me/no-learn',
        {'on': true},
      ],
      [
        '/v1/agents/me',
        {
          'name': 'Bot của Tôi',
          'persona': 'Hay đùa, cà khịa vừa phải. Nói ngắn, xưng "tui".',
        },
      ],
    ]);
    expect(find.text('Chat riêng'), findsOneWidget);
  });

  testWidgets('a gated send asks for consent, rereads a new version, retries', (
    tester,
  ) async {
    backend.agent = {'name': 'Sóc', 'persona': '', 'created': true};
    backend.consentRequired = true;
    await pump(tester, const AgentDMScreen());
    await tester.enterText(find.byType(TextField), 'chào');
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pumpAndSettle();
    expect(find.text('Sóc chạy bằng AI.'), findsOneWidget);

    // Điều khoản lên bản mới trong lúc màn đang mở.
    backend.consentVersion = 2;
    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();
    expect(find.text('Trước khi bắt đầu'), findsOneWidget);
    await tester.tap(find.text('Đồng ý'));
    await tester.pumpAndSettle();

    final consents = [
      for (final r in backend.requests)
        if (r.url.path == '/v1/agents/me/consent') jsonDecode(r.body),
    ];
    expect(consents, [
      {'version': 1},
      {'version': 2},
    ]);
    expect(find.text('Trước khi bắt đầu'), findsNothing);
    // Gửi lại đúng một lần sau khi đồng ý.
    final sends = backend.requests.where(
      (r) => r.method == 'POST' && r.url.path == '/v1/agents/me/dm',
    );
    expect(sends.length, 2);
    expect(jsonDecode(sends.last.body), {'text': 'chào'});
    expect(find.widgetWithText(TextField, 'chào'), findsNothing);
    await close(tester);
  });
}
