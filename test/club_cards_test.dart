import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
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
      });
      expect(item.ownerUid, 'u1');
      expect(item.sharedAt, DateTime.utc(2026, 10, 25, 1));
      expect(item.card.id, 'a1');
      expect(item.card.tier, GameCardTier.superRare);
      expect(item.card.km, 23.5);
      expect(item.card.artPath, 'users/u1/runCards/a1/art-1.png');
      expect(item.card.snapshot.route, isEmpty);
      expect(item.card.snapshot.splits, hasLength(1));
    },
  );

  test('thẻ khoe chưa có tranh thì không có artPath', () {
    final item = ClubCard.fromJson({
      'ownerUid': 'u1',
      'activityId': 'a1',
      'tier': 'rare',
    });
    expect(item.card.artPath, isNull);
  });
}
