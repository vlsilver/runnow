import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_card.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

void main() {
  // iPhone 375pt trừ padding list (32) và card (30) còn 313pt; chữ phóng to
  // thì hàng số người, hạn và badge không vừa một dòng.
  testWidgets('fits a narrow phone with large text', (tester) async {
    final game = GameListItem.fromJson({
      'id': 'g1',
      'title': 'Ma Sói',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'playerCount': 12,
      'maxPlayers': 16,
      'hasTodo': true,
      'nextDeadline': DateTime.utc(2026, 10, 18, 10).toIso8601String(),
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunNowTheme(RunNowElement.water),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 343,
                child: GameCard(game: game, onTap: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Có việc cho bạn'), findsOneWidget);
  });
}
