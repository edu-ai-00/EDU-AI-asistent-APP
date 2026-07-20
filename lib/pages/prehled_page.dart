import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/providers/core_providers.dart';
import '../core/providers/practice_providers.dart';
import '../data/repositories/user_stats_repository.dart';
import '../models/course_model.dart';
import '../utils/achievement_stats.dart';
import '../widgets/widgets.dart';
import 'achievements_page.dart';
import 'course_detail_page.dart';
import 'knihovna_page.dart';
import 'practice_page.dart';
import 'quiz_page.dart';

// Placeholder pages
class PrehledPage extends ConsumerWidget {
  final VoidCallback? onOpenDrawer;
  final String? userName;
  final Map<String, QuizProgress> quizProgressCache;

  const PrehledPage({super.key, this.onOpenDrawer, this.userName, required this.quizProgressCache});

  void _openAchievements(BuildContext context, WidgetRef ref, UserStats? stats) async {
    final config = ref.read(gamificationConfigProvider).valueOrNull;
    final earnedIds = ref.read(earnedAchievementsProvider).valueOrNull ?? <String>[];

    // Refresh skills to get latest data (may fetch from API if not synced yet).
    ref.invalidate(skillDisplayProvider);
    final skills = await ref.read(skillDisplayProvider.future);

    // Count lessons/courses/quizzes from user courses
    final userCourses = ref.read(userCoursesStreamProvider).valueOrNull ?? [];
    final counts = countAchievementStats(userCourses);

    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AchievementsPage(
          level: stats?.level ?? 1,
          currentXp: stats?.xpForCurrentLevel ?? 0,
          xpForNextLevel: stats?.xpForNextLevel ?? 500,
          totalXp: stats?.xpPoints ?? 0,
          streakDays: stats?.streakDays ?? 1,
          trophiesCount: stats?.achievementsCount ?? 0,
          lessonsCompleted: counts.lessons,
          coursesCompleted: counts.courses,
          quizzesCompleted: counts.quizzes,
          config: config,
          earnedIds: earnedIds.toSet(),
          skills: skills,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userCoursesAsync = ref.watch(userCoursesStreamProvider);
    final stats = ref.watch(userStatsStreamProvider).valueOrNull;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
            // Header row: Logo, Search, Personalisation
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Logo
                  SvgPicture.asset(
                    'assets/logo.svg',
                    height: 40,
                  ),
                  const Spacer(),
                  // Level + XP indicator
                  GestureDetector(
                    onTap: () => _openAchievements(context, ref, stats),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryDark06,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Level badge
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              gradient: AppColors.headerGradient,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                '${stats?.level ?? 1}',
                                style: AppTextStyles.badge(color: Colors.white),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // XP text
                          Text(
                            '${stats?.xpPoints ?? 0} XP',
                            style: AppTextStyles.actionSmall(),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Search button hidden (TODO: re-enable when ready)
                  // Personalisation button - opens drawer
                  GestureDetector(
                    onTap: onOpenDrawer,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: AppDecorations.circleButton,
                      child: Center(
                        child: SvgPicture.asset(
                          'assets/icons/personalisation.svg',
                          width: 24,
                          height: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Welcome card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: WelcomeCard(
                title: userName != null && userName!.isNotEmpty ? userName! : AppStrings.welcomeGreeting,
                description: AppStrings.welcomeDescription,
                illustrationPath: 'assets/images/skins_bg.png',
                onTap: () {
                  // TODO: Navigate to profile or achievements
                },
              ),
            ),
            const SizedBox(height: 16),
            // Stat cards row (Streak & Trofeje)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: StatCard.streak(
                      days: stats?.streakDays ?? 1,
                      onTap: () {
                        _openAchievements(context, ref, stats);
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: StatCard.trophies(
                      count: stats?.achievementsCount ?? 0,
                      onTap: () {
                        _openAchievements(context, ref, stats);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // "Začněte s návodem" guide card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                AppStrings.guideHeading,
                style: AppTextStyles.heading1(),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InProgressCard(
                icon: Icons.menu_book_rounded,
                iconOnRight: true,
                title: AppStrings.guideTitle,
                subtitle: AppStrings.guideSubtitle,
                showProgressBar: false,
                buttonText: AppStrings.guideButton,
                onButtonTap: () async {
                  final db = ref.read(appDatabaseProvider);
                  final row = await db.getCourseByFieldCourseId('EDU_ONBOARDING_APP');
                  if (row == null || !context.mounted) return;

                  final data = jsonDecode(row.data) as Map<String, dynamic>;

                  // Find matching UserCourse for progress tracking
                  final userCourses = userCoursesAsync.valueOrNull ?? [];
                  final uc = userCourses.where((u) => u.courseId == row.id).firstOrNull;

                  final course = Course.fromJsonData(
                    id: row.id,
                    data: data,
                    completedLessons: uc?.completedLessons ?? 0,
                    isCompleted: uc?.isCompleted ?? false,
                  );

                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CourseDetailPage(
                        course: course,
                        userCourseId: uc?.id,
                      ),
                    ),
                  );
                },
              ),
            ),
            // Procvičování — shown only when the FSRS queue has due cards
            // (advanced user with something to review).
            ...(() {
              final dueCount = ref.watch(dueCardsCountProvider).valueOrNull ?? 0;
              if (dueCount <= 0) return const <Widget>[];
              return [
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    AppStrings.practiceTitle,
                    style: AppTextStyles.heading1(),
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InProgressCard(
                    icon: Icons.access_time_filled,
                    iconOnRight: true,
                    title: AppStrings.practiceDueCount(dueCount),
                    subtitle: AppStrings.practiceDashSubtitle,
                    showProgressBar: false,
                    buttonText: AppStrings.practiceStart,
                    onButtonTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const PracticePage(),
                        ),
                      );
                    },
                  ),
                ),
              ];
            }()),
            const SizedBox(height: 16),
            // Promo card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: PromoCard(
                badge: AppStrings.promoBadge,
                title: AppStrings.promoTitle,
                description: AppStrings.promoDescription,
                illustrationPath: 'assets/images/card_news_bg.png',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const KnihovnaPage(),
                    ),
                  );
                },
              ),
            ),
            // Rychlé kvízy — show downloaded courses
            ...userCoursesAsync.when(
              data: (courses) {
                if (courses.isEmpty) return [const SizedBox.shrink()];

                // Hide only_once courses from dashboard
                final visibleCourses = courses
                    .where((uc) =>
                        uc.courseData?['only_once'] != true)
                    .toList();
                if (visibleCourses.isEmpty) return [const SizedBox.shrink()];

                final cardColors = [
                  AppColors.cardBlue,
                  AppColors.cardLavender,
                  AppColors.cardPeach,
                  AppColors.cardPeachDark,
                  AppColors.successBg,
                ];

                // Rychlé kvízy: courses with exercise blocks where
                // all lessons are completed (or only_quiz flag allows
                // running quiz without completing lessons first).
                final quizCourses = visibleCourses.where((uc) {
                  if (uc.isCompleted) return false;
                  final data = uc.courseData;
                  if (data == null) return false;
                  final blocks = data['blocks'] as List<dynamic>?;
                  if (blocks == null || blocks.isEmpty) return false;

                  // Must have at least one exercise/question block
                  final hasExercise = blocks.any((b) {
                    final type = (b as Map<String, dynamic>)['type'] as String?;
                    return type == 'exercise' || type == 'question' || type == 'quiz';
                  });
                  if (!hasExercise) return false;

                  // Quiz can run if only_quiz flag is set OR all lessons done
                  final onlyQuiz = data['only_quiz'] as bool? ?? false;
                  if (onlyQuiz) return true;
                  return uc.totalLessons > 0 &&
                      uc.completedLessons >= uc.totalLessons;
                }).toList();

                final quizCards = quizCourses.map((uc) {
                  final data = uc.courseData ?? {};
                  final emoji = data['emoji'] as String? ?? '📖';
                  final colorIdx = quizCourses.indexOf(uc) % cardColors.length;

                  return CourseCard(
                    iconWidget: Text(emoji, style: const TextStyle(fontSize: 32)),
                    iconBackgroundColor: cardColors[colorIdx].withValues(alpha: 0.48),
                    title: uc.courseName ?? AppStrings.defaultCourseName,
                    badge: AppStrings.sectionQuickQuizzes,
                    metaItems: [
                      CardMetaItem(
                        icon: Icons.quiz_outlined,
                        iconColor: AppColors.progressFill,
                        label: '${(data['blocks'] as List<dynamic>? ?? []).where((b) {
                          final t = (b as Map<String, dynamic>)['type'] as String?;
                          return t == 'exercise' || t == 'question' || t == 'quiz';
                        }).length}',
                      ),
                    ],
                    onTap: () {
                      if (data.isNotEmpty) {
                        final course = Course.fromJsonData(
                          id: uc.courseId,
                          data: data,
                          completedLessons: uc.completedLessons,
                          isCompleted: uc.isCompleted,
                        );
                        final questionBlocks = course.getAllQuestionBlocks();
                        if (questionBlocks.isEmpty) return;
                        final progress = quizProgressCache.putIfAbsent(
                          course.id, () => QuizProgress());
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => QuizPage(
                              questionBlocks: questionBlocks,
                              courseTitle: course.title,
                              courseId: course.id,
                              evaluate: course.quizEvaluate,
                              onlyOnce: course.onlyOnce,
                              progress: progress,
                            ),
                          ),
                        );
                      }
                    },
                  );
                }).toList();

                // Pokračovat — courses with any recorded progress that aren't
                // yet completed. Uses UserCourse.hasStarted (not just
                // completedLessons) so block/quiz-based courses, which never
                // increment completedLessons, still appear here instead of
                // falling through both sections (BR-ZBW7TB).
                final inProgressCourses = visibleCourses
                    .where((uc) =>
                        uc.hasStarted &&
                        uc.courseData != null &&
                        // only_quiz courses live in "Rychlé kvízy"; don't
                        // duplicate them here.
                        uc.courseData?['only_quiz'] != true)
                    .toList();

                return [
                  if (quizCards.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    CardSection(
                      title: AppStrings.sectionQuickQuizzes,
                      carouselHeight: 200,
                      cards: quizCards,
                    ),
                  ],
                  if (inProgressCourses.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    CardSection(
                      title: AppStrings.sectionContinue,
                      carouselHeight: 220,
                      cards: inProgressCourses.map((uc) {
                        final data = uc.courseData!;
                        final emoji = data['emoji'] as String? ?? '📖';
                        final description = data['description'] as String?;
                        final colorIdx = inProgressCourses.indexOf(uc) % cardColors.length;

                        return CourseCard(
                          iconWidget: Text(emoji, style: const TextStyle(fontSize: 32)),
                          iconBackgroundColor: cardColors[colorIdx].withValues(alpha: 0.48),
                          title: uc.courseName ?? AppStrings.defaultCourseName,
                          description: description,
                          onTap: () {
                            final course = Course.fromJsonData(
                              id: uc.courseId,
                              data: data,
                              completedLessons: uc.completedLessons,
                              isCompleted: uc.isCompleted,
                            );
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CourseDetailPage(
                                  course: course,
                                  userCourseId: uc.id,
                                ),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ];
              },
              loading: () => [const SizedBox.shrink()],
              error: (_, __) => [const SizedBox.shrink()],
            ),
          // Bottom padding to account for bottom nav
          const SizedBox(height: 120),
        ],
      ),
    );
  }
}
