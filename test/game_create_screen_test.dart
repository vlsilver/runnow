import 'dart:convert';
import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/games/game_create_screen.dart';
import 'package:myrun/src/games/game_card_art.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
import 'package:myrun/src/games/game_round_dial.dart';
import 'package:myrun/src/games/game_skill_cards.dart';
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

// Backend cho chỉnh độ dài từng pha (ô kiểu phase, pha có settingKey) và số
// vòng mỗi ngày.
Map<String, dynamic> _phaseList() {
  final list = _tabbedList();
  final options = list['createOptions'] as Map<String, dynamic>;
  const keys = ['nightMin', 'dawnMin', 'dayMin', 'trialMin'];
  const lengths = [120, 600, 600, 120];
  final phases = (options['round'] as Map<String, dynamic>)['phases'] as List;
  for (var i = 0; i < keys.length; i++) {
    (phases[i] as Map<String, dynamic>)['settingKey'] = keys[i];
  }
  options['settings'] = <Object>[
    ...options['settings'] as List,
    {
      'key': 'roundsPerDay',
      'label': 'Số vòng mỗi ngày',
      'description': 'Số vòng trong một ngày.',
      'type': 'number',
      'default': 1,
      'min': 1,
      'max': 6,
      'step': 1,
      'unit': 'vòng',
      'group': 'time',
    },
    for (var i = 0; i < keys.length; i++)
      {
        'key': keys[i],
        'label': 'Độ dài pha ${i + 1}',
        'description': 'Phút.',
        'type': 'phase',
        'default': lengths[i],
        'min': 60,
        'max': 1260,
        'step': 30,
        'unit': 'phút',
        'group': 'round',
      },
  ];
  return list;
}

// Backend cho mỗi vòng trong ngày một lịch pha riêng (ô kiểu roundPhases).
Map<String, dynamic> _roundPhasesList() {
  final list = _phaseList();
  final options = list['createOptions'] as Map<String, dynamic>;
  options['settings'] = <Object>[
    ...options['settings'] as List,
    {
      'key': 'roundPhases',
      'label': 'Lịch từng vòng',
      'description': 'Mỗi vòng chia giờ riêng.',
      'type': 'roundPhases',
      'default': [
        [120, 600, 600, 120],
      ],
      'group': 'round',
    },
  ];
  return list;
}

// Backend có tab Giao tiếp với công tắc Telegram.
Map<String, dynamic> _talkList() {
  final list = _tabbedList();
  final options = list['createOptions'] as Map<String, dynamic>;
  options['groups'] = <Object>[
    ...options['groups'] as List,
    {'key': 'talk', 'label': 'Giao tiếp', 'icon': 'chat'},
  ];
  options['settings'] = <Object>[
    ...options['settings'] as List,
    {
      'key': 'telegram',
      'label': 'Telegram group',
      'description': 'Bot 3i đăng tin vào group.',
      'type': 'toggle',
      'default': true,
      'group': 'talk',
    },
  ];
  return list;
}

// Backend gom đặc quyền phe Sói thành một khối (section) của tab Vai.
Map<String, dynamic> _darkList() {
  final list = _tabbedList();
  final options = list['createOptions'] as Map<String, dynamic>;
  const section = 'Phe Sói · Đặc quyền hắc ám';
  options['settings'] = <Object>[
    ...options['settings'] as List,
    {
      'key': 'darkVote',
      'label': 'Phiếu Đôi',
      'description': 'Phiếu một sói tính 2.',
      'type': 'toggle',
      'default': false,
      'group': 'roles',
      'section': section,
      'hint': 'Mỗi đêm',
      'warn': 'Bảng phiếu lộ có phiếu đôi.',
      'icon': 'vote',
    },
    {
      'key': 'darkKm',
      'label': 'Km để mở',
      'description': 'Km mỗi sói.',
      'type': 'number',
      'default': 1,
      'min': 0.5,
      'max': 5,
      'step': 0.5,
      'unit': 'km',
      'group': 'roles',
      'section': section,
      'hint': '× số sói còn sống',
      'enabledIf': [
        {'key': 'kmOff', 'equals': false},
      ],
    },
  ];
  return list;
}

// Backend gửi bộ bài theo số người (bảng 1.2) và tuỳ chọn số sói tự chỉnh.
Map<String, dynamic> _deckList() {
  final list = _tabbedList();
  final options = list['createOptions'] as Map<String, dynamic>;
  options['roles'] = [
    for (final (k, l) in [
      ('seer', 'Tiên tri'),
      ('guard', 'Bảo vệ'),
      ('witch', 'Phù thuỷ'),
      ('hunter', 'Thợ săn'),
      ('cupid', 'Cupid'),
    ])
      {'key': k, 'label': l, 'description': '', 'default': true},
  ];
  options['settings'] = <Object>[
    {
      'key': 'wolves',
      'label': 'Số sói',
      'description': '0 là theo số người.',
      'type': 'number',
      'default': 0,
      'min': 0,
      'max': 8,
      'step': 1,
      'unit': 'sói',
      'group': 'roles',
    },
    {
      'key': 'elder',
      'label': 'Già làng',
      'description': 'Chịu được một lần bị cắn.',
      'type': 'toggle',
      'default': false,
      'group': 'roles',
    },
    ...(options['settings'] as List).where((s) => s['key'] != 'elder'),
  ];
  options['deck'] = {
    'note': 'Bot chia lúc đủ người.',
    'fixedNote': 'Chia đúng số lá đã chỉnh.',
    'wolvesKey': 'wolves',
    'preview': 12,
    'tiers': [
      {'from': 10, 'to': 10, 'wolves': 2, 'specials': 2},
      {'from': 11, 'to': 11, 'wolves': 3, 'specials': 3},
      {'from': 12, 'to': 12, 'wolves': 3, 'specials': 4},
      {'from': 13, 'to': 16, 'wolves': 3, 'specials': 5},
      {'from': 17, 'to': 20, 'wolves': 4, 'specials': 5},
      {'from': 21, 'to': 24, 'wolves': 5, 'specials': 5},
    ],
  };
  return list;
}

// Tab Kỹ năng theo luật km: chế độ có Chi tiết, thẻ km mỗi lượt có icon, dòng
// con theo parent, thẻ vai theo role, Top bật bằng công tắc.
Map<String, dynamic> _skillList() {
  final list = _tabbedList();
  final options = list['createOptions'] as Map<String, dynamic>;
  const kmOn = [
    {'key': 'kmOff', 'equals': false},
  ];
  Map<String, Object> km(String key, String label, String hint, String icon) =>
      {
        'key': key,
        'label': label,
        'description': '$label mô tả.',
        'type': 'number',
        'default': 1,
        'min': 0,
        'max': 20,
        'step': 0.5,
        'unit': 'km',
        'group': 'km',
        'section': 'Km mỗi lượt',
        'hint': hint,
        'icon': icon,
        'enabledIf': kmOn,
      };
  options['settings'] = <Object>[
    for (final s in options['settings'] as List)
      if ((s as Map)['key'] != 'skillKm') s,
    {
      'key': 'vote',
      'label': 'Chế độ dùng kỹ năng',
      'description': 'Km chốt 22h quyết định ai dùng được kỹ năng.',
      'type': 'choice',
      'default': 'cut',
      'group': 'km',
      'section': 'Chế độ dùng kỹ năng',
      'enabledIf': kmOn,
      'choices': [
        {
          'value': 'cut',
          'label': 'Theo nhóm',
          'hint': 'Km cả nhóm chia ra số lượt',
          'description': 'Cộng km cả nhóm.',
          'details': [
            {'icon': 'sum', 'title': 'Cách tính', 'text': 'Cộng km cả nhóm.'},
          ],
        },
        {
          'value': 'solo',
          'label': 'Riêng',
          'hint': 'Ai đủ km người đó dùng',
          'description': 'Ai đủ km thì dùng.',
          'details': [
            {'icon': 'one', 'title': 'Cách tính', 'text': 'Ai đủ km.'},
          ],
        },
      ],
    },
    km('kmPerUnit', 'Biểu quyết', 'Mọi người · km một phiếu', 'vote'),
    {
      'key': 'maxHang',
      'label': 'Treo tối đa mỗi vòng',
      'description': 'Số người lên giàn mỗi vòng.',
      'type': 'number',
      'default': 3,
      'min': 1,
      'max': 3,
      'step': 1,
      'unit': 'người',
      'group': 'km',
      'section': 'Km mỗi lượt',
      'parent': 'kmPerUnit',
    },
    {
      ...km('wolfKm', 'Bầu cắn', 'Phe Sói · km một phiếu', 'wolf'),
      'default': 0,
      'warn': 'Dễ lộ sói',
    },
    {...km('seerKm', 'Tiên tri soi', 'Tiên tri', 'seer'), 'role': 'seer'},
    {...km('hunterKm', 'Thợ săn bắn', 'Thợ săn', 'hunter'), 'role': 'hunter'},
    {
      'key': 'topOn',
      'label': 'Top N được x phiếu',
      'description': 'Người chạy nhiều nhất được nhiều phiếu hơn.',
      'type': 'toggle',
      'default': false,
      'group': 'km',
      'section': 'Đặc quyền',
      'hint': 'Người chạy nhiều nhất',
      'icon': 'bolt',
      'enabledIf': kmOn,
    },
    {
      'key': 'topWeight',
      'label': 'Phiếu mỗi người',
      'description': 'Mỗi người trong top được bấy nhiêu phiếu.',
      'type': 'number',
      'default': 2,
      'min': 2,
      'max': 5,
      'step': 1,
      'unit': 'phiếu',
      'group': 'km',
      'section': 'Đặc quyền',
      'parent': 'topOn',
      'enabledIf': [
        {'key': 'kmOff', 'equals': false},
        {'key': 'topOn', 'equals': true},
      ],
    },
  ];
  return list;
}

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
    expect(find.text('MỞ VÁN'), findsNothing);
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
    await tester.tap(find.text('MỞ VÁN'));
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

    await tester.tap(find.text('MỞ VÁN'));
    await tester.pumpAndSettle();

    expect(find.text('Đang có ván khác chạy.'), findsOneWidget);
    expect(find.text('MỞ VÁN'), findsOneWidget);
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
    await tester.tap(find.text('MỞ VÁN'));
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
    await tester.tap(find.text('MỞ VÁN'));
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
    await tester.tap(find.text('MỞ VÁN'));
    await tester.pumpAndSettle();

    final create = backend.requests.singleWhere(
      (r) => r.method == 'POST' && r.url.path == '/v1/games',
    );
    expect((jsonDecode(create.body) as Map)['settings'], {'kmOff': true});
  });

  group('tabbed form', () {
    testWidgets('only the default preset wears the default badge', (
      tester,
    ) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      final badge = find.text('MẶC ĐỊNH');
      expect(badge, findsOneWidget);
      // Nhãn vắt trên ô Chuẩn PSC, cùng cột và nằm trên mép ô.
      final std = tester.getRect(find.text('CHUẨN PSC'));
      final at = tester.getRect(badge);
      expect((at.center.dx - std.center.dx).abs(), lessThan(1));
      expect(at.bottom, lessThan(std.top));
    });

    testWidgets('a preset fills the settings it sends', (tester) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      await tester.tap(find.text('CỔ ĐIỂN'));
      await tester.pump();
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {'kmOff': true});
    });

    testWidgets('the default preset sends no settings', (tester) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      // Kiểu ván không còn dòng tóm tắt bên dưới.
      expect(find.text('Ván tuần quen thuộc'), findsNothing);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      expect(_createBody(backend).containsKey('settings'), isFalse);
    });

    testWidgets('an edit goes on top of the preset and unselects its tile', (
      tester,
    ) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);
      final selectedTile = find.byWidgetPredicate(
        (w) => w is GamePresetTile && w.selected,
      );
      expect(selectedTile, findsOneWidget);

      await tester.tap(find.text('Km'));
      await tester.pump();
      await tester.tap(find.byTooltip('Tăng Km mở kỹ năng'));
      await tester.pump();
      expect(find.text('1.5 km'), findsOneWidget);
      expect(selectedTile, findsNothing);
      await tester.tap(find.text('MỞ VÁN'));
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

      await tester.tap(find.text('CỔ ĐIỂN'));
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
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {
        'kmOff': true,
        'roundHours': 12,
      });
    });

    testWidgets(
      'the round dial trades time between phases and sends all four',
      (tester) async {
        backend.list = _phaseList();
        await pumpScreen(tester);

        await tester.tap(find.text('Vòng chơi'));
        await tester.pump();
        expect(find.text('24'), findsOneWidget);
        await tester.tap(find.byTooltip('Thêm Đêm'));
        await tester.pump();
        // Đêm dài thêm nửa tiếng, lấy từ Rạng sáng: 22h–0h30, rồi 0h30–10h.
        expect(find.textContaining('22h – 0h30', findRichText: true), findsOne);
        expect(find.textContaining('0h30 – 10h', findRichText: true), findsOne);
        expect(find.text('24'), findsOneWidget);
        await tester.tap(find.text('MỞ VÁN'));
        await tester.pumpAndSettle();

        expect(_createBody(backend)['settings'], {
          'nightMin': 150,
          'dawnMin': 570,
          'dayMin': 600,
          'trialMin': 120,
        });
      },
    );

    testWidgets('more rounds a day shrink the km round and send the phases', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      // Ván km chỉ chọn số vòng chia hết 24 tiếng: không có ô 5 vòng.
      expect(find.bySemanticsLabel('5 vòng'), findsNothing);
      expect(find.bySemanticsLabel('6 vòng'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('3 vòng'));
      await tester.pump();
      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      // 3 vòng chia 24 tiếng: vòng 8h, Đêm 22h–23h, Biểu quyết 5h–6h.
      expect(find.text('8'), findsOneWidget);
      expect(find.textContaining('22h – 23h', findRichText: true), findsOne);
      expect(find.textContaining('5h – 6h', findRichText: true), findsOne);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {
        'roundsPerDay': 3,
        'nightMin': 60,
        'dawnMin': 180,
        'dayMin': 180,
        'trialMin': 60,
      });
    });

    // Hai vòng mỗi ngày: chip V1/V2 trên đồng hồ, chỉnh vòng 2 không đụng
    // vòng 1, gửi lịch của cả hai vòng.
    testWidgets('each round of the day gets its own phases', (tester) async {
      backend.list = _roundPhasesList();
      await pumpScreen(tester);

      await tester.tap(find.bySemanticsLabel('2 vòng'));
      await tester.pump();
      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      expect(find.text('V1'), findsOneWidget);
      await tester.tap(find.text('V2'));
      await tester.pump();
      // Vòng 2 mở 10h, lịch như vòng 1: Đêm 10h–11h, Rạng sáng 11h–16h.
      expect(find.textContaining('10h – 11h', findRichText: true), findsOne);
      await tester.tap(find.byTooltip('Thêm Đêm'));
      await tester.pump();
      expect(find.textContaining('10h – 11h30', findRichText: true), findsOne);
      expect(find.textContaining('11h30 – 16h', findRichText: true), findsOne);

      await tester.tap(find.text('V1'));
      await tester.pump();
      expect(find.textContaining('22h – 23h', findRichText: true), findsOne);

      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      final settings = _createBody(backend)['settings'] as Map;
      expect(settings['nightMin'], 60);
      expect(settings['roundPhases'], [
        [60, 300, 300, 60],
        [90, 270, 300, 60],
      ]);
    });

    // Backend chưa có lịch từng vòng thì không có chip, không gửi roundPhases.
    testWidgets('an older backend keeps one schedule for every round', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      await tester.tap(find.bySemanticsLabel('2 vòng'));
      await tester.pump();
      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      expect(find.text('V2'), findsNothing);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      expect(
        (_createBody(backend)['settings'] as Map).containsKey('roundPhases'),
        isFalse,
      );
    });

    testWidgets('dragging the end of the night on the dial moves it', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      final face = find.descendant(
        of: find.byType(GameRoundDial),
        matching: find.byType(CustomPaint),
      );
      final box = tester.getRect(face.first);
      // Vòng nằm cách mép 19 điểm. Mốc cuối Đêm ở 0h, tức đỉnh mặt đồng hồ.
      final r = box.width / 2 - 19;
      Offset at(double hour) {
        final a = hour / 24 * 2 * math.pi - math.pi / 2;
        return box.center + Offset(math.cos(a), math.sin(a)) * r;
      }

      final drag = await tester.startGesture(at(0));
      for (final h in [0.25, 0.5, 0.75, 1.0]) {
        await drag.moveTo(at(h));
        await tester.pump();
      }
      await drag.up();
      await tester.pump();
      // Đêm kéo tới 1h: Đêm 22h–1h, Rạng sáng 1h–10h.
      expect(find.textContaining('22h – 1h', findRichText: true), findsOne);
      expect(find.textContaining('1h – 10h', findRichText: true), findsOne);
    });

    testWidgets('the deadline sheet picks a day, hour and minute', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      // Mặc định đóng đăng ký theo giờ, 21h mai.
      expect(find.textContaining('21:00 · '), findsOneWidget);
      await tester.tap(find.text('ĐÓNG ĐĂNG KÝ'));
      await tester.pumpAndSettle();
      Finder inSheet(String text) => find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(text),
      );
      await tester.tap(inSheet('MAI'));
      await tester.tap(inSheet('8h'));
      await tester.tap(inSheet(':30'));
      await tester.pump();
      expect(find.text('08:30'), findsOneWidget);
      await tester.tap(find.text('Xong'));
      await tester.pumpAndSettle();
      expect(find.textContaining('08:30 · '), findsOneWidget);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1, 8, 30);
      expect(
        _createBody(backend)['registrationDeadline'],
        tomorrow.toUtc().toIso8601String(),
      );
    });

    testWidgets('schedule tab: owner closes registration, start at a time', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      // Chủ phòng đóng: không gửi hạn. Bắt đầu theo giờ: mặc định 30 phút sau
      // giờ đóng đăng ký mặc định (21h mai), không có hạn thì vẫn 21:30 mai.
      expect(find.text('Chủ phòng bấm Bắt đầu khi đủ người'), findsOneWidget);
      await tester.tap(find.text('Chủ phòng đóng'));
      await tester.pump();
      expect(find.text('Mở tới khi chủ phòng bắt đầu ván'), findsOneWidget);
      await tester.tap(find.text('Theo giờ').last);
      await tester.pump();
      expect(find.text('CHIA BÀI LÚC'), findsOneWidget);
      expect(find.textContaining('21:30 · '), findsOneWidget);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final body = _createBody(backend);
      expect(body.containsKey('registrationDeadline'), isFalse);
      expect(
        body['startAt'],
        DateTime(
          now.year,
          now.month,
          now.day + 1,
          21,
          30,
        ).toUtc().toIso8601String(),
      );
    });

    // Số lá của một vai trên ô bộ bài.
    String deckCount(WidgetTester tester, String label) {
      final tile = tester.widget<GameDeckTile>(
        find.ancestor(
          of: find.text(label),
          matching: find.byType(GameDeckTile),
        ),
      );
      return '${tile.count}';
    }

    testWidgets('deck by player count previews the cards bot will deal', (
      tester,
    ) async {
      backend.list = _deckList();
      await pumpScreen(tester);
      await tester.tap(find.text('Vai'));
      await tester.pump();

      expect(find.text('Bot chia lúc đủ người.'), findsOneWidget);
      expect(find.text('13–16 người'), findsOneWidget);
      expect(find.text('3 sói · 4 vai'), findsOneWidget);
      // 12 người: 3 sói, 4 vai đầu, Cupid chưa có, 5 Dân.
      expect(deckCount(tester, 'Sói'), '3');
      expect(deckCount(tester, 'Cupid'), '0');
      expect(deckCount(tester, 'Dân'), '5');
      // Không còn ô "Số sói" riêng: số sói nằm trong bộ bài.
      expect(find.widgetWithText(GameCreateStepper, 'Số sói'), findsNothing);

      await tester.tap(find.byTooltip('Tăng số người'));
      await tester.pump();
      expect(deckCount(tester, 'Cupid'), '1');
      await tester.tap(find.byTooltip('Thêm Già làng'));
      await tester.pump();
      expect(deckCount(tester, 'Già làng'), '1');
      expect(deckCount(tester, 'Dân'), '4');
      // Theo số người thì vai đặc biệt khoá, chỉ vai thêm có nút.
      expect(find.byTooltip('Bớt Tiên tri'), findsNothing);

      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      expect(_createBody(backend)['settings'], {'elder': true});
    });

    testWidgets('fixed deck sends the wolves and roles shown', (tester) async {
      backend.list = _deckList();
      await pumpScreen(tester);
      await tester.tap(find.text('Vai'));
      await tester.pump();

      // Chuyển sang tự chỉnh giữ đúng bộ bài đang xem (12 người: Cupid 0).
      await tester.tap(find.text('Tự chỉnh'));
      await tester.pump();
      expect(find.text('Chia đúng số lá đã chỉnh.'), findsOneWidget);
      expect(find.text('13–16 người'), findsNothing);
      expect(deckCount(tester, 'Cupid'), '0');
      await tester.tap(find.byTooltip('Thêm Sói'));
      await tester.pump();
      await tester.tap(find.byTooltip('Bớt Phù thuỷ'));
      await tester.pump();
      expect(deckCount(tester, 'Sói'), '4');
      expect(deckCount(tester, 'Dân'), '5');

      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      final body = _createBody(backend);
      expect(body['settings'], {'wolves': 4.0});
      expect(body['roles'], {
        'seer': true,
        'guard': true,
        'witch': false,
        'hunter': true,
        'cupid': false,
      });
    });

    testWidgets('wolf powers are cards in their own block, not role chips', (
      tester,
    ) async {
      backend.list = _darkList();
      await pumpScreen(tester);

      await tester.tap(find.text('Vai'));
      await tester.pump();
      expect(find.text('PHE SÓI · ĐẶC QUYỀN HẮC ÁM'), findsOneWidget);
      expect(find.text('× số sói còn sống'), findsOneWidget);
      expect(find.widgetWithText(GameRoleChip, 'Phiếu Đôi'), findsNothing);
      expect(find.text('MỖI ĐÊM · ⚠ ĐỂ LỘ'), findsOneWidget);
      // Mô tả và cảnh báo ẩn tới khi mở thẻ.
      expect(find.text('Bảng phiếu lộ có phiếu đôi.'), findsNothing);
      await tester.tap(find.byTooltip('Xem Phiếu Đôi'));
      await tester.pump();
      expect(find.text('Phiếu một sói tính 2.'), findsOneWidget);
      expect(find.text('Bảng phiếu lộ có phiếu đôi.'), findsOneWidget);
      // Khối đặc quyền có "Là gì?" riêng trên tiêu đề, kể hết các đặc quyền.
      final why = find.text('Là gì?');
      expect(why, findsNWidgets(2));
      expect(
        (tester.getCenter(why.last).dy -
                tester.getCenter(find.text('PHE SÓI · ĐẶC QUYỀN HẮC ÁM')).dy)
            .abs(),
        lessThan(4),
      );

      // Chưa bật đặc quyền nào thì "Km để mở" mờ.
      double kmOpacity() => tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.text('Km để mở'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity;
      expect(kmOpacity(), lessThan(1));

      await tester.tap(find.text('Phiếu Đôi'));
      await tester.pump();
      expect(kmOpacity(), 1);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      expect(_createBody(backend)['settings'], {'darkVote': true});
    });

    testWidgets(
      'the skill tab draws mode cards, skill cards and nested lines',
      (tester) async {
        backend.list = _skillList();
        await pumpScreen(tester);

        await tester.tap(find.text('Km'));
        await tester.pump();
        expect(find.text('Km cả nhóm chia ra số lượt'), findsOneWidget);
        expect(find.text('Ai đủ km người đó dùng'), findsOneWidget);
        Finder inCard(String card, Finder f) => find.descendant(
          of: find.widgetWithText(GameSkillCard, card),
          matching: f,
        );
        expect(
          inCard('Biểu quyết', find.text('Treo tối đa mỗi vòng')),
          findsOneWidget,
        );
        // Chỉ vai có trong bộ bài mới có thẻ.
        expect(find.text('Tiên tri soi'), findsOneWidget);
        expect(find.text('Thợ săn bắn'), findsNothing);
        // Bầu cắn 0 km thì chưa cảnh báo.
        expect(find.text('⚠ Dễ lộ sói'), findsNothing);
        expect(find.text('Phiếu mỗi người'), findsNothing);

        await tester.tap(find.text('Riêng'));
        await tester.tap(find.byTooltip('Tăng Bầu cắn'));
        await tester.tap(inCard('Top N được x phiếu', find.byType(Switch)));
        await tester.pump();
        expect(find.text('⚠ Dễ lộ sói'), findsOneWidget);
        expect(
          inCard('Top N được x phiếu', find.text('Phiếu mỗi người')),
          findsOneWidget,
        );

        await tester.tap(find.text('Chi tiết').first);
        await tester.pumpAndSettle();
        expect(find.text('Cách tính'), findsOneWidget);
        expect(find.text('Cộng km cả nhóm.'), findsWidgets);
        await tester.tapAt(const Offset(400, 40));
        await tester.pumpAndSettle();

        await tester.tap(find.text('MỞ VÁN'));
        await tester.pumpAndSettle();
        expect(_createBody(backend)['settings'], {
          'vote': 'solo',
          'wolfKm': 0.5,
          'topOn': true,
        });
      },
    );

    testWidgets('a classic round loses a whole hour from its last phase', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      await tester.tap(find.text('CỔ ĐIỂN'));
      await tester.pump();
      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      expect(find.byTooltip('Giảm Độ dài một vòng'), findsNothing);
      await tester.tap(find.byTooltip('Bớt Biểu quyết'));
      await tester.pump();
      expect(find.text('23'), findsOneWidget);
      expect(find.textContaining('20h – 21h', findRichText: true), findsOne);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {
        'kmOff': true,
        'nightMin': 120,
        'dawnMin': 600,
        'dayMin': 600,
        'trialMin': 60,
      });
    });

    testWidgets('open and close rows move the round start and end', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      // Ván km mở vòng lúc 22h và chốt sau đúng 24 tiếng: hai dòng khoá.
      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      IconButton button(String tip) => tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tip),
          matching: find.byType(IconButton),
        ),
      );
      expect(button('Thêm Mở vòng').onPressed, isNull);
      expect(button('Bớt Chốt vòng').onPressed, isNull);

      // Cổ điển: mở muộn một tiếng thì Đêm ngắn đi, chốt sớm một tiếng thì
      // Biểu quyết ngắn đi.
      await tester.tap(find.text('CỔ ĐIỂN'));
      await tester.pump();
      await tester.tap(find.byTooltip('Thêm Mở vòng'));
      await tester.pump();
      await tester.tap(find.byTooltip('Bớt Chốt vòng'));
      await tester.pump();
      expect(find.textContaining('23h – 0h', findRichText: true), findsOne);
      expect(find.textContaining('20h – 21h', findRichText: true), findsOne);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {
        'kmOff': true,
        'startHour': 23,
        'nightMin': 60,
        'dawnMin': 600,
        'dayMin': 600,
        'trialMin': 60,
      });
    });

    // Ván km khoá giờ mở: "Là gì?" của tab Vòng chơi nói vì sao; ván cổ điển
    // chỉnh được nên không có dòng đó.
    testWidgets('the round tab explains why a km game opens at a fixed hour', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      await tester.tap(find.text('Là gì?'));
      await tester.pumpAndSettle();
      expect(find.text('Ván đua km mở lúc 22h.'), findsOneWidget);
      Navigator.of(tester.element(find.text('Ván đua km mở lúc 22h.'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('CỔ ĐIỂN'));
      await tester.pump();
      await tester.tap(find.text('Là gì?'));
      await tester.pumpAndSettle();
      expect(find.text('Ván đua km mở lúc 22h.'), findsNothing);
    });

    testWidgets('a classic game picks 2 rounds first and its phases halve', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      await tester.tap(find.text('CỔ ĐIỂN'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('2 vòng'));
      await tester.pump();
      await tester.tap(find.text('Vòng chơi'));
      await tester.pump();
      // Vòng 24h (2h/10h/10h/2h) co còn 12h: 1h/5h/5h/1h từ 22h.
      expect(find.text('12'), findsOneWidget);
      expect(find.textContaining('9h – 10h', findRichText: true), findsOne);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      expect(_createBody(backend)['settings'], {
        'kmOff': true,
        'roundsPerDay': 2,
        'nightMin': 60,
        'dawnMin': 300,
        'dayMin': 300,
        'trialMin': 60,
      });
    });

    testWidgets('the preset tiles are the same height', (tester) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      final heights = {
        for (final t in tester.widgetList(find.byType(GamePresetTile)))
          tester.getSize(find.byWidget(t)).height,
      };
      expect(heights, hasLength(1));
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

      await tester.tap(find.text('CỔ ĐIỂN'));
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
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();

      final body = _createBody(backend);
      expect(body['roles'], {'seer': true, 'cupid': false});
      expect(body['settings'], {'elder': true});
    });

    // Đầu màn theo bản thiết kế: emblem trăng, tên hai dòng, dòng phụ; nút
    // mở ván viết hoa.
    testWidgets('shows the moon header and the open button', (tester) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      expect(find.text('MỞ VÁN\nMA SÓI'), findsOneWidget);
      expect(find.text('Chọn kiểu ván, hẹn giờ, mở.'), findsOneWidget);
      expect(find.byType(GameMoonEmblem), findsOneWidget);
      expect(find.byType(AppBar), findsNothing);

      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      expect(find.text('ván g9'), findsOneWidget);
    });

    // Có tab Giao tiếp thì chỗ bot đăng nằm trong tab đó, không còn dòng Bot
    // đăng vào ở chân mọi tab; tắt Telegram thì ẩn topic và gửi telegram tắt.
    testWidgets('the talk tab holds where the bot posts', (tester) async {
      backend.list = _talkList();
      await pumpScreen(tester);

      expect(find.text('Bot đăng vào'), findsNothing);
      await tester.tap(find.text('Giao tiếp'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'ID topic (không bắt buộc)'),
        '42',
      );
      await tester.pump();
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      expect(_createBody(backend)['threadId'], 42);
    });

    testWidgets('turning Telegram off hides the topic', (tester) async {
      backend.list = _talkList();
      await pumpScreen(tester);

      await tester.tap(find.text('Giao tiếp'));
      await tester.pump();
      expect(find.text('ID topic (không bắt buộc)'), findsOneWidget);
      await tester.tap(find.text('Telegram group'));
      await tester.pump();
      expect(find.text('ID topic (không bắt buộc)'), findsNothing);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      final body = _createBody(backend);
      expect((body['settings'] as Map)['telegram'], isFalse);
      expect(body.containsKey('threadId'), isFalse);
    });

    testWidgets('the bot row edits where the bot posts in a sheet', (
      tester,
    ) async {
      backend.list = _tabbedList();
      await pumpScreen(tester);

      expect(find.text('General'), findsOneWidget);
      expect(find.text('Ván thử'), findsNothing);
      await tester.tap(find.text('Bot đăng vào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ván thử'));
      await tester.pump();
      await tester.enterText(
        find.widgetWithText(TextField, 'Chat ID group test'),
        '-1001',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'ID topic (không bắt buộc)'),
        '42',
      );
      await tester.pump();
      Navigator.of(tester.element(find.text('Ván thử'))).pop();
      await tester.pumpAndSettle();

      expect(find.text('Ván thử · Topic 42'), findsOneWidget);
      await tester.tap(find.text('MỞ VÁN'));
      await tester.pumpAndSettle();
      final body = _createBody(backend);
      expect(body['testMode'], isTrue);
      expect(body['chatId'], '-1001');
      expect(body['threadId'], 42);
    });

    // "Là gì?" nằm trên dòng tiêu đề khối đầu tab; tab km thì thẻ nào cũng có
    // Chi tiết riêng nên không có.
    testWidgets('puts "Là gì?" on the first block title of a tab', (
      tester,
    ) async {
      backend.list = _phaseList();
      await pumpScreen(tester);

      for (final (tab, title) in [
        ('Lịch', 'ĐĂNG KÝ'),
        ('Vòng chơi', 'KÉO MỐC ĐỂ CHIA GIỜ'),
        ('Vai', 'BỘ BÀI'),
      ]) {
        await tester.tap(find.text(tab));
        await tester.pump();
        final why = find.text('Là gì?');
        expect(why, findsOneWidget, reason: tab);
        expect(
          (tester.getCenter(why).dy - tester.getCenter(find.text(title)).dy)
              .abs(),
          lessThan(4),
          reason: tab,
        );
      }
      await tester.tap(find.text('Km'));
      await tester.pump();
      expect(find.text('Là gì?'), findsNothing);
    });

    // Màn điện thoại hẹp: hint dài của thẻ kỹ năng xuống dòng, không bị cắt.
    testWidgets('a long skill hint wraps instead of being cut', (tester) async {
      const hint = 'Mọi người còn sống · km một phiếu, chạy nhiều phiếu nặng';
      final list = _skillList();
      final settings =
          (list['createOptions'] as Map<String, dynamic>)['settings'] as List;
      for (final s in settings.cast<Map<String, dynamic>>()) {
        if (s['key'] == 'kmPerUnit') s['hint'] = hint;
      }
      backend.list = list;
      await pumpScreen(tester);
      tester.view.physicalSize = const Size(390, 1400);
      await tester.pump();

      await tester.tap(find.text('Km'));
      await tester.pump();
      final text = find.textContaining(hint);
      expect(text, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(text);
      expect(paragraph.didExceedMaxLines, isFalse);
      expect(tester.getSize(text).height, greaterThan(20));
    });

    testWidgets('a toggle shows its hint under the label', (tester) async {
      final list = _skillList();
      final settings =
          (list['createOptions'] as Map<String, dynamic>)['settings'] as List;
      for (final s in settings.cast<Map<String, dynamic>>()) {
        if (s['key'] == 'kmOff') {
          s['hint'] = 'Chơi như Ma Sói thường';
          s['group'] = 'km';
        }
      }
      backend.list = list;
      await pumpScreen(tester);

      await tester.tap(find.text('Km'));
      await tester.pump();
      final label = tester.getRect(find.text('Không dùng km'));
      final hint = tester.getRect(find.text('Chơi như Ma Sói thường'));
      expect(hint.top, greaterThanOrEqualTo(label.bottom));
      expect((hint.left - label.left).abs(), lessThan(1));
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
