import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../core/strings/app_strings.dart';
import '../../models/course_model.dart';
import '../../widgets/markdown_latex_widget.dart';

/// Display the hint/help bottom sheet for a content block.
///
/// All XP-penalty / tracking side-effects are pushed back into the page via
/// callbacks so this widget stays presentational. The sheet does, however,
/// retain ownership of the StatefulBuilder and the local feedback controller
/// so the show-help/feedback transitions happen inside the modal — exactly as
/// in the original implementation.
void showLessonHintSheet({
  required BuildContext context,
  required ContentBlock block,
  required VoidCallback onShown,
  required VoidCallback onEscalateToHelp,
  required VoidCallback onSavePractice,
  required VoidCallback onAskAi,
  required void Function(String studentMessage) onSendFeedback,
}) {
  // Notify caller the hint was shown (so it can record XP penalty).
  onShown();

  final hint = block.currentHint!;
  final title = block.displayTitle;

  // Track selected feedback option
  String? selectedFeedback;
  bool showHelp = false;
  final feedbackController = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          final displayedText = showHelp
              ? (block.currentHelp ?? hint)
              : hint;
          final displayedTitle = showHelp
              ? AppStrings.lessonDetailedExplanation(title)
              : AppStrings.lessonExplanationTitle(title);
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          return Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            // Push content up when keyboard is open
            padding: EdgeInsets.only(bottom: keyboardHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Close button
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 16),
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.background,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 20,
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ),
                  ),
                ),
                // Content
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: AppDecorations.radiusS,
                          ),
                          child: Icon(
                            Icons.help_outline,
                            color: AppColors.quizPurple,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Title
                        Text(
                          displayedTitle,
                          style: AppTextStyles.heading4(),
                        ),
                        const SizedBox(height: 16),
                        // Hint/help content - render with markdown/LaTeX support
                        MarkdownLatexWidget(
                          content: displayedText,
                          textColor: AppColors.primaryDark88,
                        ),
                        const SizedBox(height: 24),
                        // Feedback options (Phase 1 only)
                        if (!showHelp) ...[
                          _HintFeedbackOption(
                            icon: Icons.check,
                            iconColor: AppColors.success,
                            label: AppStrings.lessonFeedbackClear,
                            isSelected: selectedFeedback == 'clear',
                            onTap: () {
                              Navigator.of(context).pop();
                            },
                          ),
                          const SizedBox(height: 8),
                          _HintFeedbackOption(
                            icon: Icons.bookmark_border,
                            iconColor: AppColors.quizPurple,
                            label: AppStrings.lessonFeedbackPractice,
                            isSelected: selectedFeedback == 'practice',
                            onTap: () {
                              // Actually save the bookmark for practice
                              onSavePractice();
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.of(context).pop();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(AppStrings.lessonFeedbackPracticeAdded),
                                  backgroundColor: AppColors.success,
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          _HintFeedbackOption(
                            icon: Icons.sentiment_dissatisfied_outlined,
                            iconColor: AppColors.orange,
                            label: AppStrings.lessonFeedbackConfused,
                            isSelected: selectedFeedback == 'confused',
                            onTap: () {
                              setModalState(() {
                                showHelp = true;
                              });
                              // Escalate hint usage to "help" level for ELO penalty
                              onEscalateToHelp();
                            },
                          ),
                          const SizedBox(height: 8),
                          _HintFeedbackOption(
                            icon: Icons.smart_toy_outlined,
                            iconColor: AppColors.primary,
                            label: 'Zeptat se AI',
                            isSelected: false,
                            onTap: () {
                              Navigator.of(context).pop();
                              onAskAi();
                            },
                          ),
                        ],
                        // Help form (Phase 2 only)
                        if (showHelp) ...[
                        const SizedBox(height: 20),
                        // Question input
                        Row(
                          children: [
                            Text(
                              AppStrings.lessonFeedbackClarify,
                              style: AppTextStyles.statSuffix(),
                            ),
                            Text(
                              ' *',
                              style: AppTextStyles.statSuffix(color: AppColors.orange),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            borderRadius: AppDecorations.radiusS,
                            border: Border.all(
                              color: AppColors.surfaceLight,
                            ),
                          ),
                          child: TextField(
                            controller: feedbackController,
                            maxLines: 4,
                            maxLength: 500,
                            decoration: InputDecoration(
                              hintText: AppStrings.lessonFeedbackHint,
                              hintStyle: AppTextStyles.bodySmall(color: AppColors.disabled),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(16),
                              counterText: '',
                            ),
                            style: AppTextStyles.bodySmall(),
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            AppStrings.lessonFeedbackCharCount(feedbackController.text.length),
                            style: AppTextStyles.caption(color: AppColors.disabled),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // Send to AI button — disabled when text is empty
                        Builder(builder: (ctx) {
                          final isEmpty = feedbackController.text.trim().isEmpty;
                          return GestureDetector(
                            onTap: isEmpty
                                ? null
                                : () {
                                    final studentMessage = feedbackController.text.trim();
                                    Navigator.of(ctx).pop();
                                    onSendFeedback(studentMessage);
                                  },
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                color: isEmpty
                                    ? AppColors.primary.withValues(alpha: 0.4)
                                    : AppColors.primary,
                                borderRadius: AppDecorations.radiusXL,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    AppStrings.lessonFeedbackSend,
                                    style: AppTextStyles.buttonLarge(
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.send,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                        ], // end if (showHelp)
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

class _HintFeedbackOption extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _HintFeedbackOption({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.background : AppColors.surface,
          borderRadius: AppDecorations.radiusXL,
          border: Border.all(
            color: isSelected ? AppColors.quizPurple : AppColors.surfaceLight,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppTextStyles.bodySmall(),
            ),
          ],
        ),
      ),
    );
  }
}
