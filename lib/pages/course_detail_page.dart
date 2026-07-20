import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme/app_theme.dart';
import '../core/strings/app_strings.dart';
import '../models/course_model.dart';
import '../widgets/card_carousel.dart';
import '../widgets/course_card.dart';
import '../core/providers/core_providers.dart';
import '../core/providers/bookmark_provider.dart';
import '../data/repositories/user_course_repository.dart';
import '../main.dart' show routeObserver, countAchievementStats;
import 'lesson_detail_page.dart';
import 'exercise_page.dart';
import 'quiz_page.dart';
import 'achievements_page.dart';
import 'package:eduai/core/util/silent_log.dart';

/// Course Detail Page displaying full course information
class CourseDetailPage extends ConsumerStatefulWidget {
  final Course course;
  final String? userCourseId; // For progress tracking

  const CourseDetailPage({
    super.key,
    required this.course,
    this.userCourseId,
  });

  @override
  ConsumerState<CourseDetailPage> createState() => _CourseDetailPageState();
}

class _CourseDetailPageState extends ConsumerState<CourseDetailPage> with RouteAware {
  bool _isDescriptionExpanded = false;

  bool _isBookmarked = false;
  bool _quizStarted = false;
  bool _quizCompleted = false;
  final QuizProgress _quizProgress = QuizProgress();
  final QuizProgress _exerciseProgress = QuizProgress();
  Course? _courseOverride; // Mutable course that can be refreshed
  String? _resolvedUserCourseId; // Mutable — discovered at runtime if widget.userCourseId is null

  // Block-level progress tracking
  int _totalBlocks = 0;
  int _completedBlocks = 0;
  bool _isCourseCompleted = false;

  // Cvičení filtering: only show completed default_practice blocks
  Set<String> _completedBlockIds = {};
  Set<String> _removedPracticeBlocks = {};

  // Course update state
  bool _hasUpdate = false;
  bool _isUpdating = false;

  Course get _course => _courseOverride ?? widget.course;

  /// Best-known userCourseId — from widget or discovered at runtime.
  String? get _userCourseId => _resolvedUserCourseId ?? widget.userCourseId;

  /// Whether the initial quiz is required and not yet completed.
  bool get _quizRequired => _course.startsWithQuiz && !_quizCompleted;

  /// Whether this is a quiz-only course (no lessons shown).
  bool get _isOnlyQuiz => _course.onlyQuiz;

  /// Label for the quiz button based on current state.
  String get _quizButtonLabel => _quizStarted ? AppStrings.courseContinueQuiz : AppStrings.courseStartQuiz;

  /// Lessons that actually have blocks — skip empty ones.
  List<Lesson> get _nonEmptyLessons {
    if (!_course.hasBlockV2Data) return _course.lessons;
    return _course.lessons
        .where((l) => _course.getBlocksForLesson(l.id).isNotEmpty)
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _isBookmarked = widget.course.isBookmarked;
    _calculateTotalBlocks();
    // Load progress data after init, then check for updates
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCourseProgress().then((_) => _checkForUpdate());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  /// Called when a route that was pushed on top of this one is popped,
  /// making this page visible again. Handles the case where lesson pages
  /// use pushReplacement (which resolves the original push Future early).
  @override
  void didPopNext() {
    _refreshCourseProgress();
  }

  /// Calculate total blocks across all lessons
  void _calculateTotalBlocks() {
    _totalBlocks = _course.lessons.fold<int>(
      0,
      (sum, lesson) => sum + lesson.questionCount,
    );
  }

  /// Refresh course data from database to get updated lesson statuses
  Future<void> _refreshCourseProgress() async {
    try {
      final repository = ref.read(userCourseRepositoryProvider);
      UserCourse? userCourse;

      // Try by known ID first
      if (_userCourseId != null) {
        userCourse = await repository.getUserCourseById(_userCourseId!);
        if (userCourse != null) _resolvedUserCourseId = _userCourseId;
      }

      // Fallback: look up by course ID + active user
      if (userCourse == null) {
        final localCourseId = await _resolveLocalCourseId();
        if (localCourseId != null) {
          final db = ref.read(appDatabaseProvider);
          final user = await db.getActiveUser();
          if (user != null) {
            final row = await db.getUserCourseByUserAndCourse(user.id, localCourseId);
            if (row != null) {
              _resolvedUserCourseId = row.id;
              userCourse = await repository.getUserCourseById(row.id);
            }
          }
        }
      }

      if (userCourse == null || userCourse.courseData == null) return;

      // Count completed blocks from progress data
      int completedBlockCount = 0;
      final lessonsProgress = userCourse.progressData['lessons'] as Map<String, dynamic>?;
      if (lessonsProgress != null) {
        for (final entry in lessonsProgress.entries) {
          final lessonData = entry.value as Map<String, dynamic>?;
          final completedBlocks = lessonData?['completed_blocks'] as List<dynamic>?;
          completedBlockCount += completedBlocks?.length ?? 0;
        }
      }

      // For quiz-only courses: count answered quiz questions as completed blocks
      if (completedBlockCount == 0) {
        final quizAnswers = userCourse.progressData['quiz_answers'] as Map<String, dynamic>?;
        if (quizAnswers != null) {
          completedBlockCount = quizAnswers.values
              .where((a) => a is Map && a['is_answered'] == true)
              .length;
        }
      }

      // Rebuild course with updated progress. Carry forward the best-known
      // title (set by the caller / current course) so a stale R2 payload
      // missing `name` doesn't reset the app bar to "Kurz".
      final fallbackTitle = (userCourse.courseName?.trim().isNotEmpty ?? false)
          ? userCourse.courseName!.trim()
          : _course.title;
      final updatedCourse = Course.fromJsonData(
        id: _course.id,
        data: userCourse.courseData!,
        completedLessons: userCourse.completedLessons,
        isCompleted: userCourse.status == UserCourseStatus.completed,
        isBookmarked: _isBookmarked,
        lessonsProgress: lessonsProgress,
        fallbackName: fallbackTitle,
      );

      // Extract completed block IDs + removed practice blocks for Cvičení filtering
      final completedIds = Course.extractCompletedBlockIds(userCourse.progressData);
      final removed = userCourse.progressData['removed_practice_blocks'] as List<dynamic>?;
      final removedIds = removed?.map((e) => e as String).toSet() ?? <String>{};

      if (mounted) {
        setState(() {
          _courseOverride = updatedCourse;
          _completedBlocks = completedBlockCount;
          _completedBlockIds = completedIds;
          _removedPracticeBlocks = removedIds;
          _hasUpdate = userCourse!.hasUpdate;
          _calculateTotalBlocks(); // Recalculate in case course data changed
          _isCourseCompleted = userCourse.status == UserCourseStatus.completed
              || (_completedBlocks >= _totalBlocks && _totalBlocks > 0);
        });
      }
    } catch (e, st) { silentLog('course_detail_page', e, st); }
  }

  /// Check server for a newer course version (metadata only, no download).
  /// Called once on page open. Updates local metadata so hasUpdate reflects reality.
  Future<void> _checkForUpdate() async {
    try {
      final localCourseId = await _resolveLocalCourseId();
      if (localCourseId == null) return;
      final courseRepo = ref.read(courseRepositoryProvider);
      await courseRepo.checkCourseVersionOnly(localCourseId);
      // Re-read userCourse to pick up the new hasUpdate value
      await _refreshCourseProgress();
    } catch (e, st) { silentLog('course_detail_page', e, st); }
  }

  /// Resolve the local DB UUID for the course.
  /// _course.id is the slug (e.g. "A2-Rovnice_c1"), but DB lookups need the
  /// UUID primary key. We read it from the user_courses.courseId column.
  Future<String?> _resolveLocalCourseId() async {
    final db = ref.read(appDatabaseProvider);
    final ucId = _resolvedUserCourseId ?? widget.userCourseId;
    if (ucId != null) {
      final uc = await db.getUserCourseById(ucId);
      if (uc != null) return uc.courseId;
    }
    // Last resort: try _course.id directly (works when id IS the UUID)
    final row = await db.getCourseById(_course.id);
    return row?.id;
  }

  /// Download the latest course content and update the local version.
  Future<void> _performUpdate() async {
    if (_isUpdating) return;

    setState(() => _isUpdating = true);

    try {
      final db = ref.read(appDatabaseProvider);
      final courseRepo = ref.read(courseRepositoryProvider);

      final ucId = _resolvedUserCourseId ?? widget.userCourseId;
      if (ucId == null) throw Exception('No user course');

      // Resolve real DB UUID — _course.id may be a slug
      final localCourseId = await _resolveLocalCourseId();
      if (localCourseId == null) throw Exception('Course not found in DB');

      // Download full content from R2
      await courseRepo.downloadFullCourseJson(localCourseId);

      // Read version AFTER download — downloadFullCourseJson step 0 may
      // have bumped courses.version via upsertFromServer.
      final courseRow = await db.getCourseById(localCourseId);
      final version = courseRow?.version ?? 1;

      // Set downloadedVersion = courses.version to clear hasUpdate.
      await db.updateUserCourseDownloadedVersion(
        id: ucId,
        downloadedVersion: version,
      );

      // Reload course data + clear _hasUpdate
      await _refreshCourseProgress();

      if (mounted) {
        setState(() {
          _isUpdating = false;
          _hasUpdate = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.libraryCourseUpdated(_course.title)),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.libraryCourseUpdateError('$e')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _navigateToCurrentLesson() {
    final lessons = _nonEmptyLessons;
    if (lessons.isEmpty) return;

    // Find the first in-progress lesson, or first non-completed lesson
    int idx = lessons.indexWhere(
      (l) => l.status == LessonStatus.inProgress,
    );

    // If no in-progress, find first non-completed
    if (idx == -1) {
      idx = lessons.indexWhere(
        (l) => l.status != LessonStatus.completed,
      );
    }

    // If all completed, go to first lesson
    if (idx == -1) idx = 0;

    _navigateToLesson(lessons[idx]);
  }

  Future<void> _navigateToLesson(Lesson lesson) async {
    // Find the real index in the full list for LessonDetailPage
    final realIndex = _course.lessons.indexOf(lesson);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => LessonDetailPage(
          course: _course,
          lesson: lesson,
          lessonIndex: realIndex >= 0 ? realIndex : 0,
          userCourseId: _userCourseId,
        ),
      ),
    );
    // Refresh course progress when returning from lesson
    if (mounted) {
      await _refreshCourseProgress();
    } else {
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Main scrollable content
          SingleChildScrollView(
            child: Column(
              children: [
                // Header with cover image
                _buildHeader(),
                // White content area (starts right after header, overlaps by 40px)
                Container(
                  transform: Matrix4.translationValues(0, -40, 0),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Course info card content
                      _buildCourseInfoCardContent(),
                      // Divider
                      _buildDivider(),
                      // Progress section
                      _buildProgressSection(),
                      // Divider
                      _buildDivider(),
                      // Description section
                      _buildDescriptionSection(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
                // Adjust for the transform
                const SizedBox(height: 0),
                // Light purple background section with top radius
                Transform.translate(
                  offset: const Offset(0, -40),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Lessons section
                        _buildLessonsSection(),
                        // Quizzes section
                        _buildQuizzesSection(),
                        // Bottom padding for action bar
                        const SizedBox(height: 120),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Fixed top navigation buttons
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _buildNavigationButtons(),
          ),
          // Bottom action bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _buildBottomActionBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 280,
      decoration: BoxDecoration(
        gradient: AppColors.headerGradient,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Text(
            _course.iconEmoji,
            style: const TextStyle(fontSize: 120),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Back button
            _buildCircleButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.pop(context),
            ),
            const Spacer(),
            // Bookmark + menu button hidden (TODO: re-enable when ready)
          ],
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: AppDecorations.circleButton,
        child: Icon(
          icon,
          color: AppColors.primaryDark,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildDivider({double topPadding = 32, double bottomPadding = 27}) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, topPadding, 24, bottomPadding),
      child: Container(
        height: 2,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  Widget _buildCourseInfoCardContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              _course.title,
              style: AppTextStyles.heading1(),
            ),
            const SizedBox(height: 4),
            // Subtitle
            Text(
              _course.subtitle,
              style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
            ),
            const SizedBox(height: 12),
            // Meta info row
            Row(
              children: [
                Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: AppColors.primaryDark48,
                ),
                const SizedBox(width: 4),
                Text(
                  AppStrings.lessonsCount(_course.lessonCount),
                  style: AppTextStyles.meta(color: AppColors.primaryDark64),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: AppColors.primaryDark48,
                ),
                const SizedBox(width: 4),
                Text(
                  AppStrings.durationSmart(_course.durationMinutes),
                  style: AppTextStyles.meta(color: AppColors.primaryDark64),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Tags row + skills button
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (_course.badge.isNotEmpty) _buildBadge(_course.badge),
                      if (_course.difficulty.isNotEmpty) _buildBadge(_course.difficulty),
                      if (_isCourseCompleted) _buildCompletedBadge(),
                    ],
                  ),
                ),
                _buildSkillsButton(),
              ],
            ),
          ],
        ),
    );
  }

  Widget _buildBadge(String text) {
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
        text,
        style: AppTextStyles.badgeSmall(),
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
            AppStrings.courseCompleted,
            style: AppTextStyles.badgeSmall(color: AppColors.success),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsButton() {
    return GestureDetector(
      onTap: _navigateToSkills,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.quizPurple,
          borderRadius: AppDecorations.radiusS,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insights,
              size: 16,
              color: AppColors.surface,
            ),
            const SizedBox(width: 6),
            Text(
              AppStrings.achievementsSkills,
              style: AppTextStyles.badgeSmall(color: AppColors.surface),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToSkills() async {
    final stats = ref.read(userStatsProvider).valueOrNull;
    final config = ref.read(gamificationConfigProvider).valueOrNull;
    final earnedIds = ref.read(earnedAchievementsProvider).valueOrNull ?? <String>[];

    ref.invalidate(skillDisplayProvider);
    final skills = await ref.read(skillDisplayProvider.future);

    // Count lessons/courses/quizzes from user courses
    final userCourses = ref.read(userCoursesStreamProvider).valueOrNull ?? [];
    final counts = countAchievementStats(userCourses);

    if (!mounted) return;
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
          scrollToSkills: true,
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.courseProgress,
            style: AppTextStyles.cardTitle(),
          ),
          const SizedBox(height: 12),
          _buildProgressBar(),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    // Calculate progress based on completed blocks
    final progress = _isCourseCompleted ? 1.0
        : _totalBlocks > 0 ? _completedBlocks / _totalBlocks : 0.0;
    final Color progressColor =
        _isCourseCompleted ? AppColors.success : AppColors.progressFill;

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
              if (progressWidth > 0)
                Container(
                  width: progressWidth.clamp(40.0, constraints.maxWidth), // Minimum width to show text
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
                            '$_completedBlocks/$_totalBlocks',
                            style: AppTextStyles.actionText(color: Colors.white),
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

  Widget _buildDescriptionSection() {
    final descriptionStyle = AppTextStyles.bodySmall(color: AppColors.primaryDark64).copyWith(
      height: 1.5,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.courseDescription,
            style: AppTextStyles.cardTitle(),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              // Measure if text would overflow at 3 lines
              final textSpan = TextSpan(
                text: _course.description,
                style: descriptionStyle,
              );
              final textPainter = TextPainter(
                text: textSpan,
                maxLines: 3,
                textDirection: TextDirection.ltr,
              );
              textPainter.layout(maxWidth: constraints.maxWidth);
              final needsExpansion = textPainter.didExceedMaxLines;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _course.description,
                    maxLines: _isDescriptionExpanded ? null : 3,
                    overflow: _isDescriptionExpanded ? null : TextOverflow.ellipsis,
                    style: descriptionStyle,
                  ),
                  // Only show expand button if text actually overflows
                  if (needsExpansion) ...[
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isDescriptionExpanded = !_isDescriptionExpanded;
                        });
                      },
                      child: Container(
                        height: 28,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: AppDecorations.radiusXS,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Transform.rotate(
                              angle: _isDescriptionExpanded ? -1.5708 : 1.5708,
                              child: Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: AppColors.primaryDark,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _isDescriptionExpanded ? AppStrings.courseShowLess : AppStrings.courseShowMore,
                              style: AppTextStyles.actionText(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLessonsSection() {
    // Hide lessons entirely for quiz-only courses
    if (_isOnlyQuiz) return const SizedBox.shrink();

    final lessons = _nonEmptyLessons;

    // Show error state when course has no lessons (corrupted/incomplete download)
    if (lessons.isEmpty) {
      return _buildCorruptedCourseNotice();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 32),
          Text(
            AppStrings.courseLessons,
            style: AppTextStyles.heading1(),
          ),
          const SizedBox(height: 16),
          // Update required banner
          if (_hasUpdate) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.10),
                borderRadius: AppDecorations.radiusM,
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.32),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.warning, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      AppStrings.courseUpdateRequired,
                      style: AppTextStyles.bodySmall(color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Quiz-first button when quiz is required
          if (_quizRequired) ...[
            _buildStartQuizCard(),
            const SizedBox(height: 12),
          ],
          // Lesson cards
          for (int i = 0; i < lessons.length; i++) ...[
            _buildLessonCard(lessons[i], i),
            if (i < lessons.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildCorruptedCourseNotice() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const SizedBox(height: 32),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppDecorations.radiusL,
              border: Border.all(
                color: AppColors.warning.withValues(alpha: 0.32),
                width: 1,
              ),
              boxShadow: AppDecorations.shadowLight,
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.warning,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.courseCorruptedTitle,
                  style: AppTextStyles.cardTitleSmall(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.courseCorruptedMessage,
                  style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.warning,
                      borderRadius: AppDecorations.radiusM,
                    ),
                    child: Text(
                      AppStrings.courseBack,
                      style: AppTextStyles.statValueAlt(color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonCard(Lesson lesson, int index) {
    Color iconBgColor;
    String iconPath;

    switch (lesson.status) {
      case LessonStatus.completed:
        iconBgColor = AppColors.successBg;
        iconPath = 'assets/icons/check.svg';
        break;
      case LessonStatus.inProgress:
        iconBgColor = AppColors.background;
        iconPath = 'assets/icons/play.svg';
        break;
      case LessonStatus.locked:
        iconBgColor = AppColors.background;
        iconPath = 'assets/icons/lock.svg';
        break;
    }

    // Force lock all lessons when quiz is required or update is available
    if (_quizRequired || _hasUpdate) {
      iconBgColor = AppColors.background;
      iconPath = 'assets/icons/lock.svg';
    }

    final isInProgress = !_quizRequired && !_hasUpdate && lesson.status == LessonStatus.inProgress;
    final isLocked = _quizRequired || _hasUpdate || lesson.status == LessonStatus.locked;

    return GestureDetector(
      onTap: isLocked ? null : () => _navigateToLesson(lesson),
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDecorations.radiusXL,
        boxShadow: AppDecorations.shadowStrong,
      ),
      child: Row(
        children: [
          // Status icon circle
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: SvgPicture.asset(
                iconPath,
                width: 24,
                height: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          // Title and meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title row with optional AKTUALNI badge
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        lesson.title,
                        style: AppTextStyles.statValue(),
                      ),
                    ),
                    if (isInProgress) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primaryDark,
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          AppStrings.courseCurrent,
                          style: AppTextStyles.badgeTiny(),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                // Meta row
                Row(
                  children: [
                    SvgPicture.asset(
                      'assets/icons/clipboard.svg',
                      width: 16,
                      height: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppStrings.courseQuestionsCount(lesson.questionCount),
                      style: AppTextStyles.meta(color: AppColors.primaryDark64),
                    ),
                    const SizedBox(width: 12),
                    SvgPicture.asset(
                      'assets/icons/clock.svg',
                      width: 16,
                      height: 16,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      AppStrings.courseDurationMin(lesson.durationMinutes),
                      style: AppTextStyles.meta(color: AppColors.primaryDark64),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildQuizzesSection() {
    if (_course.quizzes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: CardSection(
        title: AppStrings.courseQuizzes,
        actionText: AppStrings.courseShowAll,
        onActionTap: () {
          // TODO: Navigate to all quizzes
        },
        carouselHeight: 200,
        cards: _course.quizzes.map((quiz) => CourseCard(
          iconWidget: Text(
            _course.iconEmoji,
            style: const TextStyle(fontSize: 32),
          ),
          iconBackgroundColor: _course.iconBackgroundColor.withValues(alpha: 0.48),
          title: AppStrings.courseQuizPrefix(quiz.title),
          badge: _course.badge,
          metaItems: [
            CardMetaItem(
              icon: Icons.grid_view_rounded,
              iconColor: AppColors.progressFill,
              label: '${quiz.questionCount}',
            ),
            CardMetaItem(
              icon: Icons.rocket_launch,
              iconColor: AppColors.orange,
              label: '+25 XP',
            ),
          ],
          onTap: () {
            // TODO: Navigate to quiz
          },
        )).toList(),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    // Hide action bar when course data is corrupted/empty
    if (_course.lessons.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryDark08,
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: _hasUpdate
          ? _buildUpdateBanner()
          : _isOnlyQuiz
              ? _buildQuizRequiredActionButton()
              : _quizRequired
                  ? _buildQuizRequiredActionButton()
                  : _isCourseCompleted
                      ? _buildCompletedActionButtons()
                      : _buildInProgressActionButtons(),
    );
  }

  /// Update banner shown when a newer course version is available.
  Widget _buildUpdateBanner() {
    return GestureDetector(
      onTap: _isUpdating ? null : _performUpdate,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.warning,
          borderRadius: AppDecorations.radiusM,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: _isUpdating
              ? [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    AppStrings.libraryUpdating,
                    style: AppTextStyles.statValue(color: Colors.white),
                  ),
                ]
              : [
                  Icon(Icons.system_update_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.libraryUpdate,
                    style: AppTextStyles.statValue(color: Colors.white),
                  ),
                ],
        ),
      ),
    );
  }

  /// Action buttons when course is in progress: Cviceni + Pokracovat v lekci
  Widget _buildInProgressActionButtons() {
    final bookmarkNotifier = ref.read(bookmarkProvider.notifier);
    final hasExerciseBlocks = _course.getExerciseBlocks(
      bookmarkNotifier.getBookmarksForCourse(_course.id),
      completedBlockIds: _completedBlockIds,
      removedBlockIds: _removedPracticeBlocks,
    ).isNotEmpty;
    final hasQuestions = _course.getAllQuestionBlocks().isNotEmpty;

    final continueButton = GestureDetector(
      onTap: _navigateToCurrentLesson,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: AppDecorations.radiusM,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 6),
            Text(
              AppStrings.courseActionLessons,
              style: AppTextStyles.statValue(color: Colors.white),
            ),
          ],
        ),
      ),
    );

    // All buttons in a single row
    return Row(
      children: [
        // Lekce button (primary)
        Expanded(child: continueButton),
        // Cviceni button (secondary)
        if (hasExerciseBlocks)
          const SizedBox(width: 12),
        if (hasExerciseBlocks)
          Expanded(
            child: GestureDetector(
              onTap: _navigateToExercise,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: AppDecorations.radiusM,
                  border: Border.all(
                    color: AppColors.primaryDark,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/icons/chat.svg',
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        AppColors.primaryDark,
                        BlendMode.srcIn,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.courseExercise,
                      style: AppTextStyles.statValue(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Kviz button (secondary)
        if (hasQuestions)
          const SizedBox(width: 12),
        if (hasQuestions)
          Expanded(
            child: GestureDetector(
              onTap: _navigateToQuiz,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: AppDecorations.radiusM,
                  border: Border.all(
                    color: AppColors.success,
                    width: 2,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.quiz_outlined,
                      color: AppColors.success,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.courseQuiz,
                      style: AppTextStyles.statValue(
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Action buttons when course is completed: Cviceni (bookmarked + default_practice) + Kviz (all questions)
  Widget _buildCompletedActionButtons() {
    final bookmarkNotifier = ref.read(bookmarkProvider.notifier);
    final hasExerciseBlocks = _course.getExerciseBlocks(
      bookmarkNotifier.getBookmarksForCourse(_course.id),
      completedBlockIds: _completedBlockIds,
      removedBlockIds: _removedPracticeBlocks,
    ).isNotEmpty;
    final hasQuestions = _course.getAllQuestionBlocks().isNotEmpty;

    // If neither exercise blocks nor questions exist, show "Pokračovat" to re-enter lessons
    if (!hasExerciseBlocks && !hasQuestions) {
      return GestureDetector(
        onTap: _navigateToCurrentLesson,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: AppDecorations.radiusM,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
              const SizedBox(width: 6),
              Text(
                AppStrings.courseActionLessons,
                style: AppTextStyles.statValue(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        if (hasExerciseBlocks)
          Expanded(
            child: GestureDetector(
              onTap: _navigateToExercise,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryDark,
                  borderRadius: AppDecorations.radiusM,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.bookmark_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.courseExercise,
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
              onTap: _navigateToQuiz,
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: AppDecorations.radiusM,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.quiz_outlined,
                      color: Colors.white,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStrings.courseQuiz,
                      style: AppTextStyles.statValue(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Card button prompting user to start the initial quiz
  Widget _buildStartQuizCard() {
    return GestureDetector(
      onTap: _navigateToQuiz,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: AppDecorations.radiusXL,
          boxShadow: AppDecorations.shadowStrong,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _quizButtonLabel,
                    style: AppTextStyles.statValue(color: Colors.white),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppStrings.courseQuizUnlockHint,
                    style: AppTextStyles.meta(
                      color: Colors.white.withValues(alpha: 0.64),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white.withValues(alpha: 0.64),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  /// Full-width quiz button for bottom bar when quiz is required
  Widget _buildQuizRequiredActionButton() {
    return GestureDetector(
      onTap: _navigateToQuiz,
      child: Container(
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          color: AppColors.primaryDark,
          borderRadius: AppDecorations.radiusM,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.play_arrow_rounded,
              color: Colors.white,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              _quizButtonLabel,
              style: AppTextStyles.statValue(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigate to exercise based on default_practice + bookmarked blocks
  Future<void> _navigateToExercise() async {
    final bookmarkNotifier = ref.read(bookmarkProvider.notifier);
    final exerciseBlocks = _course.getExerciseBlocks(
      bookmarkNotifier.getBookmarksForCourse(_course.id),
      completedBlockIds: _completedBlockIds,
      removedBlockIds: _removedPracticeBlocks,
    );

    if (exerciseBlocks.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.bookmark_border, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppStrings.courseNoBookmarks,
                  style: AppTextStyles.subtitle(color: Colors.white),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.primaryDark,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppDecorations.radiusS),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => QuizPage(
          questionBlocks: exerciseBlocks,
          courseTitle: _course.title,
          courseId: _course.id,
          progress: _exerciseProgress,
          onlyOnce: _course.onlyOnce,
          evaluate: true,
          isExercise: true,
          // In-lesson practice mirrors the dashboard practice UX: display
          // self-rating bar + hint on "Připomeň" + no mentor robot (BR-ZDYA83).
          selfRateDisplayBlocks: true,
        ),
      ),
    );
    if (mounted) {
      await _refreshCourseProgress();
    }
  }

  /// Navigate to quiz based on all question blocks from the course
  Future<void> _navigateToQuiz() async {
    // Get all question blocks from the course
    final questionBlocks = _course.getAllQuestionBlocks();

    if (questionBlocks.isEmpty) {
      // Show message if no questions available
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.courseNoQuestions,
            style: AppTextStyles.subtitle(color: Colors.white),
          ),
          backgroundColor: AppColors.primaryDark,
        ),
      );
      return;
    }

    // Mark quiz as started
    if (!_quizStarted) {
      setState(() => _quizStarted = true);
    }

    final completed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => QuizPage(
          questionBlocks: questionBlocks,
          courseTitle: _course.title,
          courseId: _course.id,
          progress: _quizProgress,
          evaluate: _course.quizEvaluate,
          onlyOnce: _course.onlyOnce,
        ),
      ),
    );

    // For onlyOnce courses, go back to course list after quiz completion.
    // Check BEFORE any setState to avoid rebuild-then-pop race.
    if (completed == true && _course.onlyOnce && mounted) {
      // Mark the user_course as completed so re-entry via PIN is blocked.
      if (_userCourseId != null) {
        final repository = ref.read(userCourseRepositoryProvider);
        await repository.updateProgress(
          id: _userCourseId!,
          progressPercent: 100,
        );
        // Force-sync so the completion reaches the server immediately.
        ref.read(syncServiceProvider).sync();
      }
      // Defer pop to next frame so any pending didPopNext rebuilds settle.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
      return;
    }

    // Only unlock lessons when quiz is actually completed
    if (completed == true && _course.startsWithQuiz && mounted) {
      setState(() {
        _quizCompleted = true;
      });
    }

    // Refresh progress after returning from quiz
    if (mounted) {
      await _refreshCourseProgress();
    }
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
