import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/admin/admin_screen.dart';
import 'package:myrun/src/admin/agent_config_screen.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

class _FakeUser implements User {
  @override
  String get uid => 'me';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Backend giả cho /v1/admin/agent-config: giữ state, đổi version mỗi lần lưu
/// và ghi lại body PATCH.
class _ConfigBackend {
  // Qua JSON một vòng để map lồng nhau là Map<String, dynamic> như thật, test
  // gán null vào được.
  late Map<String, dynamic> state = _json({
    'fields': [
      {
        'key': 'dailyBudgetUsd',
        'label': 'Trần chi phí mỗi ngày',
        'help': 'Chạm trần thì bot nghỉ tới 0h. Để 0 là không giới hạn.',
        'kind': 'number',
        'unit': 'USD/ngày',
        'min': 0,
        'max': 1000,
        'default': 0,
        'value': 3,
      },
      {
        'key': 'dmDailyMax',
        'label': 'Số câu chat riêng',
        'help': 'Mỗi người hỏi bot riêng tối đa bấy nhiêu câu một ngày.',
        'kind': 'int',
        'unit': 'câu/người/ngày',
        'min': 0,
        'max': 1000,
        'default': 100,
        'value': null,
      },
      // Key, kind lạ: app phải dựng theo những gì backend gửi.
      {
        'key': 'futureKnob',
        'label': 'Núm thử Zeta-7',
        'help': 'Câu một giải thích. Câu hai nói thêm khi nào nên tăng.',
        'kind': 'fraction',
        'unit': 'nấc',
        'min': 1,
        'max': 9,
        'default': 4,
        'value': 7,
      },
    ],
    'priceFields': [
      for (final (key, label, unit) in [
        ('inputPer1M', 'Giá input', 'USD / 1M token'),
        ('outputPer1M', 'Giá output', 'USD / 1M token'),
        ('thinkingPer1M', 'Giá thinking', 'USD / 1M token'),
        ('cachedPer1M', 'Giá cached', 'USD / 1M token'),
        ('searchPerCall', 'Giá tìm kiếm', 'USD / lượt'),
      ])
        {'key': key, 'label': label, 'help': 'Giải thích $key.', 'unit': unit},
    ],
    'prices': [
      {
        'model': 'gemini-3.8-flash',
        'inputPer1M': 0.75,
        'outputPer1M': 3.75,
        'thinkingPer1M': null,
        'cachedPer1M': 0.075,
        'searchPerCall': 0.035,
      },
    ],
    'models': [
      {
        'model': 'gemini-3.8-flash',
        'use': 'Trả lời chat riêng và nói trong phòng bot',
        'priced': true,
      },
      {'model': 'gemini-x-pro', 'use': 'Tóm tắt ký ức', 'priced': false},
    ],
    'usage': {
      'day': '2026-10-22',
      'costUsd': 0.12,
      'calls': 10,
      'searchCalls': 1,
      'budgetHit': false,
    },
    'version': 'v1',
  });

  static Map<String, dynamic> _json(Map<String, dynamic> raw) =>
      jsonDecode(jsonEncode(raw)) as Map<String, dynamic>;

  final patches = <Map<String, dynamic>>[];
  var gets = 0;

  /// Lần PATCH tới trả lỗi này thay vì lưu.
  ({int status, String code, String message})? failNext;

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.5.0+12',
    appPlatform: 'web',
    httpClient: MockClient((request) async {
      http.Response json(Object body, [int status = 200]) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
      switch ((request.method, request.url.path)) {
        case ('GET', '/v1/admin/settings'):
          return json({
            'roles': {
              'admin': ['me'],
            },
            'telegram': {'chatId': '-1001', 'botUsername': 'threei_bot'},
          });
        case ('GET', '/v1/admin/agent-config'):
          gets++;
          return json(state);
        case ('PATCH', '/v1/admin/agent-config'):
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          patches.add(body);
          final fail = failNext;
          if (fail != null) {
            failNext = null;
            return json({
              'error': fail.code,
              'message': fail.message,
            }, fail.status);
          }
          final values = body['values'] as Map<String, dynamic>? ?? {};
          for (final f in state['fields'] as List) {
            final field = f as Map<String, dynamic>;
            if (values.containsKey(field['key'])) {
              field['value'] = values[field['key']];
            }
          }
          if (body.containsKey('prices')) state['prices'] = body['prices'];
          state['version'] = 'v${patches.length + 1}';
          return json(state);
      }
      return json({'error': 'not_found'}, 404);
    }),
  );
}

void main() {
  late _ConfigBackend backend;

  setUp(() => backend = _ConfigBackend());

  Future<void> pump(
    WidgetTester tester, {
    Widget? home,
    double width = 800,
  }) async {
    // Đủ cao để cả trang dựng hết, khỏi phải cuộn.
    tester.view.physicalSize = Size(width, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
          membersProvider.overrideWith((ref) => Stream.value(const [])),
        ],
        child: MaterialApp(home: home ?? const AgentConfigScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openField(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('admin screen opens the config screen', (tester) async {
    await pump(tester, home: const AdminScreen());
    await tester.tap(find.text('Trần và giá'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentConfigScreen), findsOneWidget);
    expect(backend.gets, 1);
  });

  testWidgets('renders every field the server sends, with help and default', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Núm thử Zeta-7'), findsOneWidget);
    expect(
      find.text('Câu một giải thích. Câu hai nói thêm khi nào nên tăng.'),
      findsOneWidget,
    );
    expect(find.text('7 nấc'), findsOneWidget);
    expect(find.text('Mặc định: 4 nấc'), findsOneWidget);
    expect(find.text('3 USD/ngày'), findsOneWidget);
    expect(find.text('Mặc định: 0 USD/ngày'), findsOneWidget);
    // Chưa đặt thì hiện mặc định làm giá trị đang dùng.
    expect(find.text('100 câu/người/ngày (mặc định)'), findsOneWidget);
  });

  testWidgets('fits a phone screen', (tester) async {
    // Tràn layout thì flutter_test báo lỗi ngay lúc dựng.
    await pump(tester, width: 360);
    await tester.tap(find.text('Thêm giá'));
    await tester.pumpAndSettle();
    expect(find.text('Giải thích searchPerCall.'), findsOneWidget);
  });

  testWidgets('usage card shows cost against the budget and budget hit', (
    tester,
  ) async {
    (backend.state['usage'] as Map)['budgetHit'] = true;
    await pump(tester);
    expect(find.text('Hôm nay (2026-10-22)'), findsOneWidget);
    expect(find.text('\$0.12 · trần \$3.00'), findsOneWidget);
    expect(find.text('10 lượt gọi · 1 lượt tìm kiếm'), findsOneWidget);
    expect(find.text('Đã chạm trần, bot đang nghỉ tới 0h'), findsOneWidget);
  });

  testWidgets('budget unset means no limit and no budget-hit line', (
    tester,
  ) async {
    ((backend.state['fields'] as List)[0] as Map)['value'] = null;
    await pump(tester);
    expect(find.text('\$0.12 · không giới hạn'), findsOneWidget);
    expect(find.text('Đã chạm trần, bot đang nghỉ tới 0h'), findsNothing);
  });

  testWidgets('editing a field sends only that key with the last version', (
    tester,
  ) async {
    await pump(tester);
    await openField(tester, 'Số câu chat riêng');
    await tester.enterText(find.byType(TextField), '50');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(backend.patches.single, {
      'version': 'v1',
      'values': {'dmDailyMax': 50},
    });
    expect(find.text('50 câu/người/ngày'), findsOneWidget);

    // Lần sau phải dùng version của response vừa rồi, không phải bản GET đầu.
    await openField(tester, 'Trần chi phí mỗi ngày');
    await tester.tap(find.text('Về mặc định'));
    await tester.pumpAndSettle();
    expect(backend.patches.last, {
      'version': 'v2',
      'values': {'dailyBudgetUsd': null},
    });
    expect(find.text('0 USD/ngày (mặc định)'), findsOneWidget);
    expect(backend.gets, 1);
  });

  testWidgets('out-of-range or non-integer input is blocked locally', (
    tester,
  ) async {
    await pump(tester);
    await openField(tester, 'Số câu chat riêng');
    expect(find.text('Từ 0 đến 1000'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '1001');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Từ 0 đến 1000.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '2.5');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Phải là số nguyên.'), findsOneWidget);

    await tester.tap(find.text('Huỷ'));
    await tester.pumpAndSettle();
    // Kind lạ coi như số thập phân, vẫn chặn theo min/max.
    await openField(tester, 'Núm thử Zeta-7');
    await tester.enterText(find.byType(TextField), '0.5');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Từ 1 đến 9.'), findsOneWidget);
    expect(backend.patches, isEmpty);

    await tester.enterText(find.byType(TextField), '2.5');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(backend.patches.single['values'], {'futureKnob': 2.5});
  });

  testWidgets('server validation error is shown', (tester) async {
    await pump(tester);
    backend.failNext = (
      status: 400,
      code: 'invalid_request',
      message: 'dmDailyMax phải từ 0 tới 1000',
    );
    await openField(tester, 'Số câu chat riêng');
    await tester.enterText(find.byType(TextField), '5');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('dmDailyMax phải từ 0 tới 1000'), findsOneWidget);
  });

  testWidgets('unpriced model warns; adding its price sends the whole table', (
    tester,
  ) async {
    await pump(tester);
    expect(
      find.text('Chưa có giá — đang tính theo giá dự phòng cao'),
      findsOneWidget,
    );
    await tester.tap(find.text('Thêm giá'));
    await tester.pumpAndSettle();
    final dialog = find.byType(AlertDialog);
    final inputs = find.descendant(
      of: dialog,
      matching: find.byType(TextField),
    );
    expect(
      tester.widget<TextField>(inputs.at(0)).controller!.text,
      'gemini-x-pro',
    );
    // Help của từng cột hiện ngay dưới ô.
    expect(find.text('Giải thích thinkingPer1M.'), findsOneWidget);
    await tester.enterText(inputs.at(1), '1.25');
    await tester.enterText(inputs.at(2), '10');
    await tester.tap(find.descendant(of: dialog, matching: find.text('Lưu')));
    await tester.pumpAndSettle();
    expect(backend.patches.single, {
      'version': 'v1',
      'prices': [
        {
          'model': 'gemini-3.8-flash',
          'inputPer1M': 0.75,
          'outputPer1M': 3.75,
          'thinkingPer1M': null,
          'cachedPer1M': 0.075,
          'searchPerCall': 0.035,
        },
        {
          'model': 'gemini-x-pro',
          'inputPer1M': 1.25,
          'outputPer1M': 10,
          'thinkingPer1M': null,
          'cachedPer1M': null,
          'searchPerCall': null,
        },
      ],
    });
  });

  testWidgets('deleting a price row sends the table without it', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Xoá giá'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xoá'));
    await tester.pumpAndSettle();
    expect(backend.patches.single, {'version': 'v1', 'prices': []});
  });

  testWidgets('config_changed reloads and tells the admin', (tester) async {
    await pump(tester);
    expect(backend.gets, 1);
    backend.failNext = (
      status: 409,
      code: 'config_changed',
      message: 'config_changed',
    );
    // Admin khác đã lưu: GET lại phải thấy bản mới.
    ((backend.state['fields'] as List)[1] as Map)['value'] = 80;
    await openField(tester, 'Số câu chat riêng');
    await tester.enterText(find.byType(TextField), '50');
    await tester.tap(find.text('Lưu'));
    await tester.pumpAndSettle();
    expect(find.text('Admin khác vừa sửa, đã tải lại'), findsOneWidget);
    expect(backend.gets, 2);
    expect(find.text('80 câu/người/ngày'), findsOneWidget);
  });
}
