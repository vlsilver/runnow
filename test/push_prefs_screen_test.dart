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

  @override
  Future<PushPermission> permission() async => status;

  @override
  Future<PushPermission> requestPermission() async =>
      status = PushPermission.granted;

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

  setUp(() {
    requests = [];
    off = {};
    failPut = false;
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
    expect(find.text('Chưa lưu được, thử lại sau.'), findsOneWidget);
    expect(off, isEmpty);

    failPut = false;
    await tester.tap(find.byType(RunNowSwitch).first);
    await tester.pumpAndSettle();
    expect(puts().last, '{"off":["live"]}');
  });

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
}
