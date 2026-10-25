import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_detail_screen.dart';
import 'package:myrun/src/providers.dart';
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

void main() {
  late DateTime now;
  late FakeGameBackend backend;
  late List<Uri> opened;
  late bool openOk;
  late CardShareStore shareStore;
  final share = _FakeShare();

  setUpAll(() => SharePlatform.instance = share);

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
          cardShareStoreProvider.overrideWithValue(shareStore),
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
      // Chưa chia vai thì /me chưa có role: chưa có lá bài.
      expect(find.textContaining('Lá bài của bạn'), findsNothing);
      await close(tester);
    });
  });

  const faceDown = 'Đang úp. Chạm để xem vai, việc cần làm và chat phe.';

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
        'roleRules': 'Mỗi đêm soi một người.',
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
      expect(find.text('Tiên tri'), findsNothing);
      expect(find.text('Vòng 1: An là Dân'), findsNothing);

      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Tiên tri'), findsWidgets);
      expect(find.text('Mỗi đêm soi một người.'), findsOneWidget);
      expect(find.text('Vòng 1: An là Dân'), findsOneWidget);

      await tester.tap(find.text('Vào nhóm Sói'));
      await tester.pump();
      expect(opened, [Uri.parse('https://t.me/+wolves')]);

      await tester.tap(find.text('Chạm ra ngoài lá bài để úp lại.'));
      await tester.pumpAndSettle();
      expect(find.text('Mỗi đêm soi một người.'), findsNothing);
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

      await tester.tap(find.text('Khoe video 3d'));
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
      expect(find.text('Tiên tri'), findsWidgets);

      // App switcher của iOS chụp màn lúc inactive.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(find.text(faceDown), findsOneWidget);
      expect(find.text('Tiên tri'), findsNothing);
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
      expect(find.text('Việc của bạn'), findsNothing);
      expect(find.text('Cắn'), findsNothing);

      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Việc của bạn'), findsOneWidget);
      expect(find.text('Cắn'), findsOneWidget);
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
      expect(find.text('Tới giờ của bạn'), findsNothing);

      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Tới giờ của bạn'), findsOneWidget);
      expect(
        find.textContaining('Còn 1 giờ 5 phút · khoá lúc'),
        findsOneWidget,
      );

      await elapse(tester, const Duration(hours: 1, minutes: 10));
      expect(find.text('Tới giờ của bạn'), findsNothing);
      expect(find.text('Giờ này bạn nghỉ'), findsOneWidget);
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
      expect(find.text('Chưa tới giờ của bạn'), findsOneWidget);
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
      expect(find.text('Bạn đã bị loại'), findsOneWidget);
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

      expect(find.textContaining('Lá bài của bạn'), findsNothing);
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

      expect(find.text('Chết vòng 2 · Thợ săn'), findsOneWidget);
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

      expect(find.text('Đã chết · Sói'), findsOneWidget);
      expect(find.text('Đã chết · Thợ săn'), findsOneWidget);
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

    testWidgets('sends the pick for the action kind', (tester) async {
      await pumpScreen(tester);
      await tester.pump();
      await tester.tap(find.text(faceDown));
      await tester.pumpAndSettle();
      expect(find.text('Việc của bạn'), findsOneWidget);

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

    testWidgets('shows your km against the mark and both columns per player', (
      tester,
    ) async {
      // Danh sách người chơi nằm dưới card km; màn cao để ListView dựng đủ.
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

      expect(find.text('Km của bạn'), findsOneWidget);
      expect(find.text('Thiếu 0.6'), findsOneWidget);
      expect(
        find.text('Chạy thêm 0.6 km trước 22h để đủ mốc.'),
        findsOneWidget,
      );
      expect(find.text('Km chốt lúc 22h.'), findsOneWidget);
      // 0.96 km chưa đủ mốc 1 km nên không được hiện thành 1.0.
      expect(find.text('0.9'), findsOneWidget);
      expect(find.text('2.3'), findsOneWidget);
      expect(find.text('Bạn'), findsOneWidget);
      // Người chết không còn tính km, kể cả km đã chốt.
      expect(find.text('5.0'), findsNothing);
      expect(find.text('Chết vòng 1'), findsOneWidget);
      await close(tester);
    });

    testWidgets('without the table keeps one column of 22h km', (tester) async {
      backend.game = game([
        {'uid': 'u2', 'name': 'Chi', 'alive': true, 'lastKm': 0.96},
      ])..remove('kmTable');
      await pumpScreen(tester);
      await tester.pump();

      expect(find.text('Km của bạn'), findsNothing);
      expect(find.text('Km chốt'), findsOneWidget);
      expect(find.text('0.9'), findsOneWidget);
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
      expect(
        find.text('Phe cần thêm 0.8 km trước 22h thì đêm nay mới cắn được.'),
        findsOneWidget,
      );
      await close(tester);
    });
  });
}
