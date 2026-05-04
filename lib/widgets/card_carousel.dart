import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// A horizontal carousel for cards that shows peek of next card
class CardCarousel extends StatelessWidget {
  /// List of card widgets to display
  final List<Widget> children;

  /// Card width as fraction of screen width (0.0 to 1.0)
  /// Default is 0.75 (75% of available width)
  final double cardWidthFraction;

  /// Spacing between cards
  final double spacing;

  /// Horizontal padding at the start and end of carousel
  final double horizontalPadding;

  /// Height of the carousel (should match card height)
  final double? height;

  const CardCarousel({
    super.key,
    required this.children,
    this.cardWidthFraction = 0.75,
    this.spacing = 12,
    this.horizontalPadding = 16,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final parentWidth = constraints.maxWidth;
        final availableWidth = parentWidth - (horizontalPadding * 2);

        // If only one card, use full width
        final cardWidth = children.length == 1
            ? availableWidth
            : availableWidth * cardWidthFraction;

        return SizedBox(
          height: height,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none, // Allow shadows to overflow
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
            itemCount: children.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(
                  right: index < children.length - 1 ? spacing : 0,
                ),
                child: SizedBox(
                  width: cardWidth,
                  child: children[index],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// A section combining header and carousel
class CardSection extends StatelessWidget {
  /// Section title
  final String title;

  /// Action button text
  final String? actionText;

  /// Callback when action button is tapped
  final VoidCallback? onActionTap;

  /// Cards to display in carousel
  final List<Widget> cards;

  /// Height of the carousel
  final double carouselHeight;

  /// Card width fraction (0.75 = 75% of screen width)
  final double cardWidthFraction;

  /// Spacing between header and carousel
  final double headerSpacing;

  const CardSection({
    super.key,
    required this.title,
    this.actionText,
    this.onActionTap,
    required this.cards,
    this.carouselHeight = 220,
    this.cardWidthFraction = 0.75,
    this.headerSpacing = 16,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _SectionHeader(
          title: title,
          actionText: actionText,
          onActionTap: onActionTap,
        ),
        SizedBox(height: headerSpacing),
        CardCarousel(
          cardWidthFraction: cardWidthFraction,
          height: carouselHeight,
          children: cards,
        ),
      ],
    );
  }
}

/// Internal section header
class _SectionHeader extends StatelessWidget {
  final String title;
  final String? actionText;
  final VoidCallback? onActionTap;

  const _SectionHeader({
    required this.title,
    this.actionText,
    this.onActionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: AppTextStyles.heading1(),
            ),
          ),
          if (actionText != null) ...[
            const SizedBox(width: 16),
            Padding(
              padding: const EdgeInsets.only(top: 5),
              child: GestureDetector(
                onTap: onActionTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: AppDecorations.radiusXS,
                  ),
                  child: Text(
                    actionText!,
                    style: AppTextStyles.actionText(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
