import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/run_now_switch.dart';

void main() {
  Widget app(RunNowStyle style, Widget child) => MaterialApp(
    theme: buildRunNowTheme(
      RunNowElement.water,
      appearance: RunNowAppearance.light,
      style: style,
    ),
    home: Scaffold(body: child),
  );

  testWidgets('kiểu Thép: hàng công tắc không dùng Switch tròn, chạm thì đổi', (
    tester,
  ) async {
    final changes = <bool>[];
    await tester.pumpWidget(
      app(
        RunNowStyle.iron,
        RunNowSwitchListTile(
          value: false,
          onChanged: changes.add,
          title: const Text('Live lên group'),
        ),
      ),
    );

    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.text('Live lên group'));
    expect(changes, [true]);
  });

  testWidgets('kiểu Thép: công tắc bị khoá thì chạm không đổi', (tester) async {
    await tester.pumpWidget(
      app(
        RunNowStyle.iron,
        const Center(child: RunNowSwitch(value: true, onChanged: null)),
      ),
    );

    await tester.tap(find.byType(RunNowSwitch));
    expect(tester.takeException(), isNull);
  });

  testWidgets('kiểu thường vẫn là Switch của Material', (tester) async {
    await tester.pumpWidget(
      app(
        RunNowStyle.elemental,
        RunNowSwitch(value: true, onChanged: (_) {}),
      ),
    );

    expect(find.byType(Switch), findsOneWidget);
  });
}
