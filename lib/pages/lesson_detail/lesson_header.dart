import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import 'diagonal_stripes_painter.dart';

/// Top header with back button, course/lesson title, XP badge,
/// and progress bar. Pure presentational — receives all data + the
/// back-press callback as props.
class LessonHeader extends StatelessWidget {
  final String courseTitle;
  final String lessonTitle;
  final int lessonIndex;
  final int xpReward;
  final int completedCount;
  final int blockCount;
  final VoidCallback onBack;

  const LessonHeader({
    super.key,
    required this.courseTitle,
    required this.lessonTitle,
    required this.lessonIndex,
    required this.xpReward,
    required this.completedCount,
    required this.blockCount,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: AppDecorations.shadowStrong,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Top row with back button, title, and XP badge
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  // Back button
                  GestureDetector(
                    onTap: onBack,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: AppDecorations.circleButton,
                      child: Icon(
                        Icons.arrow_back,
                        color: AppColors.primaryDark,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Title section
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          courseTitle,
                          style: AppTextStyles.statValue(),
                        ),
                        Text(
                          'Lekce ${lessonIndex + 1}: $lessonTitle',
                          style: AppTextStyles.body(color: AppColors.primaryDark64),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // XP Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.orange,
                      borderRadius: AppDecorations.radiusS,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.bolt,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '+$xpReward XP',
                          style: AppTextStyles.badge(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: LessonProgressBar(
                completedCount: completedCount,
                blockCount: blockCount,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Progress bar with diagonal stripes background and animated fill.
class LessonProgressBar extends StatelessWidget {
  final int completedCount;
  final int blockCount;

  const LessonProgressBar({
    super.key,
    required this.completedCount,
    required this.blockCount,
  });

  @override
  Widget build(BuildContext context) {
    final progress = blockCount == 0 ? 0.0 : completedCount / blockCount;

    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final progressWidth = constraints.maxWidth * progress;
          final minProgressWidth = progress > 0 ? 60.0 : 0.0;
          final actualProgressWidth = progressWidth < minProgressWidth ? minProgressWidth : progressWidth;

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
                    painter: DiagonalStripesPainter(
                      stripeColor: AppColors.background,
                      stripeWidth: 4,
                      spacing: 8.964,
                    ),
                  ),
                ),
              ),
              // Progress fill with text
              if (progress > 0)
                Container(
                  width: actualProgressWidth,
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
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.progressBorder,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '$completedCount/$blockCount',
                              style: AppTextStyles.actionText(color: Colors.white),
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
