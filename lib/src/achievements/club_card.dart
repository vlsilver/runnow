import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/games/game_player_card.dart';
import 'package:myrun/src/journey/journey_card.dart';

/// Thẻ một người khoe với club, doc clubCards/{ownerUid}_{key}. Cùng dạng doc
/// thẻ của chủ (đã bỏ phần riêng tư), nên vẽ bằng khuôn của Bộ thẻ.
class ClubCard {
  const ClubCard({
    required this.ownerUid,
    required this.key,
    required this.card,
    this.sharedAt,
  });

  /// Đọc một doc clubCards. Thẻ buổi chạy không có kind; kind app chưa biết
  /// (backend mới hơn app) thì trả null để mục thẻ bỏ qua.
  static ClubCard? fromJson(Map<String, dynamic> json) {
    String text(String field) => json[field] as String? ?? '';
    final (String, CollectedCard)? parsed = switch (json['kind']) {
      null => (
        text('activityId'),
        CollectedRunCard(RunCard.fromJson({...json, 'id': text('activityId')})),
      ),
      'game' => (
        'game_${text('gameId')}',
        CollectedGameCard(GamePlayerCard.fromJson(text('gameId'), json)),
      ),
      'journey' => (
        'journey_${text('campaign')}',
        CollectedJourneyCard(JourneyCard.fromJson(text('campaign'), json)),
      ),
      _ => null,
    };
    if (parsed == null) return null;
    final sharedAt = json['sharedAt'];
    return ClubCard(
      ownerUid: text('ownerUid'),
      key: parsed.$1,
      card: parsed.$2,
      sharedAt: sharedAt is DateTime ? sharedAt : null,
    );
  }

  final String ownerUid;

  /// Phần sau `{ownerUid}_` của id thẻ khoe và của tim thẻ: activityId,
  /// `game_{gameId}` hay `journey_{campaign}`.
  final String key;
  final CollectedCard card;
  final DateTime? sharedAt;
}

/// Thẻ gốc trong bộ thẻ của mình ứng với thẻ khoe [item], để mở bằng màn xem
/// của chủ thẻ (có nút khoe, đủ đường chạy). Id thẻ khoe và thẻ trong bộ giống
/// nhau: activityId, `masoi-{gameId}`, `journey-{campaign}`.
CollectedCard? ownClubCard(Iterable<CollectedCard> mine, ClubCard item) =>
    mine.where((card) => card.id == item.card.id).firstOrNull;

/// Bậc hiếm cao trước; cùng bậc thì nhiều tim trước; vẫn bằng thì thẻ khoe
/// mới trước. So cả sharedAt vì List.sort không giữ thứ tự sẵn có của phần tử
/// bằng nhau.
List<ClubCard> rankClubCards(
  Iterable<ClubCard> cards,
  int Function(ClubCard card) hearts,
) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  return [...cards]..sort((a, b) {
    final byTier = b.card.tier.index.compareTo(a.card.tier.index);
    if (byTier != 0) return byTier;
    final byHearts = hearts(b).compareTo(hearts(a));
    if (byHearts != 0) return byHearts;
    return (b.sharedAt ?? epoch).compareTo(a.sharedAt ?? epoch);
  });
}
