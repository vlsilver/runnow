import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/theme.dart';

Future<Brightness?> _iconsUnderAppBar(
  WidgetTester tester,
  RunNowAppearance appearance,
  RunNowStyle style,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunNowTheme(
        RunNowElement.values.first,
        appearance: appearance,
        style: style,
      ),
      home: Scaffold(appBar: AppBar(title: const Text('Buổi chạy'))),
    ),
  );
  return tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.byType(AnnotatedRegion<SystemUiOverlayStyle>).first,
      )
      .value
      .statusBarIconBrightness;
}

void main() {
  // AppBar nền trong suốt: icon thanh trạng thái theo nền app, vì trang
  // không có AppBar (Home) giữ nguyên kiểu của trang trước.
  for (final style in RunNowStyle.values) {
    testWidgets('nền sáng ($style) thì icon thanh trạng thái tối', (
      tester,
    ) async {
      expect(
        await _iconsUnderAppBar(tester, RunNowAppearance.light, style),
        Brightness.dark,
      );
    });

    testWidgets('nền tối ($style) thì icon thanh trạng thái sáng', (
      tester,
    ) async {
      expect(
        await _iconsUnderAppBar(tester, RunNowAppearance.dark, style),
        Brightness.light,
      );
    });
  }
}
