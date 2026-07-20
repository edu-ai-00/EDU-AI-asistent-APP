import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/practice_providers.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import 'quiz_page.dart';

/// PracticePage — minimal entry point for the FSRS spaced-repetition queue.
///
/// MVP scope: shows the due-card count, resolves the queued cards to their
/// content blocks across courses, and reuses the proven exercise [QuizPage]
/// to run the session.
///
/// FSRS review write-back IS wired: QuizPage runs with isFsrsPractice=true and
/// calls PracticeService.reviewCard per graded block (scheduler + review log),
/// and shows a session summary (success rate + XP) on completion.
class PracticePage extends ConsumerStatefulWidget {
  const PracticePage({super.key});

  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage> {
  bool _starting = false;

  Future<void> _start() async {
    setState(() => _starting = true);
    try {
      final result = await ref.read(playablePracticeProvider.future);
      if (!mounted) return;

      final blocks = result.blocks;
      if (blocks.isEmpty) {
        setState(() => _starting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.practiceEmpty)),
        );
        return;
      }

      // Practice cards may span multiple courses; QuizPage attributes the
      // session to a single course. MVP: use the first resolved block's
      // course context for evaluation/ELO.
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => QuizPage(
            questionBlocks: blocks,
            courseTitle: AppStrings.practiceTitle,
            courseId: result.courseId ?? '',
            progress: QuizProgress(),
            evaluate: true,
            isExercise: true,
            isFsrsPractice: true,
          ),
        ),
      );
      if (mounted) setState(() => _starting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _starting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.genericError('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final queueAsync = ref.watch(playablePracticeProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.primaryDark,
        title: Text(
          AppStrings.practiceTitle,
          style: AppTextStyles.heading2Bold(),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: queueAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => Text(
                AppStrings.genericError('$e'),
                textAlign: TextAlign.center,
                style: AppTextStyles.body(color: AppColors.primaryDark64),
              ),
              data: (result) {
                final blocks = result.blocks;
                final isEmpty = blocks.isEmpty;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Hero card — gives the practice entry a clear identity
                    // instead of a bare emoji + button.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 32),
                      decoration: BoxDecoration(
                        gradient: AppColors.headerGradient,
                        borderRadius: AppDecorations.radiusXL,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.28),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              isEmpty ? '🎉' : '🧠',
                              style: const TextStyle(fontSize: 38),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            isEmpty
                                ? AppStrings.practiceEmpty
                                : AppStrings.practiceDueCount(blocks.length),
                            textAlign: TextAlign.center,
                            style:
                                AppTextStyles.heading2Bold(color: Colors.white),
                          ),
                          if (!isEmpty) ...[
                            const SizedBox(height: 8),
                            Text(
                              AppStrings.practiceDashSubtitle,
                              textAlign: TextAlign.center,
                              style: AppTextStyles.body(
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (!isEmpty) ...[
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _starting ? null : _start,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: AppDecorations.radiusM,
                            ),
                          ),
                          child: _starting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white,
                                    ),
                                  ),
                                )
                              : Text(
                                  AppStrings.practiceStart,
                                  style: AppTextStyles.actionSmall(
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
