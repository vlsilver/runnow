import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/app_update.dart';

const _store = 'https://apps.apple.com/app/id1';

void main() {
  test('compares versions number by number, ignoring the build', () {
    expect(compareVersions('1.10.0', '1.9.9'), 1);
    expect(compareVersions('1.4.3', '1.5.0'), -1);
    expect(compareVersions('1.5', '1.5.0'), 0);
    expect(compareVersions('1.5.0+12', '1.5.0'), 0);
    expect(compareVersions(' 2.0.0 ', '1.99.99'), 1);
    for (final bad in ['', 'abc', '1..2', '1.x', '-1.0']) {
      expect(compareVersions(bad, '1.0.0'), isNull, reason: bad);
    }
  });

  late List<Uri> opened;
  late bool openResult;

  Future<void> pump(
    WidgetTester tester, {
    required String current,
    required AppUpdateConfig config,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentAppVersionProvider.overrideWith((ref) async => current),
          appUpdateConfigProvider.overrideWith((ref) => Stream.value(config)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: AppUpdatePrompt(
              openUrl: (uri) async {
                opened.add(uri);
                return openResult;
              },
              child: const Text('home'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() {
    opened = [];
    openResult = true;
  });

  testWidgets('asks to update when a newer version is out', (tester) async {
    await pump(
      tester,
      current: '1.4.3',
      config: const AppUpdateConfig(latest: '1.5.0', storeUrl: _store),
    );
    expect(find.text('Có bản mới'), findsOneWidget);
    expect(find.textContaining('1.5.0'), findsOneWidget);

    await tester.tap(find.text('Cập nhật'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse(_store)]);
    expect(find.text('Có bản mới'), findsNothing);
  });

  testWidgets('"Để sau" closes it for the rest of this launch', (tester) async {
    await pump(
      tester,
      current: '1.4.3',
      config: const AppUpdateConfig(latest: '1.5.0', storeUrl: _store),
    );
    await tester.tap(find.text('Để sau'));
    await tester.pumpAndSettle();
    expect(find.text('Có bản mới'), findsNothing);
    expect(opened, isEmpty);

    // Remote Config báo lại cùng giá trị (fetch xong, realtime) thì không hỏi lại.
    final container = ProviderScope.containerOf(
      tester.element(find.text('home')),
    );
    container.invalidate(appUpdateConfigProvider);
    await tester.pumpAndSettle();
    expect(find.text('Có bản mới'), findsNothing);
  });

  testWidgets('stays quiet when the app is up to date or config is unusable', (
    tester,
  ) async {
    for (final (current, config) in [
      ('1.5.0', const AppUpdateConfig(latest: '1.5.0', storeUrl: _store)),
      ('1.6.0', const AppUpdateConfig(latest: '1.5.0', storeUrl: _store)),
      // Remote Config chưa có giá trị, sai dạng, hay thiếu link store.
      ('1.4.3', const AppUpdateConfig()),
      ('1.4.3', const AppUpdateConfig(latest: 'mới', storeUrl: _store)),
      ('1.4.3', const AppUpdateConfig(latest: '1.5.0')),
    ]) {
      await pump(tester, current: current, config: config);
      expect(find.text('Có bản mới'), findsNothing, reason: '$current $config');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('below the minimum version the popup cannot be dismissed', (
    tester,
  ) async {
    openResult = false;
    await pump(
      tester,
      current: '1.4.3',
      config: const AppUpdateConfig(
        latest: '1.6.0',
        min: '1.5.0',
        storeUrl: _store,
      ),
    );
    expect(find.text('Để sau'), findsNothing);
    expect(find.textContaining('Cập nhật lên 1.6.0'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // chạm ra ngoài popup
    await tester.pumpAndSettle();
    expect(find.text('Có bản mới'), findsOneWidget);

    // Không mở được store thì báo, popup vẫn còn.
    await tester.tap(find.text('Cập nhật'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(1));
    expect(find.text('Không mở được cửa hàng ứng dụng.'), findsOneWidget);
    expect(find.text('Có bản mới'), findsOneWidget);

    // Mở được store thì popup vẫn giữ: quay lại app mà chưa cập nhật vẫn bị chặn.
    openResult = true;
    await tester.tap(find.text('Cập nhật'));
    await tester.pumpAndSettle();
    expect(opened, hasLength(2));
    expect(find.text('Có bản mới'), findsOneWidget);
  });

  testWidgets('keeps the popup and says so when the store does not open', (
    tester,
  ) async {
    openResult = false;
    await pump(
      tester,
      current: '1.4.3',
      config: const AppUpdateConfig(latest: '1.5.0', storeUrl: _store),
    );
    await tester.tap(find.text('Cập nhật'));
    await tester.pumpAndSettle();
    expect(find.text('Không mở được cửa hàng ứng dụng.'), findsOneWidget);
    expect(find.text('Có bản mới'), findsOneWidget);
  });

  testWidgets('forced with no latest version names the minimum', (
    tester,
  ) async {
    await pump(
      tester,
      current: '1.4.3',
      config: const AppUpdateConfig(min: '1.5.0', storeUrl: _store),
    );
    expect(find.textContaining('Cập nhật lên 1.5.0'), findsOneWidget);
    expect(find.text('Để sau'), findsNothing);
  });
}
