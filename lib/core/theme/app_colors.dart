import 'package:flutter/material.dart';

/// Moodly brand palette.
///
/// Central place for every brand color so the design system stays consistent
/// across screens and both themes.
abstract final class AppColors {
  // Brand
  static const Color primary = Color(0xFF7654D6); // lavender/purple
  static const Color deepPurple = Color(0xFF35245F);
  static const Color paleLavender = Color(0xFFF4F0FF);
  static const Color mint = Color(0xFFB8E8D0);
  static const Color white = Color(0xFFFFFFFF);
  static const Color bodyText = Color(0xFF29243A);
  static const Color secondaryText = Color(0xFF777286);

  // Light surfaces
  static const Color lightBackground = Color(0xFFFAF9FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFECE7FB);

  // Dark surfaces
  static const Color darkBackground = Color(0xFF151021);
  static const Color darkSurface = Color(0xFF201936);
  static const Color darkCardBorder = Color(0xFF322A4B);
  static const Color darkText = Color(0xFFECE7F8);
  static const Color darkSecondaryText = Color(0xFFA79FC0);

  // Feedback
  static const Color danger = Color(0xFFC94F6C);

  /// Soft brand gradient used for hero cards and the splash screen.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, deepPurple],
  );
}
