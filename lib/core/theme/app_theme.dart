import 'package:flutter/material.dart';
import 'package:music_app/core/constants/app_colors.dart';
import 'package:music_app/core/constants/app_typography.dart';
export 'package:music_app/core/constants/app_colors.dart';

/// Google Stitch MelodyFlow Material 3 Theme.
/// Dark-first acoustic club aesthetic with glassmorphism and electric violet accents.
class AppTheme {
  AppTheme._();

  /// Item 6.2: app ini dark-only. [light] dipertahankan sebagai alias supaya
  /// test/widget yang memakai `AppTheme.light()` tetap tervalidasi, tapi
  /// aplikasi hanya memasang satu tema (lihat main.dart) tanpa themeMode
  /// ganda — tidak ada lagi "tema terang yang tidak pernah terpakai".
  static ThemeData light() => dark(); // MelodyFlow is an immersive dark-first experience

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: AppColors.primaryContainer,
      onPrimaryContainer: AppColors.onPrimaryContainer,
      secondary: AppColors.secondary,
      onSecondary: AppColors.onSecondary,
      secondaryContainer: AppColors.secondaryContainer,
      onSecondaryContainer: AppColors.onSecondaryContainer,
      tertiary: AppColors.tertiary,
      onTertiary: AppColors.onTertiary,
      tertiaryContainer: AppColors.tertiaryContainer,
      onTertiaryContainer: AppColors.onTertiaryContainer,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: AppColors.errorContainer,
      onErrorContainer: AppColors.onErrorContainer,
      surface: AppColors.surface,
      onSurface: AppColors.onSurface,
      surfaceContainerLowest: AppColors.surfaceContainerLowest,
      surfaceContainerLow: AppColors.surfaceContainerLow,
      surfaceContainer: AppColors.surfaceContainer,
      surfaceContainerHigh: AppColors.surfaceContainerHigh,
      surfaceContainerHighest: AppColors.surfaceContainerHighest,
      onSurfaceVariant: AppColors.onSurfaceVariant,
      outline: AppColors.outline,
      outlineVariant: AppColors.outlineVariant,
      inverseSurface: AppColors.onSurface,
      onInverseSurface: AppColors.background,
      inversePrimary: AppColors.inversePrimary,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      // Item 6.1: Plus Jakarta Sans sebagai font utama aplikasi.
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppColors.onSurface,
          letterSpacing: -0.02,
        ),
        iconTheme: IconThemeData(color: AppColors.onSurface),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceContainerLowest,
        elevation: 0,
        indicatorColor: AppColors.primaryContainer.withAlpha(60),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.primaryFixedDim, size: 24);
          }
          return const IconThemeData(color: AppColors.outline, size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryFixedDim,
              letterSpacing: 0.02,
            );
          }
          return const TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.outline,
            letterSpacing: 0.02,
          );
        }),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surfaceContainerLow,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: EdgeInsets.zero,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceContainerHighest,
        thumbColor: Colors.white,
        overlayColor: AppColors.primary.withAlpha(40),
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceContainerHigh,
        selectedColor: AppColors.primary,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.outlineVariant.withAlpha(35),
        thickness: 1,
        space: 1,
      ),
    );

    // TextTheme bawaan M3 menempelkan fontFamily 'Roboto' secara eksplisit, jadi
    // `fontFamily:` di ThemeData saja tidak cukup — perlu di-apply ulang supaya
    // Plus Jakarta Sans benar-benar dipakai di semua gaya teks (item 6.1).
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: AppTypography.fontFamily),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: AppTypography.fontFamily),
    );
  }
}
