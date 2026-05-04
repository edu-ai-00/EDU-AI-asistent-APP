import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';
import 'theme_config.dart';

/// Centralized text style factories for the entire app.
///
/// Font families are read from [ThemeManager.typography] so they follow
/// the active theme. Each method accepts an optional [color] parameter
/// that defaults to [AppColors.primaryDark].
abstract final class AppTextStyles {
  // ── Helpers ───────────────────────────────────────────────────
  static String get _heading => ThemeManager.typography.headingFont;
  static String get _body => ThemeManager.typography.bodyFont;
  static String get _code => ThemeManager.typography.codeFont;

  // ── Headings (heading font) ───────────────────────────────────

  /// 32px w900 — Page titles (e.g. "Denni procvicovani", "Chaty")
  static TextStyle heading1({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 32,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
        height: 34 / 32,
      );

  /// 28px w800 — Section headers (e.g. "Rychle kvizy", "Kurzy")
  static TextStyle heading2({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        color: color ?? AppColors.primaryDark,
        height: 1.2,
      );

  /// 28px w900 — Bold variant for Kurzy, AddPage, Novinky titles
  static TextStyle heading2Bold({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 28,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
      );

  /// 24px w900 — Dialog titles, H1 in markdown
  static TextStyle heading3({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 24,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
      );

  /// 24px w700 — Alternate subheading
  static TextStyle heading3Alt({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.primaryDark,
      );

  /// 22px w900 — Medium headings (empty states)
  static TextStyle heading4({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
      );

  /// 20px w900 — Card titles, H2 in markdown, user name in drawer
  static TextStyle cardTitle({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
        height: 24 / 20,
      );

  /// 20px w700 — Alternate card title
  static TextStyle cardTitleAlt({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.primaryDark,
      );

  /// 18px w900 — Small card titles (kurzy card), H3 markdown heading
  static TextStyle cardTitleSmall({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 18,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
        height: 1.2,
      );

  /// 18px w700 — H3 level subtitles
  static TextStyle subtitle({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.primaryDark,
      );

  /// 17px w700 — Drawer menu items
  static TextStyle menuItem({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.primaryDark,
      );

  /// 16px w900 — Stat values, button text, nav text bold, chat names
  static TextStyle statValue({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
        height: 20 / 16,
      );

  /// 16px w800 — Explore button text
  static TextStyle statValueAlt({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 16,
        fontWeight: FontWeight.w800,
        color: color ?? AppColors.primaryDark,
      );

  /// 16px w700 — Stat suffix labels
  static TextStyle statSuffix({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.primaryDark,
        height: 1,
      );

  /// 15px w900 — Action links, progress bar text, carousel action
  static TextStyle actionText({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
        height: 20 / 15,
      );

  /// 15px w900 — Filter chips
  static TextStyle chipLabelNunito({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
        height: 20 / 15,
      );

  /// 14px w600 — Small action text (section header action button)
  static TextStyle actionSmall({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primaryDark,
      );

  /// 12px w900 — Badge labels (e.g. "NOVE")
  static TextStyle badge({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
        height: 1,
      );

  /// 11px w900 — Badge labels (unread count)
  static TextStyle badgeSmall({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
      );

  /// 10.67px w900 — Tiny badge text (course card badge)
  static TextStyle badgeTiny({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 10.67,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
        height: 11 / 10.67,
      );

  /// 11px w600/w400 — Bottom nav labels
  static TextStyle navLabel({Color? color, FontWeight? weight}) =>
      GoogleFonts.getFont(
        _heading,
        fontSize: 11,
        fontWeight: weight ?? FontWeight.w400,
        color: color ?? AppColors.primaryDark,
      );

  // ── Body (body font) ──────────────────────────────────────────

  /// 16px w600 — Primary buttons
  static TextStyle buttonLarge({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primaryDark,
      );

  /// 16px w500 — Form inputs
  static TextStyle bodyLarge({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.primaryDark,
      );

  /// 15px w700 — Bold body text
  static TextStyle bodyBold({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: color ?? AppColors.primaryDark,
      );

  /// 15px w600 — Semi-bold body text (multi-select chips, etc.)
  static TextStyle bodySemiBold({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primaryDark,
      );

  /// 15px w500 — Default body / description text
  static TextStyle body({Color? color, double? height}) => GoogleFonts.getFont(
        _body,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.primaryDark,
        height: height ?? 20 / 15,
      );

  /// 15px w500 italic — Emphasis / blockquote
  static TextStyle bodyItalic({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 15,
        fontWeight: FontWeight.w500,
        fontStyle: FontStyle.italic,
        color: color ?? AppColors.primaryDark,
      );

  /// 14px w600 — Medium labels
  static TextStyle labelMedium({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primaryDark,
      );

  /// 14px w500 — Secondary text / subtitle in chat & banners
  static TextStyle bodySmall({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.primaryDark,
      );

  /// 13px w500 — Meta info (lesson count, duration)
  static TextStyle meta({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.primaryDark,
      );

  /// 13px w600 — Skill labels, semi-bold meta
  static TextStyle metaBold({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primaryDark,
      );

  /// 13px w900 heading font — Progress bar counts
  static TextStyle progressCount({Color? color}) => GoogleFonts.getFont(
        _heading,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        color: color ?? AppColors.primaryDark,
      );

  /// 12px w500 — Timestamps, captions
  static TextStyle caption({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: color ?? AppColors.primaryDark,
      );

  /// 12px w600 — Section headers in profile drawer
  static TextStyle captionBold({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primaryDark,
      );

  /// 11px w600 — Chip labels, small section headers
  static TextStyle chipLabel({Color? color}) => GoogleFonts.getFont(
        _body,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color ?? AppColors.primaryDark,
        letterSpacing: 0.5,
      );

  // ── Code (code font) ──────────────────────────────────────────

  /// 13px — Code blocks
  static TextStyle codeBlock({Color? color}) => GoogleFonts.getFont(
        _code,
        fontSize: 13,
        color: color ?? AppColors.primaryDark,
      );

  /// 14px — Inline code / error fallback
  static TextStyle codeInline({Color? color}) => GoogleFonts.getFont(
        _code,
        fontSize: 14,
        color: color ?? AppColors.primaryDark,
      );
}
