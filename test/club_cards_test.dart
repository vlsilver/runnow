import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
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
}
