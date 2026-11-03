import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/hearts.dart';

class _CountingHearts implements HeartRepository {
  _CountingHearts(this.hearts);

  final Map<String, int> hearts;
  final counted = <String>[];

  @override
  Stream<Hearts> watch(String target) => Stream.value(Hearts.empty);

  @override
  Future<int> count(String target) async {
    counted.add(target);
    return hearts[target] ?? 0;
  }

  @override
  Future<void> like(String target) async {}

  @override
  Future<void> unlike(String target) async {}
}

ClubCard _card(String id, String tier) =>
    ClubCard.fromJson({'ownerUid': 'u1', 'activityId': id, 'tier': tier})!;

void main() {
  test(
    'top thẻ: bậc trước, tim sau; thẻ bậc thấp nhiều tim không chen vào',
    () async {
      final repository = _CountingHearts({
        'card_u1_a': 1,
        'card_u1_b': 5,
        'card_u1_r': 99,
      });
      final container = ProviderContainer(
        overrides: [
          clubCardsProvider.overrideWith(
            (ref) => Stream.value([
              _card('r', 'rare'),
              _card('a', 'legendary'),
              _card('m', 'mythic'),
              _card('b', 'legendary'),
            ]),
          ),
          heartRepositoryProvider.overrideWithValue(repository),
        ],
      );
      addTearDown(container.dispose);
      final provider = topClubCardsProvider(2);
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);

      final top = await container.read(provider.future);

      expect([for (final item in top) item.key], ['m', 'b']);
      expect(repository.counted, isNot(contains('card_u1_r')));
    },
  );

  group('clubCardsDecidingTop', () {
    final mythic = _card('m', 'mythic');
    final legendA = _card('a', 'legendary');
    final legendB = _card('b', 'legendary');
    final rare = _card('r', 'rare');
    final all = [rare, legendA, mythic, legendB];

    test('bỏ thẻ dưới bậc của thẻ cuối top', () {
      expect(clubCardsDecidingTop(all, 2), [legendA, mythic, legendB]);
    });

    test('top chỉ gồm bậc cao nhất thì bỏ các bậc còn lại', () {
      expect(clubCardsDecidingTop(all, 1), [mythic]);
    });

    test('ít thẻ hơn hay vừa đủ top thì giữ hết', () {
      expect(clubCardsDecidingTop(all, 4), all);
      expect(clubCardsDecidingTop(all, 10), all);
    });
  });

  test(
    'thẻ khoe: id là activityId, có chủ thẻ, tranh và không có đường chạy',
    () {
      final item = ClubCard.fromJson({
        'ownerUid': 'u1',
        'activityId': 'a1',
        'tier': 'epic',
        'km': 23.5,
        'sharedAt': DateTime.utc(2026, 10, 25, 1),
        'startedAt': DateTime.utc(2026, 10, 24, 23),
        'snapshot': {
          'name': 'Buổi a1',
          'sportType': 'Run',
          'distanceMeters': 23500.0,
          'movingTimeSeconds': 7200.0,
          'splits': [
            {'distanceMeters': 1000.0, 'movingTimeSeconds': 300.0},
          ],
        },
        'art': {'status': 'done', 'path': 'users/u1/runCards/a1/art-1.png'},
      })!;
      expect(item.ownerUid, 'u1');
      expect(item.sharedAt, DateTime.utc(2026, 10, 25, 1));
      expect(item.key, 'a1');
      final card = (item.card as CollectedRunCard).card;
      expect(card.id, 'a1');
      expect(card.tier, GameCardTier.superRare);
      expect(card.km, 23.5);
      expect(card.artPath, 'users/u1/runCards/a1/art-1.png');
      expect(card.snapshot.route, isEmpty);
      expect(card.snapshot.splits, hasLength(1));
    },
  );

  test('thẻ khoe chưa có tranh thì không có artPath', () {
    final item = ClubCard.fromJson({
      'ownerUid': 'u1',
      'activityId': 'a1',
      'tier': 'rare',
    })!;
    expect((item.card as CollectedRunCard).card.artPath, isNull);
  });

  test('thẻ Ma Sói khoe: khoá game_{gameId}, đủ vai, phe và vòng chết', () {
    final item = ClubCard.fromJson({
      'kind': 'game',
      'ownerUid': 'u1',
      'sharedAt': DateTime.utc(2026, 10, 25, 1),
      'gameId': 'g1',
      'tier': 'legendary',
      'role': 'seer',
      'team': 'village',
      'winner': 'village',
      'alive': false,
      'deathRound': 2,
      'rounds': 4,
      'playerCount': 8,
      'endedAt': DateTime.utc(2026, 10, 20, 14),
    })!;
    expect(item.key, 'game_g1');
    expect(item.ownerUid, 'u1');
    final card = (item.card as CollectedGameCard).card;
    expect(card.gameId, 'g1');
    expect(card.tier, GameCardTier.legendary);
    expect(card.role, 'seer');
    expect(card.winner, 'village');
    expect(card.alive, isFalse);
    expect(card.deathRound, 2);
    expect(card.round, 4);
    expect(card.playerCount, 8);
    expect(card.endedAt, DateTime.utc(2026, 10, 20, 14));
  });

  test('thẻ Hành trình khoe: khoá journey_{campaign}', () {
    final item = ClubCard.fromJson({
      'kind': 'journey',
      'ownerUid': 'u2',
      'campaign': 'marathon',
      'routeId': 'athens_marathon',
      'level': 1,
      'tier': 'rare',
      'distanceMeters': 42195.0,
      'runCount': 9,
      'finishedAt': DateTime.utc(2026, 9, 1),
    })!;
    expect(item.key, 'journey_marathon');
    final card = (item.card as CollectedJourneyCard).card;
    expect(card.campaign, 'marathon');
    expect(card.level, 1);
    expect(card.tier, GameCardTier.rare);
    expect(card.distanceMeters, 42195.0);
    expect(card.runCount, 9);
  });

  test('thẻ BXH khoe: khoá rank_{boardId}, đủ hạng, kỳ và câu', () {
    final item = ClubCard.fromJson({
      'kind': 'rank',
      'ownerUid': 'u3',
      'boardId': 'week_run_2026-10-19',
      'range': 'week',
      'sport': 'run',
      'periodStart': '2026-10-19',
      'periodEnd': '2026-10-26',
      'rank': 2,
      'participants': 14,
      'tier': 'epic',
      'score': 42.5,
      'displayName': 'An',
      'quote': 'Bám đuôi số 1 cả tuần.',
      'stats': {'runMeters': 42500, 'walkMeters': 3000},
      'revealedAt': DateTime.utc(2026, 10, 27, 1, 30),
      'sharedAt': DateTime.utc(2026, 10, 27, 1, 30),
    })!;
    expect(item.key, 'rank_week_run_2026-10-19');
    expect(item.ownerUid, 'u3');
    final card = (item.card as CollectedRankCard).card;
    expect(card.uid, 'u3');
    expect(card.boardId, 'week_run_2026-10-19');
    expect(card.rank, 2);
    expect(card.tier, GameCardTier.superRare);
    expect(card.quote, 'Bám đuôi số 1 cả tuần.');
    expect(card.revealed, isTrue);
  });

  test('thẻ BXH có bộ môn app chưa biết thì bỏ qua', () {
    expect(
      ClubCard.fromJson({
        'kind': 'rank',
        'ownerUid': 'u3',
        'boardId': 'week_swim_2026-10-19',
        'range': 'week',
        'sport': 'swim',
        'periodStart': '2026-10-19',
        'periodEnd': '2026-10-26',
        'tier': 'rare',
      }),
      isNull,
    );
  });

  test('loại thẻ app chưa biết thì bỏ qua', () {
    expect(
      ClubCard.fromJson({'kind': 'badge', 'ownerUid': 'u1', 'tier': 'rare'}),
      isNull,
    );
  });

  test('thẻ khoe của mình mở bằng thẻ gốc trong bộ (đủ đường chạy)', () {
    // Thẻ gốc trong bộ có đường chạy; bản khoe ở club đã bỏ.
    final myRun = CollectedRunCard(
      RunCard.fromJson({
        'id': 'a1',
        'tier': 'rare',
        'snapshot': {
          'name': 'Sáng',
          'route': [
            {'latitude': 21.0, 'longitude': 105.8},
          ],
        },
      }),
    );
    final myGame = CollectedGameCard(
      GamePlayerCard.fromJson('g1', {'tier': 'epic', 'role': 'seer'}),
    );
    final mine = [myGame, myRun];
    ClubCard club(Map<String, dynamic> json) =>
        ClubCard.fromJson({'ownerUid': 'me', 'tier': 'rare', ...json})!;

    expect(ownClubCard(mine, club({'activityId': 'a1'})), same(myRun));
    expect(
      ownClubCard(mine, club({'kind': 'game', 'gameId': 'g1'})),
      same(myGame),
    );
    // Chưa có trong bộ (bộ chưa tải, hay thẻ của buổi khác) thì không có.
    expect(ownClubCard(mine, club({'activityId': 'a2'})), isNull);
    expect(
      ownClubCard(mine, club({'kind': 'journey', 'campaign': 'marathon'})),
      isNull,
    );
  });

  test(
    'xếp thẻ: bậc cao trước, cùng bậc nhiều tim trước, rồi mới khoe trước',
    () {
      ClubCard card(String id, String tier, int day) => ClubCard.fromJson({
        'ownerUid': 'u1',
        'activityId': id,
        'tier': tier,
        'sharedAt': DateTime.utc(2026, 10, day),
      })!;
      // Thứ tự như clubCardsProvider trả về: mới khoe trước.
      final all = [
        card('c', 'common', 30),
        card('r1', 'rare', 29),
        card('l', 'legendary', 28),
        card('r2', 'rare', 27),
        card('m', 'mythic', 26),
        card('e', 'epic', 25),
        card('r3', 'rare', 24),
      ];
      const hearts = {'c': 9, 'r1': 1, 'r2': 5, 'r3': 1, 'e': 2};
      expect(
        [
          for (final item in rankClubCards(all, (c) => hearts[c.key] ?? 0))
            item.key,
        ],
        // Thường 9 tim vẫn đứng cuối; r2 nhiều tim hơn r1; r1, r3 bằng tim
        // thì r1 khoe mới hơn.
        ['m', 'l', 'e', 'r2', 'r1', 'r3', 'c'],
      );
    },
  );
}
