import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_detail_screen.dart';
import 'package:myrun/src/providers.dart';

import 'support/fake_game_backend.dart';

void main() {
  late DateTime now;
  late FakeGameBackend backend;
  late List<Uri> opened;
  late bool openOk;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
        ],
        child: MaterialApp(
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

  setUp(() {
    now = DateTime.utc(2026, 10, 17, 14);
    backend = FakeGameBackend(() => now);
    opened = [];
    openOk = true;
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
    await tester.tap(find.text('Luật chơi'));
    await tester.pumpAndSettle();
    expect(find.text('Sói cắn mỗi đêm.'), findsOneWidget);

    backend.game['rulesText'] = 'Sói cắn mỗi đêm, trừ đêm đầu.';
    await elapse(tester, const Duration(seconds: 30));

    expect(find.text('Sói cắn mỗi đêm.'), findsNothing);
    expect(find.text('Sói cắn mỗi đêm, trừ đêm đầu.'), findsOneWidget);
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
        'key': 'r2.day',
        'label': 'Ngày 2: đề cử',
        'deadline': now.add(const Duration(minutes: 5)).toIso8601String(),
        'state': 'open',
      },
    };
    await pumpScreen(tester);
    expect(find.text('Ngày 2: đề cử'), findsOneWidget);

    await elapse(tester, const Duration(minutes: 5));

    expect(find.text('Ngày 2: đề cử'), findsNothing);
    expect(find.text('Đang chốt…'), findsOneWidget);
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

    expect(find.text('Đã liên kết @an.'), findsOneWidget);
    expect(gameReads, hasLength(2));
    await close(tester);
  });

  testWidgets('shows why unlinking is refused mid-game', (tester) async {
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
    backend.failures['DELETE /v1/telegram/link'] = (
      409,
      {'error': 'in_game', 'message': 'Đang trong ván, chưa huỷ được.'},
    );
    await pumpScreen(tester);

    await tester.tap(find.text('Không phải bạn? Huỷ'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Đang trong ván, chưa huỷ được.'), findsOneWidget);
    expect(find.text('Đã liên kết @an.'), findsOneWidget);
    expect(backend.calls.where((c) => c == 'GET /v1/games/g1'), hasLength(1));
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

    expect(find.text('Đã liên kết @an.'), findsOneWidget);
    await close(tester);
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
      expect(find.text('8 người sẽ chơi, cần 8–16.'), findsOneWidget);
      expect(find.text('Bình: chưa liên kết Telegram'), findsOneWidget);
      expect(starts(), ['dryRun=true']);

      await tester.tap(find.text('Bắt đầu'));
      await tester.pumpAndSettle();

      expect(starts(), ['dryRun=true', '']);
      expect(find.text('Đang chia bài'), findsOneWidget);
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
      expect(find.text('Bắt đầu'), findsNothing);

      await tester.tap(find.text('Đóng'));
      await tester.pumpAndSettle();
      expect(starts(), ['dryRun=true']);
      expect(find.text('Bắt đầu ván'), findsOneWidget);
      await close(tester);
    });

    testWidgets('is hidden from players', (tester) async {
      backend.game = registering(admin: false);
      await pumpScreen(tester);

      expect(find.text('Đăng ký'), findsOneWidget);
      expect(find.text('Bắt đầu ván'), findsNothing);
      await close(tester);
    });
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
        tester.widget(find.widgetWithText(FilledButton, 'Đăng ký'));

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

      await tester.tap(find.text('Đăng ký'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Bạn chưa đủ điều kiện đăng ký.'), findsOneWidget);
      expect(find.text('Đang ở trong group PSC'), findsOneWidget);
      expect(registerButton(tester).onPressed, isNull);
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
      await close(tester);
    });
  });
}
