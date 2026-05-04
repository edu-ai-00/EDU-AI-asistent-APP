import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/strings/app_strings.dart';

/// Bottom action bar shown after lesson completion. Switches between
/// the course-completed state (Cvičení/Kvíz buttons) and the regular
/// next-lesson button. Pure presentational — receives flags + callbacks.
class LessonNav extends StatelessWidget {
  final bool courseCompleted;
  final bool isLastLesson;
  final bool hasExerciseBlocks;
  final bool hasQuestions;
  final VoidCallback onNextLesson;
  final VoidCallback onCviceni;
  final VoidCallback onKviz;
  final VoidCallback onBackToCourse;

  const LessonNav({
    super.key,
    required this.courseCompleted,
    required this.isLastLesson,
    required this.hasExerciseBlocks,
    required this.hasQuestions,
    required this.onNextLesson,
    required this.onCviceni,
    required this.onKviz,
    required this.onBackToCourse,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark16,
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: courseCompleted
          ? _buildCourseCompletedButtons(context)
          : _buildNextLessonButton(),
    );
  }

  /// Buttons shown after course is completed: Cvičení + Kvíz
  Widget _buildCourseCompletedButtons(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Success message
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.successBgLight,
            borderRadius: AppDecorations.radiusS,
          ),
          child: Row(
            children: [
              Icon(Icons.emoji_events, color: AppColors.success, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppStrings.lessonCourseCompleted,
                  style: AppTextStyles.actionSmall(color: AppColors.success),
                ),
              ),
            ],
          ),
        ),
        // Buttons row — only show buttons when relevant content exists
        Builder(builder: (context) {
          if (!hasExerciseBlocks && !hasQuestions) return const SizedBox.shrink();

          return Row(
            children: [
              if (hasExerciseBlocks)
                Expanded(
                  child: GestureDetector(
                    onTap: onCviceni,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark,
                        borderRadius: AppDecorations.radiusS,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.bookmark_outlined, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Cvičení',
                            style: AppTextStyles.statValue(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (hasExerciseBlocks && hasQuestions)
                const SizedBox(width: 12),
              if (hasQuestions)
                Expanded(
                  child: GestureDetector(
                    onTap: onKviz,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        borderRadius: AppDecorations.radiusS,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.quiz_outlined, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Kvíz',
                            style: AppTextStyles.statValue(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        }),
        const SizedBox(height: 12),
        // Back to course button
        GestureDetector(
          onTap: onBackToCourse,
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              borderRadius: AppDecorations.radiusS,
              border: Border.all(color: AppColors.primaryDark, width: 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_back, color: AppColors.primaryDark, size: 20),
                const SizedBox(width: 8),
                Text(
                  AppStrings.lessonBackToDetail,
                  style: AppTextStyles.actionSmall(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Regular next lesson / complete course button
  Widget _buildNextLessonButton() {
    return GestureDetector(
      onTap: onNextLesson,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: AppDecorations.radiusS,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isLastLesson ? AppStrings.lessonFinishCourse : AppStrings.lessonNextLesson,
              style: AppTextStyles.statValue(color: Colors.white),
            ),
            const SizedBox(width: 8),
            Icon(
              isLastLesson ? Icons.check : Icons.arrow_forward,
              color: Colors.white,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
