import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/journey/journey_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_card.dart';

RunCard _card(String id, String tier, int daysAgo) => RunCard.fromJson({
  'id': id,
  'tier': tier,
  'km': 10.0,
  'rolledAt': DateTime.utc(2026, 10, 24).subtract(Duration(days: daysAgo)),
  'snapshot': {
    'name': 'Buổi $id',
    'sportType': 'Run',
    'distanceMeters': 10000,
    'movingTimeSeconds': 3000,
  },
});

Future<void> _pump(
  WidgetTester tester,
  List<RunCard> cards, {
  List<GamePlayerCard> games = const [],
  List<JourneyCard> journeys = const [],
  List<RankCard> ranks = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runCardsProvider.overrideWith((ref) => Stream.value(cards)),
        gameCardsProvider.overrideWith((ref) => Stream.value(games)),
        journeyCardsProvider.overrideWith((ref) => Stream.value(journeys)),
        myRankCardsProvider.overrideWith((ref) => Stream.value(ranks)),
        userProfileProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: const MaterialApp(home: RunCardCollectionScreen()),
    ),
  );
  // Thẻ Thần thoại chạy hiệu ứng mãi, nên không chờ settle. Mỗi nguồn thẻ
  // cần một frame để có giá trị.
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

/// Thẻ Ma Sói của ván kết thúc [daysAgo] ngày trước, như doc gameCards.
GamePlayerCard _game(String id, String tier, int daysAgo) =>
    GamePlayerCard.fromJson(id, {
      'tier': tier,
      'role': 'seer',
      'team': 'village',
      'winner': 'village',
      'alive': true,
      'rounds': 3,
      'playerCount': 10,
      'endedAt': DateTime.utc(2026, 10, 24).subtract(Duration(days: daysAgo)),
    });

List<String> _shown(WidgetTester tester) => [
  for (final t in tester.widgetList<CollectedCardThumb>(
    find.byType(CollectedCardThumb),
  ))
    t.card.id,
];

void main() {
  testWidgets('cards keep the newest-first order and filter by tier', (
    tester,
  ) async {
    await _pump(tester, [
      _card('a', 'rare', 1),
      _card('b', 'mythic', 2),
      _card('c', 'rare', 3),
    ]);
    expect(_shown(tester), ['a', 'b', 'c']);
    expect(find.text('Tất cả · 3'), findsOneWidget);
    expect(find.text('Thần thoại · 1'), findsOneWidget);
    expect(find.text('Hiếm · 2'), findsOneWidget);

    // Bậc chưa có thẻ vẫn hiện nhưng không chọn được.
    final common = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Thường · 0'),
    );
    expect(common.onSelected, isNull);

    await tester.tap(find.text('Hiếm · 2'));
    await tester.pump();
    expect(_shown(tester), ['a', 'c']);

    await tester.tap(find.text('Tất cả · 3'));
    await tester.pump();
    expect(_shown(tester), ['a', 'b', 'c']);
  });

  testWidgets('Ma Sói cards join the collection by time and can be shown off', (
    tester,
  ) async {
    await _pump(
      tester,
      [_card('a', 'rare', 1), _card('c', 'rare', 3)],
      games: [_game('g', 'epic', 2)],
    );
    expect(_shown(tester), ['a', 'masoi-g', 'c']);
    expect(find.text('Tất cả · 3'), findsOneWidget);
    expect(find.text('Siêu hiếm · 1'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CollectedCardThumb && w.card.id == 'masoi-g',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Khoe thẻ'), findsOneWidget);
  });

  testWidgets('journey cards join the collection by award time', (
    tester,
  ) async {
    // Buổi chạy qua mốc về đích từ tháng 3, nhưng thẻ mới trao hai ngày
    // trước (phát bù): thẻ đứng theo lúc trao, như thẻ chạy theo lúc lật.
    await _pump(
      tester,
      [_card('a', 'rare', 1), _card('c', 'rare', 3)],
      journeys: [
        JourneyCard.fromJson('mont_blanc', {
          'routeId': 'tour_du_mont_blanc',
          'level': 2,
          'tier': 'epic',
          'distanceMeters': 170000,
          'runCount': 31,
          'finishedAt': DateTime.utc(2026, 3, 1),
          'awardedAt': DateTime.utc(2026, 10, 22),
        }),
      ],
    );
    expect(_shown(tester), ['a', 'journey-mont_blanc', 'c']);
    expect(find.text('Siêu hiếm · 1'), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CollectedCardThumb && w.card.id == 'journey-mont_blanc',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Hành trình · Level 2'), findsOneWidget);
    expect(find.text('Khoe thẻ'), findsOneWidget);
  });

  testWidgets('a flipped BXH card joins by flip time, a face-down one waits', (
    tester,
  ) async {
    RankCard rank(String boardId, DateTime? revealedAt) =>
        RankCard.fromJson('me', boardId, {
          'range': 'week',
          'sport': 'run',
          'periodStart': '2026-10-12',
          'periodEnd': '2026-10-19',
          'rank': 1,
          'participants': 9,
          'tier': 'legendary',
          'score': 30000,
          'displayName': 'Linh',
          'awardedAt': DateTime.utc(2026, 10, 19, 5),
          'revealedAt': revealedAt,
        })!;
    await _pump(
      tester,
      [_card('a', 'rare', 1), _card('c', 'rare', 3)],
      ranks: [
        rank('week_2026-10-12_run', DateTime.utc(2026, 10, 22)),
        rank('week_2026-10-12_steps', null),
      ],
    );
    expect(_shown(tester), ['a', 'rank-week_2026-10-12_run', 'c']);

    await tester.tap(
      find.byWidgetPredicate(
        (w) =>
            w is CollectedCardThumb && w.card.id == 'rank-week_2026-10-12_run',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('BXH tuần · Quán quân'), findsOneWidget);
    expect(find.text('Khoe thẻ'), findsOneWidget);
  });

  testWidgets('a failing source shows the error, not half the collection', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runCardsProvider.overrideWith(
            (ref) => Stream.value([_card('a', 'rare', 1)]),
          ),
          gameCardsProvider.overrideWith(
            (ref) => Stream.error(StateError('permission-denied')),
          ),
          journeyCardsProvider.overrideWith((ref) => Stream.value(const [])),
          myRankCardsProvider.overrideWith((ref) => Stream.value(const [])),
          userProfileProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: RunCardCollectionScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CollectedCardThumb), findsNothing);
    expect(find.textContaining('Không tải được bộ thẻ'), findsOneWidget);
  });

  testWidgets('an empty collection says how to get a card', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(CollectedCardThumb), findsNothing);
    expect(find.text(collectedCardsEmpty), findsOneWidget);
  });
}
