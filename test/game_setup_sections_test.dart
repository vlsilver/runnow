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

  testWidgets('giá trị dài xuống hàng dưới nhãn, không tràn', (tester) async {
    const value =
        'Bạn là thám tử Conan, phong thái điềm tĩnh, lối lập luận sắc bén, '
        'hay chốt câu bằng một suy luận bất ngờ.';
    await _pump(tester, const [
      GameSetupItem(
        key: 'persona',
        icon: '',
        label: 'Tính cách Quản trò',
        value: value,
      ),
    ]);

    expect(tester.takeException(), isNull);
    final label = tester.getRect(find.text('Tính cách Quản trò'));
    final body = tester.getRect(find.text(value));
    // Nhãn nằm trọn một dòng (cỡ chữ 14.5), giá trị bắt đầu bên dưới nhãn.
    expect(label.height, lessThan(30));
    expect(body.top, greaterThanOrEqualTo(label.bottom));
    expect(body.right, lessThanOrEqualTo(800 - 13));
  });

  testWidgets('giá trị ngắn vẫn nằm sát mép phải cùng hàng với nhãn', (
    tester,
  ) async {
    await _pump(tester, const [
      GameSetupItem(key: 'shot', icon: '', label: 'Bắn khi ngã', value: '1 km'),
    ]);

    final label = tester.getRect(find.text('Bắn khi ngã'));
    final value = tester.getRect(find.text('1 km'));
    expect(value.center.dy, closeTo(label.center.dy, 0.5));
    // Màn test rộng 800: trừ viền 1 + padding 12.
    expect(value.right, 800 - 13);
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
