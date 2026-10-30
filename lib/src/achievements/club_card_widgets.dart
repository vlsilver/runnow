import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/club_run_row.dart';
import 'package:myrun/src/widgets/heart_button.dart';

/// Chủ thẻ và tên in trên thẻ: thẻ của mình ghi "Bạn" ở dưới nhưng trên thẻ
/// vẫn in tên. Danh sách thành viên đọc mọi publicProfiles, cả hồ sơ riêng
/// tư; lúc danh sách chưa tải xong thì tên mình lấy từ hồ sơ của mình.
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

/// Thẻ của chính mình mở bằng thẻ gốc trong bộ để khoe được; thẻ người khác,
/// hay bộ thẻ chưa tải xong, thì chỉ xem.
VoidCallback _onOpen(
  BuildContext context,
  WidgetRef ref,
  ClubCard item,
  ({MemberProfile? member, String name, bool isMe}) owner,
  AchievementCardData data,
) {
  final own = owner.isMe
      ? ownClubCard(ref.watch(collectedCardsProvider).value ?? const [], item)
      : null;
  if (own == null) return () => showClubCardViewer(context, item, data);
  return () => own.open(context, own.data(owner.name));
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
    final data = item.card.data(owner.name);
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
              onTap: _onOpen(context, ref, item, owner, data),
              child: _CardFace(data: data, member: owner.member, width: width),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  owner.isMe ? 'Bạn' : owner.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
              HeartButton(
                target: cardHeartTarget(item.ownerUid, item.key),
                size: 14,
              ),
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
    final data = item.card.data(owner.name);
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            button: true,
            label: 'Xem thẻ của ${owner.isMe ? 'bạn' : owner.name}',
            child: GestureDetector(
              onTap: _onOpen(context, ref, item, owner, data),
              child: _CardFace(
                data: data,
                member: owner.member,
                width: constraints.maxWidth,
              ),
            ),
          ),
          Row(
            children: [
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
                target: cardHeartTarget(item.ownerUid, item.key),
                size: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Mặt thẻ khoe, avatar chủ thẻ ở góc trên phải (góc trái là dấu bậc thẻ).
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.data,
    required this.member,
    required this.width,
  });

  final AchievementCardData data;
  final MemberProfile? member;
  final double width;

  @override
  Widget build(BuildContext context) {
    final avatar = (width * 0.22).clamp(20.0, 34.0);
    final inset = width * 0.06;
    return Stack(
      children: [
        GameCardScaled(
          width: width,
          size: achievementCardSize,
          child: AchievementCard(data: data),
        ),
        Positioned(
          top: inset,
          right: inset,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: RunNowGameTokens.nightInk,
            ),
            child: Padding(
              padding: const EdgeInsets.all(1.5),
              child: ClubAvatar(member: member, size: avatar - 3),
            ),
          ),
        ),
      ],
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
    switch (item.card) {
      CollectedRunCard(:final card) => '${runCardKm(card.km)} km',
      CollectedGameCard() => 'Ma Sói',
      CollectedJourneyCard(:final card) => 'Hành trình · Level ${card.level}',
      CollectedRankCard() => 'BXH',
    },
  ],
  cardSize: achievementCardSize,
);
