import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import '../../core/theme/app_theme.dart';
import '../../core/strings/app_strings.dart';
import '../../core/utils/image_url.dart';
import '../../models/course_model.dart';
import '../../widgets/markdown_latex_widget.dart';
import 'card_container.dart';
import 'network_image.dart';
import 'video_embed.dart';

bool _looksMarkdown(String content) =>
    content.contains('**') ||
    content.contains('__') ||
    content.contains('##') ||
    content.contains('```') ||
    content.contains('*') ||
    content.contains('_') ||
    content.contains('![');

bool _looksHtml(String content) =>
    content.contains('<') && content.contains('>');

/// Display card for atomic format blocks (v2). Shows formatted text content
/// plus optional video/image.
class LessonAtomicDisplayCard extends StatelessWidget {
  final ContentBlock block;
  final Widget actionRow;

  const LessonAtomicDisplayCard({
    super.key,
    required this.block,
    required this.actionRow,
  });

  @override
  Widget build(BuildContext context) {
    final content = block.displayContent;
    final hasMarkdown = _looksMarkdown(content);
    final hasHtml = _looksHtml(content);

    return LessonCardContainer(
      children: [
        if (hasMarkdown)
          MarkdownLatexWidget(
            content: content,
            textColor: AppColors.primaryDark,
          )
        else if (hasHtml)
          Html(
            data: resolveHtmlImageUrls(content),
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(15),
                fontWeight: FontWeight.w500,
                color: AppColors.primaryDark88,
                lineHeight: const LineHeight(1.5),
                fontFamily: 'Poppins',
              ),
              'p': Style(margin: Margins.only(bottom: 12)),
              'h3': Style(
                fontSize: FontSize(18),
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
                margin: Margins.only(bottom: 12, top: 8),
              ),
              'strong': Style(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
              'em': Style(fontStyle: FontStyle.italic),
              'ul': Style(margin: Margins.only(bottom: 12)),
              'li': Style(margin: Margins.only(bottom: 6)),
            },
          )
        else
          Text(
            content,
            style: AppTextStyles.body(
              color: AppColors.primaryDark.withValues(alpha: 0.72),
              height: 1.5,
            ),
          ),
        if (block.hasVideo) ...[
          const SizedBox(height: 16),
          LessonVideoEmbed(videoUrl: block.videoUrl!),
        ],
        if (block.hasImage) ...[
          const SizedBox(height: 16),
          LessonBlockImage(image: block.blockImage!),
        ],
        const SizedBox(height: 24),
        actionRow,
      ],
    );
  }
}

/// Question card for atomic format blocks. Supports both open-text input
/// (via [openInput]) and multiple-choice options.
class LessonAtomicQuestionCard extends StatelessWidget {
  final ContentBlock block;
  final AtomicQuestion? question;
  final bool isAnswered;
  final bool evaluate;
  final Widget? openInput;
  final Widget actionRow;
  final ValueChanged<String> onOptionSelected;

  const LessonAtomicQuestionCard({
    super.key,
    required this.block,
    required this.question,
    required this.isAnswered,
    required this.evaluate,
    required this.openInput,
    required this.actionRow,
    required this.onOptionSelected,
  });

  @override
  Widget build(BuildContext context) {
    final content = block.displayContent;
    final hasMarkdown = _looksMarkdown(content);
    final hasHtml = _looksHtml(content);

    return LessonCardContainer(
      children: [
        if (hasMarkdown)
          MarkdownLatexWidget(
            content: content,
            textColor: AppColors.primaryDark,
          )
        else if (hasHtml)
          Html(
            data: resolveHtmlImageUrls(content),
            style: {
              'body': Style(
                margin: Margins.zero,
                padding: HtmlPaddings.zero,
                fontSize: FontSize(16),
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
                lineHeight: const LineHeight(1.4),
                fontFamily: 'Poppins',
              ),
            },
          )
        else
          Text(content, style: AppTextStyles.buttonLarge()),
        const SizedBox(height: 16),
        if (openInput != null)
          openInput!
        else if (question != null && question!.options.isNotEmpty) ...[
          ...question!.options.map((option) {
            final isSelected = block.selectedOptionId == option.id;
            final isCorrect = option.isCorrect;
            final showResult = isAnswered || block.isCompleted;
            final isLocked = showResult || block.isCompleted;

            Color bgColor = AppColors.surface;
            Color borderColor = AppColors.primaryDark16;

            if (showResult && isSelected && evaluate) {
              bgColor = isCorrect
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.error.withValues(alpha: 0.1);
              borderColor =
                  isCorrect ? AppColors.success : AppColors.error;
            } else if (showResult && isCorrect && evaluate) {
              bgColor = AppColors.success.withValues(alpha: 0.05);
              borderColor = AppColors.success.withValues(alpha: 0.5);
            } else if (isSelected) {
              bgColor = AppColors.primary.withValues(alpha: 0.1);
              borderColor = AppColors.primary;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: isLocked ? null : () => onOptionSelected(option.id),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: AppDecorations.radiusS,
                    border: Border.all(color: borderColor, width: 1.5),
                  ),
                  child: Text(
                    option.text,
                    style: isSelected
                        ? AppTextStyles.body(color: AppColors.primaryDark)
                            .copyWith(fontWeight: FontWeight.w600)
                        : AppTextStyles.body(),
                  ),
                ),
              ),
            );
          }),
          if ((isAnswered || block.isCompleted) &&
              evaluate &&
              question!.solution != null &&
              question!.showSolution) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppDecorations.radiusS,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 ${AppStrings.lessonExplanation}',
                    style: AppTextStyles.actionSmall(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    question!.solution!,
                    style: AppTextStyles.bodySmall(
                        color: AppColors.primaryDark80),
                  ),
                ],
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        actionRow,
      ],
    );
  }
}

/// Open-text question input with check button + result/solution feedback.
class LessonAtomicOpenQuestionInput extends StatelessWidget {
  final TextEditingController controller;
  final AtomicQuestion question;
  final String userAnswer;
  final String correctAnswer;
  final bool isAnswered;
  final bool isCorrect;
  final bool showEvaluation;
  final VoidCallback onChanged;
  final VoidCallback onCheckAnswer;

  const LessonAtomicOpenQuestionInput({
    super.key,
    required this.controller,
    required this.question,
    required this.userAnswer,
    required this.correctAnswer,
    required this.isAnswered,
    required this.isCorrect,
    required this.showEvaluation,
    required this.onChanged,
    required this.onCheckAnswer,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          enabled: !isAnswered,
          style: AppTextStyles.subtitle(),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            hintText: AppStrings.lessonWriteAnswer,
            hintStyle: AppTextStyles.bodyLarge(
                color: AppColors.primaryDark.withValues(alpha: 0.4)),
            filled: true,
            fillColor: isAnswered && showEvaluation
                ? (isCorrect
                    ? AppColors.success.withValues(alpha: 0.1)
                    : AppColors.error.withValues(alpha: 0.1))
                : AppColors.background,
            border: OutlineInputBorder(
              borderRadius: AppDecorations.radiusS,
              borderSide: BorderSide(
                color: isAnswered
                    ? (isCorrect ? AppColors.success : AppColors.error)
                    : AppColors.primaryDark16,
                width: 1.5,
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppDecorations.radiusS,
              borderSide: BorderSide(
                color: AppColors.primaryDark16,
                width: 1.5,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppDecorations.radiusS,
              borderSide: BorderSide(color: AppColors.primary, width: 2),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: AppDecorations.radiusS,
              borderSide: BorderSide(
                color: showEvaluation
                    ? (isCorrect ? AppColors.success : AppColors.error)
                    : AppColors.primaryDark16,
                width: 1.5,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onCheckAnswer(),
        ),
        const SizedBox(height: 12),
        if (!isAnswered && userAnswer.isNotEmpty)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCheckAnswer,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: AppDecorations.radiusS,
                ),
              ),
              child: Text(
                AppStrings.lessonCheckAnswer,
                style: AppTextStyles.buttonLarge(),
              ),
            ),
          ),
        if (isAnswered && showEvaluation) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isCorrect
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.error.withValues(alpha: 0.1),
              borderRadius: AppDecorations.radiusS,
            ),
            child: Row(
              children: [
                Icon(
                  isCorrect ? Icons.check_circle : Icons.cancel,
                  color: isCorrect ? AppColors.success : AppColors.error,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isCorrect
                        ? AppStrings.lessonCorrect
                        : AppStrings.lessonCorrectAnswer(correctAnswer),
                    style: AppTextStyles.labelMedium(
                      color: isCorrect
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (question.solution != null && question.showSolution) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppDecorations.radiusS,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💡 ${AppStrings.lessonExplanation}',
                    style: AppTextStyles.actionSmall(),
                  ),
                  const SizedBox(height: 4),
                  if (question.solution!.contains('**') ||
                      question.solution!.contains('*'))
                    MarkdownLatexWidget(
                      content: question.solution!,
                      textColor: AppColors.primaryDark80,
                    )
                  else
                    Text(
                      question.solution!,
                      style: AppTextStyles.meta(
                          color: AppColors.primaryDark80),
                    ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }
}
