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

// Ba kiểu tuỳ chọn backend gửi trong createOptions.settings.
final _settings = [
  {
    'key': 'kmOff',
    'label': 'Không dùng km',
    'description': 'Kỹ năng không cần km, mỗi người một phiếu.',
    'type': 'toggle',
    'default': false,
  },
  {
    'key': 'seerKm',
    'label': 'Km cho Tiên tri',
    'description': 'Km Tiên tri phải chạy để soi.',
    'type': 'number',
    'default': 1.0,
    'min': 0,
    'max': 2,
    'step': 0.5,
    'unit': 'km',
    'enabledIf': [
      {'key': 'kmOff', 'equals': false},
    ],
  },
  {
    'key': 'vote',
    'label': 'Km và phiếu',
    'description': 'Km tác động lên phiếu thế nào.',
    'type': 'choice',
    'default': 'cut',
    'choices': [
      {
        'value': 'cut',
        'label': 'Thiếu km thì mất phiếu',
        'description': 'Ít km nhất mất phiếu trước.',
      },
      {
        'value': 'flat',
        'label': 'Mỗi người một phiếu',
        'description': 'Km không tác động lên phiếu.',
      },
    ],
    'enabledIf': [
      {'key': 'kmOff', 'equals': false},
    ],
  },
];

Map<String, dynamic> _listWithSettings() =>
    _list(canCreate: true)
      ..['createOptions'] = {
        ...(_list(canCreate: true)['createOptions'] as Map<String, dynamic>),
        'settings': _settings,
      };

// createOptions của backend có tab và kiểu ván dựng sẵn.
Map<String, dynamic> _tabbedList() => {
  'viewer': {'canCreate': true},
  'createOptions': {
    'roles': [
      {
        'key': 'seer',
        'label': 'Tiên tri',
        'description': 'Mỗi đêm soi một người.',
        'default': true,
      },
      {
        'key': 'cupid',
        'label': 'Cupid',
        'description': 'Đêm 1 ghép đôi.',
        'default': true,
      },
    ],
    'settings': [
      {
        'key': 'elder',
        'label': 'Thêm Già làng',
        'description': 'Chịu được một lần bị cắn.',
        'type': 'toggle',
        'default': false,
        'group': 'roles',
      },
      {
        'key': 'kmOff',
        'label': 'Không dùng km',
        'description': 'Ma Sói thường.',
        'type': 'toggle',
        'default': false,
      },
      {
        'key': 'startHour',
        'label': 'Giờ mở vòng đầu',
        'description': 'Giờ mở vòng đầu tiên.',
        'type': 'number',
        'default': 22,
        'min': 0,
        'max': 23,
        'step': 1,
        'unit': 'giờ',
        'group': 'time',
        'enabledIf': [
          {'key': 'kmOff', 'equals': true},
        ],
      },
      {
        'key': 'roundHours',
        'label': 'Độ dài một vòng',
        'description': 'Mọi mốc co theo vòng.',
        'type': 'number',
        'default': 24,
        'min': 4,
        'max': 24,
        'step': 2,
        'unit': 'tiếng',
        'group': 'round',
        'enabledIf': [
          {'key': 'kmOff', 'equals': true},
        ],
      },
      {
        'key': 'skillKm',
        'label': 'Km mở kỹ năng',
        'description': 'Km mỗi vai cần chạy.',
        'type': 'number',
        'default': 1,
        'min': 0,
        'max': 20,
        'step': 0.5,
        'unit': 'km',
        'group': 'km',
        'enabledIf': [
          {'key': 'kmOff', 'equals': false},
        ],
      },
    ],
    'groups': [
      {
        'key': 'time',
        'label': 'Lịch',
        'icon': 'clock',
        'offNote': 'Ván đua km mở lúc 22h.',
      },
      {'key': 'round', 'label': 'Vòng chơi', 'icon': 'moon'},
      {'key': 'roles', 'label': 'Vai', 'icon': 'people'},
      {
        'key': 'km',
        'label': 'Km',
        'icon': 'run',
        'offNote': 'Ván không dùng km.',
      },
    ],
    'presets': [
      {
        'key': 'std',
        'label': 'Chuẩn PSC',
        'icon': 'run',
        'summary': 'Ván tuần quen thuộc',
        'details': ['Thiếu km thì mất phiếu.'],
        'default': true,
        'settings': {},
      },
      {
        'key': 'classic',
        'label': 'Cổ điển',
        'icon': 'moon',
        'summary': 'Ma Sói thường, không cần chạy',
        'details': ['Không dùng km.'],
        'settings': {'kmOff': true},
      },
    ],
    'round': {
      'phases': [
        {
          'key': 'night',
          'label': 'Đêm',
          'description': 'Sói cắn.',
          'from': 0,
          'to': 2,
        },
        {
          'key': 'dawn',
          'label': 'Rạng sáng',
          'description': 'Phù thuỷ.',
          'from': 2,
          'to': 12,
        },
        {
          'key': 'day',
          'label': 'Ngày',
          'description': 'Đề cử.',
          'from': 12,
          'to': 22,
        },
        {
          'key': 'trial',
          'label': 'Biểu quyết',
          'description': 'Treo hay tha.',
          'from': 22,
          'to': 24,
        },
      ],
      'reminders': [
        {'label': 'Nhắc đề cử', 'at': 20},
      ],
      'start': 'Ván chạy tới khi một phe thắng.',
    },
  },
  'items': [],
};

Map<String, dynamic> _createBody(FakeGameBackend backend) =>
    jsonDecode(
          backend.requests
              .singleWhere(
                (r) => r.method == 'POST' && r.url.path == '/v1/games',
              )
              .body,
        )
        as Map<String, dynamic>;

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

  testWidgets('shows every setting with its description', (tester) async {
    backend.list = _listWithSettings();
    await pumpScreen(tester);

    for (final text in [
      'Không dùng km',
      'Kỹ năng không cần km, mỗi người một phiếu.',
      'Km cho Tiên tri',
      'Km Tiên tri phải chạy để soi.',
      '1 km',
      'Km và phiếu',
      'Km tác động lên phiếu thế nào.',
      'Thiếu km thì mất phiếu',
      'Ít km nhất mất phiếu trước.',
      'Mỗi người một phiếu',
      'Km không tác động lên phiếu.',
    ]) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
  });

  testWidgets('sends only the settings the creator changed', (tester) async {
    backend.list = _listWithSettings();
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Tăng Km cho Tiên tri'));
    await tester.pump();
    expect(find.text('1.5 km'), findsOneWidget);
    await tester.tap(find.text('Mỗi người một phiếu'));
    await tester.pump();
    await tester.tap(find.text('Mở ván'));
    await tester.pumpAndSettle();

    final create = backend.requests.singleWhere(
      (r) => r.method == 'POST' && r.url.path == '/v1/games',
    );
    expect((jsonDecode(create.body) as Map)['settings'], {
      'seerKm': 1.5,
      'vote': 'flat',
    });
  });

  testWidgets('greys out and drops settings whose condition fails', (
    tester,
  ) async {
    backend.list = _listWithSettings();
    await pumpScreen(tester);

    await tester.tap(find.byTooltip('Tăng Km cho Tiên tri'));
    await tester.tap(find.text('Không dùng km'));
    await tester.pump();
    final plus = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.add_rounded),
    );
    expect(plus.onPressed, isNull);
    await tester.tap(find.text('Mở ván'));
    await tester.pumpAndSettle();

    final create = backend.requests.singleWhere(
      (r) => r.method == 'POST' && r.url.path == '/v1/games',
    );
    expect((jsonDecode(create.body) as Map)['settings'], {'kmOff': true});
  });

  group('tabbed form', () {
    testWidgets('a preset fills the settings it sends', (tester) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Cổ điển'));
      await tester.pump();
      await tester.tap(find.text('Mở ván'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {'kmOff': true});
    });

    testWidgets('the default preset sends no settings', (tester) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      expect(find.text('Ván tuần quen thuộc'), findsOneWidget);
      expect(find.text('ĐÃ CHỈNH'), findsNothing);
      await tester.tap(find.text('Mở ván'));
      await tester.pumpAndSettle();

      expect(_createBody(backend).containsKey('settings'), isFalse);
    });

    testWidgets('an edit goes on top of the preset and marks the form', (
      tester,
    ) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Km'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tăng Km mở kỹ năng'));
      await tester.pump();
      expect(find.text('1.5 km'), findsOneWidget);
      expect(find.text('ĐÃ CHỈNH'), findsOneWidget);
      expect(find.text('Đã chỉnh từ kiểu Chuẩn PSC'), findsOneWidget);
      await tester.tap(find.text('Mở ván'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {'skillKm': 1.5});
    });

    testWidgets('the round tab scales the phases to the round length', (
      tester,
    ) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      // Vòng 24 tiếng mở 22h: đêm 22h–0h, biểu quyết 20h–22h, nhắc 18h.
      expect(find.textContaining('22h – 0h', findRichText: true), findsOne);
      expect(find.textContaining('20h – 22h', findRichText: true), findsOne);
      expect(find.text('Nhắc đề cử lúc 18h'), findsOneWidget);
      expect(find.byTooltip('Giảm Độ dài một vòng'), findsNothing);

      await tester.tap(find.text('Cổ điển'));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.byTooltip('Giảm Độ dài một vòng'));
        await tester.pump();
      }
      // Vòng 12 tiếng: đêm 22h–23h, biểu quyết 9h–10h, nhắc 8h.
      expect(find.text('12 tiếng'), findsOneWidget);
      expect(find.textContaining('22h – 23h', findRichText: true), findsOne);
      expect(find.textContaining('9h – 10h', findRichText: true), findsOne);
      expect(find.text('Nhắc đề cử lúc 8h'), findsOneWidget);
      await tester.tap(find.text('Mở ván'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {
        'kmOff': true,
        'roundHours': 12,
      });
    });

    testWidgets('a tab whose settings are all off shows its note', (
      tester,
    ) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Km'));
      await tester.pump();
      expect(find.text('Km mở kỹ năng'), findsOneWidget);
      expect(find.text('Ván không dùng km.'), findsNothing);

      await tester.tap(find.text('Cổ điển'));
      await tester.pump();
      expect(find.text('Km mở kỹ năng'), findsNothing);
      expect(find.text('Ván không dùng km.'), findsOneWidget);
    });

    testWidgets('role chips send roles and extra roles', (tester) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      await tester.tap(find.text('Vai'));
      await tester.pump();
      await tester.tap(find.text('Cupid'));
      await tester.tap(find.text('Thêm Già làng'));
      await tester.pump();
      await tester.tap(find.text('Mở ván'));
      await tester.pumpAndSettle();

      final body = _createBody(backend);
      expect(body['roles'], {'seer': true, 'cupid': false});
      expect(body['settings'], {'elder': true});
    });

    testWidgets('a backend without tabs gets the old form', (tester) async {
      backend.list = _listWithSettings();
      await pumpScreen(tester);

      expect(find.text('Kiểu ván'.toUpperCase()), findsNothing);
      expect(find.text('Không dùng km'), findsOneWidget);
    });
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
