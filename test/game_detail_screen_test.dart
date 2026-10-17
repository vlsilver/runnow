import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_detail_screen.dart';
import 'package:myrun/src/providers.dart';

import 'support/fake_game_backend.dart';

void main() {
  late DateTime now;
  late FakeGameBackend backend;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
        ],
        child: MaterialApp(
          home: GameDetailScreen(gameId: 'g1', clock: () => now),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> elapse(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(d);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 17, 14);
    backend = FakeGameBackend(() => now);
  });

  testWidgets('follows rules text from backend', (tester) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 30,
      'rulesText': 'Sói cắn mỗi đêm.',
    };
    await pumpScreen(tester);
    await tester.tap(find.text('Luật chơi'));
    await tester.pumpAndSettle();
    expect(find.text('Sói cắn mỗi đêm.'), findsOneWidget);

    backend.game['rulesText'] = 'Sói cắn mỗi đêm, trừ đêm đầu.';
    await elapse(tester, const Duration(seconds: 30));

    expect(find.text('Sói cắn mỗi đêm.'), findsNothing);
    expect(find.text('Sói cắn mỗi đêm, trừ đêm đầu.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('shows closing instead of the old phase past deadline', (
    tester,
  ) async {
    backend.game = {
      'id': 'g1',
      'title': 'Ma Sói tuần 42',
      'status': 'running',
      'statusLabel': 'Đang chơi',
      'refreshAfterSeconds': 300,
      'phase': {
        'key': 'r2.day',
        'label': 'Ngày 2: đề cử',
        'deadline': now.add(const Duration(minutes: 5)).toIso8601String(),
        'state': 'open',
      },
    };
    await pumpScreen(tester);
    expect(find.text('Ngày 2: đề cử'), findsOneWidget);

    await elapse(tester, const Duration(minutes: 5));

    expect(find.text('Ngày 2: đề cử'), findsNothing);
    expect(find.text('Đang chốt…'), findsOneWidget);
    await close(tester);
  });

  testWidgets('shows backend message when the game cannot load', (
    tester,
  ) async {
    backend.failGame = (
      404,
      {'error': 'not_found', 'message': 'Không tìm thấy ván.'},
    );
    await pumpScreen(tester);

    expect(find.text('Không tìm thấy ván.'), findsOneWidget);
    await close(tester);
  });
}
