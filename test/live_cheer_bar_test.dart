import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/live_cheers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/widgets/live_cheer_bar.dart';

class _FakeCheers implements LiveCheerRepository {
  _FakeCheers([this.cheers = const []]);

  final List<LiveCheer> cheers;
  final sent = <String>[];
  Object? failWith;

  @override
  Stream<List<LiveCheer>> watch(String sessionId) => Stream.value(cheers);

  @override
  Future<void> send(String sessionId, String emoji) async {
    if (failWith case final error?) throw error;
    sent.add('$sessionId $emoji');
  }
}

Future<void> _pump(WidgetTester tester, _FakeCheers fake, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
        liveCheerRepositoryProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('bấm emoji thì gửi; chưa hết giãn cách thì bấm tiếp không gửi', (
    tester,
  ) async {
    final fake = _FakeCheers();
    await _pump(tester, fake, const LiveCheerBar(sessionId: 's1'));

    await tester.tap(find.text('🔥'));
    await tester.pump();
    await tester.tap(find.text('👏'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('👏'));
    await tester.pump(const Duration(seconds: 2));
    await tester.tap(find.text('💪'));
    await tester.pump();

    expect(fake.sent, ['s1 🔥', 's1 💪']);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('gửi lỗi thì báo người xem', (tester) async {
    final fake = _FakeCheers()..failWith = StateError('permission-denied');
    await _pump(tester, fake, const LiveCheerBar(sessionId: 's1'));

    await tester.tap(find.text('🔥'));
    await tester.pump();

    expect(find.text('Không gửi được cổ vũ, thử lại nhé.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('dòng tổng cổ vũ: nhiều nhất trước, chưa có thì không hiện', (
    tester,
  ) async {
    final fake = _FakeCheers([
      LiveCheer(uid: 'a', emoji: '🔥', at: null, counts: const {'🔥': 3}),
      LiveCheer(
        uid: 'b',
        emoji: '👏',
        at: null,
        counts: const {'👏': 1, '🔥': 1},
      ),
    ]);
    await _pump(tester, fake, const LiveCheerTotals(sessionId: 's1'));
    expect(find.text('🔥 4'), findsOneWidget);
    expect(find.text('👏 1'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('🔥 4')).dx,
      lessThan(tester.getTopLeft(find.text('👏 1')).dx),
    );

    await _pump(tester, _FakeCheers(), const LiveCheerTotals(sessionId: 's2'));
    expect(find.textContaining('🔥'), findsNothing);
  });
}
