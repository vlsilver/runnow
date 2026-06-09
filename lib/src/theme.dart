import 'package:flutter/material.dart';

abstract final class AppColors {
  /// Accent chính của app: xanh điện (FitPulse-style). Để giữ tương thích với
  /// ~80 chỗ đang gọi [red]/[amber], các tên cũ được trỏ về bảng màu xanh đơn
  /// sắc thay vì đỏ/vàng — toàn app dịu lại mà không phải sửa từng widget.
  static const accent = Color(0xff2f8dff);
  static const accentDeep = Color(0xff123f7e);
  static const red = accent;
  static const redDeep = accentDeep;
  static const black = Color(0xff071019);
  static const blue = Color(0xff2f8dff);
  static const blueGlow = Color(0xff5bc8ff);
  static const amber = Color(0xff86b9ec);

  /// Chỉ dùng cho trạng thái lỗi/cảnh báo thật sự.
  static const alert = Color(0xffff5a6a);

  static const background = Color(0xff0b1623);
  static const lightBackground = Color(0xffeef3f8);
  static const lightSurface = Color(0xfff9fbff);
  static const lightSurfaceAlt = Color(0xffeef4fb);
  static const lightText = Color(0xff07111f);
  static const lightMuted = Color(0xff607086);
  static const glass = Color(0x4d0e2138);
  static const glassStrong = Color(0x99102a45);
  static const glassBorder = Color(0x3a5bc8ff);
}

ThemeData buildRunNowDarkTheme() {
  const colorScheme = ColorScheme.dark(
    primary: AppColors.red,
    onPrimary: Colors.white,
    secondary: AppColors.blueGlow,
    onSecondary: Colors.white,
    tertiary: AppColors.amber,
    error: AppColors.alert,
    onError: Colors.white,
    surface: AppColors.glass,
    onSurface: Colors.white,
  );
  return _baseRunNowTheme(colorScheme).copyWith(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Colors.white,
        fontFamily: 'Exo 2',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.glass,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.glassBorder),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: AppColors.glassBorder),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.red),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.blueGlow,
      textColor: Colors.white,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    ),
    dividerColor: Colors.white12,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.red,
    ),
  );
}

ThemeData buildRunNowLightTheme() {
  const colorScheme = ColorScheme.light(
    primary: AppColors.red,
    onPrimary: Colors.white,
    secondary: Color(0xff005ed6),
    onSecondary: Colors.white,
    tertiary: AppColors.amber,
    error: AppColors.alert,
    onError: Colors.white,
    surface: AppColors.lightSurface,
    onSurface: AppColors.lightText,
    outline: Color(0x330b1d33),
  );
  return _baseRunNowTheme(colorScheme).copyWith(
    brightness: Brightness.light,
    scaffoldBackgroundColor: Colors.transparent,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: AppColors.lightText,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      elevation: 0,
      titleTextStyle: TextStyle(
        color: AppColors.lightText,
        fontFamily: 'Exo 2',
        fontSize: 28,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.lightSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: const Color(0x2608172b),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.lightText,
        side: const BorderSide(color: Color(0x330b1d33)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.red),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: Color(0xff005ed6),
      textColor: AppColors.lightText,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
    ),
    dividerColor: const Color(0x1f071426),
    iconTheme: const IconThemeData(color: AppColors.lightText),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: AppColors.red,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? Colors.white : AppColors.lightText,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          color: selected ? AppColors.lightText : AppColors.lightMuted,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
        );
      }),
    ),
  );
}

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
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.red),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.red,
    ),
  );
}
