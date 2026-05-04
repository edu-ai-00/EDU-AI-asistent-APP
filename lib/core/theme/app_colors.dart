import 'package:flutter/material.dart';
import 'theme_config.dart';

/// Centralized color accessors for the entire app.
///
/// All getters delegate to [ThemeManager.colors] so switching themes
/// at runtime is as simple as calling [ThemeManager.apply].
abstract final class AppColors {
  // ── Core Brand ──────────────────────────────────────────────
  static Color get primary => ThemeManager.colors.primary;
  static Color get primaryDark => ThemeManager.colors.primaryDark;
  static Color get background => ThemeManager.colors.background;
  static Color get gradientPurple => ThemeManager.colors.gradientPurple;
  static Color get surface => ThemeManager.colors.surface;

  // ── PrimaryDark Opacity Variants ────────────────────────────
  static Color get primaryDark06 => primaryDark.withValues(alpha: 0.06);
  static Color get primaryDark08 => primaryDark.withValues(alpha: 0.08);
  static Color get primaryDark12 => primaryDark.withValues(alpha: 0.12);
  static Color get primaryDark16 => primaryDark.withValues(alpha: 0.16);
  static Color get primaryDark24 => primaryDark.withValues(alpha: 0.24);
  static Color get primaryDark32 => primaryDark.withValues(alpha: 0.32);
  static Color get primaryDark48 => primaryDark.withValues(alpha: 0.48);
  static Color get primaryDark64 => primaryDark.withValues(alpha: 0.64);
  static Color get primaryDark72 => primaryDark.withValues(alpha: 0.72);
  static Color get primaryDark80 => primaryDark.withValues(alpha: 0.80);
  static Color get primaryDark88 => primaryDark.withValues(alpha: 0.88);

  // ── Status ──────────────────────────────────────────────────
  static Color get success => ThemeManager.colors.success;
  static Color get orange => ThemeManager.colors.orange;
  static Color get warning => ThemeManager.colors.warning;
  static Color get error => ThemeManager.colors.error;
  static Color get errorLight => ThemeManager.colors.errorLight;

  // ── UI Surfaces ─────────────────────────────────────────────
  static Color get surfaceLight => ThemeManager.colors.surfaceLight;
  static Color get progressTrack => ThemeManager.colors.progressTrack;
  static Color get progressFill => ThemeManager.colors.progressFill;
  static Color get quizPurple => ThemeManager.colors.quizPurple;
  static Color get inputBg => ThemeManager.colors.inputBg;
  static Color get infoBg => ThemeManager.colors.infoBg;
  static Color get disabled => ThemeManager.colors.disabled;
  static Color get disabledButton => ThemeManager.colors.disabledButton;
  static Color get progressBorder => ThemeManager.colors.progressBorder;

  // ── Card / Badge Backgrounds ────────────────────────────────
  static Color get cardBlue => ThemeManager.colors.cardBlue;
  static Color get cardLavender => ThemeManager.colors.cardLavender;
  static Color get cardPeach => ThemeManager.colors.cardPeach;
  static Color get cardPeachDark => ThemeManager.colors.cardPeachDark;
  static Color get cardYellow => ThemeManager.colors.cardYellow;
  static Color get successBg => ThemeManager.colors.successBg;
  static Color get errorBg => ThemeManager.colors.errorBg;
  static Color get hintBg => ThemeManager.colors.hintBg;
  static Color get hintBorder => ThemeManager.colors.hintBorder;
  static Color get hintIconColor => ThemeManager.colors.hintIconColor;
  static Color get orangeBg => ThemeManager.colors.orangeBg;
  static Color get successBgLight => ThemeManager.colors.successBgLight;
  static Color get videoDark => ThemeManager.colors.videoDark;
  static Color get hintIcon => ThemeManager.colors.hintIcon;
  static Color get bannerOrange => ThemeManager.colors.bannerOrange;
  static Color get bannerOrangeDark => ThemeManager.colors.bannerOrangeDark;

  // ── Avatar Colors ───────────────────────────────────────────
  static Color get avatarFox => ThemeManager.colors.avatarFox;
  static Color get avatarPanda => ThemeManager.colors.avatarPanda;
  static Color get avatarLion => ThemeManager.colors.avatarLion;
  static Color get avatarFrog => ThemeManager.colors.avatarFrog;
  static Color get avatarOwl => ThemeManager.colors.avatarOwl;
  static Color get avatarCat => ThemeManager.colors.avatarCat;

  static List<Color> get avatarColors => [
    avatarFox,
    avatarPanda,
    avatarLion,
    avatarFrog,
    avatarOwl,
    avatarCat,
  ];

  // ── Subject Colors ──────────────────────────────────────────
  static Color get subjectGrammar => ThemeManager.colors.subjectGrammar;
  static Color get subjectLiterature => ThemeManager.colors.subjectLiterature;
  static Color get subjectMath => ThemeManager.colors.subjectMath;
  static Color get subjectChemistry => ThemeManager.colors.subjectChemistry;
  static Color get subjectBiology => ThemeManager.colors.subjectBiology;

  // ── Skill Colors ──────────────────────────────────────────
  static Color get skillRed => ThemeManager.colors.skillRed;
  static Color get skillBlue => ThemeManager.colors.skillBlue;

  // ── Gradients ───────────────────────────────────────────────
  static LinearGradient get authGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [gradientPurple, primaryDark],
  );

  static LinearGradient get bannerGradient => LinearGradient(
    colors: [bannerOrange, bannerOrangeDark],
  );

  static LinearGradient get headerGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, gradientPurple],
  );

  static Color get gradientGold => ThemeManager.colors.gradientGold;

  static LinearGradient get xpGradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [orange, gradientGold],
  );

  // ── Orange Opacity Variants ───────────────────────────────
  static Color get orange16 => orange.withValues(alpha: 0.16);

  // ── Banner Orange Opacity Variants ────────────────────────
  static Color get bannerOrange16 => bannerOrange.withValues(alpha: 0.16);

  // ── Error Opacity Variants ────────────────────────────────
  static Color get error08 => error.withValues(alpha: 0.08);
  static Color get error32 => error.withValues(alpha: 0.32);
}
