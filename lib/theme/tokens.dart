import 'package:flutter/widgets.dart';

/// 声纹设计系统 — 与 voiceprint/colors_and_type.css 一一对应
///
/// 所有视觉 token 集中在此，避免页面间出现颜色/间距漂移。
class VpTokens {
  VpTokens._();

  // ===== Brand Primary =====
  static const Color primary = Color(0xFF0A84FF);
  static const Color primaryHover = Color(0xFF0066CC);
  static const Color primaryActive = Color(0xFF0052A3);
  static const Color primary50 = Color(0xFFF0F7FF);
  static const Color primary100 = Color(0xFFE3F0FF);
  static const Color primary200 = Color(0xFFC7DEFF);
  static const Color primary300 = Color(0xFF8AC0FF);
  static const Color primary400 = Color(0xFF4D9FFF);
  static const Color primary500 = Color(0xFF0A84FF);
  static const Color primary600 = Color(0xFF0066CC);
  static const Color primary700 = Color(0xFF0052A3);

  // ===== Neutral Surface =====
  static const Color bg = Color(0xFFF5F5F7);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceSecondary = Color(0xFFFAFAFA);
  static const Color surfaceTertiary = Color(0xFFF0F0F2);

  // ===== Border =====
  static const Color border = Color(0xFFD2D2D7);
  static const Color borderLight = Color(0xFFE8E8ED);
  static const Color borderStrong = Color(0xFFB0B0B5);

  // ===== Text =====
  static const Color textPrimary = Color(0xFF1D1D1F);
  static const Color textSecondary = Color(0xFF6E6E73);
  static const Color textTertiary = Color(0xFFAEAEB2);
  static const Color textInverse = Color(0xFFFFFFFF);

  // ===== State Colors =====
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFF9F0A);
  static const Color error = Color(0xFFFF3B30);
  static const Color info = Color(0xFF0A84FF);

  // ===== Radii =====
  static const double radiusSm = 4;
  static const double radiusMd = 8;
  static const double radiusLg = 12;
  static const double radiusFull = 9999;

  // ===== Spacing =====
  static const double spaceXs = 4;
  static const double spaceSm = 8;
  static const double spaceMd = 12;
  static const double spaceBase = 16;
  static const double spaceLg = 20;
  static const double spaceXl = 24;
  static const double space2xl = 32;

  // ===== Font sizes =====
  static const double fontXs = 11;
  static const double fontSm = 13;
  static const double fontBase = 15;
  static const double fontLg = 17;
  static const double fontXl = 20;
  static const double font2xl = 24;
  static const double font3xl = 30;
  static const double font4xl = 36;

  // ===== Font weights =====
  static const FontWeight wRegular = FontWeight.w400;
  static const FontWeight wMedium = FontWeight.w500;
  static const FontWeight wSemibold = FontWeight.w600;
  static const FontWeight wBold = FontWeight.w700;

  // ===== Shadows (static surface) =====
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color(0x0A000000), offset: Offset(0, 2), blurRadius: 8),
  ];
  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 4), blurRadius: 16),
  ];
  // Floating layers
  static const List<BoxShadow> shadowFloating = [
    BoxShadow(color: Color(0x1F000000), offset: Offset(0, 8), blurRadius: 32),
  ];

  // ===== Chart palette =====
  static const Color chartGrid = Color(0xFFE8E8ED);
  static const Color chartGridStrong = Color(0xFFD2D2D7);
  static const Color chartBg = Color(0xFFFAFAFA);
  static const Color chartPitchFill = Color(0x140A84FF);
  static const Color chartTargetLine = Color(0xFFAEAEB2);
  static const Color chartSpectrum1 = primary;
  static const Color chartSpectrum2 = Color(0xFF64D2FF);
  static const Color chartSpectrum3 = Color(0xFFBF5AF2);
  static const Color chartWaveform = textPrimary;
  static const Color chartAnnotation = warning;

  // iOS-style status bar / tab bar dimensions
  static const double iosStatusBarHeight = 44;
  static const double tabBarItemHeight = 50;
  static const double homeIndicatorHeight = 10;
}
