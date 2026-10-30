import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/club_run_row.dart';
import 'package:myrun/src/widgets/heart_button.dart';

/// Chủ thẻ và tên in trên thẻ: thẻ của mình ghi "Bạn" ở dưới nhưng trên thẻ
/// vẫn in tên. Danh sách thành viên chỉ có hồ sơ public, nên tên mình lấy từ
/// hồ sơ của mình; người khác để riêng tư thì in "Thành viên".
({MemberProfile? member, String name, bool isMe}) _owner(
  WidgetRef ref,
  ClubCard item,
) {
  final isMe = item.ownerUid == ref.watch(firebaseUserProvider).value?.uid;
  final member = ref
      .watch(membersProvider)
      .value
      ?.where((member) => member.uid == item.ownerUid)
      .firstOrNull;
  final myName = isMe
      ? ref.watch(userProfileProvider).value?.displayName
      : null;
  return (
    member: member,
    name: member?.displayName ?? myName ?? 'Thành viên',
    isMe: isMe,
  );
}

/// Chiều cao một [ClubCardThumb] rộng [width], để danh sách ngang đặt cỡ.
double clubCardThumbHeight(double width) =>
    width * achievementCardSize.height / achievementCardSize.width + 30;

/// Thẻ khoe thu nhỏ: mặt thẻ, dưới là chủ thẻ và số tim. Chạm để xem 3D.
class ClubCardThumb extends ConsumerWidget {
  const ClubCardThumb({required this.item, required this.width, super.key});

  final ClubCard item;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = _owner(ref, item);
    final data = runCardData(item.card, owner: owner.name);
    final hearts = ref
        .watch(heartsProvider(cardHeartTarget(item.ownerUid, item.card.id)))
        .value;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Xem thẻ của ${owner.isMe ? 'bạn' : owner.name}',
            child: GestureDetector(
              onTap: () => showClubCardViewer(context, item, data),
              child: GameCardScaled(
                width: width,
                size: achievementCardSize,
                child: AchievementCard(data: data),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ClubAvatar(member: owner.member, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  owner.isMe ? 'Bạn' : owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
              if (hearts != null && hearts.count > 0) ...[
                Icon(
                  Icons.favorite_rounded,
                  size: 13,
                  color: RunNowDataColors.heart,
                ),
                const SizedBox(width: 2),
                Text(
                  '${hearts.count}',
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Một ô ở trang Thẻ của club: mặt thẻ, dưới là chủ thẻ và nút tim.
class ClubCardTile extends ConsumerWidget {
  const ClubCardTile({required this.item, super.key});

  final ClubCard item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = _owner(ref, item);
    final data = runCardData(item.card, owner: owner.name);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Xem thẻ của ${owner.isMe ? 'bạn' : owner.name}',
            child: GestureDetector(
              onTap: () => showClubCardViewer(context, item, data),
              child: GameCardScaled(
                width: constraints.maxWidth,
                size: achievementCardSize,
                child: AchievementCard(data: data),
              ),
            ),
          ),
          Row(
            children: [
              ClubAvatar(member: owner.member, size: 22),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  owner.isMe ? 'Bạn' : owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              HeartButton(
                target: cardHeartTarget(item.ownerUid, item.card.id),
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Xem thẻ khoe 3D, lật hai mặt. Không có nút khoe: thẻ của người khác.
void showClubCardViewer(
  BuildContext context,
  ClubCard item,
  AchievementCardData data,
) => showCardViewer(
  context,
  front: (pose) => AchievementCard(data: data, pose: pose),
  back: (pose) => AchievementCard(data: data, pose: pose, back: true),
  chips: [
    gameCardTiers[item.card.tier]!.label,
    '${runCardKm(item.card.km)} km',
  ],
  cardSize: achievementCardSize,
);
