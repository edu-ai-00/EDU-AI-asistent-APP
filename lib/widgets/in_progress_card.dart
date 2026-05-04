import 'package:flutter/material.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';

/// Small badge item for displaying emoji/icon avatars
class BadgeItem {
  final String emoji;
  final Color? backgroundColor;

  const BadgeItem({
    required this.emoji,
    this.backgroundColor,
  });
}

/// A card widget showing course/task progress with a continue button.
///
/// Features:
/// - Icon with background circle
/// - Title and subtitle
/// - Avatar badges on the right
/// - Striped progress bar with fraction display
/// - "Pokracovat" (Continue) button
class InProgressCard extends StatelessWidget {
  /// Icon to display (e.g., calendar-clock)
  final IconData? icon;

  /// Widget for icon (e.g., emoji)
  final Widget? iconWidget;

  /// Background color of the icon circle
  final Color? iconBackgroundColor;

  /// Icon color
  final Color? iconColor;

  /// Main title text
  final String title;

  /// Subtitle text
  final String subtitle;

  /// Current progress value
  final int currentProgress;

  /// Total/max progress value
  final int totalProgress;

  /// Badge items to show on the right (max 3 recommended)
  final List<BadgeItem>? badges;

  /// Button text
  final String buttonText;

  /// Whether to show the progress bar
  final bool showProgressBar;

  /// Place the icon on the right side instead of left
  final bool iconOnRight;

  /// Callback when button is tapped
  final VoidCallback? onButtonTap;

  /// Callback when card is tapped
  final VoidCallback? onTap;

  const InProgressCard({
    super.key,
    this.icon,
    this.iconWidget,
    this.iconBackgroundColor,
    this.iconColor,
    required this.title,
    required this.subtitle,
    this.currentProgress = 0,
    this.totalProgress = 0,
    this.badges,
    this.buttonText = AppStrings.actionContinue,
    this.showProgressBar = true,
    this.iconOnRight = false,
    this.onButtonTap,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDecorations.radiusXL,
          boxShadow: AppDecorations.shadowStrong,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: Icon, title/subtitle, badges
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!iconOnRight) ...[
                  _buildIconContainer(),
                  const SizedBox(width: 12),
                ],
                // Title and subtitle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.cardTitle(),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTextStyles.body(
                          color: AppColors.primaryDark64,
                        ),
                      ),
                    ],
                  ),
                ),
                // Badges
                if (badges != null && badges!.isNotEmpty) _buildBadges(),
                if (iconOnRight) ...[
                  const SizedBox(width: 12),
                  _buildIconContainer(),
                ],
              ],
            ),
            if (showProgressBar) ...[
              const SizedBox(height: 16),
              // Progress bar
              _buildProgressBar(),
            ],
            const SizedBox(height: 24),
            // Continue button
            _buildButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildIconContainer() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: iconBackgroundColor ?? AppColors.background,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: iconWidget ??
            Icon(
              icon ?? Icons.schedule,
              size: 24,
              color: iconColor ?? AppColors.primary,
            ),
      ),
    );
  }

  Widget _buildBadges() {
    const double badgeSize = 40;
    const double overlap = 16;

    return SizedBox(
      width: badgeSize + (badges!.length - 1) * (badgeSize - overlap),
      height: badgeSize,
      child: Stack(
        children: [
          for (int i = 0; i < badges!.length; i++)
            Positioned(
              left: i * (badgeSize - overlap),
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: badges![i].backgroundColor ?? AppColors.cardBlue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(
                    badges![i].emoji,
                    style: const TextStyle(fontSize: 20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final double progress = totalProgress > 0
        ? (currentProgress / totalProgress).clamp(0.0, 1.0)
        : 0.0;

    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final progressWidth = constraints.maxWidth * progress;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Background with diagonal stripes
              ClipRRect(
                borderRadius: AppDecorations.radiusXS,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.progressTrack,
                  ),
                  child: CustomPaint(
                    size: Size(constraints.maxWidth, 24),
                    painter: _DiagonalStripesPainter(
                      stripeColor: AppColors.background,
                      stripeWidth: 4,
                      spacing: 8.964,
                    ),
                  ),
                ),
              ),
              // Progress fill with text
              Container(
                width: progressWidth,
                decoration: BoxDecoration(
                  color: AppColors.progressFill,
                  borderRadius: AppDecorations.radiusXS,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // White progress line at top
                    Positioned(
                      left: 4,
                      top: 4,
                      right: 4,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    // Progress text at the end of progress bar
                    Positioned(
                      right: 4,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          '$currentProgress/$totalProgress',
                          style: AppTextStyles.actionText(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildButton() {
    return GestureDetector(
      onTap: onButtonTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: AppDecorations.radiusS,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              buttonText,
              style: AppTextStyles.statValue(
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward,
              size: 24,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for diagonal stripes pattern
class _DiagonalStripesPainter extends CustomPainter {
  final Color stripeColor;
  final double stripeWidth;
  final double spacing;

  _DiagonalStripesPainter({
    required this.stripeColor,
    required this.stripeWidth,
    required this.spacing,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = stripeColor
      ..strokeWidth = stripeWidth
      ..style = PaintingStyle.stroke;

    final double step = stripeWidth + spacing;
    final double diagonal = size.width + size.height;

    for (double i = -size.height; i < diagonal; i += step) {
      canvas.drawLine(
        Offset(i, size.height),
        Offset(i + size.height, 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
