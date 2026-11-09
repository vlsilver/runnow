import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_skill_cards.dart';

Future<void> _pump(WidgetTester tester, List<GameSetupItem> items) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: GameSetupSections([
            GameSetupSection(title: 'Lịch', items: items),
          ]),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('khối không dòng nào có icon thì không chừa ô icon', (
    tester,
  ) async {
    await _pump(tester, const [
      GameSetupItem(
        key: 'startHour',
        icon: '',
        label: 'Giờ mở vòng đầu',
        value: '22h',
      ),
    ]);

    // Chỉ còn viền 1 + padding ngang 12 của khung.
    expect(tester.getTopLeft(find.text('Giờ mở vòng đầu')).dx, 13);
  });

  testWidgets('khối có icon thì dòng không icon vẫn thẳng hàng', (
    tester,
  ) async {
    await _pump(tester, const [
      GameSetupItem(
        key: 'darkVote',
        icon: 'vote',
        label: 'Phiếu Đôi',
        value: 'Bật',
      ),
      GameSetupItem(
        key: 'darkKm',
        icon: '',
        label: 'Km để mở',
        value: '1.5 km',
      ),
    ]);

    // Viền 1 + padding 12 + ô icon 28 + khoảng cách 12.
    expect(tester.getTopLeft(find.text('Phiếu Đôi')).dx, 53);
    expect(tester.getTopLeft(find.text('Km để mở')).dx, 53);
  });
}
