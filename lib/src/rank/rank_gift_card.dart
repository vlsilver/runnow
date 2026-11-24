import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/rank/rank_card.dart';
import 'package:myrun/src/rank/rank_card_art.dart';
import 'package:myrun/src/rank/rank_reward.dart';
import 'package:myrun/src/rank/rank_reward_widgets.dart';
import 'package:myrun/src/theme_tokens.dart';
import 'package:myrun/src/widgets/storage_image.dart';

/// Thẻ quà luôn một bậc, không theo hạng: người trúng bốc thăm ở hạng 14 cũng
/// cầm lá bài sáng như quán quân.
const rankGiftCardTier = GameCardTier.legendary;

/// "Trúng bốc thăm trong 23 người" hay "Quà Quán quân tuần".
String rankGiftCardLine(RankCard card) {
  final pool = card.reward!.drawPool;
  if (pool != null) return 'Trúng bốc thăm trong $pool người';
  return 'Quà ${rankTitle(card.rank)} ${card.month ? 'tháng' : 'tuần'}';
}

/// Mặt trước: ảnh quà (hay biểu tượng khi chưa có ảnh), tên quà, số km và số
/// phụ của kỳ. Mặt sau: hộp quà gói kín, là mặt úp lúc chủ thẻ mở quà.
AchievementCardData rankGiftCardData(RankCard card) {
  final reward = card.reward!;
  final rankData = rankCardData(card);
  final giver = reward.giverName.isEmpty ? '' : ' · ${reward.giverName} trao';
  return AchievementCardData(
    tier: rankGiftCardTier,
    art: RankGiftArt(reward: reward),
    backFace: const RankGiftBackArt(),
    kind:
        '${card.month ? 'QUÀ BXH THÁNG' : 'QUÀ BXH TUẦN'} · '
        '${rankSportNames[card.sport]}',
    hero: rankData.hero,
    heroUnit: rankData.heroUnit,
    title: reward.name,
    quote: '${rankGiftCardLine(card)}$giver',
    stats: [
      (value: '#${card.rank}', label: 'TRÊN ${card.participants}'),
      ...rankCardExtraStats(card),
    ],
    owner: rankData.owner,
    serial: reward.drawPool != null ? 'BỐC THĂM' : 'HẠNG ${card.rank}',
    desc: '',
    meta: rankData.meta,
    date: rankData.date,
  );
}

CardShareSubject rankGiftCardShareSubject(RankCard card) {
  final reward = card.reward!;
  return CardShareSubject(
    id: 'gift-${card.boardId}',
    printed: [
      card.boardId,
      card.rank,
      card.participants,
      card.score,
      card.displayName,
      reward.name,
      reward.icon,
      reward.photos.firstOrNull ?? '',
      reward.drawPool ?? '',
      reward.giverName,
    ].join('|'),
    text:
        'Nhận ${reward.name} từ BXH ${card.month ? 'tháng' : 'tuần'} · '
        '${rankSportNames[card.sport]}\nChia sẻ từ 3i',
  );
}

/// Xem thẻ quà toàn màn hình. [faceDown] mở hộp quà đang gói để chủ thẻ tự
/// lật. Khoe thẻ và nhận quà là hai việc riêng: khoe lúc nào cũng được, còn
/// nút "Nhận quà" mở luồng nhắn người trao.
Future<void> showRankGiftCardViewer(
  BuildContext context,
  RankCard card, {
  bool faceDown = false,
}) {
  final data = rankGiftCardData(card);
  return showCardViewer(
    context,
    front: (pose) => AchievementCard(data: data, pose: pose),
    back: (pose) => AchievementCard(data: data, pose: pose, back: true),
    chips: [
      'Thẻ quà',
      if (card.reward!.drawPool != null) 'Bốc thăm' else rankTitle(card.rank),
    ],
    cardSize: achievementCardSize,
    startBack: faceDown,
    // Đóng thẻ rồi mở sheet trên màn gọi, như mọi action của màn xem thẻ.
    // Lúc hộp quà còn gói thì giấu, kẻo bấm là thấy tên quà mà chưa lật;
    // mở lại thẻ quà từ dòng quà dưới thẻ hạng thì có nút.
    action: faceDown
        ? null
        : (
            label: 'Nhận quà',
            icon: Icons.redeem,
            onPressed: () => showRankCardRewardSheet(context, card),
          ),
    onShare: (_, origin) => showCardShare(
      origin,
      subject: rankGiftCardShareSubject(card),
      data: data,
    ),
  );
}

/// Nền mặt trước: ảnh đầu của quà, hay biểu tượng quà trên nền vàng.
class RankGiftArt extends StatelessWidget {
  const RankGiftArt({required this.reward, super.key});

  final RankCardReward reward;

  @override
  Widget build(BuildContext context) {
    final icon = _GiftIconArt(icon: rankRewardIcon(reward.icon));
    final photo = reward.photos.firstOrNull;
    if (photo == null) return icon;
    return RankGiftPhotoArt(
      photo: StorageImage(path: photo, cacheWidth: 900, placeholder: icon),
    );
  }
}

/// Ảnh quà thường là ảnh shop nền trắng, còn chữ của thẻ màu sáng. Nên ảnh chỉ
/// chiếm nửa trên rồi mờ dần vào nền tối, để phần chữ ở nửa dưới luôn đọc được.
class RankGiftPhotoArt extends StatelessWidget {
  const RankGiftPhotoArt({required this.photo, super.key});

  final Widget photo;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RunNowGameTokens.cardArt,
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionallySizedBox(
          heightFactor: 0.6,
          widthFactor: 1,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: [0, 0.55, 0.85],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(rect),
            child: SizedBox.expand(child: photo),
          ),
        ),
      ),
    );
  }
}

class _GiftIconArt extends StatelessWidget {
  const _GiftIconArt({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tier = gameCardTiers[rankGiftCardTier]!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 0.9,
          colors: [tier.gem.withValues(alpha: 0.55), RunNowGameTokens.cardArt],
        ),
      ),
      child: Align(
        alignment: const Alignment(0, -0.35),
        child: Icon(icon, size: 120, color: tier.gem),
      ),
    );
  }
}

/// Mặt úp của thẻ quà: hộp quà buộc nơ.
class RankGiftBackArt extends StatelessWidget {
  const RankGiftBackArt({super.key});

  @override
  Widget build(BuildContext context) {
    final tier = gameCardTiers[rankGiftCardTier]!;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tier.gem.withValues(alpha: 0.35), RunNowGameTokens.cardArt],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.redeem, size: 110, color: tier.gem),
            const SizedBox(height: 12),
            Text(
              'LẬT ĐỂ MỞ QUÀ',
              style: TextStyle(
                color: tier.gem,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
