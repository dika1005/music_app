import 'package:flutter/material.dart';

class AppTypography {
  AppTypography._();

  /// Item 6.1: font utama MelodyFlow. Nama harus sama dengan `family` di pubspec.
  static const String fontFamily = 'PlusJakartaSans';

  // Typography scale following Material 3 guidelines
  static const TextStyle displayLarge = TextStyle(
    fontSize: 57,
    fontWeight: FontWeight.bold,
    letterSpacing: -0.25,
  );

  static const TextStyle headlineMedium = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.15,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.normal,
    letterSpacing: 0.25,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
  );
}
