import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_dialog.dart';
import 'package:myrun/src/theme_tokens.dart';

void main() {
  late Future<bool> result;

  Future<void> open(WidgetTester tester, {String? confirmLabel}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => result = showGameConfirm(
              context,
              title: 'Bắt đầu ván?',
              body: const Text('Nội dung'),
              confirmLabel: confirmLabel,
              cancelLabel: 'Thôi',
            ),
            child: const Text('Mở'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Mở'));
    await tester.pumpAndSettle();
  }

  Color? fillOf(WidgetTester tester, Finder button) => tester
      .widget<Material>(
        find.descendant(of: button, matching: find.byType(Material)).first,
      )
      .color;

  // Màn ván gọi popup bằng context của State, nằm phía trên Theme trăng của màn.
  testWidgets('is moonlit even when the caller sits above the screen theme', (
    tester,
  ) async {
    await open(tester, confirmLabel: 'Bắt đầu');

    expect(
      fillOf(tester, find.widgetWithText(FilledButton, 'Bắt đầu')),
      RunNowMoonlitTokens.amber,
    );
    expect(
      tester
          .widget<Material>(
            find
                .descendant(
                  of: find.widgetWithText(OutlinedButton, 'Thôi'),
                  matching: find.byType(Material),
                )
                .first,
          )
          .textStyle
          ?.color,
      RunNowMoonlitTokens.ink,
    );
  });

  testWidgets('confirm answers true', (tester) async {
    await open(tester, confirmLabel: 'Bắt đầu');

    await tester.tap(find.text('Bắt đầu'));
    await tester.pumpAndSettle();

    expect(await result, isTrue);
  });

  testWidgets('cancel answers false', (tester) async {
    await open(tester, confirmLabel: 'Bắt đầu');

    await tester.tap(find.text('Thôi'));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('tapping outside answers false', (tester) async {
    await open(tester, confirmLabel: 'Bắt đầu');

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(await result, isFalse);
  });

  testWidgets('without a confirm label only the cancel button shows', (
    tester,
  ) async {
    await open(tester);

    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Thôi'), findsOneWidget);
  });
}
