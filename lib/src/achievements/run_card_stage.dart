import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart';

typedef _T = RunNowAchievementTokens;

// Màn lật thẻ luôn nền tối cho thẻ nổi lên, nên màu chữ và nút không theo theme.
final stageLine = _T.hero.withValues(alpha: 0.28);
final stageHint = TextStyle(
  color: _T.hero.withValues(alpha: 0.66),
  fontSize: 13,
);
ButtonStyle stagePrimaryButton(BuildContext context) => FilledButton.styleFrom(
  backgroundColor: _T.titleGold2,
  foregroundColor: _T.shade,
  disabledBackgroundColor: _T.titleGold2.withValues(alpha: 0.35),
  disabledForegroundColor: _T.shade.withValues(alpha: 0.7),
  minimumSize: const Size.fromHeight(54),
  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
  shape: RoundedRectangleBorder(
    borderRadius: context.runNowPalette.radius(14),
  ),
);
ButtonStyle stageQuietButton(BuildContext context) => OutlinedButton.styleFrom(
  foregroundColor: _T.hero,
  disabledForegroundColor: _T.hero.withValues(alpha: 0.4),
  side: BorderSide(color: stageLine),
  minimumSize: const Size(96, 54),
  padding: const EdgeInsets.symmetric(horizontal: 10),
  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
  shape: RoundedRectangleBorder(
    borderRadius: context.runNowPalette.radius(14),
  ),
);

/// Thẻ vẽ ở kích thước gốc rồi thu cho vừa chỗ đặt, ngang tối đa 300.
class RunCardFrame extends StatelessWidget {
  const RunCardFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GameCardScaled(
        width: [
          achievementCardSize.width,
          constraints.maxWidth,
          constraints.maxHeight * achievementCardSize.aspectRatio,
        ].reduce(math.min),
        size: achievementCardSize,
        child: child,
      ),
    );
  }
}
