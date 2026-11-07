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
  final watched = <String>[];

  @override
  Stream<List<LiveCheer>> watch(String sessionId) {
    watched.add(sessionId);
    return Stream.value([
      LiveCheer(
        uid: 'fan',
        emoji: '🔥',
        at: null,
        counts: const {'🔥': 3, '👏': 1, '🐢': 1},
      ),
    ]);
  }

  @override
  Future<void> send(String sessionId, String emoji) async {}
}

Future<_FakeCheers> _pumpThumb(WidgetTester tester, ClubCard item) async {
  final cheers = _FakeCheers();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
        membersProvider.overrideWith((ref) => Stream.value(const [])),
        heartRepositoryProvider.overrideWithValue(_FakeHearts()),
        liveCheerRepositoryProvider.overrideWithValue(cheers),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Center(child: ClubCardThumb(item: item, width: 180)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return cheers;
}

void main() {
  testWidgets('thẻ buổi chạy hiện hai emoji được cổ vũ nhiều nhất lúc live', (
    tester,
  ) async {
    final run = ClubCard.fromJson({
      'ownerUid': 'u1',
      'activityId': 'a1',
      'tier': 'rare',
    })!;
    final cheers = await _pumpThumb(tester, run);

    expect(cheers.watched, contains('a1'));
    expect(find.text('🔥 3'), findsOneWidget);
    expect(find.text('👏 1'), findsOneWidget);
    expect(find.text('🐢 1'), findsNothing);
  });

  testWidgets('thẻ Ma Sói không có buổi live nên không đọc cổ vũ', (
    tester,
  ) async {
    final game = ClubCard.fromJson({
      'kind': 'game',
      'ownerUid': 'u1',
      'gameId': 'g1',
      'tier': 'rare',
      'role': 'seer',
      'team': 'village',
    })!;
    final cheers = await _pumpThumb(tester, game);

    expect(cheers.watched, isEmpty);
    expect(find.textContaining('🔥'), findsNothing);
  });
}
