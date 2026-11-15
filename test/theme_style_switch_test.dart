import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/theme.dart';

void main() {
  // MaterialApp chuyển dần giữa hai theme. Nhãn nút của hai kiểu mà khác
  // `inherit` thì TextStyle.lerp ném assert giữa chừng, lượt build đó bỏ dở và
  // các màn đang mở kẹt ở kiểu cũ.
  for (final (from, to) in [
    (RunNowStyle.elemental, RunNowStyle.iron),
    (RunNowStyle.iron, RunNowStyle.elemental),
    (RunNowStyle.elemental, RunNowStyle.pixel),
    (RunNowStyle.pixel, RunNowStyle.elemental),
    (RunNowStyle.iron, RunNowStyle.pixel),
    (RunNowStyle.pixel, RunNowStyle.iron),
  ]) {
    testWidgets('đổi kiểu ${from.name} sang ${to.name} lúc đang có nút', (
      tester,
    ) async {
      Widget app(RunNowStyle style) => MaterialApp(
        theme: buildRunNowTheme(
          RunNowElement.water,
          appearance: RunNowAppearance.light,
          style: style,
        ),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('Áp dụng')),
              OutlinedButton(onPressed: () {}, child: const Text('Huỷ')),
              TextButton(onPressed: () {}, child: const Text('Xem')),
            ],
          ),
        ),
      );

      await tester.pumpWidget(app(from));
      await tester.pumpWidget(app(to));
      for (var frame = 0; frame < 30; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.takeException(), isNull, reason: 'frame $frame');
      }
    });
  }
}
