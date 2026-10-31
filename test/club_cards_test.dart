import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';

void main() {
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

  test('loại thẻ app chưa biết thì bỏ qua', () {
    expect(
      ClubCard.fromJson({'kind': 'rank', 'ownerUid': 'u1', 'tier': 'rare'}),
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
    'tab Hiếm+: bỏ thẻ Thường, bậc cao trước, cùng bậc thì mới khoe trước',
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
      expect(
        [for (final item in rareFirst(all)) item.key],
        ['m', 'l', 'e', 'r1', 'r2', 'r3'],
      );
    },
  );
}
