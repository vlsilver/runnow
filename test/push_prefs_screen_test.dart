import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/push.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/screens/push_prefs_screen.dart';
import 'package:myrun/src/widgets/run_now_switch.dart';

class _FakeMessaging implements PushMessaging {
  _FakeMessaging(this.status);

  PushPermission status;
  bool failRead = false;

  @override
  Future<PushPermission> permission() async {
    if (failRead) throw StateError('settings unavailable');
    return status;
  }

  /// Có thì hỏi quyền chờ tới khi nó xong, để test rời màn giữa chừng.
  Completer<void>? asking;

  @override
  Future<PushPermission> requestPermission() async {
    await asking?.future;
    return status = PushPermission.granted;
  }

  @override
  Future<String?> token() async => 'fcm-a';

  @override
  Stream<String> get tokenRefresh => const Stream.empty();

  @override
  Future<Map<String, dynamic>?> launchTap() async => null;

  @override
  Stream<Map<String, dynamic>> get taps => const Stream.empty();
}

const _json = {'content-type': 'application/json; charset=utf-8'};

void main() {
  late List<http.Request> requests;
  late Set<String> off;
  late bool failPut;
  late bool savedButFailed;

  setUp(() {
    requests = [];
    off = {};
    failPut = false;
    savedButFailed = false;
  });

  String view() => jsonEncode({
    'groups': [
      for (final (id, label) in [
        ('live', 'Người trong club chạy live'),
        ('gift', 'Quà'),
      ])
        {'id': id, 'label': label, 'on': !off.contains(id)},
    ],
  });

  RunNowApiClient client() => RunNowApiClient(
    tokenProvider: ({required forceRefresh}) async => 'id-token',
    baseUri: Uri.parse('https://api.test'),
    // PackageInfo không chạy trong widget test.
    appVersion: () async => '1.17.0+35',
    appPlatform: 'ios',
    httpClient: MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/v1/push-token') {
        return http.Response('{"ok":true}', 200);
      }
      if (request.method == 'PUT') {
        if (failPut) return http.Response('{"error":"x"}', 500);
        off = {...(jsonDecode(request.body)['off'] as List).cast<String>()};
        if (savedButFailed) return http.Response('{"error":"x"}', 502);
      }
      return http.Response(view(), 200, headers: _json);
    }),
  );

  Future<void> pump(WidgetTester tester, _FakeMessaging fcm) async {
    final api = client();
    final push = PushController(
      MockFirebaseAuth(signedIn: true),
      api,
      fcm,
      'ios',
      tokenRetryDelay: Duration.zero,
    );
    addTearDown(push.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(api),
          pushControllerProvider.overrideWithValue(push),
        ],
        child: const MaterialApp(home: PushPrefsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Iterable<String> puts() => [
    for (final r in requests)
      if (r.method == 'PUT' && r.url.path == '/v1/me/push-prefs') r.body,
  ];

  testWidgets('turning a group off sends only that group as off', (
    tester,
  ) async {
    await pump(tester, _FakeMessaging(PushPermission.granted));
    expect(find.text('Người trong club chạy live'), findsOneWidget);
    expect(find.text('Bật thông báo'), findsNothing);

    await tester.tap(find.byType(RunNowSwitch).first);
    await tester.pumpAndSettle();
    expect(puts(), ['{"off":["live"]}']);
  });

  testWidgets('a failed save puts the switch back', (tester) async {
    await pump(tester, _FakeMessaging(PushPermission.granted));
    failPut = true;
    await tester.tap(find.byType(RunNowSwitch).first);
    await tester.pumpAndSettle();
    expect(find.text('Lưu bị lỗi, đã tải lại cài đặt.'), findsOneWidget);
    expect(off, isEmpty);

    failPut = false;
    await tester.tap(find.byType(RunNowSwitch).first);
    await tester.pumpAndSettle();
    expect(puts().last, '{"off":["live"]}');
  });

  testWidgets(
    'a save that failed after the server stored it shows the server',
    (tester) async {
      await pump(tester, _FakeMessaging(PushPermission.granted));
      savedButFailed = true;
      await tester.tap(find.byType(RunNowSwitch).first);
      await tester.pumpAndSettle();
      expect(find.text('Lưu bị lỗi, đã tải lại cài đặt.'), findsOneWidget);
      // Server đã lưu "live" tắt; màn phải đọc lại chứ không bật lại công tắc.
      expect(off, {'live'});
      expect(
        tester.widget<RunNowSwitch>(find.byType(RunNowSwitch).first).value,
        isFalse,
      );
    },
  );

  testWidgets('not asked yet: the button asks and registers the token', (
    tester,
  ) async {
    await pump(tester, _FakeMessaging(PushPermission.notAsked));
    await tester.tap(find.text('Bật thông báo'));
    await tester.pumpAndSettle();
    expect(find.text('Bật thông báo'), findsNothing);
    expect(requests.where((r) => r.url.path == '/v1/push-token'), hasLength(1));
  });

  testWidgets('denied in the OS: tells where to turn it back on', (
    tester,
  ) async {
    await pump(tester, _FakeMessaging(PushPermission.denied));
    expect(find.textContaining('Cài đặt của máy'), findsOneWidget);
    expect(find.text('Bật thông báo'), findsNothing);
  });

  testWidgets('turned back on in the OS: coming back hides the denied card', (
    tester,
  ) async {
    final fcm = _FakeMessaging(PushPermission.denied);
    await pump(tester, fcm);
    expect(find.textContaining('Cài đặt của máy'), findsOneWidget);

    expect(requests.where((r) => r.url.path == '/v1/push-token'), isEmpty);

    fcm.status = PushPermission.granted;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.textContaining('Cài đặt của máy'), findsNothing);
    // Lúc mở app chưa có quyền nên chưa đăng ký; quay về thì phải đăng ký.
    expect(requests.where((r) => r.url.path == '/v1/push-token'), hasLength(1));
  });

  testWidgets('permission unreadable: groups still load, no permission card', (
    tester,
  ) async {
    await pump(tester, _FakeMessaging(PushPermission.denied)..failRead = true);
    expect(tester.takeException(), isNull);
    expect(find.text('Người trong club chạy live'), findsOneWidget);
    expect(find.textContaining('Cài đặt của máy'), findsNothing);
  });

  testWidgets('leaving while asking, then asking fails: no error after close', (
    tester,
  ) async {
    final fcm = _FakeMessaging(PushPermission.notAsked)
      ..asking = Completer<void>();
    await pump(tester, fcm);
    await tester.tap(find.text('Bật thông báo'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    fcm.asking!.completeError(StateError('denied by the OS'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
