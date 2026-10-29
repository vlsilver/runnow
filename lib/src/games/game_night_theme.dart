import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

/// Tông đêm của lá bài Ma Sói: nền mực tím đen, kính trắng mờ, nhấn vàng. Chỉ
/// dùng cho chỗ là tranh (màn xem thẻ, cảnh đêm/ngày đầu màn ván); trang ván
/// theo sáng/tối và hành của app như mọi màn khác.
const gameNightGold = RunNowGameTokens.gold;
const gameNightGoldDeep = RunNowGameTokens.goldDeep;
const gameNightInk = RunNowGameTokens.nightInk;
const gameNightMuted = RunNowGameTokens.nightMuted;
const gameNightBackground = RunNowGameTokens.nightBackground;
const _onGold = RunNowGameTokens.onGold;
const _surface = RunNowGameTokens.nightSurface;
const _danger = RunNowGameTokens.nightDanger;

/// Dải vàng foil cho chip và nút chính.
const gameNightFoil = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [
    gameNightGoldDeep,
    RunNowGameTokens.goldPale,
    RunNowGameTokens.goldShade,
  ],
);

/// Dải màu hành cho nút đang chọn và thanh giờ trên trang ván, thay vàng foil.
LinearGradient gameAccentFoil(RunNowPalette palette) => LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [palette.accentDeep, palette.accent],
);

ThemeData gameNightTheme() {
  final base = buildRunNowTheme(RunNowElement.fire);
  final palette = base.extension<RunNowPalette>()!.copyWith(
    accent: gameNightGold,
    accentDeep: gameNightGoldDeep,
    secondary: gameNightGoldDeep,
    tertiary: RunNowGameTokens.goldPale,
    ink: gameNightInk,
    // Tint phải đặc: vàng 12% trộn lên nền kính.
    tint: Color.alphaBlend(gameNightGold.withValues(alpha: 0.12), _surface),
    textMuted: gameNightMuted,
    background: gameNightBackground,
    backgroundMid: gameNightBackground,
    backgroundDeep: gameNightBackground,
    glassStart: Colors.white.withValues(alpha: 0.06),
    glassEnd: Colors.white.withValues(alpha: 0.04),
    gridMinor: Colors.transparent,
    gridMajor: Colors.transparent,
    glowStrong: gameNightGold.withValues(alpha: 0.10),
    glowSoft: gameNightGold.withValues(alpha: 0.05),
    border: Colors.white.withValues(alpha: 0.1),
    foreground: gameNightInk,
  );
  final scheme = base.colorScheme.copyWith(
    primary: gameNightGold,
    onPrimary: _onGold,
    secondary: gameNightGoldDeep,
    onSecondary: _onGold,
    secondaryContainer: Color.alphaBlend(
      gameNightGold.withValues(alpha: 0.18),
      _surface,
    ),
    onSecondaryContainer: gameNightGold,
    error: _danger,
    surface: _surface,
    onSurface: gameNightInk,
    onSurfaceVariant: gameNightMuted,
    outline: Colors.white.withValues(alpha: 0.18),
  );
  return base.copyWith(
    colorScheme: scheme,
    extensions: [palette],
    scaffoldBackgroundColor: gameNightBackground,
    dividerColor: palette.border,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      foregroundColor: gameNightInk,
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        color: gameNightInk,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: gameNightGold,
        foregroundColor: _onGold,
        // Giữ font của theme; TextStyle trần làm nút rơi về font hệ thống.
        textStyle: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: gameNightInk,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: gameNightGold),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: gameNightGold,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: _surface),
    expansionTileTheme: const ExpansionTileThemeData(
      iconColor: gameNightGold,
      collapsedIconColor: gameNightMuted,
      textColor: gameNightInk,
      collapsedTextColor: gameNightInk,
    ),
  );
}

/// Nền đêm: quầng tím ở đỉnh tan dần vào mực.
class GameNightBackdrop extends StatelessWidget {
  const GameNightBackdrop({super.key, required this.child, this.glow});

  final Widget child;

  /// Màu quầng ở đỉnh; mặc định tím đêm.
  final Color? glow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment.topCenter,
          radius: 1.2,
          colors: [glow ?? RunNowGameTokens.nightGlow, gameNightBackground],
          stops: const [0, 0.6],
        ),
      ),
      child: child,
    );
  }
}
