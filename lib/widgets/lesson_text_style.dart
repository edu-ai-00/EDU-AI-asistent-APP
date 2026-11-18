import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../core/theme/app_theme.dart';

/// The one look lesson text has, whichever widget ends up rendering it
/// (BR-92JSBK).
///
/// Course content arrives without a reliable format flag, so every paragraph is
/// sniffed and handed to [MarkdownLatexWidget], the HTML widget or a plain
/// [Text]. Those paths used to bring their own styles — full colour with
/// markdown, 72 % grey without it, 88 % for HTML, 13px in feedback — so a
/// single `$` in a sentence changed how the whole paragraph looked. The admin
/// preview runs every field through one markdown renderer (rule 12.6), so the
/// markdown body is the reference: [MarkdownLatexWidget] takes its paragraph
/// style from here and the plain and HTML branches next to it do the same.
TextStyle lessonBodyStyle(Color color) =>
    AppTextStyles.body(color: color, height: 1.5);

/// [lessonBodyStyle] for flutter_html, in the main content colour — the one
/// the markdown branches beside every HTML call site pass.
Map<String, Style> lessonHtmlStyle() {
  final body = lessonBodyStyle(AppColors.primaryDark);
  return {
    'body': Style(
      margin: Margins.zero,
      padding: HtmlPaddings.zero,
      fontSize: FontSize(body.fontSize!),
      fontWeight: body.fontWeight,
      color: body.color,
      lineHeight: LineHeight(body.height),
      fontFamily: 'Poppins',
    ),
    'p': Style(margin: Margins.only(bottom: 12)),
    'h3': Style(
      fontSize: FontSize(18),
      fontWeight: FontWeight.w700,
      color: AppColors.primaryDark,
      margin: Margins.only(bottom: 12, top: 8),
    ),
    'strong': Style(fontWeight: FontWeight.w700, color: AppColors.primaryDark),
    'em': Style(fontStyle: FontStyle.italic),
    'ul': Style(margin: Margins.only(bottom: 12)),
    'li': Style(margin: Margins.only(bottom: 6)),
  };
}
