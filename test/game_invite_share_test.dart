import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_invite_share.dart';
import 'package:myrun/src/games/game_models.dart';

GameDetail _game({
  int count = 8,
  int max = 12,
  DateTime? deadline,
  List<String> players = const [],
  bool km = true,
}) => GameDetail.fromJson({
  'id': 'g1',
  'title': 'Đêm trăng PSC',
  'status': 'registering',
  'statusLabel': 'Đang mở đăng ký',
  'refreshAfterSeconds': 300,
  'playerCount': count,
  'minPlayers': 8,
  'maxPlayers': max,
  'registrationDeadline': deadline?.toUtc().toIso8601String(),
  'players': [
    for (final name in players) {'uid': name, 'name': name, 'alive': true},
  ],
  'rulesCard': [
    if (km)
      {
        'title': 'Km',
        'items': [
          {'key': 'kmWindow', 'label': 'Tính km', 'value': '22h'},
        ],
      },
  ],
});

GameDetail _running({
  int alive = 8,
  int dead = 2,
  List<String?> deadRoles = const [],
  String? phase = 'Đêm 2, sói đang chọn',
  bool km = true,
  String title = 'Đêm trăng PSC',
}) => GameDetail.fromJson({
  'id': 'g1',
  'title': title,
  'status': 'running',
  'statusLabel': 'Đang chơi',
  'refreshAfterSeconds': 30,
  'phase': phase == null
      ? null
      : {
          'key': 'night',
          'label': phase,
          'deadline': DateTime(2026, 11, 9, 20, 30).toUtc().toIso8601String(),
          'state': 'open',
        },
  if (km)
    'kmTable': {
      'lastLabel': 'Chốt',
      'todayLabel': 'Tới giờ',
      'unitKm': 1,
      'note': '',
    },
  'players': [
    for (var i = 0; i < alive; i++)
      {'uid': 'a$i', 'name': 'Sống$i', 'alive': true, if (km) 'todayKm': 5.4},
    for (var i = 0; i < dead; i++)
      {
        'uid': 'd$i',
        'name': 'Ngã$i',
        'alive': false,
        'revealedRoleLabel': i < deadRoles.length ? deadRoles[i] : 'Tiên tri',
      },
  ],
});

GameSummary _summary({
  String winnerLabel = 'Phe Dân thắng',
  String subtitle = '',
  int titles = 1,
  int stats = 1,
}) => GameSummary.fromJson({
  'winner': winnerLabel.isEmpty ? '' : 'village',
  'winnerLabel': winnerLabel,
  'subtitle': subtitle,
  'stats': [
    for (var i = 0; i < stats; i++)
      {'label': 'Số $i', 'value': '${212 + i} km'},
  ],
  'titles': [
    for (var i = 0; i < titles; i++)
      {
        'key': 'runner',
        'label': 'Chạy nhiều nhất $i',
        'name': 'Nguyễn Thị Ngọc Ánh Dương $i',
        'value': '38.2 km',
      },
  ],
});

void main() {
  group('gameInviteCaption', () {
    const link = 'https://threei.run/games/g1';

    test('says the free seats and the local closing time', () {
      expect(
        gameInviteCaption(_game(deadline: DateTime(2026, 11, 9, 20))),
        'Còn 4 chỗ, chốt 20:00 T2 09/11. Vào không?\n$link',
      );
    });

    test('calls Sunday CN', () {
      expect(
        gameInviteCaption(_game(deadline: DateTime(2026, 11, 8, 7, 5))),
        'Còn 4 chỗ, chốt 07:05 CN 08/11. Vào không?\n$link',
      );
    });

    test('leaves out the closing time when the game has none', () {
      expect(gameInviteCaption(_game()), 'Còn 4 chỗ. Vào không?\n$link');
    });

    test('does not promise a seat in a full game', () {
      expect(
        gameInviteCaption(_game(count: 12)),
        'Đã đủ 12 người. Vào xem không?\n$link',
      );
    });
  });

  group('gameLiveCaption', () {
    const link = 'https://threei.run/games/g1';

    test('says the phase and who is still alive', () {
      expect(
        gameLiveCaption(_running()),
        'Đêm 2, sói đang chọn. Còn 8/10 người sống, ai là sói?\n$link',
      );
    });

    test('still reads well without a phase', () {
      expect(
        gameLiveCaption(_running(phase: null)),
        'Ma Sói đang chơi. Còn 8/10 người sống, ai là sói?\n$link',
      );
    });
  });

  group('GameLiveCard', () {
    Future<void> pump(WidgetTester tester, GameDetail game) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(child: GameLiveCard(game: game)),
          ),
        );

    testWidgets('shows the phase, the survivors and the village km', (
      tester,
    ) async {
      await pump(tester, _running());

      expect(find.text('ĐANG CHƠI'), findsOneWidget);
      expect(find.text('Đêm 2'), findsOneWidget);
      expect(find.text('sói đang chọn'), findsOneWidget);
      expect(find.text('Đêm trăng PSC'), findsOneWidget);
      expect(find.text('8/10'), findsOneWidget);
      expect(find.text('còn sống'), findsOneWidget);
      expect(find.text('43'), findsOneWidget); // 8 × 5,4 km = 43,2
      expect(find.text('km cả làng'), findsOneWidget);
    });

    testWidgets('leaves out the title when it is just the game name', (
      tester,
    ) async {
      await pump(tester, _running(title: 'Ma Sói'));

      expect(find.text('Ma Sói'), findsNothing);
    });

    testWidgets('a phase with no detail is just the headline', (tester) async {
      await pump(tester, _running(phase: 'Chuẩn bị'));

      expect(find.text('Chuẩn bị'), findsOneWidget);
      expect(find.text('Đêm trăng PSC'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('counts the dead and the wolves the village knows are dead', (
      tester,
    ) async {
      await pump(
        tester,
        _running(
          alive: 6,
          dead: 4,
          // Sói lộ lá bài, Sói bị treo chỉ lộ phe, một Dân, một người chưa lộ.
          deadRoles: ['Sói', 'Phe Sói', 'Phe Dân', null],
        ),
      );

      expect(find.text('6/10'), findsOneWidget);
      expect(find.text('4'), findsOneWidget);
      expect(find.text('đã ngủm'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('sói đã ngủm'), findsOneWidget);
    });

    testWidgets('a game without km shows when the phase closes', (
      tester,
    ) async {
      await pump(tester, _running(km: false));

      expect(find.text('km cả làng'), findsNothing);
      expect(find.text('20:30'), findsOneWidget);
      expect(find.text('chốt lượt này'), findsOneWidget);
    });

    testWidgets('never shows a revealed role or anyone km', (tester) async {
      await pump(tester, _running());

      expect(find.textContaining('Tiên tri'), findsNothing);
      expect(find.textContaining('5,4'), findsNothing);
    });

    testWidgets('a full village fits the fixed card', (tester) async {
      await pump(
        tester,
        _running(
          alive: 20,
          dead: 4,
          phase: 'Chuẩn bị, đêm 1 bắt đầu lúc 22:00',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(GameLiveCard)), const Size(320, 400));
    });
  });

  group('gameEndedCaption', () {
    const link = 'https://threei.run/games/g1';

    test('says who won which game', () {
      expect(
        gameEndedCaption(_running(), _summary()),
        'Phe Dân thắng ván Đêm trăng PSC.\n$link',
      );
    });

    test('still reads well without a winner from an old backend', () {
      expect(
        gameEndedCaption(_running(title: 'Ma Sói'), _summary(winnerLabel: '')),
        'Ván Ma Sói đã kết thúc.\n$link',
      );
    });
  });

  group('GameEndedCard', () {
    Future<void> pump(
      WidgetTester tester,
      GameSummary summary, {
      String title = 'Đêm trăng PSC',
      int rounds = 4,
    }) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GameEndedCard(
            game: _running(title: title),
            summary: summary,
            rounds: rounds,
          ),
        ),
      ),
    );

    testWidgets('shows the winner, the titles and the game numbers', (
      tester,
    ) async {
      await pump(tester, _summary(subtitle: 'Treo đủ 3 sói'));

      expect(find.text('PHE DÂN THẮNG'), findsOneWidget);
      expect(find.text('SAU 4 VÒNG'), findsOneWidget);
      expect(find.text('Treo đủ 3 sói'), findsOneWidget);
      expect(find.text('Đêm trăng PSC'), findsOneWidget);
      expect(find.text('Chạy nhiều nhất 0'), findsOneWidget);
      expect(
        find.text('Nguyễn Thị Ngọc Ánh Dương 0 · 38.2 km'),
        findsOneWidget,
      );
      expect(find.text('212 km'), findsOneWidget);
    });

    testWidgets('a game without a known winner or rounds still reads well', (
      tester,
    ) async {
      await pump(tester, _summary(winnerLabel: ''), title: 'Ma Sói', rounds: 0);

      expect(find.text('ĐÃ KẾT THÚC'), findsOneWidget);
      expect(find.textContaining('VÒNG'), findsNothing);
      expect(find.text('Ma Sói'), findsNothing);
    });

    testWidgets('a full summary fits the fixed card', (tester) async {
      await pump(
        tester,
        _summary(
          subtitle: 'Treo đủ 3 sói · còn 5 người sống · làng chạy 212 km',
          titles: 6,
          stats: 6,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(GameEndedCard)), const Size(320, 400));
      expect(find.text('Chạy nhiều nhất 3'), findsNothing);
      expect(find.text('216 km'), findsNothing);
    });
  });

  group('GameInviteCard', () {
    Future<void> pump(WidgetTester tester, GameDetail game) =>
        tester.pumpWidget(
          MaterialApp(
            home: Center(child: GameInviteCard(game: game)),
          ),
        );

    testWidgets('shows the game, its seats and when it closes', (tester) async {
      await pump(tester, _game(deadline: DateTime(2026, 11, 9, 20)));

      expect(find.text('Đêm trăng PSC'), findsOneWidget);
      expect(find.text('8/12'), findsOneWidget);
      expect(find.text('người đã vào'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget);
      expect(find.text('chốt, T2 09/11'), findsOneWidget);
    });

    testWidgets('has no closing cell without a deadline', (tester) async {
      await pump(tester, _game());

      expect(find.text('8/12'), findsOneWidget);
      expect(find.textContaining('chốt'), findsNothing);
    });

    testWidgets('shows four faces and counts the rest', (tester) async {
      await pump(
        tester,
        _game(players: ['An', 'Bình', 'Lan', 'Tú', 'Minh', 'Hà', 'Sơn', 'Vy']),
      );

      expect(find.text('A'), findsOneWidget);
      expect(find.text('T'), findsOneWidget);
      expect(find.text('M'), findsNothing);
      expect(find.text('+4'), findsOneWidget);
    });

    testWidgets('has no extra face when four or fewer joined', (tester) async {
      await pump(tester, _game(count: 2, players: ['An', 'Bình']));

      expect(find.text('B'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('does not talk about running in a game without km', (
      tester,
    ) async {
      await pump(tester, _game());
      expect(find.text('Chạy thật, sống sót thật'), findsOneWidget);

      await pump(tester, _game(km: false));
      expect(find.text('Chạy thật, sống sót thật'), findsNothing);
    });

    testWidgets('keeps a long title inside the card', (tester) async {
      await pump(
        tester,
        GameDetail.fromJson({
          'id': 'g1',
          'title': 'Ma Sói ' * 30,
          'status': 'registering',
          'statusLabel': '',
          'refreshAfterSeconds': 300,
        }),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
