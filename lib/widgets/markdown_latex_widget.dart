import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:markdown/markdown.dart' as md;
import '../core/theme/app_theme.dart';

/// A widget that renders Markdown content with inline LaTeX support.
///
/// Uses a single MarkdownBody with custom inline syntax so that block-level
/// markdown (headers, tables, lists) and inline LaTeX ($...$, $$...$$)
/// coexist without breaking each other.
class MarkdownLatexWidget extends StatelessWidget {
  final String content;
  final TextStyle? textStyle;
  final Color? textColor;
  /// Whether text is user-selectable. Set to false when widget sits inside
  /// a tappable button so SelectableText doesn't eat the tap and show the
  /// text-cursor over LaTeX regions.
  final bool selectable;

  const MarkdownLatexWidget({
    super.key,
    required this.content,
    this.textStyle,
    this.textColor,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveTextColor = textColor ?? AppColors.primaryDark88;

    // Pre-process: promote $\begin{...}...\end{...}$ → $$...$$ so that
    // multi-line LaTeX environments render as display math even with single $
    final promoted = _promoteBlockEnvironments(content);

    // Pre-process: any $$...$$ block alone on its own line gets isolated as
    // its own paragraph (blank lines before/after) so consecutive display
    // formulas render stacked instead of inline-flowing in one paragraph.
    final isolated = _isolateBlockMath(promoted);

    // Add hard line breaks (trailing spaces) for single newlines,
    // but skip table rows (lines starting with |) and separator rows (---)
    final processed = _addHardLineBreaks(isolated);

    return MarkdownBody(
      data: processed,
      shrinkWrap: true,
      selectable: selectable,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [
        _DisplayLatexSyntax(), // $$...$$ must come before $...$
        _InlineLatexSyntax(),
      ],
      builders: {
        'latex': _LatexElementBuilder(
          textColor: textColor ?? AppColors.primaryDark,
        ),
      },
      styleSheet: MarkdownStyleSheet(
        p: AppTextStyles.body(color: effectiveTextColor, height: 1.5),
        strong: AppTextStyles.bodyBold(color: textColor ?? AppColors.primaryDark),
        em: AppTextStyles.bodyItalic(color: effectiveTextColor),
        h1: AppTextStyles.heading3(color: textColor ?? AppColors.primaryDark),
        h2: AppTextStyles.cardTitle(color: textColor ?? AppColors.primaryDark),
        h3: AppTextStyles.subtitle(color: textColor ?? AppColors.primaryDark),
        listBullet: AppTextStyles.body(color: effectiveTextColor),
        blockquote: AppTextStyles.bodyItalic(color: AppColors.primaryDark80),
        code: AppTextStyles.codeBlock(color: AppColors.primaryDark).copyWith(
          backgroundColor: AppColors.background,
        ),
        codeblockDecoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: AppDecorations.radiusXS,
        ),
        tableHead: AppTextStyles.bodyBold(color: textColor ?? AppColors.primaryDark),
        tableBody: AppTextStyles.body(color: effectiveTextColor),
        tableBorder: TableBorder.all(
          color: AppColors.primaryDark24,
          width: 1,
        ),
        tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }

  /// Promote $\begin{env}...\end{env}$ → $$\begin{env}...\end{env}$$
  /// so multi-line LaTeX environments (aligned, cases, matrix, etc.)
  /// are rendered as display math even when wrapped in single $.
  String _promoteBlockEnvironments(String text) {
    return text.replaceAllMapped(
      RegExp(r'(?<!\$)\$(?!\$)(\s*\\begin\{[\s\S]*?\\end\{[^}]+\}\s*)\$(?!\$)'),
      (m) => '\$\$${m[1]}\$\$',
    );
  }

  /// Ensure any line that consists solely of a $$…$$ block has blank lines
  /// before and after it, so the markdown parser treats each one as its own
  /// paragraph. Without this, consecutive `$$…$$` lines collapse into a
  /// single paragraph and render as inline-flowing widgets on one line.
  String _isolateBlockMath(String text) {
    final lines = text.split('\n');
    final blockMath = RegExp(r'^[ \t]*\$\$.*?\$\$[ \t]*$');
    final result = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isBlock = blockMath.hasMatch(line);
      if (isBlock) {
        final prevBlank = result.isEmpty || result.last.trim().isEmpty;
        if (!prevBlank) result.add('');
        result.add(line);
        final nextBlank = i + 1 >= lines.length || lines[i + 1].trim().isEmpty;
        if (!nextBlank) result.add('');
      } else {
        result.add(line);
      }
    }
    return result.join('\n');
  }

  /// Add trailing spaces for hard line breaks, but preserve table rows.
  String _addHardLineBreaks(String text) {
    final lines = text.split('\n');
    final result = <String>[];

    bool inTable = false;
    for (final line in lines) {
      final trimmed = line.trimLeft();
      // Detect table rows: start with | or are separator rows like |---|---|
      if (trimmed.startsWith('|') || (inTable && trimmed.startsWith('---'))) {
        inTable = true;
        result.add(line);
      } else {
        if (inTable && trimmed.isEmpty) {
          inTable = false; // table ended
        }
        // Add trailing spaces for hard line break (skip empty lines)
        if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
          result.add('$line  ');
        } else {
          result.add(line);
        }
      }
    }

    return result.join('\n');
  }
}

// ─── Custom Inline Syntax for LaTeX ──────────────────────────

/// Matches display math: $$...$$ (rendered centered, larger)
class _DisplayLatexSyntax extends md.InlineSyntax {
  // Match $$...$$ — non-greedy, can span content but not empty
  _DisplayLatexSyntax() : super(r'\$\$([^\$]+?)\$\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final latex = match[1]!.trim();
    final el = md.Element.text('latex', latex);
    el.attributes['displayMode'] = 'true';
    parser.addNode(el);
    return true;
  }
}

/// Matches inline math: $...$ (rendered inline, smaller)
class _InlineLatexSyntax extends md.InlineSyntax {
  // Match $...$ — non-greedy, no newlines, not empty, not preceded by $
  _InlineLatexSyntax() : super(r'\$([^\$\n]+?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final latex = match[1]!.trim();
    final el = md.Element.text('latex', latex);
    el.attributes['displayMode'] = 'false';
    parser.addNode(el);
    return true;
  }
}

// ─── Custom Element Builder for LaTeX ────────────────────────

class _LatexElementBuilder extends MarkdownElementBuilder {
  final Color textColor;

  _LatexElementBuilder({required this.textColor});

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    // Strip trailing whitespace per line — _addHardLineBreaks may have added
    // trailing "  " to lines inside $$...$$ which confuses flutter_math_fork.
    final rawLatex = element.textContent;
    final latex = rawLatex
        .split('\n')
        .map((l) => l.trimRight())
        .join('\n')
        .trim();
    final isDisplay = element.attributes['displayMode'] == 'true';

    final fontSize = isDisplay ? 18.0 : 15.0;
    final mathStyle = isDisplay ? MathStyle.display : MathStyle.text;

    Widget buildMath(String tex) => Math.tex(
      tex,
      textStyle: TextStyle(fontSize: fontSize, color: textColor),
      mathStyle: mathStyle,
      onErrorFallback: (error) => Text(
        '\$$tex\$',
        style: AppTextStyles.codeInline(color: AppColors.orange),
      ),
    );

    if (isDisplay) {
      // Don't split at = signs when the LaTeX content is structured math
      // (alignment environments, line breaks, alignment markers). Splitting
      // there shreds \begin{aligned}…\end{aligned} into invalid pieces.
      final hasEnv = latex.contains(r'\begin{') ||
          latex.contains(r'\end{') ||
          latex.contains(r'\\') || // LaTeX line break
          latex.contains('&'); // alignment marker

      if (!hasEnv) {
        final parts = _splitAtTopLevelEquals(latex);

        if (parts.length > 1) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 4,
              children: parts.map((p) => buildMath(p)).toList(),
            ),
          );
        }
      }

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(child: buildMath(latex)),
      );
    }

    // Inline math — render as a single inline element.
    // Wrap in RichText+WidgetSpan so flutter_markdown's _mergeInlineChildren
    // recognises it as text and merges it into the paragraph's TextSpan tree
    // instead of treating it as a standalone block widget (which causes a
    // line break before and after the formula).
    return RichText(
      text: WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: buildMath(latex),
      ),
    );
  }

  /// Split LaTeX at top-level `=` signs (not inside parentheses/braces).
  /// The `=` is kept at the end of the left part for readability.
  static List<String> _splitAtTopLevelEquals(String latex) {
    final parts = <String>[];
    int depth = 0;
    int lastSplit = 0;

    for (int i = 0; i < latex.length; i++) {
      final c = latex[i];
      if (c == '(' || c == '{' || c == '[') {
        depth++;
      } else if (c == ')' || c == '}' || c == ']') {
        depth = (depth - 1).clamp(0, 999);
      } else if (depth == 0 && c == '=') {
        // Include the = at the end of the left part
        final part = latex.substring(lastSplit, i + 1).trim();
        if (part.isNotEmpty) parts.add(part);
        lastSplit = i + 1;
      }
    }

    final remaining = latex.substring(lastSplit).trim();
    if (remaining.isNotEmpty) parts.add(remaining);

    return parts;
  }
}
