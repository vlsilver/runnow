import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/widgets/run_now_empty.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/games/game_card_art.dart';
import 'package:myrun/src/games/game_journal.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_chat_seen.dart';
import 'package:myrun/src/games/game_detail_screen.dart';
import 'package:myrun/src/games/game_invite_share.dart';
import 'package:myrun/src/games/game_links.dart';
import 'package:myrun/src/games/game_my_card.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/push.dart';
import 'package:myrun/src/theme.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

import 'support/fake_game_backend.dart';

class _FakeUser implements User {
  @override
  String get uid => 'me';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Bảng chia sẻ của máy: ghi lại thứ được gửi đi.
class _FakeShare extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// Thẻ đã khoe một lần: mọi bộ màu của [cardId] đều có sẵn ba file.
class _SavedShareStore extends CardShareStore {
  _SavedShareStore(this.cardId, this.files);

  final String cardId;
  final CardShareFiles files;
  final loaded = <String>[];
  int saves = 0;

  @override
  Future<CardShareFiles?> load(String cardId, String key) async {
    loaded.add(cardId);
    return cardId == this.cardId ? files : null;
  }

  @override
  Future<void> save(String cardId, String key, CardShareFiles files) async =>
      saves++;
}

/// Ảnh PNG 1x1 thật, vì màn khoe vẽ ảnh từ byte.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Kho thẻ đã lật trong bộ nhớ, như secure storage trên máy.
class _MemoryChatSeen extends GameChatSeen {
  _MemoryChatSeen(this.value);
  int? value;

  @override
  Future<int?> seen(String uid, String gameId, String chatKey) async => value;
}

class _MemoryReveals extends GameCardReveals {
  _MemoryReveals({required this.revealedAll});
  final bool revealedAll;
  final marked = <String>[];

  @override
  Future<bool> revealed(String uid, String gameId) async =>
      revealedAll || marked.contains('$uid/$gameId');

  @override
  Future<void> markRevealed(String uid, String gameId) async =>
      marked.add('$uid/$gameId');
}

class _SpyPush extends Fake implements PushController {
  int asks = 0;

  @override
  Future<void> askAfterJoining() async => asks++;
}

void main() {
  late DateTime now;
  late _MemoryReveals reveals;
  late FakeGameBackend backend;
  late _SpyPush push;
  late List<Uri> opened;
  late bool openOk;
  late CardShareStore shareStore;
  final share = _FakeShare();

  setUpAll(() => SharePlatform.instance = share);

  Future<void> pumpScreen(
    WidgetTester tester, {
    ThemeData? theme,
    GameChatSeen? chatSeen,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
          pushControllerProvider.overrideWithValue(push),
          cardShareStoreProvider.overrideWithValue(shareStore),
          gameCardRevealsProvider.overrideWithValue(reveals),
          gameChatSeenProvider.overrideWithValue(
            chatSeen ?? _MemoryChatSeen(null),
          ),
        ],
        child: MaterialApp(
          theme: theme,
          home: GameDetailScreen(
            gameId: 'g1',
            clock: () => now,
            openUrl: (uri) async {
              opened.add(uri);
              return openOk;
            },
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> elapse(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(d);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  Future<void> openRules(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Luật chơi'));
    await tester.pumpAndSettle();
  }

  setUp(() {
    push = _SpyPush();
    now = DateTime.utc(2026, 10, 17, 14);
    backend = FakeGameBackend(() => now);
    opened = [];
    openOk = true;
    reveals = _MemoryReveals(revealedAll: true);
    shareStore = _SavedShareStore(
      '',
      CardShareFiles(
        front: _png,
        back: _png,
        motion: Uint8List(0),
        motionType: 'video/mp4',
      ),
    );
  });

  testWidgets('follows rules text from backend', (tester) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 30,
      'rulesText': 'Sói cắn mỗi đêm.',
    };
    await pumpScreen(tester);
    expect(find.text('Sói cắn mỗi đêm.'), findsNothing);
    await openRules(tester);
    expect(find.text('Sói cắn mỗi đêm.'), findsOneWidget);
    expect(find.text('Thiết lập ván'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();

    backend.game['rulesText'] = 'Sói cắn mỗi đêm, trừ đêm đầu.';
    await elapse(tester, const Duration(seconds: 30));
    await openRules(tester);

    expect(find.text('Sói cắn mỗi đêm.'), findsNothing);
    expect(find.text('Sói cắn mỗi đêm, trừ đêm đầu.'), findsOneWidget);
    await close(tester);
  });

  for (final status in ['registering', 'running', 'ended']) {
    testWidgets('the rules button is on the bar while $status', (tester) async {
      backend.game = {
        'id': 'g1',
        'title': 'Ma Sói tuần 42',
        'status': status,
        'statusLabel': status,
        'refreshAfterSeconds': 30,
        'rulesText': 'Sói cắn mỗi đêm.',
      };
      await pumpScreen(tester);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('Luật chơi'),
        ),
        findsOneWidget,
      );
      await close(tester);
    });
  }

  testWidgets('rules card draws backend rows instead of the long text', (
    tester,
  ) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 30,
      'rulesText': 'Đoạn luật rất dài.',
      'rulesCard': [
        {
          'title': 'Một vòng',
          'items': [
            {
              'key': 'nominate',
              'icon': 'day',
              'label': '10h–20h',
              'value': 'Đề cử, tối đa 2 người',
            },
          ],
        },
        {
          'title': 'Lộ bài',
          'items': [
            {'key': 'reveal', 'label': '', 'value': 'Bị treo chỉ lộ phe.'},
          ],
        },
      ],
    };
    await pumpScreen(tester);
    await openRules(tester);

    expect(find.text('MỘT VÒNG'), findsOneWidget);
    expect(find.text('10h–20h'), findsOneWidget);
    expect(find.text('Đề cử, tối đa 2 người'), findsOneWidget);
    expect(find.text('Bị treo chỉ lộ phe.'), findsOneWidget);
    expect(find.text('Đoạn luật rất dài.'), findsNothing);
    await close(tester);
  });

  testWidgets('rules card draws each layout, unknown layout as a list', (
    tester,
  ) async {
    Map<String, dynamic> section(String layout, String title) => {
      'title': title,
      'layout': layout,
      'items': [
        {
          'key': title,
          'icon': 'night',
          'label': '$title nhãn',
          'value': '$title chữ',
        },
      ],
    };
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 30,
      'rulesCard': [
        section('timeline', 'a'),
        section('tiles', 'b'),
        section('layout-mới', 'c'),
      ],
    };
    await pumpScreen(tester);
    await openRules(tester);

    for (final t in ['a', 'b', 'c']) {
      expect(find.text('$t nhãn'), findsOneWidget);
      expect(find.text('$t chữ'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('the rules page shows the game settings in play', (tester) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 30,
      'setup': [
        {
          'title': 'Vòng chơi',
          'inRulesCard': true,
          'items': [
            {'key': 'rounds', 'label': 'Số vòng mỗi ngày', 'value': '1 vòng'},
          ],
        },
        {
          'title': 'Km mỗi lượt',
          'items': [
            {
              'key': 'kmPerUnit',
              'icon': 'vote',
              'label': 'Biểu quyết',
              'value': '2 km',
            },
            {
              'key': 'maxHang',
              'label': 'Treo tối đa mỗi vòng',
              'value': '2 người',
              'sub': true,
            },
          ],
        },
      ],
    };
    await pumpScreen(tester);
    await openRules(tester);
    expect(find.text('Thiết lập ván'), findsOneWidget);
    expect(find.text('KM MỖI LƯỢT'), findsOneWidget);
    expect(find.text('VÒNG CHƠI'), findsNothing);
    expect(find.text('Số vòng mỗi ngày'), findsNothing);
    expect(find.text('Biểu quyết'), findsOneWidget);
    expect(find.text('2 km'), findsOneWidget);
    expect(find.text('Treo tối đa mỗi vòng'), findsOneWidget);
    expect(find.text('2 người'), findsOneWidget);
    await close(tester);
  });

  testWidgets('before night one the hero waits for the first night', (
    tester,
  ) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
      'phase': {
        'key': 'r1/setup',
        'label': 'Chuẩn bị, đêm 1 bắt đầu lúc 22h',
        'deadline': now.add(const Duration(hours: 5)).toIso8601String(),
        'state': 'open',
      },
    };
    await pumpScreen(tester);
    expect(find.text('CHUẨN BỊ'), findsOneWidget);
    expect(find.textContaining('thì vào đêm 1'), findsOneWidget);
    expect(find.textContaining('thì chốt'), findsNothing);
    expect(find.text('Biểu quyết'), findsOneWidget);
    await close(tester);
  });

  testWidgets('no rules and no setup from backend, no rules button', (
    tester,
  ) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 30,
    };
    await pumpScreen(tester);
    expect(find.byTooltip('Luật chơi'), findsNothing);
    await close(tester);
  });

  testWidgets('the page stays moonlit on a light app theme', (tester) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
    };
    await pumpScreen(
      tester,
      theme: buildRunNowTheme(
        RunNowElement.fire,
        appearance: RunNowAppearance.light,
      ),
    );

    final theme = Theme.of(tester.element(find.byType(Scaffold)));
    // Nền và nhấn của canvas ánh trăng: mực #020306, hổ phách #E5B04C.
    expect(theme.brightness, Brightness.dark);
    expect(
      theme.extension<RunNowPalette>()!.background,
      const Color(0xFF020306),
    );
    expect(theme.colorScheme.primary, const Color(0xFFE5B04C));
    expect(find.byType(GameMoonEmblem), findsOneWidget);
    await close(tester);
  });

  testWidgets('an empty journal shows the empty state', (tester) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
    };
    await pumpScreen(tester);
    await tester.tap(find.text('NHẬT KÝ'));
    await tester.pumpAndSettle();
    expect(find.byType(RunNowEmptyIcon), findsOneWidget);
    expect(find.text('Chưa có gì'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a long feed item shows its last lines until expanded', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 9000);
    addTearDown(tester.view.reset);
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
      'feed': {
        'items': [
          {
            'seq': 7,
            'at': '2026-10-17T10:00:00Z',
            'title': 'Ngày 2',
            'lines': [
              '09:01 An đề cử Bình.',
              '09:05 Chi đề cử Bình.',
              '09:12 Dũng đề cử An.',
              '09:30 Hà đề cử Bình.',
              '10:02 Giang đề cử An.',
              'Bình lên giàn.',
            ],
          },
        ],
      },
    };
    await pumpScreen(tester);
    await tester.pump();
    await tester.tap(find.text('NHẬT KÝ'));
    await tester.pump();

    expect(find.text('09:01 An đề cử Bình.'), findsNothing);
    expect(find.text('09:30 Hà đề cử Bình.'), findsOneWidget);
    expect(find.text('Bình lên giàn.'), findsOneWidget);

    await tester.tap(find.text('Xem đủ 6 dòng'));
    await tester.pump();
    expect(find.text('09:01 An đề cử Bình.'), findsOneWidget);

    await tester.tap(find.text('Thu gọn'));
    await tester.pump();
    expect(find.text('09:01 An đề cử Bình.'), findsNothing);
    await close(tester);
  });

  testWidgets('the journal shows entries with their icon and tag', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(2400, 9000);
    addTearDown(tester.view.reset);
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
      'feed': {
        'items': [
          {
            'seq': 8,
            'at': '2026-10-17T15:00:00Z',
            'title': 'Ngày 2',
            'lines': ['Bình lên giàn với 3 phiếu.'],
            'entries': [
              {'icon': 'nominee', 'text': 'Bình lên giàn', 'tag': '3 PHIẾU'},
            ],
          },
        ],
      },
    };
    await pumpScreen(tester);
    await tester.pump();
    await tester.tap(find.text('NHẬT KÝ'));
    await tester.pump();

    expect(find.text('Bình lên giàn'), findsOneWidget);
    expect(find.text('3 PHIẾU'), findsOneWidget);
    expect(find.text('Bình lên giàn với 3 phiếu.'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(GameLineRow),
        matching: find.byIcon(Icons.campaign_outlined),
      ),
      findsOneWidget,
    );
    await close(tester);
  });

  testWidgets('shows closing instead of the old phase past deadline', (
    tester,
  ) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
      'phase': {
        'key': 'r2/day',
        'label': 'Ngày 2: đề cử',
        'deadline': now.add(const Duration(minutes: 5)).toIso8601String(),
        'state': 'open',
      },
    };
    await pumpScreen(tester);
    expect(find.text('VÒNG 2'), findsOneWidget);
    expect(find.text('ĐỀ CỬ'), findsOneWidget);
    expect(find.text('Ngày 2: đề cử'), findsOneWidget);

    await elapse(tester, const Duration(minutes: 5));

    expect(find.text('Ngày 2: đề cử'), findsNothing);
    expect(find.text('ĐANG CHỐT…'), findsOneWidget);
    await close(tester);
  });

  testWidgets('shows backend message when the game cannot load', (
    tester,
  ) async {
    backend.failures['GET /v1/games/g1'] = (
      404,
      {'error': 'not_found', 'message': 'Không tìm thấy ván.'},
    );
    await pumpScreen(tester);

    expect(find.text('Không tìm thấy ván.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('links Telegram and reads the game again once linked', (
    tester,
  ) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'registering',
      'statusLabel': 'Đang mở đăng ký',
      'refreshAfterSeconds': 300,
    };
    await pumpScreen(tester);
    final gameReads = backend.calls.where((c) => c == 'GET /v1/games/g1');
    expect(gameReads, hasLength(1));

    await tester.tap(find.text('Liên kết Telegram'));
    await tester.pump();
    expect(opened.single.toString(), 'https://t.me/runnow3i_bot?start=K7Q2');
    expect(
      find.text('Bấm Start trong Telegram rồi quay lại đây.'),
      findsOneWidget,
    );

    backend.telegram = {
      'linked': true,
      'tgUsername': 'an',
      'displayName': 'An',
      'inPsc': true,
    };
    await elapse(tester, const Duration(seconds: 3));

    expect(find.text('Liên kết Telegram'), findsNothing);
    expect(gameReads, hasLength(2));
    await close(tester);
  });

  // Ván không Telegram: không có phần liên kết Telegram; phòng chung mở được
  // ngay lúc đăng ký.
  testWidgets('a game without Telegram opens its room, no Telegram link', (
    tester,
  ) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'registering',
      'statusLabel': 'Đang mở đăng ký',
      'refreshAfterSeconds': 300,
      'isRegistered': true,
      'requirements': [
        {'key': 'app_version', 'ok': true, 'label': 'Bản app đủ mới'},
      ],
      'room': {'key': 'room', 'label': 'Phòng chung', 'canSend': true},
    };
    final router = GoRouter(
      initialLocation: '/games/g1',
      routes: [
        GoRoute(
          path: '/games/:id',
          builder: (_, _) => GameDetailScreen(gameId: 'g1', clock: () => now),
        ),
        GoRoute(
          path: '/games/:id/chat/:key',
          builder: (_, state) => Text(
            'chat ${state.pathParameters['id']}/'
            '${state.pathParameters['key']}',
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
          pushControllerProvider.overrideWithValue(null),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Liên kết Telegram'), findsNothing);
    await tester.tap(find.byTooltip('Phòng chung'));
    await tester.pumpAndSettle();
    expect(find.text('chat g1/room'), findsOneWidget);
    await close(tester);
  });

  // Đã liên kết thì màn ván không còn dòng liên kết, huỷ nằm ở Cài đặt.
  testWidgets('a linked player sees no Telegram row', (tester) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'isRegistered': true,
    };
    backend.telegram = {
      'linked': true,
      'tgUsername': 'an',
      'displayName': 'An',
      'inPsc': true,
    };
    await pumpScreen(tester);

    expect(find.textContaining('@an'), findsNothing);
    expect(find.text('Không phải bạn? Huỷ'), findsNothing);
    expect(find.text('Liên kết Telegram'), findsNothing);
    await close(tester);
  });

  testWidgets('reads Telegram again when the app comes back', (tester) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'registering',
      'statusLabel': 'Đang mở đăng ký',
      'refreshAfterSeconds': 300,
    };
    await pumpScreen(tester);
    expect(find.text('Liên kết Telegram'), findsOneWidget);

    backend.telegram = {
      'linked': true,
      'tgUsername': 'an',
      'displayName': 'An',
      'inPsc': true,
    };
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(find.text('Liên kết Telegram'), findsNothing);
    await close(tester);
  });

  group('lobby recent km', () {
    Map<String, dynamic> lobby(List<Map<String, dynamic>> players) => {
      'id': 'g1',
      'title': 'Ma Sói',
      'status': 'registering',
      'statusLabel': 'Đang mở đăng ký',
      'refreshAfterSeconds': 300,
      'playerCount': players.length,
      'minPlayers': 8,
      'maxPlayers': 16,
      'players': players,
    };

    testWidgets('shows each player km of the last 24 hours', (tester) async {
      backend.game = lobby([
        {'uid': 'u1', 'name': 'An', 'alive': true, 'recentKm': 12.54},
        {'uid': 'u2', 'name': 'Bình', 'alive': true, 'recentKm': 0},
        {'uid': 'u3', 'name': 'Giả', 'alive': true, 'fake': true},
      ]);
      await pumpScreen(tester);

      expect(find.text('12.5 km'), findsOneWidget);
      expect(find.text('0 km'), findsOneWidget);
      expect(find.text('3 người · km 24h'), findsOneWidget);
      await close(tester);
    });

    testWidgets('an older backend without the number shows names only', (
      tester,
    ) async {
      backend.game = lobby([
        {'uid': 'u1', 'name': 'An', 'alive': true},
      ]);
      await pumpScreen(tester);

      expect(find.text('1 người'), findsOneWidget);
      expect(find.textContaining(' km'), findsNothing);
      await close(tester);
    });
  });

  group('cancel game', () {
    Map<String, dynamic> game(String status, {bool canManage = true}) => {
      'id': 'g1',
      'title': 'Ma Sói',
      'status': status,
      'statusLabel': status,
      'refreshAfterSeconds': 300,
      'playerCount': 9,
      'minPlayers': 8,
      'maxPlayers': 16,
      'canManage': canManage,
    };

    int cancels() => backend.requests
        .where((r) => r.url.path == '/v1/games/g1/admin/cancel')
        .length;

    Finder cancelButton() => find.descendant(
      of: find.byType(AppBar),
      matching: find.byTooltip('Huỷ ván'),
    );

    Future<void> tapCancel(WidgetTester tester) async {
      await tester.tap(cancelButton());
      await tester.pump(const Duration(milliseconds: 400));
    }

    for (final status in ['registering', 'running', 'paused']) {
      testWidgets('the host cancels a $status game after confirming', (
        tester,
      ) async {
        backend.game = game(status);
        await pumpScreen(tester);

        await tapCancel(tester);
        await tester.tap(find.text('Thôi'));
        await tester.pump(const Duration(milliseconds: 400));
        expect(cancels(), 0);

        await tapCancel(tester);
        await tester.tap(find.text('Huỷ ván').last);
        await tester.pump(const Duration(milliseconds: 400));
        expect(cancels(), 1);
        await close(tester);
      });
    }

    testWidgets('the cancel button is the rightmost header action', (
      tester,
    ) async {
      backend.game = game('running');
      await pumpScreen(tester);

      expect(
        tester.getCenter(cancelButton()).dx,
        greaterThan(tester.getCenter(find.byTooltip('Chia sẻ ván')).dx),
      );
      await close(tester);
    });

    for (final status in ['ended', 'cancelled']) {
      testWidgets('has no button once the game is $status', (tester) async {
        backend.game = game(status);
        await pumpScreen(tester);

        expect(cancelButton(), findsNothing);
        await close(tester);
      });
    }

    testWidgets('someone who cannot manage has no button', (tester) async {
      backend.game = game('running', canManage: false);
      await pumpScreen(tester);

      expect(cancelButton(), findsNothing);
      await close(tester);
    });
  });

  group('admin start', () {
    Map<String, dynamic> registering({required bool admin}) => {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'registering',
      'statusLabel': 'Đang mở đăng ký',
      'refreshAfterSeconds': 300,
      'playerCount': 9,
      'minPlayers': 8,
      'maxPlayers': 16,
      'isAdmin': admin,
    };

    List<String> starts() => [
      for (final r in backend.requests)
        if (r.url.path == '/v1/games/g1/start') r.url.query,
    ];

    testWidgets('previews, then starts once the admin confirms', (
      tester,
    ) async {
      backend.game = registering(admin: true);
      backend.startPreview = {
        'willExclude': [
          {
            'uid': 'u9',
            'name': 'Bình',
            'reason': 'not_linked',
            'reasonLabel': 'chưa liên kết Telegram',
          },
        ],
        'players': [],
        'count': 8,
        'minPlayers': 8,
        'maxPlayers': 16,
        'canStart': true,
      };
      await pumpScreen(tester);

      await tester.tap(find.text('Bắt đầu ván'));
      await tester.pumpAndSettle();
      expect(find.text('người chơi'), findsOneWidget);
      expect(find.textContaining('cần 8–16'), findsNothing);
      expect(find.text('Bình'), findsOneWidget);
      expect(find.text('chưa liên kết Telegram'), findsOneWidget);
      expect(starts(), ['dryRun=true']);

      await tester.tap(find.text('Bắt đầu'));
      await tester.pumpAndSettle();

      expect(starts(), ['dryRun=true', '']);
      expect(find.text('ĐANG CHIA BÀI'), findsOneWidget);
      expect(find.text('Bắt đầu ván'), findsNothing);
      await close(tester);
    });

    testWidgets('does not start when the preview says it cannot', (
      tester,
    ) async {
      backend.game = registering(admin: true);
      backend.startPreview = {
        'willExclude': [],
        'players': [],
        'count': 5,
        'minPlayers': 8,
        'maxPlayers': 16,
        'canStart': false,
      };
      await pumpScreen(tester);

      await tester.tap(find.text('Bắt đầu ván'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa bắt đầu được'), findsOneWidget);
      expect(find.text('người · cần 8–16'), findsOneWidget);
      expect(find.text('Bắt đầu'), findsNothing);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(starts(), ['dryRun=true']);
      expect(find.text('Bắt đầu ván'), findsOneWidget);
      await close(tester);
    });

    testWidgets('outside the day phase it shows why and cannot start', (
      tester,
    ) async {
      backend.game = registering(admin: true);
      backend.startPreview = {
        'willExclude': [],
        'players': [],
        'count': 8,
        'minPlayers': 8,
        'maxPlayers': 16,
        'canStart': true,
        'startClosed': 'Ván này chỉ bắt đầu được trong pha Ngày: 10h–20h.',
      };
      await pumpScreen(tester);

      await tester.tap(find.text('Bắt đầu ván'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa bắt đầu được'), findsOneWidget);
      expect(
        find.text('Ván này chỉ bắt đầu được trong pha Ngày: 10h–20h.'),
        findsOneWidget,
      );
      expect(find.text('Bắt đầu'), findsNothing);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(starts(), ['dryRun=true']);
      await close(tester);
    });

    // Ván thử thiếu người: admin thêm người giả bù đúng phần thiếu so với
    // người thật; đủ rồi thì nút biến mất.
    testWidgets('a test game fills up with fake players', (tester) async {
      backend.game = {
        ...registering(admin: true),
        'testMode': true,
        'minPlayers': 10,
        'playerCount': 3,
        'players': [
          {'uid': 'u1', 'name': 'An'},
          {'uid': 'u2', 'name': 'Bình'},
          {'uid': 'fake-old', 'name': 'Giả cũ', 'fake': true},
        ],
      };
      await pumpScreen(tester);

      await tester.tap(find.text('Thêm người giả cho đủ 10'));
      await tester.pumpAndSettle();
      final sent = [
        for (final r in backend.requests)
          if (r.url.path == '/v1/games/g1/admin/fake-players')
            jsonDecode(r.body),
      ];
      expect(sent, [
        {'count': 8},
      ]);
      expect(find.text('Thêm người giả cho đủ 10'), findsNothing);
      await close(tester);
    });

    testWidgets('a real game has no fake players button', (tester) async {
      backend.game = {...registering(admin: true), 'minPlayers': 10};
      await pumpScreen(tester);

      expect(find.textContaining('người giả'), findsNothing);
      await close(tester);
    });

    // Chưa đủ người thì nút mờ và nói còn thiếu bao nhiêu; đủ thì bấm được.
    testWidgets('the start button is off until enough players joined', (
      tester,
    ) async {
      backend.game = {...registering(admin: true), 'playerCount': 7};
      await pumpScreen(tester);

      final off = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Bắt đầu ván (7/8)'),
      );
      expect(off.onPressed, isNull);
      expect(starts(), isEmpty);
      await close(tester);
    });

    testWidgets('the start button works at exactly the minimum', (
      tester,
    ) async {
      backend.game = {...registering(admin: true), 'playerCount': 8};
      await pumpScreen(tester);

      final on = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Bắt đầu ván'),
      );
      expect(on.onPressed, isNotNull);
      await close(tester);
    });

    testWidgets('is hidden from players', (tester) async {
      backend.game = registering(admin: false);
      await pumpScreen(tester);

      expect(find.text('VÀO VÁN'), findsOneWidget);
      expect(find.text('Bắt đầu ván'), findsNothing);
      await close(tester);
    });

    // Chủ ván không phải admin: backend gửi canManage.
    testWidgets('shows for the host of the game', (tester) async {
      backend.game = registering(admin: false)..['canManage'] = true;
      await pumpScreen(tester);

      expect(find.text('Bắt đầu ván'), findsOneWidget);
      await close(tester);
    });

    testWidgets('canManage false hides it even from an admin', (tester) async {
      backend.game = registering(admin: true)..['canManage'] = false;
      await pumpScreen(tester);

      expect(find.text('Bắt đầu ván'), findsNothing);
      await close(tester);
    });

    // Admin không phải chủ ván: vẫn huỷ ván được nhưng không bắt đầu được.
    testWidgets('canStart false hides it from an admin who can manage', (
      tester,
    ) async {
      backend.game = registering(admin: true)
        ..['canManage'] = true
        ..['canStart'] = false;
      await pumpScreen(tester);

      expect(find.textContaining('Bắt đầu ván'), findsNothing);
      expect(find.byTooltip('Huỷ ván'), findsOneWidget);
      await close(tester);
    });

    testWidgets('anyone can share the game link while it is open', (
      tester,
    ) async {
      backend.game = registering(admin: false);
      await pumpScreen(tester);

      expect(find.byTooltip('Mời bạn'), findsOneWidget);
      expect(gameInviteLink('g1').toString(), 'https://threei.run/games/g1');
      await close(tester);
    });

    testWidgets('the invite goes out as a picture with the link in the text', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      backend.game = registering(admin: false);
      await pumpScreen(tester);
      expect(find.byTooltip('Chia sẻ ván'), findsNothing);
      final before = share.shared.length;

      await tester.tap(find.byTooltip('Mời bạn'));
      await tester.pumpAndSettle();
      expect(find.byType(GameInviteCard), findsOneWidget);
      expect(share.shared.length, before);

      await tester.tap(find.text('Gửi lời mời'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pumpAndSettle();

      final sent = share.shared.last;
      expect(share.shared.length, before + 1);
      expect(sent.text, 'Còn 7 chỗ. Vào không?\nhttps://threei.run/games/g1');
      expect(sent.files!.single.mimeType, 'image/png');
      expect(find.byType(GameInviteCard), findsNothing);
      await close(tester);
    });
  });

  testWidgets('a running game can be shared as a picture', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 30,
      'phase': {'key': 'day', 'label': 'Ngày 3', 'state': 'open'},
      'players': [
        {'uid': 'a', 'name': 'An', 'alive': true},
        {'uid': 'b', 'name': 'Bình', 'alive': false},
      ],
    };
    await pumpScreen(tester);
    expect(find.byTooltip('Mời bạn'), findsNothing);
    final before = share.shared.length;

    await tester.tap(find.byTooltip('Chia sẻ ván'));
    await tester.pumpAndSettle();
    expect(find.byType(GameLiveCard), findsOneWidget);

    await tester.tap(find.text('Chia sẻ'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 1)),
    );
    await tester.pumpAndSettle();

    expect(share.shared.length, before + 1);
    expect(
      share.shared.last.text,
      'Ngày 3. Còn 1/2 người sống, ai là sói?\nhttps://threei.run/games/g1',
    );
    expect(share.shared.last.files!.single.mimeType, 'image/png');
    await close(tester);
  });

  group('requirements', () {
    Map<String, dynamic> open(List<Map<String, dynamic>> requirements) => {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'registering',
      'statusLabel': 'Đang mở đăng ký',
      'refreshAfterSeconds': 300,
      'requirements': requirements,
    };
    const linked = {
      'key': 'telegram_linked',
      'ok': true,
      'label': 'Đã liên kết Telegram',
    };
    const notInPsc = {
      'key': 'in_psc',
      'ok': false,
      'label': 'Đang ở trong group PSC',
      'action': {'type': 'open_url', 'url': 'https://t.me/+psc'},
    };
    const appOk = {
      'key': 'app_version',
      'ok': true,
      'label': 'Bản app từ 1.5.0 trở lên',
    };

    FilledButton registerButton(WidgetTester tester) =>
        tester.widget(find.widgetWithText(FilledButton, 'VÀO VÁN'));

    testWidgets('the lobby shows seats, closing time and requirements met', (
      tester,
    ) async {
      backend.game = {
        ...open([linked, notInPsc, appOk]),
        'playerCount': 9,
        'minPlayers': 10,
        'maxPlayers': 16,
        // Giờ địa phương, nên ra đúng 21:00 ở mọi múi giờ máy chạy test.
        'registrationDeadline': DateTime(2026, 11, 8, 21).toIso8601String(),
      };
      await pumpScreen(tester);

      expect(find.text('9'), findsOneWidget);
      expect(find.text('/ 16 chỗ'), findsOneWidget);
      expect(find.text('cần ít nhất 10 để mở ván'), findsOneWidget);
      expect(find.text('21:00'), findsOneWidget);
      expect(find.text('đóng đăng ký · CN'), findsOneWidget);
      expect(find.text('ĐỦ ĐIỀU KIỆN 2/3'), findsOneWidget);
      await close(tester);
    });

    testWidgets('lists what is missing and blocks registering', (tester) async {
      backend.game = open([linked, notInPsc, appOk]);
      await pumpScreen(tester);

      expect(find.text('Đã liên kết Telegram'), findsOneWidget);
      expect(find.text('Đang ở trong group PSC'), findsOneWidget);
      expect(find.text('Bản app từ 1.5.0 trở lên'), findsOneWidget);
      expect(registerButton(tester).onPressed, isNull);

      await tester.tap(find.text('Mở'));
      await tester.pump();
      expect(opened, [Uri.parse('https://t.me/+psc')]);
      await close(tester);
    });

    testWidgets('says so when the link cannot open', (tester) async {
      backend.game = open([linked, notInPsc, appOk]);
      openOk = false;
      await pumpScreen(tester);

      await tester.tap(find.text('Mở'));
      await tester.pump();
      expect(find.text('Không mở được link.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('lets the player register once everything is met', (
      tester,
    ) async {
      backend.game = open([linked, appOk]);
      await pumpScreen(tester);

      expect(registerButton(tester).onPressed, isNotNull);
      await close(tester);
    });

    testWidgets('opens the update link or says where to update', (
      tester,
    ) async {
      backend.game = open([
        linked,
        {
          'key': 'app_version',
          'ok': false,
          'label': 'Bản app từ 1.6.0 trở lên',
          'action': {'type': 'update_app'},
        },
      ]);
      await pumpScreen(tester);
      expect(find.text('Cập nhật app trên Google Play.'), findsOneWidget);
      expect(find.text('Cập nhật'), findsNothing);
      await close(tester);

      backend.game = open([
        linked,
        {
          'key': 'app_version',
          'ok': false,
          'label': 'Bản app từ 1.6.0 trở lên',
          'action': {'type': 'update_app', 'url': 'https://store.example/3i'},
        },
      ]);
      await pumpScreen(tester);
      await tester.tap(find.text('Cập nhật'));
      await tester.pump();
      expect(opened, [Uri.parse('https://store.example/3i')]);
      await close(tester);
    });

    testWidgets('reads the game again when registering is refused', (
      tester,
    ) async {
      backend.game = open([linked, appOk]);
      backend.failures['POST /v1/games/g1/registration'] = (
        422,
        {
          'error': 'requirements_unmet',
          'message': 'Bạn chưa đủ điều kiện đăng ký.',
          'requirements': [linked, notInPsc, appOk],
        },
      );
      await pumpScreen(tester);
      backend.game = open([linked, notInPsc, appOk]);

      await tester.tap(find.text('VÀO VÁN'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Bạn chưa đủ điều kiện đăng ký.'), findsOneWidget);
      expect(find.text('Đang ở trong group PSC'), findsOneWidget);
      expect(registerButton(tester).onPressed, isNull);
      await close(tester);
    });

    testWidgets('asks for notifications when opening a game already joined', (
      tester,
    ) async {
      backend.game = {
        ...open([linked, appOk]),
        'isRegistered': true,
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(push.asks, 1);
      await close(tester);
    });

    testWidgets('does not ask for notifications on a game that ended', (
      tester,
    ) async {
      backend.game = {
        ...open([linked, appOk]),
        'status': 'ended',
        'isRegistered': true,
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(push.asks, 0);
      await close(tester);
    });

    testWidgets('asks for notifications after joining', (tester) async {
      backend.game = open([linked, appOk]);
      await pumpScreen(tester);
      expect(push.asks, 0);

      await tester.tap(find.text('VÀO VÁN'));
      await tester.pump();
      await tester.pump();

      expect(push.asks, 1);
      await close(tester);
    });

    testWidgets('hides the checklist once registered', (tester) async {
      backend.game = {
        ...open([linked, notInPsc, appOk]),
        'isRegistered': true,
      };
      await pumpScreen(tester);

      expect(find.text('Đang ở trong group PSC'), findsNothing);
      expect(find.text('Huỷ đăng ký'), findsOneWidget);
      // Chưa chia vai thì /me chưa có role: chưa có lá bài.
      expect(find.text('LÁ BÀI CỦA BẠN'), findsNothing);
      await close(tester);
    });
  });

  const faceDown = 'Chạm để lật';

  group('my card', () {
    Map<String, dynamic> running({bool registered = true}) => {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
      'isRegistered': registered,
    };

    testWidgets('stays face down until tapped, then shows what it knows', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'roleRules': 'Mỗi đêm soi một người. Giữ kín kết quả.',
        'notes': [
          {'round': 1, 'text': 'An là Dân'},
        ],
        'inviteLinks': [
          {'label': 'Vào nhóm Sói', 'url': 'https://t.me/+wolves'},
        ],
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text(faceDown), findsOneWidget);
      expect(find.byTooltip('Thêm'), findsNothing);
      expect(find.text('Vòng 1: An là Dân'), findsNothing);

      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Thêm'), findsOneWidget);
      expect(find.text('Giữ kín kết quả'), findsNothing);
      expect(find.text('Vòng 1: An là Dân'), findsOneWidget);

      await tester.tap(find.byTooltip('Thêm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Là gì?'));
      await tester.pumpAndSettle();
      expect(find.text('Giữ kín kết quả'), findsOneWidget);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Giữ kín kết quả'), findsNothing);

      await tester.tap(find.text('Vào nhóm Sói'));
      await tester.pump();
      expect(opened, [Uri.parse('https://t.me/+wolves')]);

      await tester.tap(find.byTooltip('Thêm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Úp lá bài'));
      await tester.pumpAndSettle();
      expect(find.text(faceDown), findsOneWidget);
      expect(find.byTooltip('Thêm'), findsNothing);
      await close(tester);
    });

    testWidgets('with nothing to do the face says who you are', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'roleRules': 'Mỗi đêm soi một người. Soi trúng Sói thì giữ kín.',
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      expect(find.text('TIÊN TRI'), findsWidgets);
      expect(find.text('Mỗi đêm soi một người'), findsOneWidget);
      expect(find.text('Soi trúng Sói thì giữ kín'), findsNothing);
      await close(tester);
    });

    testWidgets('a very long peeked name stays inside its chip', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'notes': [
          {'round': 1, 'text': 'Đêm 1: ${'Võ Thị Thu Trang ' * 12}là Sói.'},
        ],
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(' · SÓI'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a seer sees each peek as a chip, not a note line', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'notes': [
          {'round': 1, 'text': 'Đêm 1: An là Dân.'},
          {'round': 2, 'text': 'Đêm 2: Khoa là Sói.'},
          {'round': 2, 'text': 'Bạn đã thoát một cú cắn của sói.'},
        ],
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      expect(find.text(' · Dân'), findsOneWidget);
      expect(find.text(' · SÓI'), findsOneWidget);
      expect(find.textContaining('Đêm 1: An'), findsNothing);
      expect(
        find.text('Vòng 2: Bạn đã thoát một cú cắn của sói.'),
        findsOneWidget,
      );
      await close(tester);
    });

    testWidgets('the face opens the skin sheet previewing this card', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'cardTier': 'rare',
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Thêm'));
      await tester.pumpAndSettle();
      expect(find.text('Là gì?'), findsNothing);
      await tester.tap(find.text('Bộ màu'));
      await tester.pumpAndSettle();
      final sample = tester
          .widget<RunCardSkinSheet>(find.byType(RunCardSkinSheet))
          .sample;
      expect(sample.tier, GameCardTier.rare);
      expect(sample.owner, 'BẠN');
      expect(sample.hero, 'TIÊN TRI');

      // Sheet mặc theme app, không mượn kính gần trong suốt của theme đêm.
      final sheetContext = tester.element(find.byType(RunCardSkinSheet));
      final app = ProviderScope.containerOf(
        sheetContext,
      ).read(themeControllerProvider);
      final glass = Theme.of(
        sheetContext,
      ).extension<RunNowPalette>()!.glassStart;
      expect(
        glass,
        buildRunNowTheme(
          app.element,
          appearance: app.appearance,
          darkTone: app.darkTone,
        ).extension<RunNowPalette>()!.glassStart,
      );
      expect(
        glass,
        isNot(gameNightTheme().extension<RunNowPalette>()!.glassStart),
      );
      await close(tester);
    });

    testWidgets('the card stays face down until flipped, then shows its tier', (
      tester,
    ) async {
      reveals = _MemoryReveals(revealedAll: false);
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'cardTier': 'legendary',
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      // Vai đã ngửa, nhưng thẻ còn úp nên chưa biết bậc.
      expect(find.byTooltip('Thêm'), findsOneWidget);
      expect(find.byType(AchievementCard), findsNothing);
      expect(reveals.marked, isEmpty);

      await tester.tap(find.text('Lật thẻ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      final card = tester.widget<AchievementCard>(find.byType(AchievementCard));
      expect(card.data.tier, GameCardTier.legendary);
      expect(reveals.marked, ['me/g1']);
      await close(tester);
    });

    // Lá xem to có hoạt ảnh lặp nên không pumpAndSettle được.
    Future<void> openBigCard(WidgetTester tester) async {
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(AchievementCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('locks bragging while the game runs and the viewer lives', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
      };
      await pumpScreen(tester);
      await tester.pump();
      await openBigCard(tester);

      expect(find.textContaining('khoe thẻ lúc này là lộ vai'), findsOneWidget);
      expect(find.text('Khoe thẻ'), findsNothing);
      await close(tester);
    });

    testWidgets('closes the secret big card when the app leaves the screen', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
      };
      await pumpScreen(tester);
      await tester.pump();
      await openBigCard(tester);

      final binding = tester.binding;
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      // Frame chụp app switcher đã không còn lá ngửa.
      expect(
        find.descendant(
          of: find.byType(GameCardViewer),
          matching: find.byType(AchievementCard),
        ),
        findsNothing,
      );
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // App nền không vẽ frame; route chạy hết hiệu ứng đóng sau khi quay lại.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('lộ vai'), findsNothing);
      // Chỉ đóng lá to, màn ván vẫn còn và lá đã úp lại.
      expect(find.text(faceDown), findsOneWidget);
      await close(tester);
    });

    // Người chết giữa ván không khoe được nữa: thẻ chỉ thuộc về phe thắng.
    testWidgets('keeps bragging locked for the dead while the game runs', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': false,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
      };
      await pumpScreen(tester);
      await tester.pump();
      await openBigCard(tester);

      expect(find.text('Khoe thẻ'), findsNothing);
      expect(find.textContaining('ván kết thúc và phe bạn thắng'), findsOne);
      await close(tester);
    });

    Map<String, dynamic> ended() => {
      ...running(),
      'status': 'ended',
      'statusLabel': 'Đã kết thúc',
      'winner': 'village',
    };

    testWidgets('unlocks bragging for the winning side once the game ends', (
      tester,
    ) async {
      backend.game = ended();
      backend.me = {
        'status': 'ended',
        'alive': false,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'cardTier': 'rare',
        'cardOwned': true,
      };
      await pumpScreen(tester);
      await tester.pump();
      await openBigCard(tester);

      expect(find.text('Khoe thẻ'), findsOneWidget);
      expect(find.text('Hiếm'), findsOneWidget);
      expect(find.textContaining('lộ vai'), findsNothing);
      await close(tester);
    });

    testWidgets('an ended game shows its summary, reveal and replay', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 9000);
      addTearDown(tester.view.reset);
      backend.game = {
        ...running(),
        'status': 'ended',
        'statusLabel': 'Đã kết thúc',
        'winner': 'village',
        'winnerLabel': 'Phe Dân',
      };
      backend.me = {
        'status': 'ended',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'cardRounds': 4,
        'summary': {
          'winner': 'village',
          'winnerLabel': 'Phe Dân',
          'subtitle': 'Treo đủ 3 sói · còn 5 người sống',
          'stats': [
            {'label': 'Km cả làng', 'value': '212 km'},
          ],
          'titles': [
            {
              'key': 'runner',
              'label': 'Chạy nhiều nhất',
              'uids': ['u3'],
              'name': 'Ngọc',
              'value': '38.2 km',
            },
          ],
          'teams': [
            {
              'team': 'village',
              'label': 'Phe Dân',
              'won': true,
              'players': [
                {
                  'uid': 'u3',
                  'name': 'Ngọc',
                  'role': 'cupid',
                  'roleLabel': 'Cupid',
                  'alive': true,
                  'fate': 'Sống',
                },
              ],
            },
            {
              'team': 'wolves',
              'label': 'Phe Sói',
              'won': false,
              'players': [
                {
                  'uid': 'u2',
                  'name': 'Bình',
                  'role': 'wolf',
                  'roleLabel': 'Sói',
                  'alive': false,
                  'fate': 'Ngày 1',
                  'causeLabel': 'Bị treo',
                },
              ],
            },
          ],
          'replay': [
            {
              'title': 'Đêm 1',
              'night': true,
              'lines': [
                {'icon': 'bite', 'text': 'Sói cắn An.', 'tag': 'CỨU'},
              ],
            },
          ],
        },
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('PHE DÂN THẮNG'), findsOneWidget);
      expect(find.text('KẾT THÚC SAU 4 VÒNG'), findsOneWidget);
      expect(find.text('Treo đủ 3 sói · còn 5 người sống'), findsOneWidget);
      expect(find.text('212 km'), findsOneWidget);
      expect(find.text('Chạy nhiều nhất'), findsOneWidget);
      expect(find.text('LÀNG'), findsNothing);

      await tester.tap(find.text('LẬT BÀI'));
      await tester.pump();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Bình'), findsOneWidget);
      expect(find.text('Sói'), findsOneWidget);
      expect(find.text('NGÀY 1'), findsOneWidget);
      expect(find.text('Sói cắn An.'), findsNothing);

      await tester.tap(find.text('DIỄN LẠI'));
      await tester.pump();
      expect(find.text('ĐÊM 1'), findsOneWidget);
      expect(find.text('Sói cắn An.'), findsOneWidget);
      expect(find.text('CỨU'), findsOneWidget);
      await close(tester);
    });

    testWidgets('the header shrinks and the tabs stay when scrolling', (
      tester,
    ) async {
      backend.game = {
        ...running(),
        'players': [
          for (var i = 0; i < 40; i++)
            {'uid': 'u$i', 'name': 'Người $i', 'alive': true},
        ],
      };
      await pumpScreen(tester);
      await tester.pump();
      const sticky = ValueKey('game-sticky-header');
      expect(find.byKey(sticky), findsNothing);

      await tester.drag(find.text('Người 1'), const Offset(0, -900));
      await tester.pumpAndSettle();
      final tabs = find.descendant(
        of: find.byKey(sticky),
        matching: find.text('NHẬT KÝ'),
      );
      expect(tabs, findsOneWidget);

      // Đổi tab lúc đang dính thì nội dung mới bắt đầu ngay dưới hàng tab.
      await tester.tap(tabs);
      await tester.pumpAndSettle();
      expect(find.text('Người 39'), findsNothing);
      await close(tester);
    });

    testWidgets('the chat button marks unread messages', (tester) async {
      backend.game = {
        ...running(),
        'room': {
          'key': 'room',
          'label': 'Phòng chung',
          'canSend': true,
          'latestSeq': 3,
        },
      };
      await pumpScreen(tester, chatSeen: _MemoryChatSeen(2));
      await tester.pump();
      expect(find.bySemanticsLabel('Có tin mới'), findsOneWidget);
      await close(tester);

      await pumpScreen(tester, chatSeen: _MemoryChatSeen(3));
      await tester.pump();
      expect(find.bySemanticsLabel('Có tin mới'), findsNothing);
      await close(tester);

      // Chưa đọc được máy đã xem tới đâu thì không báo bừa.
      await pumpScreen(tester, chatSeen: _MemoryChatSeen(null));
      await tester.pump();
      expect(find.bySemanticsLabel('Có tin mới'), findsNothing);
      await close(tester);
    });

    testWidgets('an ended game does not ask to link Telegram', (tester) async {
      backend.game = {
        ...running(),
        'status': 'ended',
        'statusLabel': 'Đã kết thúc',
      };
      backend.me = {'status': 'ended', 'alive': true, 'role': 'seer'};
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Liên kết Telegram'), findsNothing);
      await close(tester);
    });

    testWidgets('the replay groups a round and shows the vote split', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 9000);
      addTearDown(tester.view.reset);
      backend.game = {
        ...running(),
        'status': 'ended',
        'statusLabel': 'Đã kết thúc',
      };
      backend.me = {
        'status': 'ended',
        'alive': true,
        'role': 'seer',
        'summary': {
          'winner': 'village',
          'winnerLabel': 'Phe Dân',
          'replay': [
            {
              'title': 'Đêm 2',
              'night': true,
              'round': 2,
              'date': '16/10',
              'lines': [
                {'icon': 'death', 'text': 'An ngã xuống.'},
              ],
            },
            {
              'title': 'Ngày 2',
              'night': false,
              'round': 2,
              'date': '17/10',
              'lines': [
                {
                  'icon': 'vote',
                  'text': 'Làng treo Bình.',
                  'hang': 7,
                  'spare': 2,
                },
                {'icon': 'death', 'text': 'Bình ngã xuống.'},
              ],
            },
          ],
        },
      };
      await pumpScreen(tester);
      await tester.pump();

      await tester.tap(find.text('DIỄN LẠI'));
      await tester.pump();
      expect(find.text('VÒNG 2 · 16–17/10 · 2 người ngã'), findsOneWidget);
      expect(find.text('ĐÊM 2'), findsOneWidget);
      expect(find.text('Treo 7'), findsOneWidget);
      expect(find.text('Tha 2'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a winner claims the card from the face-up block', (
      tester,
    ) async {
      backend.game = {
        ...running(),
        'status': 'ended',
        'statusLabel': 'Đã kết thúc',
      };
      backend.me = {
        'status': 'ended',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'cardTier': 'rare',
        'cardOwned': true,
        'cardRounds': 3,
      };
      await pumpScreen(tester);
      await tester.pump();
      expect(find.text('NHẬN THẺ'), findsNothing);

      await tester.tap(find.text('Chạm để lật'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Thắng · sống tới cuối'), findsOneWidget);
      expect(find.text('NHẬN THẺ'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a voter in the top slots shows the backend vote tag', (
      tester,
    ) async {
      backend.game = {
        ...running(),
        'players': [
          {'uid': 'u2', 'name': 'Bình', 'alive': true, 'voteTag': 'x2'},
        ],
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('x2'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a winner brags through the card share screen', (tester) async {
      // Byte giả: màn khoe không giải mã video, chỉ gửi đi.
      final video = Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]);
      final store = _SavedShareStore(
        'masoi-g1',
        CardShareFiles(
          front: _png,
          back: _png,
          motion: video,
          motionType: 'video/mp4',
        ),
      );
      shareStore = store;
      backend.game = ended();
      backend.me = {
        'status': 'ended',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'cardTier': 'rare',
        'cardOwned': true,
        'cardRounds': 3,
      };
      await pumpScreen(tester);
      await tester.pump();
      await openBigCard(tester);

      await tester.tap(find.text('Khoe thẻ'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(store.loaded, contains('masoi-g1'));
      expect(store.saves, 0, reason: 'có sẵn thì không tạo lại');
      for (final label in ['Mặt trước', 'Mặt sau', 'Video 3D']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('Khoe'));
      await tester.pump();
      final sent = share.shared.last;
      expect(sent.fileNameOverrides, ['3i-masoi-g1-motion.mp4']);
      expect(await sent.files!.single.readAsBytes(), video);
      expect(sent.text, startsWith('Tiên tri · Dân làng thắng'));
      await close(tester);
    });

    testWidgets('keeps bragging locked for the losing side', (tester) async {
      backend.game = ended();
      backend.me = {
        'status': 'ended',
        'alive': true,
        'role': 'wolf',
        'roleLabel': 'Sói',
        'cardTier': 'rare',
        'cardOwned': false,
      };
      await pumpScreen(tester);
      await tester.pump();
      await openBigCard(tester);

      expect(find.text('Khoe thẻ'), findsNothing);
      expect(find.textContaining('Chỉ người phe thắng'), findsOneWidget);
      await close(tester);
    });

    testWidgets('opens faction chats listed in /me from the face', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'wolf',
        'roleLabel': 'Sói',
        'chats': [
          {'key': 'wolves', 'label': 'Phe Sói', 'canSend': true},
          {'key': 'lovers', 'label': 'Cặp đôi', 'canSend': false},
        ],
      };
      final router = GoRouter(
        initialLocation: '/games/g1',
        routes: [
          GoRoute(
            path: '/games/:id',
            builder: (_, _) => GameDetailScreen(gameId: 'g1', clock: () => now),
          ),
          GoRoute(
            path: '/games/:id/chat/:key',
            builder: (_, state) => Text(
              'chat ${state.pathParameters['id']}/'
              '${state.pathParameters['key']}',
            ),
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pushControllerProvider.overrideWithValue(null),
            runNowApiClientProvider.overrideWithValue(backend.client()),
            firebaseUserProvider.overrideWith(
              (ref) => Stream.value(_FakeUser()),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Tên chat lộ phe, nên chỉ hiện khi lật bài.
      expect(find.text('Chat Phe Sói'), findsNothing);
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Chat Cặp đôi'), findsOneWidget);

      await tester.tap(find.text('Chat Phe Sói'));
      await tester.pumpAndSettle();
      expect(find.text('chat g1/wolves'), findsOneWidget);

      // Quay lại từ chat thì bài đã úp.
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text(faceDown), findsOneWidget);
      expect(find.text('Chat Phe Sói'), findsNothing);
      await close(tester);
    });

    testWidgets('turns face down when the app leaves the foreground', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Thêm'), findsOneWidget);

      // App switcher của iOS chụp màn lúc inactive.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text(faceDown), findsOneWidget);
      expect(find.byTooltip('Thêm'), findsNothing);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await close(tester);
    });

    testWidgets('hides what you must do while the card is face down', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'wolf',
        'roleLabel': 'Sói',
        'actions': [
          {
            'kind': 'wolf_bite',
            'label': 'Cắn',
            'help': 'Chọn người phe Sói cắn đêm nay.',
            'input': 'single_target',
            'enabled': true,
            'options': [
              {'id': 'u2', 'label': 'Bình'},
            ],
          },
        ],
      };
      await pumpScreen(tester);
      await tester.pump();

      // Người ngồi cạnh đọc được "Cắn" là biết người này là sói; ban đêm
      // dân không có việc gì, nên có mục này thôi cũng đã lộ.
      expect(find.text('Chọn người phe Sói cắn đêm nay'), findsNothing);

      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Chọn người phe Sói cắn đêm nay'), findsOneWidget);
      await close(tester);
    });

    testWidgets('the face says whether now is your turn, on server time', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'wolf',
        'roleLabel': 'Sói',
        'actions': [
          {
            'kind': 'wolf_bite',
            'label': 'Cắn',
            'help': '',
            'input': 'single_target',
            'enabled': true,
            'opensAt': '2026-10-17T13:00:00Z',
            'closesAt': '2026-10-17T15:05:00Z',
            'options': [
              {'id': 'u2', 'label': 'Bình'},
            ],
          },
        ],
      };
      await pumpScreen(tester);
      await tester.pump();
      expect(find.text('TỚI LƯỢT BẠN'), findsNothing);

      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('TỚI LƯỢT BẠN'), findsOneWidget);
      expect(
        find.textContaining('Còn 1 giờ 5 phút · khoá lúc'),
        findsOneWidget,
      );

      await elapse(tester, const Duration(hours: 1, minutes: 10));
      expect(find.text('TỚI LƯỢT BẠN'), findsNothing);
      expect(find.text('GIỜ NÀY BẠN NGHỈ'), findsOneWidget);
      await close(tester);
    });

    testWidgets('the face says when your turn opens, or that you are out', (
      tester,
    ) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'villager',
        'roleLabel': 'Dân',
        'actions': [
          {
            'kind': 'vote',
            'label': 'Biểu quyết',
            'help': '',
            'input': 'choice',
            'enabled': false,
            'opensAt': '2026-10-17T17:00:00Z',
            'closesAt': '2026-10-17T19:00:00Z',
          },
        ],
      };
      await pumpScreen(tester);
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('CHƯA TỚI GIỜ'), findsOneWidget);
      await close(tester);

      backend.me = {
        'status': 'running',
        'alive': false,
        'role': 'villager',
        'roleLabel': 'Dân',
      };
      await pumpScreen(tester);
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('BẠN ĐÃ BỊ LOẠI'), findsOneWidget);
      await close(tester);
    });

    testWidgets('shows the witch her potions', (tester) async {
      backend.game = running();
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'witch',
        'roleLabel': 'Phù thuỷ',
        'potions': {'save': false, 'poison': true},
      };
      await pumpScreen(tester);
      await tester.pump();

      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Bình cứu: đã dùng · Bình độc: còn'), findsOneWidget);
      await close(tester);
    });

    testWidgets('is not there for people outside the game', (tester) async {
      backend.game = running(registered: false);
      backend.me = {
        'status': 'running',
        'role': 'seer',
        'roleLabel': 'Tiên tri',
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('LÁ BÀI CỦA BẠN'), findsNothing);
      expect(backend.calls, isNot(contains('GET /v1/games/g1/me')));
      await close(tester);
    });

    testWidgets('players list shows a revealed card while the game runs', (
      tester,
    ) async {
      backend.game = {
        ...running(registered: false),
        'players': [
          {
            'uid': 'u2',
            'name': 'Bình',
            'alive': false,
            'deathRound': 2,
            'revealedRoleLabel': 'Thợ săn',
          },
        ],
      };
      await pumpScreen(tester);

      expect(find.text('Chết vòng 2'), findsOneWidget);
      expect(find.text('Thợ săn'), findsOneWidget);
      await close(tester);
    });

    testWidgets('players list shows every role once the game ends', (
      tester,
    ) async {
      backend.game = {
        ...running(),
        'status': 'ended',
        'statusLabel': 'Đã kết thúc',
        'players': [
          {'uid': 'u1', 'name': 'An', 'alive': false},
          {
            'uid': 'u2',
            'name': 'Bình',
            'alive': false,
            'revealedRoleLabel': 'Thợ săn',
          },
          {'uid': 'u3', 'name': 'Chi', 'alive': true},
        ],
      };
      backend.me = {
        'status': 'ended',
        'alive': true,
        'role': 'villager',
        'roleLabel': 'Dân',
        'allRoles': [
          {'uid': 'u1', 'name': 'An', 'role': 'wolf', 'roleLabel': 'Sói'},
          {
            'uid': 'u2',
            'name': 'Bình',
            'role': 'hunter',
            'roleLabel': 'Thợ săn',
          },
          {'uid': 'u3', 'name': 'Chi', 'role': 'villager', 'roleLabel': 'Dân'},
        ],
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Sói'), findsOneWidget);
      expect(find.text('Thợ săn'), findsOneWidget);
      expect(find.text('Dân'), findsOneWidget);
      await close(tester);
    });
  });

  group('actions', () {
    setUp(() {
      backend.game = {
        'id': 'g1',
        'title': 'Ma Sói tuần 42',
        'status': 'running',
        'statusLabel': 'Đang chơi',
        'refreshAfterSeconds': 300,
        'isRegistered': true,
      };
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'villager',
        'roleLabel': 'Dân',
        'actions': [
          {
            'kind': 'nominate',
            'label': 'Đề cử',
            'help': 'Chọn một người lên giàn.',
            'input': 'single_target',
            'enabled': true,
            'options': [
              {'id': 'u2', 'label': 'Bình'},
            ],
          },
        ],
      };
    });

    testWidgets('the actions live in the card block, under the card', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      expect(find.text('Việc của bạn'), findsNothing);
      final inCard = find.descendant(
        of: find.byType(GameMyCard),
        matching: find.text('Bình'),
      );
      expect(inCard, findsOneWidget);

      // Một việc thì câu hỏi nằm cạnh lá bài, không lặp tiêu đề dưới nút.
      expect(find.text('Chọn một người lên giàn'), findsOneWidget);
      expect(find.text('Đề cử'), findsNothing);

      // Bấm trượt cạnh nút chọn người thì lá bài không được úp xuống.
      await tester.ensureVisible(find.text('Bình'));
      await tester.pumpAndSettle();
      await tester.tapAt(
        tester.getCenter(find.text('Bình')) + const Offset(180, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Thêm'), findsOneWidget);
      await close(tester);
    });

    testWidgets('sends the pick for the action kind', (tester) async {
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Bình'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bình'));
      await tester.pump();
      await tester.pump();

      final sent = backend.requests.singleWhere(
        (r) => r.url.path == '/v1/games/g1/actions',
      );
      expect(jsonDecode(sent.body), {
        'kind': 'nominate',
        'targets': ['u2'],
      });
      await close(tester);
    });

    testWidgets('shows why the backend refused the pick', (tester) async {
      backend.failures['POST /v1/games/g1/actions'] = (
        409,
        {'error': 'phase_closed', 'message': 'Đã quá giờ đề cử.'},
      );
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Bình'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bình'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Đã quá giờ đề cử.'), findsOneWidget);
      await close(tester);
    });
  });

  group('km table', () {
    const table = {
      'lastLabel': 'Hôm qua · chốt 22h',
      'todayLabel': 'Hôm nay · tới 15:40',
      'unitKm': 1,
      'note': 'Km chốt lúc 22h.',
    };
    Map<String, dynamic> game(List<Map<String, dynamic>> players) => {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
      'isRegistered': true,
      'kmTable': table,
      'players': players,
    };

    testWidgets('ranks the living by today km, then 22h km, the dead last', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 9000);
      addTearDown(tester.view.reset);
      backend.game = game([
        {'uid': 'a', 'name': 'An', 'alive': true, 'lastKm': 5, 'todayKm': 0.4},
        {'uid': 'b', 'name': 'Bình', 'alive': false, 'deathRound': 1},
        {
          'uid': 'c',
          'name': 'Chi',
          'alive': true,
          'lastKm': 0.4,
          'todayKm': 3.1,
        },
        {
          'uid': 'd',
          'name': 'Dũng',
          'alive': true,
          'lastKm': 7.3,
          'todayKm': 2,
        },
        {'uid': 'h', 'name': 'Hà', 'alive': true, 'lastKm': 2, 'todayKm': 2},
      ]);
      await pumpScreen(tester);
      await tester.pump();

      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      final order = ['An', 'Bình', 'Chi', 'Dũng', 'Hà']
        ..sort((a, b) => y(a).compareTo(y(b)));
      expect(order, ['Chi', 'Dũng', 'Hà', 'An', 'Bình']);
      await close(tester);
    });

    testWidgets('without the table ranks by 22h km', (tester) async {
      tester.view.physicalSize = const Size(2400, 9000);
      addTearDown(tester.view.reset);
      backend.game = game([
        {'uid': 'a', 'name': 'An', 'alive': true, 'lastKm': 1.2},
        {'uid': 'c', 'name': 'Chi', 'alive': true, 'lastKm': 4},
        {'uid': 'k', 'name': 'Khoa', 'alive': true},
      ])..remove('kmTable');
      await pumpScreen(tester);
      await tester.pump();

      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      final order = ['An', 'Chi', 'Khoa']..sort((a, b) => y(a).compareTo(y(b)));
      expect(order, ['Chi', 'An', 'Khoa']);
      await close(tester);
    });

    testWidgets('shows today km per player and the km rule under the list', (
      tester,
    ) async {
      // Danh sách người chơi nằm dưới lá bài; màn cao để ListView dựng đủ.
      tester.view.physicalSize = const Size(2400, 9000);
      addTearDown(tester.view.reset);
      backend.game = game([
        {
          'uid': 'me',
          'name': 'Nam',
          'alive': true,
          'lastKm': 3.2,
          'todayKm': 0.4,
        },
        {
          'uid': 'u2',
          'name': 'Chi',
          'alive': true,
          'lastKm': 0.96,
          'todayKm': 2.35,
        },
        {
          'uid': 'u3',
          'name': 'Minh',
          'alive': false,
          'deathRound': 1,
          'lastKm': 5.0,
        },
      ]);
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Km chốt lúc 22h.'), findsOneWidget);
      // Luật không cắt phiếu thì không có đường cắt.
      expect(find.textContaining('MẤT PHIẾU'), findsNothing);
      expect(find.text('0.4 km'), findsOneWidget);
      expect(find.text('2.3 km'), findsOneWidget);
      expect(find.text('Bạn'), findsOneWidget);
      // Người chết không còn tính km, kể cả km đã chốt.
      expect(find.textContaining('5.0'), findsNothing);
      expect(find.text('Chết vòng 1'), findsOneWidget);
      await close(tester);
    });

    testWidgets(
      'the cut line sits between who keeps the vote and who may not',
      (tester) async {
        tester.view.physicalSize = const Size(2400, 9000);
        addTearDown(tester.view.reset);
        backend.game = game([
          {'uid': 'a', 'name': 'An', 'alive': true, 'todayKm': 0.5},
          {'uid': 'c', 'name': 'Chi', 'alive': true, 'todayKm': 2},
        ]);
        backend.game['kmTable'] = {
          ...table,
          'unitLabel': 'giữ phiếu',
          'cutLabel': 'Dưới 1 km · có thể mất phiếu',
        };
        await pumpScreen(tester);
        await tester.pump();

        final cut = find.text('DƯỚI 1 KM · CÓ THỂ MẤT PHIẾU');
        expect(cut, findsOneWidget);
        double y(Finder f) => tester.getTopLeft(f).dy;
        expect(y(find.text('Chi')), lessThan(y(cut)));
        expect(y(cut), lessThan(y(find.text('An'))));
        expect(find.text('giữ phiếu'), findsOneWidget);
        await close(tester);
      },
    );

    testWidgets('without the table shows 22h km', (tester) async {
      backend.game = game([
        {'uid': 'u2', 'name': 'Chi', 'alive': true, 'lastKm': 0.96},
      ])..remove('kmTable');
      await pumpScreen(tester);
      await tester.pump();

      // 0.96 km chưa đủ 1 km nên không được hiện thành 1.0.
      expect(find.text('0.9 km'), findsOneWidget);
      expect(find.text('xếp theo km hôm nay'), findsNothing);
      await close(tester);
    });

    testWidgets('km goals that give the role away show only face up', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2400, 9000);
      addTearDown(tester.view.reset);
      backend.game = game([
        {'uid': 'me', 'name': 'Nam', 'alive': true, 'todayKm': 1.4},
      ]);
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'wolf',
        'roleLabel': 'Sói',
        'kmGoals': [
          {
            'key': 'vote',
            'label': 'Giữ phiếu biểu quyết',
            'needKm': 1,
            'haveKm': 1.4,
          },
          {
            'key': 'team_skill',
            'label': 'Phe Sói cắn ở đêm tới',
            'needKm': 2,
            'haveKm': 1.2,
          },
        ],
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Giữ phiếu biểu quyết · 1 km'), findsOneWidget);
      expect(find.text('ĐỦ'), findsOneWidget);
      expect(find.text('Phe Sói cắn ở đêm tới · 2 km'), findsNothing);

      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Phe Sói cắn ở đêm tới · 2 km'), findsOneWidget);
      expect(find.text('còn 0.8 km'), findsOneWidget);
      await close(tester);
    });

    Map<String, Object?> witchAction(
      String kind,
      String label,
      String closes,
    ) => {
      'kind': kind,
      'label': label,
      'help': '',
      'input': 'single_target',
      'enabled': true,
      'opensAt': '2026-10-17T13:00:00Z',
      'closesAt': closes,
      'options': [
        {'id': 'u2', 'label': 'Bình'},
      ],
    };

    testWidgets('a trial game carries no trial label on screen', (
      tester,
    ) async {
      backend.game = {
        ...game([
          {'uid': 'me', 'name': 'Nam', 'alive': true},
        ]),
        'testMode': true,
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('VÁN THỬ'), findsNothing);
      await close(tester);
    });

    testWidgets('a locked task states its reason only once', (tester) async {
      backend.game = game([
        {'uid': 'me', 'name': 'Nam', 'alive': true},
      ]);
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'seer',
        'roleLabel': 'Tiên tri',
        'actions': [
          {
            ...witchAction('seer_check', 'Soi', '2026-10-17T15:05:00Z'),
            'help': 'Chọn một người để soi.',
            'enabled': false,
            'disabledReason': 'Chưa đủ km.',
          },
        ],
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      expect(find.text('CHƯA BẤM ĐƯỢC'), findsOneWidget);
      expect(find.text('Chưa đủ km.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('two tasks sharing a window show the time once', (
      tester,
    ) async {
      backend.game = game([
        {'uid': 'me', 'name': 'Nam', 'alive': true},
      ]);
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'witch',
        'roleLabel': 'Phù thuỷ',
        'actions': [
          witchAction('witch_save', 'Cứu', '2026-10-17T15:05:00Z'),
          witchAction('witch_poison', 'Độc', '2026-10-17T15:05:00Z'),
        ],
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      expect(find.textContaining('Còn 1 giờ 5 phút'), findsOneWidget);
      expect(find.textContaining('khoá lúc'), findsOneWidget);
      await close(tester);
    });

    testWidgets('two tasks closing at different times each keep their time', (
      tester,
    ) async {
      backend.game = game([
        {'uid': 'me', 'name': 'Nam', 'alive': true},
      ]);
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'witch',
        'roleLabel': 'Phù thuỷ',
        'actions': [
          witchAction('witch_save', 'Cứu', '2026-10-17T15:05:00Z'),
          witchAction('witch_poison', 'Độc', '2026-10-17T16:05:00Z'),
        ],
      };
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();

      expect(find.textContaining('Còn 1 giờ 5 phút'), findsNWidgets(2));
      expect(find.text('Còn 2 giờ 5 phút'), findsOneWidget);
      await close(tester);
    });

    testWidgets('wolves see the team km only on the face-up card', (
      tester,
    ) async {
      backend.game = game([
        {
          'uid': 'me',
          'name': 'Nam',
          'alive': true,
          'lastKm': 3.2,
          'todayKm': 1.4,
        },
      ]);
      backend.me = {
        'status': 'running',
        'alive': true,
        'role': 'wolf',
        'roleLabel': 'Sói',
        'teamKm': {
          'label': 'Km phe Sói',
          'last': 2.6,
          'today': 1.2,
          'need': 2,
          'needLabel': 'Cần 2 km để cắn',
        },
      };
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Km phe Sói'), findsNothing);
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Km phe Sói'), findsOneWidget);
      expect(find.text('Thiếu 0.8'), findsOneWidget);
      const detail =
          'Phe cần thêm 0.8 km trước lần chốt tới thì đêm sau mới cắn được.';
      expect(find.text(detail), findsNothing);
      expect(find.text('Cần 2 km để cắn'), findsNothing);

      await tester.tap(find.text('Km phe Sói'));
      await tester.pumpAndSettle();
      expect(find.text(detail), findsOneWidget);
      expect(find.text('Cần 2 km để cắn'), findsOneWidget);
      expect(
        find.text('Km phe Sói'),
        findsOneWidget,
        reason: 'chạm dòng km chỉ mở chi tiết, lá bài vẫn ngửa',
      );
      await close(tester);
    });
  });
}
