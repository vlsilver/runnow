import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/games/game_create_screen.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/run_contract_analytics.dart';
import 'package:myrun/src/screens/run_contract_create_screen.dart';

import 'support/fake_game_backend.dart';

class _FakeUser implements User {
  @override
  String get uid => 'admin';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoAnalytics implements RunContractAnalytics {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

Map<String, dynamic> _list({required bool canCreate}) => {
  'viewer': {'canCreate': canCreate},
  'createOptions': {
    'roles': [
      {'key': 'seer', 'label': 'Tiên tri', 'default': true},
      {'key': 'witch', 'label': 'Phù thuỷ', 'default': true},
      {'key': 'cupid', 'label': 'Cupid', 'default': false},
    ],
  },
  'items': [],
};

void main() {
  late FakeGameBackend backend;

  Future<void> pumpScreen(WidgetTester tester) async {
    // Form dài hơn màn test mặc định 800x600.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/games/new',
      routes: [
        GoRoute(
          path: '/games/new',
          builder: (context, state) => const GameCreateScreen(),
        ),
        GoRoute(
          path: '/games/:id',
          builder: (context, state) =>
              Text('ván ${state.pathParameters['id']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  setUp(() {
    backend = FakeGameBackend(() => DateTime.utc(2026, 10, 17, 14));
  });

  testWidgets('only admins get the form', (tester) async {
    backend.list = _list(canCreate: false);
    await pumpScreen(tester);

    expect(find.text('Chỉ admin mở được ván Ma Sói.'), findsOneWidget);
    expect(find.text('Mở ván'), findsNothing);
  });

  testWidgets('sends the roles from createOptions and opens the new game', (
    tester,
  ) async {
    backend.list = _list(canCreate: true);
    await pumpScreen(tester);

    await tester.tap(find.text('Phù thuỷ'));
    await tester.tap(find.text('Ván thử'));
    await tester.pump();
    await tester.enterText(
      find.widgetWithText(TextField, 'Chat ID group test'),
      ' -1001 ',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ID topic (không bắt buộc)'),
      '42',
    );
    await tester.tap(find.text('Mở ván'));
    await tester.pumpAndSettle();

    final create = backend.requests.singleWhere(
      (r) => r.method == 'POST' && r.url.path == '/v1/games',
    );
    expect(jsonDecode(create.body), {
      'roles': {'seer': true, 'witch': false, 'cupid': false},
      'testMode': true,
      'chatId': '-1001',
      'threadId': 42,
    });
    expect(find.text('ván g9'), findsOneWidget);
  });

  testWidgets('shows the backend reason and stays on the form', (tester) async {
    backend.list = _list(canCreate: true);
    backend.failures['POST /v1/games'] = (
      409,
      {'error': 'game_active', 'message': 'Đang có ván khác chạy.'},
    );
    await pumpScreen(tester);

    await tester.tap(find.text('Mở ván'));
    await tester.pumpAndSettle();

    expect(find.text('Đang có ván khác chạy.'), findsOneWidget);
    expect(find.text('Mở ván'), findsOneWidget);
  });

  testWidgets('rejects a topic id that is not a number before sending', (
    tester,
  ) async {
    backend.list = _list(canCreate: true);
    await pumpScreen(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'ID topic (không bắt buộc)'),
      'abc',
    );
    await tester.tap(find.text('Mở ván'));
    await tester.pump();

    expect(find.text('ID topic phải là số.'), findsOneWidget);
    expect(backend.calls, isNot(contains('POST /v1/games')));
  });

  group('contract templates', () {
    Future<void> pumpTemplates(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runNowApiClientProvider.overrideWithValue(backend.client()),
            firebaseUserProvider.overrideWith(
              (ref) => Stream.value(_FakeUser()),
            ),
            runContractAnalyticsProvider.overrideWithValue(_NoAnalytics()),
          ],
          child: const MaterialApp(home: RunContractCreateScreen()),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
    }

    testWidgets('offer a game to admins', (tester) async {
      backend.list = _list(canCreate: true);
      await pumpTemplates(tester);
      expect(find.text('Ván Ma Sói'), findsOneWidget);
    });

    testWidgets('hide the game from players', (tester) async {
      backend.list = _list(canCreate: false);
      await pumpTemplates(tester);
      expect(find.text('Giáo án AI Coach'), findsOneWidget);
      expect(find.text('Ván Ma Sói'), findsNothing);
    });
  });
}
