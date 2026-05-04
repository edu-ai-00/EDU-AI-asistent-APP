import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/providers/core_providers.dart';
import '../core/util/drag_scroll_behavior.dart';
import '../core/util/silent_log.dart';
import '../data/repositories/user_course_repository.dart';
import '../models/course_model.dart';
import '../widgets/widgets.dart';
import 'course_detail_page.dart';
import 'knihovna_page.dart';

class KurzyPage extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToLibrary;

  const KurzyPage({super.key, this.onNavigateToLibrary});

  @override
  ConsumerState<KurzyPage> createState() => _KurzyPageState();
}

class _KurzyPageState extends ConsumerState<KurzyPage> {
  int _selectedFilterIndex = 0;
  final Set<String> _hydrationAttempts = <String>{};
  final List<String> _filters = [AppStrings.filterAll, AppStrings.filterInProgress, AppStrings.filterNotStarted, AppStrings.filterCompleted];

  /// Trigger an R2 download for a course whose data column is empty. Runs
  /// at most once per courseId per page lifetime; the StreamProvider will
  /// rebuild the list once data lands and `lessons` becomes non-null.
  void _ensureCourseDataDownloaded(String localCourseId) {
    if (!_hydrationAttempts.add(localCourseId)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await ref
            .read(courseRepositoryProvider)
            .downloadFullCourseJson(localCourseId);
      } catch (e, st) {
        silentLog('kurzy:hydrate', e, st);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final userCoursesAsync = ref.watch(userCoursesStreamProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        // Header row: Title, Search, Settings
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                AppStrings.kurzyTitle,
                  style: AppTextStyles.heading2Bold(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Filter chips
          FilterChipRow(
            labels: _filters,
            selectedIndex: _selectedFilterIndex,
            onSelected: (index) {
              setState(() {
                _selectedFilterIndex = index;
              });
            },
          ),
          const SizedBox(height: 16),
          // Course list
          Expanded(
            child: ScrollConfiguration(
              behavior: const DragScrollBehavior(),
              child: RefreshIndicator(
                onRefresh: _refreshCourses,
                child: userCoursesAsync.when(
                data: (userCourses) {
                  // Filter courses based on selected filter
                  // Hide only_once courses from listing
                  final visibleCourses = userCourses
                      .where((uc) =>
                          uc.courseData?['only_once'] != true)
                      .toList();
                  final filteredCourses = _filterCourses(visibleCourses);

                  if (filteredCourses.isEmpty) {
                    // Wrap empty state in scrollable so pull-to-refresh still works.
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: _buildEmptyState(),
                        ),
                      ],
                    );
                  }

                  return ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    itemCount: filteredCourses.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final userCourse = filteredCourses[index];
                      return _buildCourseCard(userCourse);
                    },
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.6,
                      child: Center(
                        child: Text(AppStrings.genericError(error.toString())),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),
        ],
    );
  }

  Future<void> _refreshCourses() async {
    try {
      // Trigger full sync (push pending + pull server state).
      await ref.read(syncServiceProvider).sync();
    } catch (e, st) {
      silentLog('kurzy:refresh', e, st);
    }
    // Stream provider rebuilds when local DB changes during sync; no manual
    // invalidate needed.
  }

  List<UserCourse> _filterCourses(List<UserCourse> courses) {
    switch (_selectedFilterIndex) {
      case 1: // Probíhající
        return courses.where((c) => c.status == UserCourseStatus.inProgress).toList();
      case 2: // Nezahájené
        return courses.where((c) => c.status == UserCourseStatus.downloaded).toList();
      case 3: // Dokončeno
        return courses.where((c) {
          if (c.status == UserCourseStatus.completed) return true;
          // Quiz-only courses: completed if quiz_completed flag is set
          final isQuizOnly = (c.courseData ?? {})['only_quiz'] == true;
          return isQuizOnly && c.progressData['quiz_completed'] == true;
        }).toList();
      default: // Všechny
        return courses;
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('📚', style: TextStyle(fontSize: 36)),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppStrings.kurzyEmptyTitle,
              style: AppTextStyles.heading4(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.kurzyEmptySubtitle,
              style: AppTextStyles.body(color: AppColors.primaryDark64),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () {
                if (widget.onNavigateToLibrary != null) {
                  widget.onNavigateToLibrary!();
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const KnihovnaPage(),
                    ),
                  );
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: AppDecorations.radiusM,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.32),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.library_books_rounded,
                      color: AppColors.surface,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.kurzyExploreLibrary,
                      style: AppTextStyles.statValueAlt(color: AppColors.surface),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseCard(UserCourse userCourse) {
    // Extract course data
    final courseData = userCourse.courseData ?? {};
    final emoji = courseData['emoji'] as String? ?? '📖';
    final description = courseData['description'] as String?;
    final badge = courseData['badge'] as String?;
    final lessons = courseData['lessons'] as List<dynamic>?;
    final lessonCount = lessons?.length ?? userCourse.totalLessons;

    // Estimate duration (about 20 minutes per lesson)
    final durationHours = (lessonCount * 20 / 60).ceil();

    // Calculate block-level progress (same as course_detail_page)
    int totalBlocks = 0;
    int completedBlocks = 0;
    if (lessons != null) {
      for (final l in lessons) {
        final lesson = l as Map<String, dynamic>;
        final blocks = lesson['blocks'] as List<dynamic>?;
        totalBlocks += blocks?.length ?? 0;
      }
    }
    final lessonsProgress = userCourse.progressData['lessons'] as Map<String, dynamic>?;
    if (lessonsProgress != null) {
      for (final entry in lessonsProgress.values) {
        final lessonData = entry as Map<String, dynamic>?;
        final completed = lessonData?['completed_blocks'] as List<dynamic>?;
        completedBlocks += completed?.length ?? 0;
      }
    }

    // Quiz-only detection and effective status/progress
    final isQuizOnly = courseData['only_quiz'] == true;
    final quizCompleted = userCourse.progressData['quiz_completed'] == true;

    // Map status (with quiz-only override)
    CourseStatus status;
    if (isQuizOnly && quizCompleted) {
      status = CourseStatus.completed;
    } else {
      switch (userCourse.status) {
        case UserCourseStatus.inProgress:
          status = CourseStatus.inProgress;
          break;
        case UserCourseStatus.completed:
          status = CourseStatus.completed;
          break;
        default:
          status = CourseStatus.notStarted;
      }
    }

    // For quiz-only courses, show 1/1 when completed
    final effectiveCurrentProgress = isQuizOnly ? (quizCompleted ? 1 : 0) : completedBlocks;
    final effectiveTotalProgress = isQuizOnly ? 1 : totalBlocks;

    // Title resolution order:
    //   1. name embedded in the full course payload (R2 JSON)
    //   2. local courses.name column (kept in sync from API)
    //   3. catalog course_id (e.g. "ZS_MAT_ZLOMKY_5") — better than nothing
    //   4. generic placeholder
    // Only the local FK UUID is treated as garbage (legacy code-entry rows).
    final courseDataName = (courseData['name'] as String?)?.trim();
    final localName = (userCourse.courseName ?? '').trim();
    final catalogId = (userCourse.catalogCourseId ?? '').trim();
    final cleanLocalName =
        (localName.isEmpty || localName == userCourse.courseId)
            ? null
            : localName;
    final resolvedTitle = (courseDataName?.isNotEmpty ?? false)
        ? courseDataName!
        : (cleanLocalName ??
            (catalogId.isNotEmpty ? catalogId : AppStrings.defaultCourseName));

    // Auto-hydrate: if course payload missing (no lessons), kick off an R2
    // download in the background so name + total lesson count populate.
    if (lessons == null) {
      _ensureCourseDataDownloaded(userCourse.courseId);
    }

    return KurzyCourseCard(
      iconWidget: Text(emoji, style: const TextStyle(fontSize: 28)),
      iconBackgroundColor: AppColors.surfaceLight.withValues(alpha: 0.48),
      title: resolvedTitle,
      description: description,
      badge: badge,
      lessonCount: lessonCount,
      durationHours: durationHours,
      currentProgress: effectiveCurrentProgress,
      totalProgress: effectiveTotalProgress,
      status: status,
      isBookmarked: false,
      hasUpdate: userCourse.hasUpdate,
      onTap: () {
        // Always navigate. If full course data is missing the detail page
        // will hydrate it; meanwhile we pass the best-known title so the
        // app bar isn't blank.
        final course = Course.fromJsonData(
          id: userCourse.courseId,
          data: courseData,
          completedLessons: userCourse.completedLessons,
          isCompleted: userCourse.isCompleted,
          fallbackName: resolvedTitle,
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CourseDetailPage(
              course: course,
              userCourseId: userCourse.id,
            ),
          ),
        );
      },
    );
  }
}
