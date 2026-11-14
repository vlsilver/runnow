import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/journey/journey_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rank/rank_card.dart';
import 'package:myrun/src/run_contracts/contract_card_models.dart';

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
  List<ContractCard> contracts = const [],
  List<ActivitySummary> unflipped = const [],
  Object? unflippedError,
  VoidCallback? onFetchUnflipped,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runCardsProvider.overrideWith((ref) => Stream.value(cards)),
        gameCardsProvider.overrideWith((ref) => Stream.value(games)),
        journeyCardsProvider.overrideWith((ref) => Stream.value(journeys)),
        myRankCardsProvider.overrideWith((ref) => Stream.value(ranks)),
        contractCardsProvider.overrideWith((ref) => Stream.value(contracts)),
        userProfileProvider.overrideWith((ref) => Stream.value(null)),
        unflippedRunsProvider.overrideWith((ref) async {
          onFetchUnflipped?.call();
          if (unflippedError case final error?) throw error;
          return unflipped;
        }),
        runCardProvider.overrideWith((ref, id) => Stream.value(null)),
        runCardViewProvider.overrideWith(
          (ref, id) async => const RunCardView(chance: 100),
        ),
      ],
      child: const MaterialApp(home: RunCardCollectionScreen()),
    ),
  );
  // Thẻ Thần thoại chạy hiệu ứng mãi, nên không chờ settle. Mỗi nguồn thẻ
  // cần một frame để có giá trị.
  for (var i = 0; i < 5; i++) {
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

ActivitySummary _run(String id, double km) => ActivitySummary(
  id: id,
  name: 'Buổi $id',
  kind: ActivityKind.run,
  startedAt: DateTime(2026, 11, 2),
  distanceMeters: km * 1000,
  movingTimeSeconds: 3000,
  elapsedTimeSeconds: 3000,
);

/// Pill bậc [label] đang hiện đúng số thẻ [count].
Finder _pill(String label, int count) =>
    find.text('$label $count', findRichText: true);

void main() {
  group('filter Chưa lật', () {
    testWidgets('hiện mặt úp của các buổi chưa lật, ẩn thẻ đã có', (
      tester,
    ) async {
      await _pump(
        tester,
        [_card('c', 'common', 0)],
        unflipped: [_run('a', 10.2), _run('b', 5)],
      );

      await tester.tap(find.text('Lật 2 buổi'));
      await tester.pump();

      expect(find.byType(RunCardFaceDown), findsNWidgets(2));
      expect(find.byType(AchievementCard), findsNothing);
      expect(find.text('10,2 KM'), findsOneWidget);
    });

    testWidgets('chưa có thẻ nào mà còn buổi chưa lật thì vẫn có filter', (
      tester,
    ) async {
      await _pump(tester, const [], unflipped: [_run('a', 10)]);

      expect(find.text(collectedCardsEmpty), findsNothing);
      expect(find.text('Lật 1 buổi'), findsOneWidget);
    });

    testWidgets('hết buổi chưa lật thì không có nút lật', (tester) async {
      await _pump(tester, [_card('c', 'common', 0)]);

      expect(find.textContaining(RegExp(r'^Lật \d')), findsNothing);
      expect(_shown(tester), ['c']);
    });

    testWidgets('từ buổi chưa lật quay về thẻ đã có', (tester) async {
      await _pump(tester, [_card('c', 'common', 0)], unflipped: [_run('a', 5)]);
      await tester.tap(find.text('Lật 1 buổi'));
      await tester.pump();
      expect(find.byType(AchievementCard), findsNothing);

      await tester.tap(find.text('Xem 1 thẻ'));
      await tester.pump();
      expect(_shown(tester), ['c']);
    });

    testWidgets('tải lỗi thì báo trong filter, thẻ đã có vẫn xem được', (
      tester,
    ) async {
      await _pump(tester, [
        _card('c', 'common', 0),
      ], unflippedError: Exception('mạng'));

      expect(find.byType(AchievementCard), findsOneWidget);
      await tester.tap(find.text('Buổi chưa lật'));
      await tester.pump();
      expect(find.text('Không tải được. Chạm để thử lại.'), findsOneWidget);
    });

    testWidgets('chạm thẻ úp mở màn lật, đóng màn thì tải lại danh sách', (
      tester,
    ) async {
      var fetches = 0;
      await _pump(
        tester,
        [_card('c', 'common', 0)],
        unflipped: [_run('a', 10)],
        onFetchUnflipped: () => fetches++,
      );
      await tester.tap(find.text('Lật 1 buổi'));
      await tester.pump();
      expect(fetches, 1);

      await tester.tap(find.byType(RunCardFaceDown));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RunCardPanel), findsOneWidget);

      Navigator.of(tester.element(find.byType(RunCardPanel))).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(fetches, 2);
    });
  });

  testWidgets('cards keep the newest-first order and filter by tier', (
    tester,
  ) async {
    // Đủ ngang để mọi pill cùng nằm trên màn, không phải cuộn hàng filter.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, [
      _card('a', 'rare', 1),
      _card('b', 'mythic', 2),
      _card('c', 'rare', 3),
    ]);
    expect(_shown(tester), ['a', 'b', 'c']);
    expect(find.text('3 thẻ', findRichText: true), findsOneWidget);
    expect(_pill('Thần thoại', 1), findsOneWidget);
    expect(_pill('Hiếm', 2), findsOneWidget);

    // Bậc chưa có thẻ vẫn hiện nhưng không chọn được.
    expect(_pill('Siêu hiếm', 0), findsOneWidget);
    await tester.tap(_pill('Siêu hiếm', 0));
    await tester.pump();
    expect(_shown(tester), ['a', 'b', 'c']);

    await tester.tap(_pill('Hiếm', 2));
    await tester.pump();
    expect(_shown(tester), ['a', 'c']);

    await tester.tap(find.text('Tất cả', findRichText: true));
    await tester.pump();
    expect(_shown(tester), ['a', 'b', 'c']);
  });

  testWidgets('bộ thẻ dài chỉ dựng các thẻ gần màn hình', (tester) async {
    await _pump(tester, [
      for (var i = 0; i < 60; i++) _card('c$i', 'mythic', i),
    ]);

    final built = find.byType(CollectedCardThumb, skipOffstage: false);
    expect(built, findsWidgets);
    expect(tester.widgetList(built).length, lessThan(30));
    expect(find.text('60 thẻ', findRichText: true), findsOneWidget);
  });

  testWidgets('cuộn bộ thẻ không dựng lại các thẻ đang hiện', (tester) async {
    await _pump(tester, [for (var i = 0; i < 30; i++) _card('c$i', 'rare', i)]);
    CollectedCardThumb thumb(String id) => tester.widget(
      find.byWidgetPredicate((w) => w is CollectedCardThumb && w.card.id == id),
    );
    final before = thumb('c6');

    // Kéo qua phần đầu trang để chính lưới cuộn, mỗi lần một ít như ngón tay.
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -60));
      await tester.pump();
    }

    expect(identical(thumb('c6'), before), isTrue);
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
    expect(find.text('3 thẻ', findRichText: true), findsOneWidget);
    expect(_pill('Siêu hiếm', 1), findsOneWidget);

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
    expect(_pill('Siêu hiếm', 1), findsOneWidget);

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
          contractCardsProvider.overrideWith((ref) => Stream.value(const [])),
          userProfileProvider.overrideWith((ref) => Stream.value(null)),
          unflippedRunsProvider.overrideWith((ref) async => const []),
        ],
        child: const MaterialApp(home: RunCardCollectionScreen()),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CollectedCardThumb), findsNothing);
    expect(find.textContaining('Không tải được bộ thẻ'), findsOneWidget);
  });

  testWidgets('a kèo card joins the collection by flip time', (tester) async {
    // Doc contractCards sau khi đọc từ Firestore: rolledAt là DateTime chứ
    // không phải chuỗi như JSON của API.
    final contract = ContractCard.fromJson({
      'contractId': 'k1',
      'tier': 'epic',
      'km': 23.5,
      'rolledAt': DateTime.utc(2026, 10, 22),
      'snapshot': {
        'title': 'Tuần 20 km',
        'metric': 'distance',
        'targetValue': 20,
        'progressValue': 23.5,
        'startAt': '2026-10-18T17:00:00Z',
        'endAtExclusive': '2026-10-25T17:00:00Z',
        'participants': 3,
        'achievers': 2,
        'displayName': 'An',
      },
    });
    await _pump(
      tester,
      [_card('a', 'rare', 1), _card('c', 'rare', 3)],
      contracts: [contract],
    );
    expect(_shown(tester), ['a', 'contract-k1', 'c']);
    expect(_pill('Siêu hiếm', 1), findsOneWidget);

    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is CollectedCardThumb && w.card.id == 'contract-k1',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Kèo · 23,5 km'), findsOneWidget);
    expect(find.text('Khoe thẻ'), findsOneWidget);
  });

  testWidgets('an empty collection says how to get a card', (tester) async {
    await _pump(tester, const []);
    expect(find.byType(CollectedCardThumb), findsNothing);
    expect(find.text(collectedCardsEmpty), findsOneWidget);
  });
}
