import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// A section header with title and optional action button
class SectionHeader extends StatelessWidget {
  /// The title text (can be multiline)
  final String title;

  /// Action button text (e.g., "Zobrazit vše")
  final String? actionText;

  /// Callback when action button is tapped
  final VoidCallback? onActionTap;

  /// Horizontal padding
  final double horizontalPadding;

  const SectionHeader({
    super.key,
    required this.title,
    this.actionText,
    this.onActionTap,
    this.horizontalPadding = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.heading2(),
            ),
          ),
          if (actionText != null) ...[
            const SizedBox(width: 16),
            GestureDetector(
              onTap: onActionTap,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppDecorations.radiusL,
                  border: Border.all(
                    color: AppColors.primaryDark24,
                    width: 1,
                  ),
                ),
                child: Text(
                  actionText!,
                  style: AppTextStyles.actionSmall(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
