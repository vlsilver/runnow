import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_time_picker.dart';

void main() {
  testWidgets('the deadline sheet fits a phone and greys out past hours', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    GameDeadlinePick? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => picked = await showGameDeadlineSheet(
              context,
              now: DateTime(2026, 11, 7, 21, 50),
            ),
            child: const Text('mở'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 21h50 thứ 7: "Tối nay 21h" đã qua, cuối tuần là thứ 7 tuần sau.
    await tester.tap(find.text('Tối nay 21h'));
    await tester.pump();
    expect(find.text('Thứ 7, 14/11'), findsNothing);
    await tester.tap(find.text('Cuối tuần 20h'));
    await tester.pump();
    expect(find.text('Thứ 7, 14/11'), findsOneWidget);
    await tester.tap(find.text('NAY'));
    await tester.pump();
    // Hôm nay 20h đã qua nên Xong không bấm được; 23h thì được.
    expect(find.text('Giờ này đã qua'), findsOneWidget);
    await tester.tap(find.text('23h'));
    await tester.tap(find.text(':00'));
    await tester.pump();
    await tester.tap(find.text('Xong'));
    await tester.pumpAndSettle();
    expect(picked?.at, DateTime(2026, 11, 7, 23));
  });

  test(
    'time left reads in days and hours, minutes only when under an hour',
    () {
      final now = DateTime(2026, 11, 6, 10);
      expect(
        gameUntil(now.add(const Duration(days: 1, hours: 3, minutes: 20)), now),
        'còn 1 ngày 3 tiếng',
      );
      expect(gameUntil(now.add(const Duration(days: 2)), now), 'còn 2 ngày');
      expect(gameUntil(now.add(const Duration(hours: 2)), now), 'còn 2 tiếng');
      expect(
        gameUntil(now.add(const Duration(minutes: 45)), now),
        'còn 45 phút',
      );
      expect(
        gameUntil(now.subtract(const Duration(minutes: 1)), now),
        'đã qua',
      );
    },
  );
}
