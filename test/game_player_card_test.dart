import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/games/game_role_card.dart';

void main() {
  group('gameRoundOf', () {
    test('reads the round from the phase key', () {
      expect(gameRoundOf('r3/day'), 3);
      expect(gameRoundOf('r12/night'), 12);
    });

    test('is 0 for keys without a round', () {
      expect(gameRoundOf(null), 0);
      expect(gameRoundOf('ended'), 0);
      expect(gameRoundOf('registration'), 0);
    });
  });

  group('GamePlayerCard.fromJson', () {
    test('reads the card the backend minted for a winner', () {
      final endedAt = DateTime.utc(2026, 10, 24, 15);
      final card = GamePlayerCard.fromJson('g1', {
        'gameId': 'g1',
        'tier': 'epic',
        'role': 'witch',
        'team': 'village',
        'winner': 'village',
        'alive': false,
        'rounds': 4,
        'playerCount': 10,
        'deathRound': 2,
        'endedAt': endedAt,
        'testMode': true,
      });

      expect(card.gameId, 'g1');
      expect(card.tier, GameCardTier.superRare);
      expect(card.owned, isTrue);
      expect(card.round, 4);
      expect(card.playerCount, 10);
      expect(card.deathRound, 2);
      expect(card.endedAt, endedAt);
      expect(card.testMode, isTrue);
      expect(card.result, 'Thắng');
      expect(card.fate, 'Ngã vòng 2');
      expect(card.teamLabel, 'Phe Dân');
    });

    test('leaves optional fields empty when missing', () {
      final card = GamePlayerCard.fromJson('g2', {
        'tier': 'common',
        'role': 'wolf',
        'team': 'wolves',
        'winner': 'wolves',
        'alive': true,
        'rounds': 3,
        'playerCount': 8,
      });

      expect(card.deathRound, isNull);
      expect(card.endedAt, isNull);
      expect(card.testMode, isFalse);
      expect(card.fate, 'Sống sót');
    });
  });

  group('GamePlayerCard.fromMe', () {
    // Backend chỉ gửi phase khi ván đang chạy.
    GameDetail detail({String? phase, String? winner}) => GameDetail.fromJson({
      'id': 'g1',
      'status': phase == null ? 'ended' : 'running',
      'playerCount': 9,
      if (phase != null) 'phase': {'key': phase},
      'winner': ?winner,
    });

    test('a winner owns the card and sits on the winning side', () {
      // Sói trong cặp đôi phe ba: thắng thì phe là cặp đôi, không phải phe Sói.
      final card = GamePlayerCard.fromMe(
        detail: detail(winner: 'lovers'),
        me: GameMe.fromJson({
          'status': 'ended',
          'alive': true,
          'role': 'wolf',
          'cardTier': 'mythic',
          'cardOwned': true,
          'cardRounds': 5,
        }),
      );

      expect(card.owned, isTrue);
      expect(card.tier, GameCardTier.mythic);
      expect(card.team, 'lovers');
      expect(card.winner, 'lovers');
      expect(card.round, 5);
      expect(card.playerCount, 9);
      expect(card.result, 'Thắng');
    });

    test('a loser does not own the card and keeps the side of the role', () {
      final card = GamePlayerCard.fromMe(
        detail: detail(winner: 'village'),
        me: GameMe.fromJson({
          'status': 'ended',
          'alive': false,
          'role': 'wolf',
          'cardTier': 'rare',
          'cardOwned': false,
          'cardRounds': 4,
        }),
      );

      expect(card.owned, isFalse);
      expect(card.team, 'wolves');
      expect(card.winner, 'village');
      expect(card.round, 4);
      expect(card.result, 'Thua');
    });

    test('a running game shows no winner even if one is sent', () {
      final card = GamePlayerCard.fromMe(
        detail: detail(phase: 'r2/day', winner: 'village'),
        me: GameMe.fromJson({
          'status': 'running',
          'alive': true,
          'role': 'seer',
          'cardTier': 'common',
        }),
      );

      expect(card.ended, isFalse);
      expect(card.owned, isFalse);
      expect(card.team, 'village');
      expect(card.round, 2);
      expect(card.result, 'Đang chơi');
      expect(card.fate, 'Còn sống');
    });
  });
}
