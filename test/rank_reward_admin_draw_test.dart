import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/admin/rank_reward_admin_screen.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

void main() {
  late Map<String, Object?> view;
  final puts = <Map<String, dynamic>>[];
  setUp(puts.clear);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      appVersion: () async => '1.5.0+12',
      appPlatform: 'web',
      httpClient: MockClient((request) async {
        if (request.method == 'PUT') {
          puts.add(jsonDecode(request.body) as Map<String, dynamic>);
        }
        return http.Response(
          jsonEncode(view),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [runNowApiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: RankRewardAdminScreen(admins: {'me': 'Tôi'}),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Map<String, Object?> viewWith(String state, List<Object?> items) => {
    'boardId': 'x',
    'state': state,
    'giverUid': 'me',
    'giverName': 'Tôi',
    'items': items,
    'winners': [],
  };

  Map<String, dynamic> sentItem() =>
      (puts.single['items'] as List).single as Map<String, dynamic>;

  testWidgets('kỳ đang chạy: mở món bốc thăm rồi lưu, mốc giữ nguyên số đã '
      'lưu, suất thêm được', (tester) async {
    // Mốc lẻ dưới mét: tính lại từ chữ trong ô thì thành 12346 và backend
    // từ chối cả lần lưu vì đổi mốc.
    view = viewWith('running', [
      {
        'id': 'a',
        'kind': 'draw',
        'minScore': 12345.6,
        'slots': 2,
        'name': 'Áo',
        'icon': 'shirt',
        'photos': <String>[],
      },
    ]);
    await pump(tester);
    await tester.tap(find.textContaining('Áo'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Số suất'), '3');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Xong'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lưu quà'));
    await tester.pumpAndSettle();

    expect(sentItem(), {
      'id': 'a',
      'name': 'Áo',
      'icon': 'shirt',
      'photos': <String>[],
      'kind': 'draw',
      'minScore': 12345.6,
      'slots': 3,
    });
  });

  for (final (input, want) in [
    ('12,3', 12300.0),
    ('Infinity', null),
    ('NaN', null),
    ('0.0004', null),
  ]) {
    testWidgets('mốc "$input" km', (tester) async {
      view = viewWith('upcoming', []);
      await pump(tester);
      await tester.tap(find.text('Thêm món'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Tên quà'), 'Áo');
      await tester.tap(find.text('Bốc thăm'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Đạt từ (km)'),
        input,
      );
      await tester.pumpAndSettle();
      final done = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Xong'),
      );
      if (want == null) {
        expect(done.onPressed, isNull);
        expect(find.text('Nhập mốc lớn hơn 0.'), findsOneWidget);
        return;
      }
      await tester.tap(find.text('Xong'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lưu quà'));
      await tester.pumpAndSettle();
      expect(sentItem()['minScore'], want);
      expect(sentItem().containsKey('fromRank'), isFalse);
    });
  }
}
