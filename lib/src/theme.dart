import 'package:flutter/material.dart';
import 'package:myrun/src/theme_tokens.dart';

export 'package:myrun/src/theme_tokens.dart';

enum RunNowElement { metal, wood, water, fire, earth }

enum RunNowAppearance { light, dark }

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

  List<Color> materialFor(RunNowElement element) => switch (this) {
    RunNowDarkTone.elemental => element.darkMaterial,
    RunNowDarkTone.slate => RunNowThemeTokens.darkSlate,
    RunNowDarkTone.dim => RunNowThemeTokens.darkDim,
    RunNowDarkTone.cloud => RunNowThemeTokens.darkCloud,
    RunNowDarkTone.warm => RunNowThemeTokens.darkWarm,
    RunNowDarkTone.cool => RunNowThemeTokens.darkCool,
  };
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
  });

  final RunNowElement element;
  final RunNowAppearance appearance;
  final Color accent;
  final Color accentDeep;
  final Color secondary;
  final Color tertiary;
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
  }) {
    final primary = element.ramp;
    final support = element.supporting.ramp;
    final material = appearance == RunNowAppearance.light
        ? element.lightMaterial
        : darkTone.materialFor(element);
    final background = material[0];
    final surface = material[1];
    final border = material[2];
    final foreground = material[3];
    return RunNowPalette(
      element: element,
      appearance: appearance,
      accent: primary[2],
      accentDeep: primary[3],
      secondary: support[2],
      tertiary: support[1],
      background: background,
      backgroundMid: background,
      backgroundDeep: background,
      glassStart: surface,
      glassEnd: surface,
      gridMinor: border.withValues(alpha: 0.34),
      gridMajor: border.withValues(alpha: 0.68),
      glowStrong: primary[2].withValues(alpha: 0.10),
      glowSoft: support[2].withValues(alpha: 0.07),
      border: border,
      foreground: foreground,
    );
  }

  @override
  RunNowPalette copyWith({
    RunNowElement? element,
    RunNowAppearance? appearance,
    Color? accent,
    Color? accentDeep,
    Color? secondary,
    Color? tertiary,
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
      accent: accent ?? this.accent,
      accentDeep: accentDeep ?? this.accentDeep,
      secondary: secondary ?? this.secondary,
      tertiary: tertiary ?? this.tertiary,
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
      accent: Color.lerp(accent, other.accent, t)!,
      accentDeep: Color.lerp(accentDeep, other.accentDeep, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      tertiary: Color.lerp(tertiary, other.tertiary, t)!,
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

extension RunNowThemeContext on BuildContext {
  RunNowPalette get runNowPalette =>
      Theme.of(this).extension<RunNowPalette>() ?? RunNowPalette.water;
}

ThemeData buildRunNowTheme(
  RunNowElement element, {
  RunNowAppearance appearance = RunNowAppearance.dark,
  RunNowDarkTone darkTone = RunNowDarkTone.elemental,
}) {
  final palette = RunNowPalette.forSelection(
    element,
    appearance: appearance,
    darkTone: darkTone,
  );
  final colorScheme = appearance == RunNowAppearance.light
      ? ColorScheme.light(
          primary: palette.accent,
          onPrimary: Colors.white,
          secondary: palette.secondary,
          onSecondary: Colors.white,
          tertiary: palette.tertiary,
          error: RunNowSemanticColors.danger,
          surface: palette.glassStart,
          onSurface: palette.foreground,
          outline: palette.border,
        )
      : ColorScheme.dark(
          primary: palette.accent,
          onPrimary: Colors.white,
          secondary: palette.secondary,
          onSecondary: Colors.white,
          tertiary: palette.tertiary,
          error: RunNowSemanticColors.danger,
          surface: palette.glassStart,
          onSurface: palette.foreground,
          outline: palette.border,
        );
  return _baseRunNowTheme(colorScheme).copyWith(
    extensions: [palette],
    brightness: appearance.brightness,
    scaffoldBackgroundColor: Colors.transparent,
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
      style: FilledButton.styleFrom(
        backgroundColor: palette.accent,
        foregroundColor: colorScheme.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.accentDeep,
        side: BorderSide(color: palette.accent),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.accent),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: palette.secondary,
      textColor: palette.foreground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    ),
    dividerColor: palette.border,
    progressIndicatorTheme: ProgressIndicatorThemeData(color: palette.accent),
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
