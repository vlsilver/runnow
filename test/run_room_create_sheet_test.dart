import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_create_sheet.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

void main() {
  late List<Map<String, dynamic>> sent;
  String? opened;

  Future<void> openSheet(WidgetTester tester, {bool scheduled = false}) async {
    sent = [];
    opened = null;
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      httpClient: MockClient((request) async {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          '{"id":"room-new"}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [runNowApiClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    opened = await showModalBottomSheet<String>(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => CreateRunRoomSheet(scheduled: scheduled),
                    ),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Hồ Tây sáng');
  }

  Future<void> tapSubmit(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('hẹn giờ: mở sẵn sáng mai, chip 18:00 đổi giờ gửi lên', (
    tester,
  ) async {
    await openSheet(tester, scheduled: true);
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1);
    const names = {
      DateTime.monday: 'thứ Hai',
      DateTime.tuesday: 'thứ Ba',
      DateTime.wednesday: 'thứ Tư',
      DateTime.thursday: 'thứ Năm',
      DateTime.friday: 'thứ Sáu',
      DateTime.saturday: 'thứ Bảy',
      DateTime.sunday: 'Chủ nhật',
    };
    final day = names[tomorrow.weekday]!;
    expect(find.text('Mở phòng · 05:30 $day'), findsOneWidget);

    await tester.tap(find.text('18:00'));
    await tester.pumpAndSettle();
    await tapSubmit(tester, 'Mở phòng · 18:00 $day');

    expect(sent, hasLength(1));
    expect(
      DateTime.parse(sent.single['startsAt'] as String).toLocal(),
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 18),
    );
    expect(opened, 'room-new');
  });

  testWidgets('giờ đã qua trong hôm nay thì chặn, không gửi', (tester) async {
    await openSheet(tester);
    await tester.tap(find.text('Hôm nay'));
    await tester.pumpAndSettle();
    // Bánh xe đang ở 05:30, mỗi nấc 34px: kéo xuống về 00:00.
    final wheels = find.byType(CupertinoPicker);
    await tester.drag(wheels.at(0), const Offset(0, 5 * 34 + 10));
    await tester.pumpAndSettle();
    await tester.drag(wheels.at(1), const Offset(0, 6 * 34 + 10));
    await tester.pumpAndSettle();
    await tapSubmit(tester, 'Mở phòng · 00:00 hôm nay');

    expect(
      find.text('Giờ này đã qua, chọn giờ khác hoặc chạy ngay.'),
      findsOneWidget,
    );
    expect(sent, isEmpty);
  });

  testWidgets('chạy ngay thì không gửi giờ hẹn', (tester) async {
    await openSheet(tester, scheduled: true);
    await tester.tap(find.text('Bây giờ'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoPicker), findsNothing);
    await tapSubmit(tester, 'Mở phòng ngay');

    expect(sent.single.containsKey('startsAt'), isFalse);
    expect(sent.single['title'], 'Hồ Tây sáng');
  });
}
