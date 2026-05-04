import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'theme_config.dart';

/// Centralized decoration constants — shadows, radii, borders.
///
/// Border radii delegate to [ThemeManager.radii] so they follow
/// the active theme. Shadows derive color from [AppColors.primaryDark].
abstract final class AppDecorations {
  // ── Border Radii ────────────────────────────────────────────
  static BorderRadius get radiusXS =>
      BorderRadius.all(Radius.circular(ThemeManager.radii.xs));
  static BorderRadius get radiusS =>
      BorderRadius.all(Radius.circular(ThemeManager.radii.s));
  static BorderRadius get radiusM =>
      BorderRadius.all(Radius.circular(ThemeManager.radii.m));
  static BorderRadius get radiusL =>
      BorderRadius.all(Radius.circular(ThemeManager.radii.l));
  static BorderRadius get radiusXL =>
      BorderRadius.all(Radius.circular(ThemeManager.radii.xl));
  static BorderRadius get radiusPill =>
      BorderRadius.all(Radius.circular(ThemeManager.radii.pill));
  static BorderRadius get radiusSheet =>
      BorderRadius.vertical(top: Radius.circular(ThemeManager.radii.sheet));

  // ── Shadows ─────────────────────────────────────────────────

  /// Very subtle shadow (cards that should barely float)
  static List<BoxShadow> get shadowLight => [
        BoxShadow(
          color: AppColors.primaryDark.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// Medium shadow (nav bar, floating buttons)
  static List<BoxShadow> get shadowMedium => [
        BoxShadow(
          color: AppColors.primaryDark.withValues(alpha: 0.12),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// Strong shadow (prominent CTAs)
  static List<BoxShadow> get shadowStrong => [
        BoxShadow(
          color: AppColors.primaryDark.withValues(alpha: 0.16),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  // ── Card Decorations ────────────────────────────────────────

  /// Standard white card with strong shadow
  static BoxDecoration get cardDecoration => BoxDecoration(
        color: AppColors.surface,
        borderRadius: radiusXL,
        boxShadow: shadowStrong,
      );

  /// Subtle white card with light shadow
  static BoxDecoration get cardDecorationLight => BoxDecoration(
        color: AppColors.surface,
        borderRadius: radiusXL,
        boxShadow: shadowLight,
      );

  /// Circle button (48x48 icons in headers)
  static BoxDecoration get circleButton => BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        boxShadow: shadowStrong,
      );
}
