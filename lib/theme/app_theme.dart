import 'package:flutter/material.dart';
import 'tokens.dart';

/// 声纹 App 主题 — Material 3 容器，但视觉表现接近 iOS 设计稿
class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);

    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: VpTokens.primary,
        onPrimary: VpTokens.textInverse,
        secondary: VpTokens.primary,
        onSecondary: VpTokens.textInverse,
        surface: VpTokens.surface,
        onSurface: VpTokens.textPrimary,
        error: VpTokens.error,
      ),
      scaffoldBackgroundColor: VpTokens.bg,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      dividerColor: VpTokens.borderLight,
      iconTheme: const IconThemeData(color: VpTokens.textPrimary, size: 22),
      textTheme: base.textTheme.copyWith(
        displayLarge: TextStyle(
          color: VpTokens.textPrimary,
          fontSize: VpTokens.font4xl,
          fontWeight: VpTokens.wBold,
          letterSpacing: -0.02,
        ),
        headlineMedium: TextStyle(
          color: VpTokens.textPrimary,
          fontSize: VpTokens.font2xl,
          fontWeight: VpTokens.wSemibold,
          letterSpacing: -0.02,
        ),
        titleLarge: TextStyle(
          color: VpTokens.textPrimary,
          fontSize: VpTokens.fontLg,
          fontWeight: VpTokens.wSemibold,
          letterSpacing: -0.02,
        ),
        titleMedium: TextStyle(
          color: VpTokens.textPrimary,
          fontSize: VpTokens.fontBase,
          fontWeight: VpTokens.wSemibold,
        ),
        bodyLarge: TextStyle(
          color: VpTokens.textPrimary,
          fontSize: VpTokens.fontBase,
          fontWeight: VpTokens.wRegular,
        ),
        bodyMedium: TextStyle(
          color: VpTokens.textSecondary,
          fontSize: VpTokens.fontSm,
          fontWeight: VpTokens.wRegular,
        ),
        bodySmall: TextStyle(
          color: VpTokens.textTertiary,
          fontSize: VpTokens.fontXs,
          fontWeight: VpTokens.wRegular,
        ),
        labelLarge: TextStyle(
          color: VpTokens.textPrimary,
          fontSize: VpTokens.fontBase,
          fontWeight: VpTokens.wSemibold,
        ),
        labelMedium: TextStyle(
          color: VpTokens.textSecondary,
          fontSize: VpTokens.fontSm,
          fontWeight: VpTokens.wMedium,
        ),
      ),
    );
  }
}
