import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/settings_screen.dart';

import 'support/fake_game_backend.dart';

const _linked = {
  'linked': true,
  'tgUsername': 'an',
  'displayName': 'An',
  'inPsc': true,
};

void main() {
  late FakeGameBackend backend;
  late List<Uri> opened;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TelegramLinkSettings(
              openUrl: (uri) async {
                opened.add(uri);
                return true;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox());

  setUp(() {
    backend = FakeGameBackend(() => DateTime.utc(2026, 10, 18, 14));
    opened = [];
  });

  testWidgets('links Telegram from settings', (tester) async {
    await pump(tester);
    expect(find.text('Liên kết Telegram'), findsOneWidget);

    await tester.tap(find.text('Liên kết Telegram'));
    await tester.pump();
    await tester.pump();
    expect(opened, [Uri.parse('https://t.me/runnow3i_bot?start=K7Q2')]);
    expect(
      find.text('Bấm Start trong Telegram rồi quay lại đây.'),
      findsOneWidget,
    );

    backend.telegram = {..._linked};
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(find.text('@an'), findsOneWidget);
    expect(find.text('Liên kết Telegram'), findsNothing);
    await close(tester);
  });

  testWidgets('re-reads the link when the app comes back', (tester) async {
    await pump(tester);
    // Người dùng bấm Start bên Telegram sau khi hết 2 phút poll.
    backend.telegram = {..._linked};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.text('@an'), findsOneWidget);
    await close(tester);
  });

  testWidgets('unlinks, and shows why when the backend refuses', (
    tester,
  ) async {
    backend.telegram = {..._linked};
    backend.failures['DELETE /v1/telegram/link'] = (
      409,
      {'error': 'in_game', 'message': 'Đang trong ván Ma Sói, chưa huỷ được.'},
    );
    await pump(tester);
    await tester.tap(find.text('Huỷ liên kết Telegram'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Đang trong ván Ma Sói, chưa huỷ được.'), findsOneWidget);
    expect(find.text('@an'), findsOneWidget);

    backend.failures.clear();
    await tester.tap(find.text('Huỷ liên kết Telegram'));
    await tester.pump();
    await tester.pump();
    expect(backend.calls, contains('DELETE /v1/telegram/link'));
    expect(find.text('Liên kết Telegram'), findsOneWidget);
    await close(tester);
  });

  testWidgets('offers a retry when the status cannot be read', (tester) async {
    backend.failures['GET /v1/telegram/link'] = (500, {'error': 'internal'});
    await pump(tester);
    expect(
      find.text('Chưa đọc được trạng thái. Chạm để thử lại.'),
      findsOneWidget,
    );

    backend.failures.clear();
    await tester.tap(find.text('Chưa đọc được trạng thái. Chạm để thử lại.'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Liên kết Telegram'), findsOneWidget);
    await close(tester);
  });
}
