import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/achievements/club_card_widgets.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/live_cheers.dart';
import 'package:myrun/src/providers.dart';

class _FakeHearts implements HeartRepository {
  @override
  Stream<Hearts> watch(String target) => Stream.value(Hearts.empty);

  @override
  Future<int> count(String target) async => 0;

  @override
  Future<void> like(String target) async {}

  @override
  Future<void> unlike(String target) async {}
}

class _FakeCheers implements LiveCheerRepository {
  @override
  Stream<List<LiveCheer>> watch(String sessionId) => Stream.value(const []);

  @override
  Future<void> send(String sessionId, String emoji) async {}
}

void main() {
  Future<void> pumpMythicThumb(
    WidgetTester tester, {
    required bool motion,
  }) async {
    final mythic = ClubCard.fromJson({
      'ownerUid': 'u1',
      'activityId': 'a1',
      'tier': 'mythic',
    })!;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
          membersProvider.overrideWith((ref) => Stream.value(const [])),
          heartRepositoryProvider.overrideWithValue(_FakeHearts()),
          liveCheerRepositoryProvider.overrideWithValue(_FakeCheers()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Center(
              child: TickerMode(
                enabled: motion,
                child: ClubCardThumb(item: mythic, width: 180),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('thẻ Thần thoại thu nhỏ có vệt sáng chạy', (tester) async {
    await pumpMythicThumb(tester, motion: true);

    expect(tester.binding.hasScheduledFrame, isTrue);
  });

  testWidgets(
    'tắt ticker thì thẻ Thần thoại thu nhỏ không giữ app vẽ liên tục',
    (tester) async {
      await pumpMythicThumb(tester, motion: false);

      expect(tester.binding.hasScheduledFrame, isFalse);
    },
  );
}
