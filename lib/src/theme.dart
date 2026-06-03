import 'package:flutter/material.dart';

abstract final class AppColors {
  static const red = Color(0xffff3b4f);
  static const redDeep = Color(0xffb50024);
  static const black = Color(0xff050a12);
  static const blue = Color(0xff0075ff);
  static const blueGlow = Color(0xff00d9ff);
  static const amber = Color(0xffffd166);
  static const background = Color(0xff000000);
  static const glass = Color(0x4d071426);
  static const glassStrong = Color(0x9908172b);
  static const glassBorder = Color(0x4200d9ff);
}

ThemeData buildRunNowTheme() {
  const colorScheme = ColorScheme.dark(
    primary: AppColors.red,
    onPrimary: Colors.white,
    secondary: AppColors.blueGlow,
    onSecondary: Colors.white,
    tertiary: AppColors.amber,
    error: AppColors.red,
    onError: Colors.white,
    surface: AppColors.glass,
    onSurface: Colors.white,
  );
  return ThemeData(
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    fontFamily: 'Exo 2',
    scaffoldBackgroundColor: Colors.transparent,
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
