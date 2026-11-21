import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/achievements/run_card_flow.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

Map<String, dynamic> _cardJson(String id) => {
  'id': id,
  'tier': 'rare',
  'km': 10.0,
  'rolledAt': '2026-11-02T00:00:00Z',
  'snapshot': {
    'name': 'Buổi $id',
    'sportType': 'Run',
    'distanceMeters': 10000,
    'movingTimeSeconds': 3000,
  },
};

const _odds = [
  {'tier': 'common', 'percent': 60.0},
  {'tier': 'rare', 'percent': 40.0},
];

ActivitySummary _run(String id) => ActivitySummary(
  id: id,
  name: 'Buổi $id',
  kind: ActivityKind.run,
  startedAt: DateTime(2026, 11, 2),
  distanceMeters: 10000,
  movingTimeSeconds: 3000,
  elapsedTimeSeconds: 3000,
);

/// API giả: POST lật thẻ đẩy thẻ vào stream của đúng buổi, như Firestore.
class _Backend {
  final gets = <String>[];
  final rolls = <String>[];
  final streams = <String, StreamController<RunCard?>>{};
  final missed = <String>{};
  bool failRoll = false;
  Completer<void>? rollGate;

  StreamController<RunCard?> stream(String id) =>
      streams.putIfAbsent(id, StreamController<RunCard?>.broadcast);

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.6.0+1',
    appPlatform: 'ios',
    httpClient: MockClient((request) async {
      final id = request.url.pathSegments[2];
      Object out;
      var status = 200;
      if (request.method == 'GET') {
        gets.add(id);
        out = missed.contains(id) && rolls.contains(id)
            ? {'card': null, 'reason': 'card_missed'}
            : {'card': null, 'odds': _odds};
      } else {
        rolls.add(id);
        await rollGate?.future;
        if (failRoll) {
          status = 500;
          out = {'error': 'internal', 'message': 'hỏng'};
        } else if (missed.contains(id)) {
          status = 409;
          out = {'error': 'card_missed', 'message': 'trượt'};
        } else {
          stream(id).add(RunCard.fromJson(_cardJson(id)));
          out = {'card': _cardJson(id)};
        }
      }
      return http.Response(
        jsonEncode(out),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

Future<void> _open(
  WidgetTester tester,
  _Backend backend,
  String id, {
  Size size = const Size(402, 874),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runNowApiClientProvider.overrideWithValue(backend.client()),
        userProfileProvider.overrideWith((ref) => Stream.value(null)),
        runCardProvider.overrideWith((ref, id) async* {
          yield null;
          yield* backend.stream(id).stream;
        }),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showRunCardFlow(context, _run(id)),
              child: const Text('mở'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('mở'));
  await _settle(tester);
}

/// Cho hiệu ứng chạy xong. Không dùng pumpAndSettle vì stream còn mở.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 800));
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await _settle(tester);
}

void main() {
  testWidgets('lật xong đứng trên thẻ đó, X đóng màn', (tester) async {
    final backend = _Backend();
    await _open(tester, backend, 'a');
    expect(find.text('Buổi a'), findsOneWidget);

    await _tap(tester, 'Lật thẻ');
    expect(backend.rolls, ['a']);
    expect(find.text('Vẽ tranh nền'), findsOneWidget);
    expect(find.text('Xong'), findsNothing);

    await tester.tap(find.byTooltip('Đóng'));
    await _settle(tester);
    expect(find.byType(RunCardFlowScreen), findsNothing);
  });

  testWidgets('chạm đúp nút lật chỉ lật một lần', (tester) async {
    final backend = _Backend()..rollGate = Completer<void>();
    await _open(tester, backend, 'a');

    await tester.tap(find.text('Lật thẻ'));
    await tester.pump();
    await tester.tap(find.text('Đang lật...'), warnIfMissed: false);
    await tester.tap(find.text('Buổi a'), warnIfMissed: false);
    await tester.pump();
    backend.rollGate!.complete();
    await _settle(tester);

    expect(backend.rolls, ['a']);
  });

  testWidgets('chạm vào lá úp cũng lật', (tester) async {
    final backend = _Backend();
    await _open(tester, backend, 'a');

    await _tap(tester, 'Buổi a');

    expect(backend.rolls, ['a']);
  });

  testWidgets('lật trượt thì báo trượt, không còn nút lật', (tester) async {
    final backend = _Backend()..missed.add('a');
    await _open(tester, backend, 'a');

    await _tap(tester, 'Lật thẻ');

    expect(find.text('LẬT THẤT BẠI'), findsOneWidget);
    expect(find.text('Lật thẻ'), findsNothing);
    expect(find.byTooltip('Đóng'), findsOneWidget);
  });

  testWidgets('API lỗi thì ở lại, lật lại được', (tester) async {
    final backend = _Backend()..failRoll = true;
    await _open(tester, backend, 'a');

    await _tap(tester, 'Lật thẻ');

    expect(find.textContaining('Không lật được thẻ'), findsOneWidget);
    backend.failRoll = false;
    await _tap(tester, 'Lật thẻ');
    expect(backend.rolls, ['a', 'a']);
    expect(find.text('Vẽ tranh nền'), findsOneWidget);
  });

  testWidgets('màn nhỏ vẫn vừa một màn hình, đủ nút', (tester) async {
    final backend = _Backend();
    // iPhone SE đời đầu.
    await _open(tester, backend, 'a', size: const Size(320, 568));
    expect(find.text('Lật thẻ').hitTestable(), findsOneWidget);
    // Thẻ co theo chỗ còn lại mà giữ đúng tỉ lệ 300:420, không bị bóp méo.
    final card = tester.getRect(find.byType(GameCardScaled));
    expect(card.width / card.height, closeTo(300 / 420, 0.01));

    await _tap(tester, 'Lật thẻ');

    expect(find.text('Vẽ tranh nền').hitTestable(), findsOneWidget);
  });
}
