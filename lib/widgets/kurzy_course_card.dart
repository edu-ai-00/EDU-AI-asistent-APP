import 'package:flutter/material.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';

/// Status of a course
enum CourseStatus {
  notStarted, // Nezahájené
  inProgress, // Probíhající
  completed, // Dokončeno
}

/// A card widget for displaying courses in the Kurzy page list.
class KurzyCourseCard extends StatelessWidget {
  /// Widget to display as icon (emoji or image)
  final Widget iconWidget;

  /// Background color of the circular icon container
  final Color? iconBackgroundColor;

  /// Title of the course
  final String title;

  /// Description/subtitle of the course
  final String? description;

  /// Badge text (e.g., "BIO", "FYZ")
  final String? badge;

  /// Number of lessons
  final int lessonCount;

  /// Duration in hours
  final int durationHours;

  /// Total duration in minutes (for smart display)
  final int durationMinutes;

  /// Current progress (for in-progress courses)
  final int? currentProgress;

  /// Total progress (for in-progress courses)
  final int? totalProgress;

  /// Course status
  final CourseStatus status;

  /// Whether the course is bookmarked
  final bool isBookmarked;

  /// Whether a newer version of the course is available on the server.
  final bool hasUpdate;

  /// Callback when the card is tapped
  final VoidCallback? onTap;

  /// Callback when bookmark is tapped
  final VoidCallback? onBookmarkTap;

  const KurzyCourseCard({
    super.key,
    required this.iconWidget,
    this.iconBackgroundColor,
    required this.title,
    this.description,
    this.badge,
    required this.lessonCount,
    required this.durationHours,
    this.durationMinutes = 0,
    this.currentProgress,
    this.totalProgress,
    this.status = CourseStatus.notStarted,
    this.isBookmarked = false,
    this.hasUpdate = false,
    this.onTap,
    this.onBookmarkTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppDecorations.radiusXL,
          boxShadow: AppDecorations.shadowLight,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top row: Icon, badge, and status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIconContainer(),
                  const Spacer(),
                  if (badge != null) _buildBadge(),
                  if (hasUpdate) ...[
                    if (badge != null) const SizedBox(width: 8),
                    _buildUpdateBadge(),
                  ],
                  if (status == CourseStatus.completed) ...[
                    if (badge != null || hasUpdate) const SizedBox(width: 8),
                    _buildCompletedBadge(),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              // Title
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.cardTitleSmall(),
              ),
              // Description
              if (description != null) ...[
                const SizedBox(height: 4),
                Text(
                  description!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodySmall(
                    color: AppColors.primaryDark64,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              // Bottom row: Meta info, progress bar, bookmark
              Row(
                children: [
                  // Lesson count
                  Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: AppColors.primaryDark48,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppStrings.lessonsCount(lessonCount),
                    style: AppTextStyles.meta(
                      color: AppColors.primaryDark64,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Duration
                  Icon(
                    Icons.access_time,
                    size: 16,
                    color: AppColors.primaryDark48,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    durationMinutes > 0
                        ? AppStrings.durationSmart(durationMinutes)
                        : AppStrings.durationHours(durationHours),
                    style: AppTextStyles.meta(
                      color: AppColors.primaryDark64,
                    ),
                  ),
                  const Spacer(),
                  // Bookmark hidden (TODO: re-enable when ready)
                ],
              ),
              // Progress bar (for in-progress or completed courses)
              if (status != CourseStatus.notStarted &&
                  currentProgress != null &&
                  totalProgress != null) ...[
                const SizedBox(height: 12),
                _buildProgressBar(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconContainer() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: iconBackgroundColor ?? AppColors.surfaceLight,
        shape: BoxShape.circle,
      ),
      child: Center(child: iconWidget),
    );
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: AppDecorations.radiusXS,
        border: Border.all(
          color: AppColors.primaryDark,
          width: 1,
        ),
      ),
      child: Text(
        badge!,
        style: AppTextStyles.badgeSmall(),
      ),
    );
  }

  Widget _buildUpdateBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.16),
        borderRadius: AppDecorations.radiusXS,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.system_update_alt_rounded,
            size: 14,
            color: AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            AppStrings.courseCardUpdate,
            style: AppTextStyles.badgeSmall(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.16),
        borderRadius: AppDecorations.radiusXS,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check,
            size: 14,
            color: AppColors.success,
          ),
          const SizedBox(width: 4),
          Text(
            AppStrings.courseCardCompleted,
            style: AppTextStyles.badgeSmall(
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    final double progress = totalProgress! > 0
        ? (currentProgress! / totalProgress!).clamp(0.0, 1.0)
        : 0.0;
    final isCompleted = status == CourseStatus.completed;
    final Color progressColor =
        isCompleted ? AppColors.success : AppColors.progressFill;

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
                  color: progressColor,
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
