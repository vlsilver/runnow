import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/run_contracts/widgets/contract_card_art.dart';
import 'package:myrun/src/theme.dart';

const _condensed = 'Barlow Condensed';

TextStyle _emblemText(Color color, double size, FontWeight weight) => TextStyle(
  fontWeight: weight,
  fontSize: size,
  letterSpacing: size >= 16 ? 1.5 : 2,
  color: color,
);

/// Con dấu góc trên phải mặt trước: phần trăm mục tiêu và chữ ĐẠT KÈO, đóng
/// nghiêng như dấu mộc. Khuôn thẻ lo vòng tròn và nền.
class ContractCardStamp extends StatelessWidget {
  const ContractCardStamp({super.key, required this.tier, required this.pct});

  final GameCardTier tier;

  /// Đã định dạng sẵn, ví dụ "117%".
  final String pct;

  @override
  Widget build(BuildContext context) {
    // Con dấu nằm trên tranh tối, nên lấy màu của bản nền tối như khối chữ.
    final skin = RunCardSkin.of(context);
    final gem = (skin.onDarkArt ?? skin).accent(tier);
    TextStyle style(double size, FontWeight weight) => TextStyle(
      fontFamily: _condensed,
      fontWeight: weight,
      fontSize: size,
      height: 1,
      letterSpacing: size * 0.06,
      color: gem,
    );
    return Transform.rotate(
      angle: -12 * math.pi / 180,
      child: Container(
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: gem, width: 0.8),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(pct, style: style(10, FontWeight.w700)),
            const SizedBox(height: 3),
            Text('ĐẠT KÈO', style: style(13, FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// Mặt sau thẻ Kèo: nền toả tia theo bộ màu, huy hiệu cờ đích tô màu bậc, tên
/// kèo và thời gian bên dưới. Khuôn thẻ vẽ viền kim loại và ánh sáng.
class ContractCardBack extends StatelessWidget {
  const ContractCardBack({
    super.key,
    required this.tier,
    required this.title,
    required this.period,
  });

  final GameCardTier tier;
  final String title;

  /// Dòng thời gian, ví dụ "19.10 → 25.10.2026 · 7 NGÀY".
  final String period;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final gem = skin.accent(tier);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.08),
          radius: 0.9,
          colors: [skin.backTop, skin.backBottom],
          stops: const [0, 0.72],
        ),
      ),
      child: ContractCardEmblem(
        gem: gem,
        ground: skin.backBottom,
        ribbon: 'ĐẠT KÈO',
        lines: [
          (
            text: title.toUpperCase(),
            y: 338,
            style: _emblemText(skin.ink, 20, FontWeight.w800),
          ),
          (
            text: period,
            y: 358,
            style: _emblemText(
              skin.ink.withValues(alpha: 0.65),
              11,
              FontWeight.w600,
            ),
          ),
          (
            text: gameCardTiers[tier]!.label.toUpperCase(),
            y: 392,
            style: _emblemText(
              gem.withValues(alpha: 0.8),
              10,
              FontWeight.w700,
            ).copyWith(letterSpacing: 3),
          ),
        ],
      ),
    );
  }
}

/// Thẻ úp chờ lật: chưa biết bậc nên huy hiệu màu bạc trên khung than chì.
/// [chip] ở đáy nói vì sao chưa lật được, hay mời chạm để lật khi [onFlip]
/// có; lúc đó thẻ sáng viền vàng.
class ContractCardFaceDown extends StatelessWidget {
  const ContractCardFaceDown({
    super.key,
    required this.title,
    required this.period,
    required this.chip,
    this.km,
    this.locked = false,
    this.onFlip,
  });

  final String title;
  final String period;
  final String chip;

  /// Km tích luỹ trong kèo; null thì bỏ dòng này.
  final double? km;

  /// Chưa tới lúc lật: thêm biểu tượng khoá trước [chip].
  final bool locked;
  final VoidCallback? onFlip;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final silver = skin.accent(GameCardTier.common);
    // Chip luôn nền tối, nên chữ chip lấy màu của bản nền tối.
    final onChip = skin.onDarkArt ?? skin;
    final glow = onChip.accent(GameCardTier.legendary);
    final ready = onFlip != null;
    final ink = ready ? glow : onChip.ink;
    final card = SizedBox.fromSize(
      size: achievementCardSize,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              RunNowAchievementTokens.graphite1,
              RunNowAchievementTokens.graphite2,
              RunNowAchievementTokens.graphite3,
              RunNowAchievementTokens.graphite4,
            ],
            stops: [0, 0.38, 0.66, 1],
          ),
          boxShadow: [
            if (ready) ...[
              BoxShadow(color: glow.withValues(alpha: 0.5), spreadRadius: 1),
              BoxShadow(color: glow.withValues(alpha: 0.35), blurRadius: 34),
            ],
            const BoxShadow(
              color: RunNowAchievementTokens.drop,
              blurRadius: 44,
              offset: Offset(0, 22),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.08),
                  radius: 0.9,
                  colors: [skin.backTop, skin.backBottom],
                  stops: const [0, 0.72],
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ContractCardEmblem(
                    gem: silver,
                    ground: skin.backBottom,
                    ribbon: 'THẺ KÈO',
                    rayAlpha: 0.08,
                    lines: [
                      (
                        text: title.toUpperCase(),
                        y: 326,
                        style: _emblemText(skin.ink, 20, FontWeight.w800),
                      ),
                      (
                        text: period,
                        y: 344,
                        style: _emblemText(
                          skin.ink.withValues(alpha: 0.65),
                          11,
                          FontWeight.w600,
                        ),
                      ),
                      if (km case final km?)
                        (
                          text: '${runCardKm(km)} KM TÍCH LUỸ',
                          y: 360,
                          style: _emblemText(silver, 11, FontWeight.w700),
                        ),
                    ],
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 14,
                    child: Center(
                      child: _Chip(
                        text: chip,
                        ink: ink,
                        line: ready
                            ? glow.withValues(alpha: 0.6)
                            : RunNowContractCardTokens.chipLine,
                        locked: locked,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!ready) return card;
    return Semantics(
      button: true,
      label: 'Lật thẻ',
      child: GestureDetector(onTap: onFlip, child: card),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.text,
    required this.ink,
    required this.line,
    required this.locked,
  });

  final String text;
  final Color ink;
  final Color line;
  final bool locked;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: RunNowContractCardTokens.chip,
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: line),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked) ...[
            Icon(Icons.lock_outline_rounded, size: 13, color: ink),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: _condensed,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                letterSpacing: 1.7,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
