import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Canonical page header used across secondary pages (Knihovna, Privacy,
/// Terms, Achievements, Profile, …). Renders a 48 px circular back button,
/// the page title next to it, and optional trailing action buttons.
///
/// Detail pages with their own bespoke headers (course detail, chat detail)
/// intentionally do not use this widget.
class PageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final TextStyle? titleStyle;
  final Color iconColor;
  final Color? backgroundButtonColor;
  final EdgeInsetsGeometry padding;

  const PageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
    this.titleStyle,
    this.iconColor = const Color(0xFF000000),
    this.backgroundButtonColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final iColor = iconColor == const Color(0xFF000000)
        ? AppColors.primaryDark
        : iconColor;
    final bgColor = backgroundButtonColor ?? AppColors.surface;

    return Padding(
      padding: padding,
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack ?? () {
              if (Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            },
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
                boxShadow: AppDecorations.shadowStrong,
              ),
              child: Icon(Icons.arrow_back, color: iColor, size: 24),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: titleStyle ?? AppTextStyles.heading2Bold(),
            ),
          ),
          for (final a in actions) ...[
            const SizedBox(width: 8),
            a,
          ],
        ],
      ),
    );
  }
}
