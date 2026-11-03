import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/live_cheers.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/club_run_row.dart';
import 'package:myrun/src/widgets/heart_button.dart';
import 'package:myrun/src/widgets/live_cheer_bar.dart';

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
  final reaction = _CardHearts(
    target: cardHeartTarget(item.ownerUid, item.key),
    liveSessionId: _liveSessionOf(item),
  );
  if (own == null) {
    return () => showClubCardViewer(context, item, data, reaction: reaction);
  }
  return () => own.open(context, own.data(owner.name), reaction: reaction);
}

/// Buổi live của thẻ buổi chạy: id buổi live trùng activityId. Thẻ khác
/// không có buổi live.
String? _liveSessionOf(ClubCard item) =>
    item.card is CollectedRunCard ? item.key : null;

/// Hàng tim ở màn xem thẻ: ai đã thả tim, nút tim để mình thả, và tổng emoji
/// người xem cổ vũ lúc chạy.
class _CardHearts extends StatelessWidget {
  const _CardHearts({required this.target, required this.liveSessionId});

  final String target;
  final String? liveSessionId;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (liveSessionId case final id?) LiveCheerTotals(sessionId: id),
      Row(
        children: [
          Expanded(
            child: HeartCheerers(target: target, label: 'đã thả tim'),
          ),
          HeartButton(target: target, size: 26),
        ],
      ),
    ],
  );
}

/// Chiều cao một [ClubCardThumb] rộng [width], để danh sách ngang đặt cỡ.
double clubCardThumbHeight(double width) =>
    width * achievementCardSize.height / achievementCardSize.width;

/// Thẻ khoe thu nhỏ: mặt thẻ có chủ thẻ và nút tim. Chạm để xem 3D.
class ClubCardThumb extends StatelessWidget {
  const ClubCardThumb({required this.item, required this.width, super.key});

  final ClubCard item;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: _ClubCardFace(item: item, width: width),
  );
}

/// Một ô ở trang Thẻ của club: mặt thẻ có chủ thẻ và nút tim.
class ClubCardTile extends StatelessWidget {
  const ClubCardTile({required this.item, super.key});

  final ClubCard item;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _ClubCardFace(item: item, width: constraints.maxWidth),
  );
}

/// Mặt thẻ chạm được để xem. Tên chủ thẻ đã in trên thẻ nên không thêm dòng
/// nào bên dưới.
class _ClubCardFace extends ConsumerWidget {
  const _ClubCardFace({required this.item, required this.width});

  final ClubCard item;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = _owner(ref, item);
    final data = item.card.data(owner.name);
    return Semantics(
      button: true,
      label: 'Xem thẻ của ${owner.isMe ? 'bạn' : owner.name}',
      child: GestureDetector(
        onTap: _onOpen(context, ref, item, owner, data),
        child: _CardFace(
          data: data,
          member: owner.member,
          heartTarget: cardHeartTarget(item.ownerUid, item.key),
          liveSessionId: _liveSessionOf(item),
          width: width,
        ),
      ),
    );
  }
}

/// Mặt thẻ khoe: góc trên phải là avatar chủ thẻ, ngay dưới là nút tim (góc
/// trái là dấu bậc thẻ). Tim nằm trên tranh tối nên có nền tối và chữ sáng
/// dù app đang sáng hay tối.
class _CardFace extends StatelessWidget {
  const _CardFace({
    required this.data,
    required this.member,
    required this.heartTarget,
    required this.liveSessionId,
    required this.width,
  });

  final AchievementCardData data;
  final MemberProfile? member;
  final String heartTarget;
  final String? liveSessionId;
  final double width;

  @override
  Widget build(BuildContext context) {
    final avatar = (width * 0.22).clamp(20.0, 34.0);
    final inset = width * 0.06;
    final theme = Theme.of(context);
    return Stack(
      children: [
        GameCardScaled(
          width: width,
          size: achievementCardSize,
          // Vệt sáng Thần thoại chỉ chạy ở màn xem: ở đây nó bắt cả trang vẽ
          // lại mỗi frame, kể cả lúc thẻ đã cuộn khỏi màn hình.
          child: AchievementCard(data: data, animate: false),
        ),
        Positioned(
          top: inset,
          right: inset,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              DecoratedBox(
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: RunNowGameTokens.nightInk,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(1.5),
                  child: ClubAvatar(member: member, size: avatar - 3),
                ),
              ),
              const SizedBox(height: 4),
              DecoratedBox(
                decoration: ShapeDecoration(
                  shape: const StadiumBorder(),
                  color: RunNowGameTokens.nightBackground.withValues(
                    alpha: 0.72,
                  ),
                ),
                child: Theme(
                  data: theme.copyWith(
                    colorScheme: theme.colorScheme.copyWith(
                      onSurface: RunNowGameTokens.nightInk,
                    ),
                  ),
                  child: HeartButton(
                    target: heartTarget,
                    size: (width * 0.1).clamp(13.0, 18.0),
                  ),
                ),
              ),
              // Hai emoji được cổ vũ nhiều nhất lúc chạy, cùng nền tối như tim.
              if (liveSessionId case final id?)
                _CheerPill(sessionId: id, width: width),
            ],
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
  AchievementCardData data, {
  Widget? reaction,
}) => showCardViewer(
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
      CollectedContractCard() => 'Kèo',
    },
  ],
  cardSize: achievementCardSize,
  reaction: reaction,
);

/// Viên tổng cổ vũ dưới nút tim trên mặt thẻ. Chưa ai cổ vũ thì không hiện
/// cả nền.
class _CheerPill extends ConsumerWidget {
  const _CheerPill({required this.sessionId, required this.width});

  final String sessionId;
  final double width;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cheers = ref.watch(liveCheersProvider(sessionId)).value ?? const [];
    if (liveCheerTotals(cheers).isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: DecoratedBox(
        decoration: ShapeDecoration(
          shape: const StadiumBorder(),
          color: RunNowGameTokens.nightBackground.withValues(alpha: 0.72),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: LiveCheerTotals(
            sessionId: sessionId,
            max: 2,
            style: TextStyle(
              color: RunNowGameTokens.nightInk,
              fontSize: (width * 0.07).clamp(9.0, 12.0),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}
