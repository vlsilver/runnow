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
}) =>
    GameDetail.fromJson({
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

  group('GameInviteCard', () {
    Future<void> pump(WidgetTester tester, GameDetail game) => tester.pumpWidget(
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
