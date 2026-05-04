import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/theme/app_theme.dart';

/// Data class for metadata items shown in the card (icons with optional text)
class CardMetaItem {
  final String? iconPath;
  final IconData? icon;
  final Color? iconColor;
  final String? label;

  const CardMetaItem({
    this.iconPath,
    this.icon,
    this.iconColor,
    this.label,
  }) : assert(iconPath != null || icon != null);
}

/// A reusable card widget for displaying courses, quizzes, or similar content.
///
/// Supports two main variants:
/// - Simple: With bookmark icon at bottom right (for courses/learning)
/// - Badge: With a text badge (e.g., "GEO") at top right (for quizzes)
class CourseCard extends StatelessWidget {
  /// The icon to display in the circular container
  final IconData? icon;

  /// SVG asset path for custom icon
  final String? iconSvgPath;

  /// Widget to display as icon (for maximum flexibility - e.g., emoji or image)
  final Widget? iconWidget;

  /// Background color of the circular icon container
  final Color? iconBackgroundColor;

  /// Color of the icon itself (only used for IconData icons)
  final Color iconColor;

  /// Size of the circular icon container
  final double iconContainerSize;

  /// Title text displayed prominently
  final String title;

  /// Description text (can be multiline)
  final String? description;

  /// Maximum lines for description
  final int descriptionMaxLines;

  /// Optional badge text (e.g., "GEO"). When provided, shows badge instead of bookmark
  final String? badge;

  /// Badge background color (border color)
  final Color? badgeBorderColor;

  /// Badge text color
  final Color? badgeTextColor;

  /// Whether to show bookmark icon (only shown if badge is null)
  final bool showBookmark;

  /// Whether the item is bookmarked (filled vs outline icon)
  final bool isBookmarked;

  /// Metadata items to show below title (icons with optional labels)
  final List<CardMetaItem>? metaItems;

  /// Card width (default adapts to parent)
  final double? width;

  /// Card height (default adapts to content)
  final double? height;

  /// Callback when the card is tapped
  final VoidCallback? onTap;

  /// Callback when bookmark is tapped
  final VoidCallback? onBookmarkTap;

  /// Callback when badge is tapped
  final VoidCallback? onBadgeTap;

  const CourseCard({
    super.key,
    this.icon,
    this.iconSvgPath,
    this.iconWidget,
    this.iconBackgroundColor,
    this.iconColor = Colors.black,
    this.iconContainerSize = 64,
    required this.title,
    this.description,
    this.descriptionMaxLines = 2,
    this.badge,
    this.badgeBorderColor,
    this.badgeTextColor,
    this.showBookmark = true,
    this.isBookmarked = false,
    this.metaItems,
    this.width,
    this.height,
    this.onTap,
    this.onBookmarkTap,
    this.onBadgeTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: AppDecorations.cardDecoration,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top row: Icon and badge (if quiz type)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIconContainer(),
                  const Spacer(),
                  if (badge != null) _buildBadge(),
                ],
              ),
              const Spacer(),
              // Bottom section: Title, meta/description, and bookmark
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Title - Nunito 900, 20px, line-height 24px
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.cardTitle(),
                        ),
                        // Meta items (for quiz cards) or description (for course cards)
                        if (metaItems != null && metaItems!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildMetaRow(),
                        ] else if (description != null) ...[
                          const SizedBox(height: 4),
                          // Description - Poppins 500, 15px, line-height 20px
                          Text(
                            description!,
                            maxLines: descriptionMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.body(
                              color: AppColors.primaryDark64,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // Bookmark hidden (TODO: re-enable when ready)
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconContainer() {
    Widget iconContent;

    if (iconWidget != null) {
      iconContent = iconWidget!;
    } else if (iconSvgPath != null) {
      iconContent = SvgPicture.asset(
        iconSvgPath!,
        width: iconContainerSize * 0.5,
        height: iconContainerSize * 0.5,
        colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
      );
    } else {
      iconContent = Icon(
        icon,
        size: iconContainerSize * 0.5,
        color: iconColor,
      );
    }

    return Container(
      width: iconContainerSize,
      height: iconContainerSize,
      decoration: BoxDecoration(
        color: iconBackgroundColor ?? AppColors.success.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(child: iconContent),
    );
  }

  Widget _buildBookmark() {
    return GestureDetector(
      onTap: onBookmarkTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          isBookmarked ? Icons.bookmark : Icons.bookmark_border,
          size: 24,
          color: AppColors.primaryDark,
        ),
      ),
    );
  }

  Widget _buildBadge() {
    return GestureDetector(
      onTap: onBadgeTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 5),
        decoration: BoxDecoration(
          borderRadius: AppDecorations.radiusXS,
          border: Border.all(
            color: badgeBorderColor ?? AppColors.primaryDark,
            width: 1,
          ),
        ),
        child: Text(
          badge!,
          style: AppTextStyles.badgeTiny(color: badgeTextColor ?? AppColors.primaryDark),
        ),
      ),
    );
  }

  Widget _buildMetaRow() {
    return Row(
      children: [
        for (int i = 0; i < metaItems!.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          _buildMetaItem(metaItems![i]),
        ],
      ],
    );
  }

  Widget _buildMetaItem(CardMetaItem item) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (item.iconPath != null)
          SvgPicture.asset(
            item.iconPath!,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(item.iconColor ?? AppColors.primaryDark, BlendMode.srcIn),
          )
        else if (item.icon != null)
          Icon(
            item.icon,
            size: 16,
            color: item.iconColor ?? AppColors.primaryDark,
          ),
        if (item.label != null) ...[
          const SizedBox(width: 4),
          // Meta text - Poppins 500, 15px
          Text(
            item.label!,
            style: AppTextStyles.body(color: AppColors.primaryDark64),
          ),
        ],
      ],
    );
  }
}
