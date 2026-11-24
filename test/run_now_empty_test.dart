import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/run_now_empty.dart';

Future<void> _pumpEmpty(WidgetTester tester, RunNowElement element) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunNowTheme(element, appearance: RunNowAppearance.light),
      home: const Scaffold(
        body: RunNowEmpty(message: 'Chưa có gì', hint: 'Gợi ý'),
      ),
    ),
  );
  // Đổi theme có hiệu ứng chuyển màu; chờ xong mới đọc.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('giữa sân là biểu tượng hành của theme đang dùng', (
    tester,
  ) async {
    await _pumpEmpty(tester, RunNowElement.fire);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsOneWidget);
    expect(find.text('Chưa có gì'), findsOneWidget);
    expect(find.text('Gợi ý'), findsOneWidget);

    await _pumpEmpty(tester, RunNowElement.water);
    expect(find.byIcon(Icons.water_drop_outlined), findsOneWidget);
    expect(find.byIcon(Icons.local_fire_department_outlined), findsNothing);
  });
}
