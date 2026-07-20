import 'package:flutter/material.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';

/// A promotional announcement card with orange border and mascot illustration.
///
/// Used for highlighting new courses, features, or announcements at the top
/// of pages like Přehled (Overview).
class PromoCard extends StatelessWidget {
  /// Badge text displayed in the top-left corner (e.g., "NOVÉ")
  /// Badge text. Null falls back to `AppStrings.promoDefaultBadge`
  /// (resolved at build time so it follows the active locale).
  final String? badge;

  /// Badge background color
  final Color? badgeColor;

  /// Main title text
  final String title;

  /// Description text below the title
  final String description;

  /// Border color of the card
  final Color? borderColor;

  /// Path to the mascot/illustration SVG asset
  final String? illustrationPath;

  /// Custom widget for illustration (for maximum flexibility)
  final Widget? illustrationWidget;

  /// Callback when the card is tapped
  final VoidCallback? onTap;

  /// Callback when the arrow button is tapped
  final VoidCallback? onArrowTap;

  const PromoCard({
    super.key,
    this.badge,
    this.badgeColor,
    required this.title,
    required this.description,
    this.borderColor,
    this.illustrationPath,
    this.illustrationWidget,
    this.onTap,
    this.onArrowTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? AppColors.orange;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDecorations.radiusXL,
          border: Border.all(
            color: effectiveBorderColor,
            width: 4,
          ),
        ),
        child: ClipRRect(
          borderRadius: AppDecorations.radiusL, // 24 - 4 (border width)
          child: Stack(
            clipBehavior: Clip.none, // Allow arrow button to overflow
            children: [
              // Main content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left side: Badge, Title, Description
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Badge
                          _buildBadge(),
                          const SizedBox(height: 8),
                          // Title - Nunito 900, 20px, line-height 24px
                          Text(
                            title,
                            style: AppTextStyles.cardTitle(),
                          ),
                          const SizedBox(height: 4),
                          // Description - Poppins 500, 15px, line-height 20px
                          Text(
                            description,
                            style: AppTextStyles.body(
                              color: AppColors.primaryDark64,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Space for illustration (positioned absolutely)
                    const SizedBox(width: 100),
                  ],
                ),
              ),
              // Illustration positioned at bottom right
              if (illustrationWidget != null || illustrationPath != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: SizedBox(
                    width: 132,
                    height: 112,
                    child: illustrationWidget ??
                        Image.asset(
                          illustrationPath!,
                          fit: BoxFit.contain,
                        ),
                  ),
                ),
              // Arrow button in bottom-right
              Positioned(
                right: 16,
                bottom: 12,
                child: _buildArrowButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor ?? AppColors.orange,
        borderRadius: AppDecorations.radiusL,
      ),
      child: Text(
        badge ?? AppStrings.promoDefaultBadge,
        style: AppTextStyles.badge(color: Colors.white),
      ),
    );
  }

  Widget _buildArrowButton() {
    return GestureDetector(
      onTap: onArrowTap ?? onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 28,
        height: 28,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDecorations.radiusXS,
        ),
        child: Center(
          child: Icon(
            Icons.arrow_forward,
            size: 16,
            color: AppColors.primaryDark,
          ),
        ),
      ),
    );
  }
}
