import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Material 3 themes for Moodly (light and dark).
///
/// The design system favors rounded shapes, generous spacing, subtle borders
/// and soft shadows to keep the app calm and premium. All colors come from
/// [AppColors] so the design system stays consistent across screens and both
/// themes.
abstract final class AppTheme {
  static const String _fontFamily = 'Roboto';

  /// Corner radius applied to every card across the app.
  static const double cardRadius = 20;

  static ThemeData light() => _base(
    brightness: Brightness.light,
    background: AppColors.lightBackground,
    surface: AppColors.lightSurface,
    surfaceTint: AppColors.lightSurfaceTint,
    onSurface: AppColors.lightPrimaryText,
    secondaryOnSurface: AppColors.lightSecondaryText,
    cardBorder: AppColors.lightCardBorder,
    brandPrimary: AppColors.primary,
    brandSecondary: AppColors.secondary,
    brandMint: AppColors.mint,
  );

  static ThemeData dark() => _base(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceTint: AppColors.darkSurfaceTint,
    onSurface: AppColors.darkPrimaryText,
    secondaryOnSurface: AppColors.darkSecondaryText,
    cardBorder: AppColors.darkCardBorder,
    brandPrimary: AppColors.darkPrimary,
    brandSecondary: AppColors.darkSecondary,
    brandMint: AppColors.darkMint,
  );

  static ThemeData _base({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color surfaceTint,
    required Color onSurface,
    required Color secondaryOnSurface,
    required Color cardBorder,
    required Color brandPrimary,
    required Color brandSecondary,
    required Color brandMint,
  }) {
    final bool isLight = brightness == Brightness.light;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: brandPrimary,
      onPrimary: Colors.white,
      primaryContainer: isLight ? AppColors.lightLavender : brandPrimary,
      onPrimaryContainer: isLight ? brandPrimary : Colors.white,
      secondary: brandMint,
      onSecondary: isLight ? const Color(0xFF3A2A6B) : brandPrimary,
      secondaryContainer: brandMint,
      onSecondaryContainer: brandPrimary,
      surface: surface,
      onSurface: onSurface,
      surfaceContainerHighest: surfaceTint,
      error: AppColors.danger,
      onError: Colors.white,
      outline: cardBorder,
      outlineVariant: cardBorder,
      surfaceContainer: surface,
    );

    final textTheme = Typography.material2021(platform: TargetPlatform.android)
        .englishLike
        .apply(
          bodyColor: onSurface,
          displayColor: onSurface,
          fontFamily: _fontFamily,
        )
        .copyWith(
          headlineLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: onSurface,
          ),
          headlineMedium: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: onSurface,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: onSurface,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
          bodyLarge: TextStyle(fontSize: 16, height: 1.6, color: onSurface),
          bodyMedium: TextStyle(fontSize: 15, height: 1.5, color: onSurface),
          bodySmall: TextStyle(
            fontSize: 13,
            height: 1.5,
            color: secondaryOnSurface,
          ),
          labelLarge: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: onSurface,
          ),
          labelMedium: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: secondaryOnSurface,
          ),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: _fontFamily,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(cardRadius),
          side: BorderSide(color: cardBorder, width: 1),
        ),
      ),
      dividerTheme: DividerThemeData(color: cardBorder, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isLight ? const Color(0xFFF7F4FF) : const Color(0xFF2A243A),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        hintStyle: TextStyle(color: secondaryOnSurface, fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: brandPrimary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: AppColors.danger, width: 1.2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 52),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: brandPrimary,
          minimumSize: const Size(64, 48),
          side: BorderSide(color: brandPrimary, width: 1.2),
          textStyle: textTheme.labelLarge,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brandPrimary,
          textStyle: textTheme.labelLarge,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: onSurface,
        contentTextStyle: TextStyle(color: surface, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: brandPrimary.withValues(alpha: 0.12),
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? brandPrimary
                : secondaryOnSurface,
            size: 24,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? brandPrimary
                : secondaryOnSurface,
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.comfortable,
          textStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: onSurface,
            ),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : onSurface,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? brandPrimary : surface,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: cardBorder)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: brandPrimary.withValues(alpha: 0.12),
        side: BorderSide(color: cardBorder),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: brandPrimary),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Color(0xFF7655C9),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        iconColor: secondaryOnSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titleTextStyle: textTheme.titleLarge,
        contentTextStyle: textTheme.bodyMedium,
      ),
    );
  }

  /// Soft elevation shadow used by cards.
  static BoxShadow cardShadow({required bool isLight}) {
    return BoxShadow(
      color: Colors.black.withValues(alpha: isLight ? 0.04 : 0.20),
      blurRadius: 12,
      offset: const Offset(0, 4),
    );
  }
}
