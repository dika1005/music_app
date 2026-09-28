import 'package:flutter/material.dart';

/// MelodyFlow Design System Color Tokens.
/// Dark-first modern music aesthetic with warm teal & amber accents.
class AppColors {
  AppColors._();

  // Primary: Deep Teal
  static const Color primary = Color(0xFF14B8A6);
  static const Color primaryContainer = Color(0xFF2DD4BF);
  static const Color primaryFixed = Color(0xFFCCFBF1);
  static const Color primaryFixedDim = Color(0xFF5EEAD4);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF042F2E);
  static const Color inversePrimary = Color(0xFF0D9488);

  // Secondary: Warm Amber
  static const Color secondary = Color(0xFFF59E0B);
  static const Color secondaryLight = Color(0xFFFBBF24);
  static const Color secondaryContainer = Color(0xFFD97706);
  static const Color secondaryFixed = Color(0xFFFEF3C7);
  static const Color onSecondary = Color(0xFF451A03);
  static const Color onSecondaryContainer = Color(0xFF78350F);

  // Tertiary: Coral Rose
  static const Color tertiary = Color(0xFFF43F5E);
  static const Color tertiaryLight = Color(0xFFFFB2B7);
  static const Color tertiaryContainer = Color(0xFFFF516A);
  static const Color tertiaryFixed = Color(0xFFFFDADB);
  static const Color onTertiary = Color(0xFF67001B);
  static const Color onTertiaryContainer = Color(0xFF5B0017);

  // Surface & Canvas: Deep Slate Tonal Hierarchy
  static const Color background = Color(0xFF0C0F12);
  static const Color surface = Color(0xFF10141A);
  static const Color surfaceDim = Color(0xFF0C0F12);
  static const Color surfaceBright = Color(0xFF353A42);
  static const Color surfaceContainerLowest = Color(0xFF0C0F12);
  static const Color surfaceContainerLow = Color(0xFF171C23);
  static const Color surfaceContainer = Color(0xFF1C2129);
  static const Color surfaceContainerHigh = Color(0xFF262C35);
  static const Color surfaceContainerHighest = Color(0xFF31373F);

  // Text & Outline
  static const Color onSurface = Color(0xFFE2E4E9);
  static const Color onSurfaceVariant = Color(0xFFA8ADB8);
  static const Color outline = Color(0xFF6B7280);
  static const Color outlineVariant = Color(0xFF3F4550);

  // Status & Accents
  static const Color seed = primary;
  static const Color success = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color error = Color(0xFFEF4444);
  static const Color errorContainer = Color(0xFF7F1D1D);
  static const Color onErrorContainer = Color(0xFFFECACA);

  // Glows & Translucent Glass
  static const Color glowTeal = Color(0x5514B8A6);
  static const Color glowAmber = Color(0x35F59E0B);
  static const Color glassSurface = Color(0xBF1C2129);
  static const Color glassBorder = Color(0x1AFFFFFF);
}

extension MelodyFlowColorScheme on ColorScheme {
  Color get secondaryLight => AppColors.secondaryLight;
  Color get tertiaryLight => AppColors.tertiaryLight;
}
