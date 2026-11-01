import 'package:flutter/material.dart';

/// Moodly brand palette — "Signature Lavender" design system.
///
/// All colors are defined here so the design system stays consistent across
/// screens and both themes. No widget should hardcode a brand color.
abstract final class AppColors {
  // ── Brand (light) ────────────────────────────────────────────────────
  static const Color primary = Color(0xFF7655C9); // signature lavender purple
  static const Color secondary = Color(0xFFA58AE8); // softer lavender
  static const Color lightLavender = Color(0xFFEEE8FF); // pale lavender tint
  static const Color mint = Color(0xFFB9E8D2); // mint accent
  static const Color white = Color(0xFFFFFFFF);

  // ── Light surfaces ───────────────────────────────────────────────────
  static const Color lightBackground = Color(0xFFF8F6FF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightCardBorder = Color(0xFFEAE5F3);
  static const Color lightSurfaceTint = Color(0xFFF3F0FF); // grouped sections

  // ── Primary text / secondary text (light) ────────────────────────────
  static const Color lightPrimaryText = Color(0xFF33264D);
  static const Color lightSecondaryText = Color(0xFF82758F);

  // ── Brand (dark) ─────────────────────────────────────────────────────
  static const Color darkPrimary = Color(0xFFB49AF5);
  static const Color darkSecondary = Color(0xFFD2C4FA);
  static const Color darkMint = Color(0xFF9DE2C3);

  // ── Dark surfaces ────────────────────────────────────────────────────
  static const Color darkBackground = Color(0xFF171321);
  static const Color darkSurface = Color(0xFF211C30);
  static const Color darkCardBorder = Color(0xFF322A4B);
  static const Color darkSurfaceTint = Color(0xFF2A243A); // grouped sections

  // ── Primary text / secondary text (dark) ─────────────────────────────
  static const Color darkPrimaryText = Color(0xFFF7F3FF);
  static const Color darkSecondaryText = Color(0xFFB9AEC9);

  // ── Feedback ─────────────────────────────────────────────────────────
  static const Color danger = Color(0xFFC94F6C);
  static const Color dangerLight = Color(0xFFFDECEF);

  // ── Mood colors (gentle, brand-aligned variations) ───────────────────
  /// Great — gentle mint green
  static const Color moodGreat = Color(0xFF4FBF8F);

  /// Good — gentle periwinkle blue
  static const Color moodGood = Color(0xFF6C8CF6);

  /// Okay — gentle golden amber
  static const Color moodOkay = Color(0xFFE9C15A);

  /// Low — gentle warm orange
  static const Color moodLow = Color(0xFFE09A6B);

  /// Terrible — gentle rose
  static const Color moodTerrible = Color(0xFFC97A8C);

  /// Soft brand gradient used for hero cards and the splash screen.
  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, Color(0xFF5B3FA6)],
  );
}
