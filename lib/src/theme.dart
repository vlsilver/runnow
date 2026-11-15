import 'package:flutter/material.dart';
import 'package:myrun/src/theme_tokens.dart';

export 'package:myrun/src/theme_tokens.dart';

enum RunNowElement { metal, wood, water, fire, earth }

enum RunNowAppearance { light, dark }

/// Kiểu giao diện cả app. [elemental] tô theo ngũ hành đang chọn. [iron] là
/// kiểu Thép: giấy trắng ngà, mực đen, một màu đỏ, tiêu đề chữ hẹp đậm. Kiểu
/// là trục riêng, không phải một hành, nên thẻ chạy vẫn giữ hành của nó.
/// [pixel] là kiểu máy chơi game 8-bit: giấy kem, mực chàm, xanh lá, mọi khối
/// vuông có góc bậc thang và viền mực dày.
enum RunNowStyle { elemental, iron, pixel }

extension RunNowStyleLabel on RunNowStyle {
  String get label => switch (this) {
    RunNowStyle.elemental => 'Ngũ hành',
    RunNowStyle.iron => 'Thép',
    RunNowStyle.pixel => 'Pixel',
  };
}

enum RunNowDarkTone { elemental, slate, dim, cloud, warm, cool }

extension RunNowAppearanceLabel on RunNowAppearance {
  String get label => this == RunNowAppearance.light ? 'Sáng' : 'Tối';

  Brightness get brightness =>
      this == RunNowAppearance.light ? Brightness.light : Brightness.dark;
}

extension RunNowDarkToneLabel on RunNowDarkTone {
  String get label => switch (this) {
    RunNowDarkTone.elemental => 'Theo hành',
    RunNowDarkTone.slate => 'Slate',
    RunNowDarkTone.dim => 'Dim',
    RunNowDarkTone.cloud => 'Mây',
    RunNowDarkTone.warm => 'Ấm',
    RunNowDarkTone.cool => 'Lạnh',
  };

  List<Color> materialFor(RunNowElement element) => element.darkMaterial;
}

extension RunNowElementLabel on RunNowElement {
  String get label => switch (this) {
    RunNowElement.metal => 'Kim',
    RunNowElement.water => 'Thủy',
    RunNowElement.wood => 'Mộc',
    RunNowElement.fire => 'Hỏa',
    RunNowElement.earth => 'Thổ',
  };

  String get description => switch (this) {
    RunNowElement.metal => 'Thổ sinh Kim · Metal',
    RunNowElement.water => 'Kim sinh Thủy · Water',
    RunNowElement.wood => 'Thủy sinh Mộc · Wood',
    RunNowElement.fire => 'Mộc sinh Hỏa · Fire',
    RunNowElement.earth => 'Hỏa sinh Thổ · Earth',
  };

  IconData get icon => switch (this) {
    RunNowElement.metal => Icons.diamond_outlined,
    RunNowElement.wood => Icons.park_outlined,
    RunNowElement.water => Icons.water_drop_outlined,
    RunNowElement.fire => Icons.local_fire_department_outlined,
    RunNowElement.earth => Icons.landscape_outlined,
  };

  RunNowElement get supporting => switch (this) {
    RunNowElement.metal => RunNowElement.earth,
    RunNowElement.water => RunNowElement.metal,
    RunNowElement.wood => RunNowElement.water,
    RunNowElement.fire => RunNowElement.wood,
    RunNowElement.earth => RunNowElement.fire,
  };

  List<Color> get ramp => switch (this) {
    RunNowElement.metal => RunNowThemeTokens.metalRamp,
    RunNowElement.water => RunNowThemeTokens.waterRamp,
    RunNowElement.wood => RunNowThemeTokens.woodRamp,
    RunNowElement.fire => RunNowThemeTokens.fireRamp,
    RunNowElement.earth => RunNowThemeTokens.earthRamp,
  };

  List<Color> get lightMaterial => switch (this) {
    RunNowElement.metal => RunNowThemeTokens.metalLight,
    RunNowElement.water => RunNowThemeTokens.waterLight,
    RunNowElement.wood => RunNowThemeTokens.woodLight,
    RunNowElement.fire => RunNowThemeTokens.fireLight,
    RunNowElement.earth => RunNowThemeTokens.earthLight,
  };

  List<Color> get darkMaterial => switch (this) {
    RunNowElement.metal => RunNowThemeTokens.metalDark,
    RunNowElement.water => RunNowThemeTokens.waterDark,
    RunNowElement.wood => RunNowThemeTokens.woodDark,
    RunNowElement.fire => RunNowThemeTokens.fireDark,
    RunNowElement.earth => RunNowThemeTokens.earthDark,
  };

  /// Tint nhạt của hành — dùng cho chip/nút phụ trên nền sáng.
  Color get tint => switch (this) {
    RunNowElement.metal => RunNowThemeTokens.metalTint,
    RunNowElement.water => RunNowThemeTokens.waterTint,
    RunNowElement.wood => RunNowThemeTokens.woodTint,
    RunNowElement.fire => RunNowThemeTokens.fireTint,
    RunNowElement.earth => RunNowThemeTokens.earthTint,
  };
}

@immutable
class RunNowPalette extends ThemeExtension<RunNowPalette> {
  const RunNowPalette({
    required this.element,
    required this.appearance,
    required this.accent,
    required this.accentDeep,
    required this.secondary,
    required this.tertiary,
    required this.ink,
    required this.tint,
    required this.textMuted,
    required this.background,
    required this.backgroundMid,
    required this.backgroundDeep,
    required this.glassStart,
    required this.glassEnd,
    required this.gridMinor,
    required this.gridMajor,
    required this.glowStrong,
    required this.glowSoft,
    required this.border,
    required this.foreground,
    this.style = RunNowStyle.elemental,
  });

  final RunNowElement element;
  final RunNowAppearance appearance;
  final RunNowStyle style;

  /// Sắc hành (brand 30%) — app bar, hero, biểu đồ, vùng định hình.
  final Color accent;

  /// Brand-strong — chữ/viền/icon nhỏ trên nền sáng.
  final Color accentDeep;
  final Color secondary;
  final Color tertiary;

  /// Mực (10%) — nút chính, tiêu đề, icon nhấn. Tách khỏi sắc hành.
  final Color ink;

  /// Tint nhạt của hành — chip, nút phụ.
  final Color tint;

  /// Chữ phụ.
  final Color textMuted;
  final Color background;
  final Color backgroundMid;
  final Color backgroundDeep;
  final Color glassStart;
  final Color glassEnd;
  final Color gridMinor;
  final Color gridMajor;
  final Color glowStrong;
  final Color glowSoft;
  final Color border;
  final Color foreground;

  static RunNowPalette get metal => forSelection(RunNowElement.metal);
  static RunNowPalette get water => forSelection(RunNowElement.water);
  static RunNowPalette get fire => forSelection(RunNowElement.fire);
  static RunNowPalette get wood => forSelection(RunNowElement.wood);
  static RunNowPalette get earth => forSelection(RunNowElement.earth);

  static RunNowPalette forElement(RunNowElement element) =>
      forSelection(element);

  static RunNowPalette forSelection(
    RunNowElement element, {
    RunNowAppearance appearance = RunNowAppearance.dark,
    RunNowDarkTone darkTone = RunNowDarkTone.elemental,
    RunNowStyle style = RunNowStyle.elemental,
  }) {
    final iron = style == RunNowStyle.iron;
    final isLight = appearance == RunNowAppearance.light;
    final primary = switch (style) {
      RunNowStyle.elemental => element.ramp,
      RunNowStyle.iron => RunNowThemeTokens.ironRamp,
      RunNowStyle.pixel => RunNowThemeTokens.pixelRamp,
    };
    final material = switch (style) {
      RunNowStyle.elemental =>
        isLight ? element.lightMaterial : darkTone.materialFor(element),
      RunNowStyle.iron =>
        isLight ? RunNowThemeTokens.ironLight : RunNowThemeTokens.ironDark,
      RunNowStyle.pixel =>
        isLight ? RunNowThemeTokens.pixelLight : RunNowThemeTokens.pixelDark,
    };
    final background = material[0];
    final surface = material[1];
    final border = material[2];
    final foreground = material[3];
    return RunNowPalette(
      element: element,
      appearance: appearance,
      style: style,
      accent: primary[2],
      accentDeep: primary[3],
      // Keep one elemental brand per screen. These legacy fields are shades
      // of that same brand, not colors from the supporting element.
      secondary: primary[3],
      tertiary: primary[1],
      ink: style != RunNowStyle.elemental
          ? foreground
          : isLight
          ? RunNowThemeTokens.lightInk
          : RunNowThemeTokens.darkInk,
      // Tint phải ĐẶC (không alpha) để dùng làm nền card mà không bị trong suốt.
      // Dark: trộn sắc hành vào surface để ra một nền tối hơi nhuốm màu.
      tint: iron
          ? (isLight
                ? RunNowThemeTokens.ironTintLight
                : RunNowThemeTokens.ironTintDark)
          : style == RunNowStyle.pixel
          ? (isLight
                ? RunNowThemeTokens.pixelTintLight
                : RunNowThemeTokens.pixelTintDark)
          : isLight
          ? element.tint
          : Color.alphaBlend(primary[2].withValues(alpha: 0.16), surface),
      textMuted: isLight
          ? RunNowThemeTokens.lightMuted
          : RunNowThemeTokens.darkMuted,
      background: background,
      backgroundMid: background,
      backgroundDeep: background,
      glassStart: surface,
      glassEnd: surface,
      gridMinor: border.withValues(alpha: 0.34),
      gridMajor: border.withValues(alpha: 0.68),
      glowStrong: primary[2].withValues(alpha: 0.10),
      glowSoft: primary[2].withValues(alpha: 0.05),
      border: border,
      foreground: foreground,
    );
  }

  @override
  RunNowPalette copyWith({
    RunNowElement? element,
    RunNowAppearance? appearance,
    RunNowStyle? style,
    Color? accent,
    Color? accentDeep,
    Color? secondary,
    Color? tertiary,
    Color? ink,
    Color? tint,
    Color? textMuted,
    Color? background,
    Color? backgroundMid,
    Color? backgroundDeep,
    Color? glassStart,
    Color? glassEnd,
    Color? gridMinor,
    Color? gridMajor,
    Color? glowStrong,
    Color? glowSoft,
    Color? border,
    Color? foreground,
  }) {
    return RunNowPalette(
      element: element ?? this.element,
      appearance: appearance ?? this.appearance,
      style: style ?? this.style,
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
      ink: ink ?? this.ink,
      tint: tint ?? this.tint,
      textMuted: textMuted ?? this.textMuted,
      background: background ?? this.background,
      backgroundMid: backgroundMid ?? this.backgroundMid,
      backgroundDeep: backgroundDeep ?? this.backgroundDeep,
      glassStart: glassStart ?? this.glassStart,
      glassEnd: glassEnd ?? this.glassEnd,
      gridMinor: gridMinor ?? this.gridMinor,
      gridMajor: gridMajor ?? this.gridMajor,
      glowStrong: glowStrong ?? this.glowStrong,
      glowSoft: glowSoft ?? this.glowSoft,
      border: border ?? this.border,
      foreground: foreground ?? this.foreground,
    );
  }

  @override
  RunNowPalette lerp(covariant RunNowPalette? other, double t) {
    if (other == null) return this;
    return RunNowPalette(
      element: t < 0.5 ? element : other.element,
      appearance: t < 0.5 ? appearance : other.appearance,
      style: t < 0.5 ? style : other.style,
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      tint: Color.lerp(tint, other.tint, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      background: Color.lerp(background, other.background, t)!,
      backgroundMid: Color.lerp(backgroundMid, other.backgroundMid, t)!,
      backgroundDeep: Color.lerp(backgroundDeep, other.backgroundDeep, t)!,
      glassStart: Color.lerp(glassStart, other.glassStart, t)!,
      glassEnd: Color.lerp(glassEnd, other.glassEnd, t)!,
      gridMinor: Color.lerp(gridMinor, other.gridMinor, t)!,
      gridMajor: Color.lerp(gridMajor, other.gridMajor, t)!,
      glowStrong: Color.lerp(glowStrong, other.glowStrong, t)!,
      glowSoft: Color.lerp(glowSoft, other.glowSoft, t)!,
      border: Color.lerp(border, other.border, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
    );
  }
}

/// Hai màu dẫn xuất dùng ở trang Tạo mới và trang giáo án.
extension RunNowPaletteMarks on RunNowPalette {
  /// Màu "đêm" của bộ accent đang chọn, làm nền các ô tối. Kiểu Thép dùng
  /// khối mực đen.
  Color get accentNight {
    if (style == RunNowStyle.iron) {
      return appearance == RunNowAppearance.dark
          ? RunNowThemeTokens.ironNightDark
          : RunNowThemeTokens.ironInk;
    }
    if (style == RunNowStyle.pixel) {
      return appearance == RunNowAppearance.dark
          ? RunNowThemeTokens.pixelTintDark
          : RunNowThemeTokens.pixelInk;
    }
    return Color.lerp(accentDeep, RunNowDataColors.coachLoadFarLight, 0.66)!;
  }

  /// Chữ và icon đặt trên nền [accent]. Kiểu Thép đặt mực đen trên đỏ.
  Color get onAccent {
    if (style == RunNowStyle.iron) return RunNowThemeTokens.ironInk;
    if (style == RunNowStyle.pixel) return RunNowThemeTokens.pixelInk;
    return appearance == RunNowAppearance.dark
        ? RunNowDataColors.coachOnAccentDark
        : Colors.white;
  }

  /// Màu cam ấm duy nhất: chấm live, hôm nay, streak, ngày đua. Kiểu Thép
  /// chỉ có một màu nên dùng luôn [accent].
  Color get warmMark {
    if (style == RunNowStyle.iron) return accent;
    if (style == RunNowStyle.pixel) return RunNowThemeTokens.pixelCoin;
    return appearance == RunNowAppearance.dark
        ? RunNowDataColors.coachIntervalDark
        : RunNowDataColors.coachIntervalLight;
  }
}

/// Màu mang nghĩa (trạng thái, huy chương, dải màu tranh nền). Kiểu Thép chỉ
/// có đỏ, đen, trắng nên mọi màu ở đây quy về ba màu đó.
extension RunNowPaletteMeaning on RunNowPalette {
  /// Dải năm bậc nhạt tới đậm để vẽ tranh nền.
  List<Color> get ramp => switch (style) {
    RunNowStyle.elemental => element.ramp,
    RunNowStyle.iron => RunNowThemeTokens.ironSceneRamp,
    RunNowStyle.pixel => RunNowThemeTokens.pixelRamp,
  };

  Color get danger => isIron ? accent : RunNowSemanticColors.danger;
  Color get success => isIron ? foreground : RunNowSemanticColors.success;
  Color get warning => isIron ? accent : RunNowSemanticColors.warning;
  Color get info => isIron ? foreground : RunNowSemanticColors.info;
  Color get heart => isIron ? accent : RunNowDataColors.heart;

  /// Lớp màu mờ làm nền hay viền nhạt. Đỏ pha loãng ra hồng, nên kiểu Thép
  /// dùng mực pha loãng ra xám.
  Color wash(Color color, double alpha) =>
      (isIron ? foreground : color).withValues(alpha: alpha);

  /// Màu hạng 1, 2, 3.
  List<Color> get medals => isIron
      ? [accent, foreground, textMuted]
      : appearance == RunNowAppearance.light
      ? RunNowRankColors.light
      : RunNowRankColors.dark;

  /// Kiểu Thép đổi một bảng nhiều màu (màu từng người, từng vùng nhịp tim)
  /// thành các bậc xám, bậc cuối là đỏ.
  List<Color> series(List<Color> colors) {
    if (!isIron) return colors;
    final last = colors.length - 1;
    return [
      for (var i = 0; i < last; i++)
        Color.lerp(border, foreground, last <= 1 ? 1 : i / (last - 1))!,
      accent,
    ];
  }
}

/// Hình khối và chữ đổi theo kiểu giao diện. Màn nào muốn theo kiểu Thép hay
/// Pixel thì lấy góc và chữ tiêu đề qua đây thay vì ghi số cứng.
extension RunNowPaletteShape on RunNowPalette {
  bool get isIron => style == RunNowStyle.iron;

  bool get isPixel => style == RunNowStyle.pixel;

  /// Kiểu Thép và Pixel dựng mọi thứ bằng khối vuông: không bo góc, không
  /// hình tròn, không viên thuốc.
  bool get squared => style != RunNowStyle.elemental;

  /// Bán kính góc: kiểu vuông thì vuông hẳn, kể cả viên thuốc và hình tròn.
  double corner(double radius) => squared ? 0 : radius;

  BorderRadius radius(double radius) => BorderRadius.circular(corner(radius));

  Radius cornerRadius(double radius) => Radius.circular(corner(radius));

  /// Hình tròn của nút, chấm, avatar: kiểu vuông thành ô vuông.
  BoxShape get round => squared ? BoxShape.rectangle : BoxShape.circle;

  OutlinedBorder get roundBorder => switch (style) {
    RunNowStyle.elemental => const CircleBorder(),
    RunNowStyle.iron => const RoundedRectangleBorder(),
    RunNowStyle.pixel => const PixelBorder(),
  };

  OutlinedBorder get pillBorder => switch (style) {
    RunNowStyle.elemental => const StadiumBorder(),
    RunNowStyle.iron => const RoundedRectangleBorder(),
    RunNowStyle.pixel => const PixelBorder(),
  };

  /// Chữ tiêu đề: kiểu Thép dùng chữ hẹp đậm, to hơn một chút vì chữ hẹp.
  /// Kiểu Pixel dùng chữ lưới điểm ảnh; mặt chữ đó nhỏ và chỉ có một độ đậm
  /// nên phóng to lên, không ép đậm (ép đậm làm nhoè ô vuông).
  TextStyle heading(TextStyle style) => switch (this.style) {
    RunNowStyle.elemental => style,
    RunNowStyle.iron => style.copyWith(
      fontFamily: _ironFont,
      fontWeight: FontWeight.w800,
      fontSize: style.fontSize == null ? null : style.fontSize! * 1.18,
      letterSpacing: 0.3,
    ),
    RunNowStyle.pixel => style.copyWith(
      fontFamily: _pixelFont,
      fontWeight: FontWeight.w400,
      fontSize: style.fontSize == null
          ? null
          : style.fontSize! * _pixelFontScale,
      letterSpacing: 0.5,
    ),
  };

  /// Tiêu đề in hoa ở kiểu Thép và Pixel.
  String title(String text) => squared ? text.toUpperCase() : text;
}

/// Viền kiểu Pixel: hình chữ nhật có bốn góc khuyết một ô vuông cạnh [step],
/// tức góc "bo" một bậc của tranh pixel.
class PixelBorder extends OutlinedBorder {
  const PixelBorder({super.side, this.step = RunNowThemeTokens.pixelStep});

  final double step;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.strokeInset);

  @override
  PixelBorder copyWith({BorderSide? side, double? step}) =>
      PixelBorder(side: side ?? this.side, step: step ?? this.step);

  @override
  ShapeBorder scale(double t) =>
      PixelBorder(side: side.scale(t), step: step * t);

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) => a is PixelBorder
      ? PixelBorder(
          side: BorderSide.lerp(a.side, side, t),
          step: a.step + (step - a.step) * t,
        )
      : super.lerpFrom(a, t);

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) => b is PixelBorder
      ? PixelBorder(
          side: BorderSide.lerp(side, b.side, t),
          step: step + (b.step - step) * t,
        )
      : super.lerpTo(b, t);

  Path _stepped(Rect r) {
    // Ô quá nhỏ thì bậc co lại, không để hai góc đè lên nhau.
    final s = [step, r.width / 2, r.height / 2].reduce((a, b) => a < b ? a : b);
    if (s <= 0) return Path()..addRect(r);
    return Path()
      ..moveTo(r.left + s, r.top)
      ..lineTo(r.right - s, r.top)
      ..lineTo(r.right - s, r.top + s)
      ..lineTo(r.right, r.top + s)
      ..lineTo(r.right, r.bottom - s)
      ..lineTo(r.right - s, r.bottom - s)
      ..lineTo(r.right - s, r.bottom)
      ..lineTo(r.left + s, r.bottom)
      ..lineTo(r.left + s, r.bottom - s)
      ..lineTo(r.left, r.bottom - s)
      ..lineTo(r.left, r.top + s)
      ..lineTo(r.left + s, r.top + s)
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _stepped(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _stepped(rect.deflate(side.strokeInset));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        _stepped(rect),
        _stepped(rect.deflate(side.width)),
      ),
      Paint()..color = side.color,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PixelBorder && other.side == side && other.step == step;

  @override
  int get hashCode => Object.hash(side, step);
}

extension RunNowThemeContext on BuildContext {
  RunNowPalette get runNowPalette =>
      Theme.of(this).extension<RunNowPalette>() ?? RunNowPalette.water;

  /// Màu bàn chơi Ma Sói theo kiểu giao diện đang chọn.
  RunNowMoonlit get moonlit => switch (runNowPalette.style) {
    RunNowStyle.elemental => RunNowMoonlit.night,
    RunNowStyle.iron => RunNowMoonlit.iron,
    RunNowStyle.pixel => RunNowMoonlit.pixel,
  };
}

ThemeData buildRunNowTheme(
  RunNowElement element, {
  RunNowAppearance appearance = RunNowAppearance.dark,
  RunNowDarkTone darkTone = RunNowDarkTone.elemental,
  RunNowStyle style = RunNowStyle.elemental,
}) {
  final palette = RunNowPalette.forSelection(
    element,
    appearance: appearance,
    darkTone: darkTone,
    style: style,
  );
  final colorScheme = appearance == RunNowAppearance.light
      ? ColorScheme.light(
          primary: palette.accent,
          onPrimary: palette.glassStart,
          secondary: palette.secondary,
          onSecondary: palette.glassStart,
          tertiary: palette.tertiary,
          error: RunNowSemanticColors.danger,
          surface: palette.glassStart,
          onSurface: palette.foreground,
          outline: palette.border,
        )
      : ColorScheme.dark(
          primary: palette.accent,
          onPrimary: palette.glassStart,
          secondary: palette.secondary,
          onSecondary: palette.glassStart,
          tertiary: palette.tertiary,
          error: RunNowSemanticColors.danger,
          surface: palette.glassStart,
          onSurface: palette.foreground,
          outline: palette.border,
        );
  final theme = _baseRunNowTheme(colorScheme).copyWith(
    extensions: [palette],
    brightness: appearance.brightness,
    scaffoldBackgroundColor: palette.background,
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: palette.foreground,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: palette.foreground,
        fontFamily: 'Exo 2',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: palette.glassStart,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: palette.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      // Nút chính (CTA) = mực (10%) làm nền, chữ là sắc hành — tách khỏi mảng
      // brand 30% để dẫn mắt tới hành động quan trọng nhất.
      style: FilledButton.styleFrom(
        backgroundColor: palette.ink,
        foregroundColor: palette.accent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.border),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.accent),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: palette.accent,
      foregroundColor: palette.glassStart,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: palette.tint,
      selectedColor: palette.accent,
      disabledColor: palette.border,
      labelStyle: TextStyle(color: palette.accentDeep),
      secondaryLabelStyle: TextStyle(color: palette.glassStart),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: palette.ink,
      unselectedLabelColor: palette.textMuted,
      indicatorColor: palette.accent,
      dividerColor: palette.border,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.glassStart,
      indicatorColor: palette.tint,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? palette.accentDeep
              : palette.textMuted,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: states.contains(WidgetState.selected)
              ? palette.ink
              : palette.textMuted,
          fontWeight: FontWeight.w700,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.glassStart,
      labelStyle: TextStyle(color: palette.textMuted),
      hintStyle: TextStyle(color: palette.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: palette.accent, width: 1.5),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: palette.accentDeep,
      textColor: palette.foreground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    ),
    // Mọi SnackBar nổi + bo tròn cho nhất quán, không dính đáy che nội dung.
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerColor: palette.border,
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
  );
  return switch (style) {
    RunNowStyle.elemental => theme,
    RunNowStyle.iron => _ironTheme(theme, palette),
    RunNowStyle.pixel => _pixelTheme(theme, palette),
  };
}

const _ironFont = 'Barlow Condensed';

/// Phần kiểu Thép khác bản ngũ hành ngoài màu: tiêu đề và nhãn nút chữ hẹp
/// đậm, góc vuông, nút chính là khối đỏ chữ đen.
ThemeData _ironTheme(ThemeData base, RunNowPalette palette) {
  TextStyle? heading(TextStyle? s) => s?.copyWith(
    fontFamily: _ironFont,
    fontWeight: FontWeight.w800,
    letterSpacing: 0.3,
    height: 1.05,
  );
  const square = RoundedRectangleBorder();
  const label = TextStyle(
    fontFamily: _ironFont,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
  );
  final text = base.textTheme;
  return base.copyWith(
    textTheme: text.copyWith(
      displaySmall: heading(text.displaySmall),
      headlineMedium: heading(text.headlineMedium),
      headlineSmall: heading(text.headlineSmall),
      titleLarge: heading(text.titleLarge),
      titleMedium: heading(text.titleMedium),
      // Nút lấy nhãn từ đây. Đừng đặt textStyle riêng ở từng theme nút: kiểu
      // đó thiếu trường (inherit: true), lúc đổi kiểu TextStyle.lerp không
      // trộn được với labelLarge đủ trường của kiểu cũ và ném assert.
      labelLarge: text.labelLarge?.merge(label),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: _ironFont,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: palette.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: square,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: BorderSide(color: palette.ink, width: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: square,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.accentDeep),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      foregroundColor: palette.onAccent,
      shape: square,
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: TextStyle(color: palette.ink),
      secondaryLabelStyle: TextStyle(color: palette.onAccent),
      shape: square,
    ),
    tabBarTheme: base.tabBarTheme.copyWith(
      labelStyle: label.copyWith(fontSize: 17),
      unselectedLabelStyle: label.copyWith(fontSize: 17),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      indicatorShape: square,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? palette.ink
              : palette.textMuted,
        ),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: palette.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: palette.ink, width: 2),
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(iconColor: palette.ink),
    snackBarTheme: base.snackBarTheme.copyWith(shape: square),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: square),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: square),
    ),
    dialogTheme: base.dialogTheme.copyWith(shape: square),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(shape: square),
    popupMenuTheme: base.popupMenuTheme.copyWith(shape: square),
  );
}

const _pixelFont = 'VT323';

/// VT323 thấp hơn Exo 2 ở cùng cỡ chữ, phóng chừng này thì cao ngang nhau.
const _pixelFontScale = 1.3;

/// Phần kiểu Pixel khác bản ngũ hành ngoài màu: mọi khối có góc bậc thang và
/// viền mực dày, nút chính là khối xanh chữ mực, không bóng mờ.
ThemeData _pixelTheme(ThemeData base, RunNowPalette palette) {
  final ink = BorderSide(color: palette.foreground, width: 2);
  const block = PixelBorder();
  final framed = PixelBorder(side: ink);
  TextStyle? heading(TextStyle? s) => s?.copyWith(
    fontFamily: _pixelFont,
    fontWeight: FontWeight.w400,
    fontSize: s.fontSize == null ? null : s.fontSize! * _pixelFontScale,
    letterSpacing: 0.5,
    height: 1,
  );
  final text = base.textTheme;
  return base.copyWith(
    textTheme: text.copyWith(
      displaySmall: heading(text.displaySmall),
      headlineMedium: heading(text.headlineMedium),
      headlineSmall: heading(text.headlineSmall),
      titleLarge: heading(text.titleLarge),
      titleMedium: heading(text.titleMedium),
      // Xem ghi chú ở _ironTheme: nhãn nút đổi qua labelLarge, không đặt
      // textStyle riêng ở từng theme nút.
      labelLarge: text.labelLarge?.merge(
        const TextStyle(
          fontFamily: _pixelFont,
          fontSize: 22,
          fontWeight: FontWeight.w400,
          letterSpacing: 1,
        ),
      ),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(
        fontFamily: _pixelFont,
        fontSize: 34,
        fontWeight: FontWeight.w400,
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: base.cardTheme.copyWith(shape: framed),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: framed,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.ink,
        side: ink,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        shape: block,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.accentDeep),
    ),
    floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
      foregroundColor: palette.onAccent,
      shape: framed,
    ),
    chipTheme: base.chipTheme.copyWith(
      labelStyle: TextStyle(color: palette.ink),
      secondaryLabelStyle: TextStyle(color: palette.onAccent),
      shape: block,
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      indicatorShape: block,
      indicatorColor: palette.accent,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? palette.onAccent
              : palette.textMuted,
        ),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: palette.border, width: 2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: palette.accentDeep, width: 3),
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(iconColor: palette.ink),
    snackBarTheme: base.snackBarTheme.copyWith(shape: block),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: block),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(shape: block),
    ),
    dialogTheme: base.dialogTheme.copyWith(shape: framed),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      shape: const RoundedRectangleBorder(),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(shape: framed),
  );
}

ThemeData buildRunNowDarkTheme() => buildRunNowTheme(RunNowElement.water);

ThemeData _baseRunNowTheme(ColorScheme colorScheme) {
  return ThemeData(
    colorScheme: colorScheme,
    fontFamily: 'Exo 2',
    useMaterial3: true,
    textTheme: const TextTheme(
      displaySmall: TextStyle(
        fontSize: 42,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
      ),
      headlineMedium: TextStyle(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
      headlineSmall: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      titleLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
      titleMedium: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      bodyLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
      bodyMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      bodySmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      labelLarge: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: colorScheme.primary),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colorScheme.primary,
    ),
  );
}
