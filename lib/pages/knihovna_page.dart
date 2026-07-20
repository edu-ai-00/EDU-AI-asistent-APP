import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/core_providers.dart';
import '../core/services/course_enroll_service.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/code_input_field.dart';
import '../data/repositories/course_repository.dart';
import '../models/course_model.dart' as models;
import 'course_detail_page.dart';
import '../core/strings/app_strings.dart';

/// KnihovnaPage - Library page showing all available courses.
/// Users can download courses from here to add them to their Kurzy (courses) list.
class KnihovnaPage extends ConsumerStatefulWidget {
  /// Called when back button is tapped and there's no route to pop.
  /// Used when KnihovnaPage is embedded as a tab to navigate home.
  final VoidCallback? onBack;

  const KnihovnaPage({super.key, this.onBack});

  @override
  ConsumerState<KnihovnaPage> createState() => _KnihovnaPageState();
}

class _KnihovnaPageState extends ConsumerState<KnihovnaPage> {
  final Set<String> _downloadingCourses = {};
  final Set<String> _updatingCourses = {};
  /// Maps course ID to downloaded version for comparison.
  final Map<String, int> _downloadedVersions = {};
  final Map<String, ({int completed, int total})> _courseProgress = {};

  // 6-char course code input — single field rendered as boxes
  final CodeInputController _codeController = CodeInputController();
  bool _isLookingUpCode = false;
  String? _codeError;

  @override
  void initState() {
    super.initState();
    _loadDownloadedCourses();
    // Auto-refresh courses from API so the list isn't empty on first open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshCourses();
    });
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  String get _pin => _codeController.code;

  void _onCodeChanged(String value) {
    // Only clear the error while the user is actively typing. A programmatic
    // clear after an invalid submit empties the field and fires onChanged('')
    // synchronously — it must NOT wipe the just-set error, or the code silently
    // disappears with no feedback (BR-ANKRJP).
    if (value.isEmpty) return;
    if (_codeError != null) {
      setState(() => _codeError = null);
    }
  }

  void _clearPin() => _codeController.clear();

  /// Lookup and download course by code, then navigate to it.
  ///
  /// Delegates the resolve+enroll+download steps to the shared
  /// [enrollCourseByCode] service so the manual code input and the /course|/pin
  /// deep links behave identically; this method only maps the outcome to the
  /// input's error text and navigates on success.
  Future<void> _lookupCourseByCode() async {
    final code = _pin;
    if (code.length < 6) {
      setState(() => _codeError = AppStrings.libraryCodeShort);
      return;
    }

    setState(() {
      _isLookingUpCode = true;
      _codeError = null;
    });

    final outcome = await enrollCourseByCode(ref, code);
    if (!mounted) return;

    if (!outcome.isSuccess) {
      setState(() {
        _isLookingUpCode = false;
        _codeError = _enrollErrorText(outcome);
      });
      _clearPin();
      return;
    }

    _clearPin();
    setState(() {
      _isLookingUpCode = false;
      _downloadedVersions[outcome.course!.id] =
          outcome.downloadedVersion ?? _downloadedVersions[outcome.course!.id] ?? 0;
    });

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailPage(
          course: outcome.course!,
          userCourseId: outcome.userCourseId,
        ),
      ),
    );
  }

  String _enrollErrorText(EnrollOutcome outcome) {
    switch (outcome.error) {
      case EnrollErrorKind.codeShort:
        return AppStrings.libraryCodeShort;
      case EnrollErrorKind.notFound:
        return AppStrings.libraryCodeNotFound(outcome.code);
      case EnrollErrorKind.loginRequired:
        return AppStrings.libraryLoginRequired;
      case EnrollErrorKind.alreadyCompleted:
        return AppStrings.libraryCourseAlreadyCompleted;
      case EnrollErrorKind.loadError:
        return AppStrings.libraryLoadError;
      case EnrollErrorKind.generic:
      case null:
        return AppStrings.genericError(outcome.message ?? '');
    }
  }

  Future<void> _refreshCourses() async {
    final repository = ref.read(courseRepositoryProvider);
    await repository.refreshCourses();
  }

  Future<void> _loadDownloadedCourses() async {
    final db = ref.read(appDatabaseProvider);
    final user = await db.getActiveUser();
    if (user == null) return;

    final userCourses = await db.getUserCourses(user.id);
    setState(() {
      _downloadedVersions.clear();
      _courseProgress.clear();
      for (final uc in userCourses) {
        _downloadedVersions[uc.courseId] = uc.downloadedVersion;
        _courseProgress[uc.courseId] = (
          completed: uc.completedLessons,
          total: uc.totalLessons,
        );
      }
    });
  }

  Future<void> _downloadCourse(Course course) async {
    final db = ref.read(appDatabaseProvider);
    final userCourseRepo = ref.read(userCourseRepositoryProvider);
    final courseRepo = ref.read(courseRepositoryProvider);
    final user = await db.getActiveUser();

    if (user == null) {
      // No active user means the session was wiped (e.g. shared-device
      // inactivity logout). Return to login cleanly instead of stranding the
      // user on a library page that can never download.
      ref.read(logoutCoordinatorProvider).forceLogoutToLogin();
      return;
    }

    // Block guests from logged_only courses.
    // Allow only real accounts: a user with an email OR a server-authenticated
    // student PIN login (flagged locally via isEmailValidated). Guests hold a
    // Sanctum token too, so token presence must NOT count as logged in
    // (BR-N2ENN4).
    if (course.data['logged_only'] == true &&
        user.email.isEmpty &&
        !user.isEmailValidated) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.authLoginRequired),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return;
    }

    if (!mounted) return;

    setState(() {
      _downloadingCourses.add(course.id);
    });

    try {
      // Step 1: Add course to user's library
      await userCourseRepo.startCourse(
        userId: user.id,
        courseId: course.id,
      );

      // Step 2: Download full course JSON from R2 (with lesson details)
      final success = await courseRepo.downloadFullCourseJson(course.id);

      if (!success) {
        if (mounted) {
          setState(() {
            _downloadingCourses.remove(course.id);
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.libraryCourseDownloadFailed(course.name)),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      // Step 3: Update downloadedVersion in user_courses to mark it as
      // fully downloaded and trigger the Kurzy stream to refresh.
      // Read version from DB — downloadFullCourseJson may have bumped it.
      final courseRow = await db.getCourseById(course.id);
      final actualVersion = courseRow?.version ?? course.version;
      final userCourse = await db.getUserCourseByUserAndCourse(user.id, course.id);
      if (userCourse != null) {
        await db.updateUserCourseDownloadedVersion(
          id: userCourse.id,
          downloadedVersion: actualVersion,
        );
      }

      if (mounted) {
        setState(() {
          _downloadedVersions[course.id] = actualVersion;
          _downloadingCourses.remove(course.id);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.libraryCourseAdded(course.name)),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadingCourses.remove(course.id);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.libraryCourseDownloadError('$e')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _updateCourse(Course course) async {
    final db = ref.read(appDatabaseProvider);
    final userCourseRepo = ref.read(userCourseRepositoryProvider);
    final courseRepo = ref.read(courseRepositoryProvider);
    final user = await db.getActiveUser();

    if (user == null) return;

    setState(() {
      _updatingCourses.add(course.id);
    });

    try {
      // Get the user course entry
      final userCourse = await db.getUserCourseByUserAndCourse(user.id, course.id);
      if (userCourse == null) return;

      // Re-download full course JSON from R2 (with new lesson details)
      await courseRepo.downloadFullCourseJson(course.id);

      // Read version from DB — downloadFullCourseJson may have bumped it.
      final courseRow = await db.getCourseById(course.id);
      final actualVersion = courseRow?.version ?? course.version;

      // Update the downloaded version in user_courses
      await db.updateUserCourseDownloadedVersion(
        id: userCourse.id,
        downloadedVersion: actualVersion,
      );

      if (mounted) {
        setState(() {
          _downloadedVersions[course.id] = actualVersion;
          _updatingCourses.remove(course.id);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.libraryCourseUpdated(course.name)),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _updatingCourses.remove(course.id);
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppStrings.libraryCourseUpdateError('$e')),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _openCourse(Course course) async {
    final courseRepo = ref.read(courseRepositoryProvider);
    final db = ref.read(appDatabaseProvider);
    final user = await db.getActiveUser();

    // Check for a newer version on the API before opening (non-blocking on failure)
    await courseRepo.checkAndUpdateCourseVersion(course.id);
    if (!mounted) return;

    final fullCourse = await courseRepo.getCourseById(course.id);
    if (fullCourse == null || !mounted) return;

    // Block guests from logged_only courses.
    // Allow only real accounts: a user with an email OR a server-authenticated
    // student PIN login (flagged locally via isEmailValidated). Guests hold a
    // Sanctum token too, so token presence must NOT count as logged in
    // (BR-N2ENN4).
    if (fullCourse.data['logged_only'] == true) {
      final activeUser = user ?? await db.getActiveUser();
      if (activeUser == null ||
          (activeUser.email.isEmpty && !activeUser.isEmailValidated)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppStrings.authLoginRequired),
            ),
          );
        }
        return;
      }
    }

    final userCourse = user != null
        ? await db.getUserCourseByUserAndCourse(user.id, course.id)
        : null;

    final courseModel = models.Course.fromJsonData(
      id: fullCourse.id,
      data: fullCourse.data,
      completedLessons: userCourse?.completedLessons ?? 0,
      isCompleted: userCourse?.status == 'completed',
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailPage(
          course: courseModel,
          userCourseId: userCourse?.id,
        ),
      ),
    );
    // Refresh downloaded versions when returning (progress may have changed)
    if (mounted) {
      _loadDownloadedCourses();
    }
  }

  @override
  Widget build(BuildContext context) {
    final coursesAsync = ref.watch(coursesStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      // MainScreen's outer Scaffold already resizes for the keyboard.
      // Letting this inner Scaffold resize too double-counts the keyboard
      // inset, squeezing the code-input card off-screen.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Back button
                  GestureDetector(
                    onTap: () {
                      if (Navigator.of(context).canPop()) {
                        Navigator.of(context).pop();
                      } else if (widget.onBack != null) {
                        widget.onBack!();
                      }
                    },
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
                  const SizedBox(width: 16),
                  Text(
                    AppStrings.libraryTitle,
                    style: AppTextStyles.heading2Bold(),
                  ),
                  const Spacer(),
                  // Search button
                  Container(
                    width: 48,
                    height: 48,
                    decoration: AppDecorations.circleButton,
                    child: Icon(
                      Icons.search,
                      color: AppColors.primaryDark,
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Subtitle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                AppStrings.librarySubtitle,
                style: AppTextStyles.body(color: AppColors.primaryDark64),
              ),
            ),
            const SizedBox(height: 16),
            // Course list (code input section scrolls with it)
            Expanded(
              child: coursesAsync.when(
                data: (courses) {
                  // Only show published courses (hide private courses — they are PIN-only)
                  final publishedCourses = courses
                      .where((c) => c.status == 'published')
                      .where((c) => c.data['private'] != true)
                      .toList();

                  if (publishedCourses.isEmpty) {
                    return RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: _refreshCourses,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: _buildCodeInputSection(),
                            ),
                            SizedBox(
                              height: MediaQuery.of(context).size.height * 0.4,
                              child: _buildEmptyState(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  // +1 for the code input section at the top
                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _refreshCourses,
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                      itemCount: publishedCourses.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _buildCodeInputSection(),
                          );
                        }
                        final course = publishedCourses[index - 1];
                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index < publishedCourses.length ? 12 : 0,
                          ),
                          child: _buildCourseCard(course),
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stack) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 48,
                          color: AppColors.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          AppStrings.libraryCoursesLoadError,
                          style: AppTextStyles.cardTitleSmall(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error.toString(),
                          style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCodeInputSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDecorations.radiusM,
        boxShadow: AppDecorations.shadowLight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.libraryCodeTitle,
            style: AppTextStyles.statValueAlt(),
          ),
          const SizedBox(height: 12),
          // 6-char course code input — single field rendered as boxes
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: CodeInputField(
              length: 6,
              controller: _codeController,
              autofocus: false,
              hasError: _codeError != null,
              onChanged: _onCodeChanged,
              onCompleted: (_) {
                if (!_isLookingUpCode) _lookupCourseByCode();
              },
            ),
          ),
          // Error message
          if (_codeError != null) ...[
            const SizedBox(height: 8),
            Text(
              _codeError!,
              style: AppTextStyles.caption(color: AppColors.error),
            ),
          ],
          // Loading indicator
          if (_isLookingUpCode) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppStrings.librarySearchingCourse,
                  style: AppTextStyles.bodySmall(color: AppColors.primary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
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
              AppStrings.libraryEmptyTitle,
              style: AppTextStyles.heading4(),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.libraryEmptySubtitle,
              style: AppTextStyles.body(color: AppColors.primaryDark64),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCourseCard(Course course) {
    final downloadedVersion = _downloadedVersions[course.id];
    // downloadedVersion == 0 means synced from server but not locally downloaded
    final isDownloaded = downloadedVersion != null && downloadedVersion > 0;
    final hasUpdate = isDownloaded && course.version > downloadedVersion;
    final isDownloading = _downloadingCourses.contains(course.id);
    final isUpdating = _updatingCourses.contains(course.id);

    // Debug: print course info

    // Extract data from course
    final data = course.data;
    final emoji = data['emoji'] as String? ?? '📖';
    final description = data['description'] as String?;
    final badge = data['badge'] as String?;
    final lessons = data['lessons'] as List<dynamic>?;
    // Fall back to the denormalized lesson_count from the listing API when the
    // full lessons array hasn't been downloaded yet.
    final lessonCount = (lessons?.isNotEmpty ?? false)
        ? lessons!.length
        : (data['lesson_count'] as int? ?? 0);
    // Full course JSON carries a top-level `blocks` array; the lightweight
    // listing data (not-yet-downloaded courses) only has placeholder lessons.
    final hasFullContent = (data['blocks'] as List<dynamic>?)?.isNotEmpty ?? false;
    // For downloaded courses, sum block durations (matches the course detail
    // page) so library and in-course duration agree. Otherwise fall back to the
    // listing's estimated_minutes — the placeholder lessons have no blocks and
    // would otherwise yield a bogus ~5 min/lesson estimate.
    final totalMinutes = hasFullContent
        ? models.Course.totalCourseMinutes(data)
        : (data['estimated_minutes'] as int? ?? 0);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDecorations.radiusXL,
        boxShadow: AppDecorations.shadowLight,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: Icon and badge
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight.withValues(alpha: 0.48),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 28)),
                  ),
                ),
                const Spacer(),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: AppDecorations.radiusXS,
                      border: Border.all(
                        color: AppColors.primaryDark,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: AppTextStyles.badgeSmall(),
                    ),
                  ),
                if (data['logged_only'] == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: AppDecorations.radiusXS,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 12, color: Colors.blue.shade600),
                        const SizedBox(width: 2),
                        Text(AppStrings.libraryLoginBadge, style: AppTextStyles.meta(color: Colors.blue.shade600)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Title
            Text(
              course.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.cardTitleSmall(),
            ),
            // Description
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
              ),
            ],
            const SizedBox(height: 12),
            // Bottom row: Meta info and download button
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
                  style: AppTextStyles.meta(color: AppColors.primaryDark64),
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
                  AppStrings.durationSmart(totalMinutes),
                  style: AppTextStyles.meta(color: AppColors.primaryDark64),
                ),
                const SizedBox(width: 12),
                // Version
                Text(
                  'v${course.version}',
                  style: AppTextStyles.meta(color: AppColors.primaryDark48),
                ),
                const Spacer(),
                // Download/Update/Added button
                _buildActionButton(
                  course,
                  isDownloaded: isDownloaded,
                  hasUpdate: hasUpdate,
                  isDownloading: isDownloading,
                  isUpdating: isUpdating,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(
    Course course, {
    required bool isDownloaded,
    required bool hasUpdate,
    required bool isDownloading,
    required bool isUpdating,
  }) {
    // Currently downloading or updating - show spinner
    if (isDownloading || isUpdating) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.16),
          borderRadius: AppDecorations.radiusS,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              isUpdating ? AppStrings.libraryUpdating : AppStrings.libraryDownloading,
              style: AppTextStyles.actionSmall(color: AppColors.primary),
            ),
          ],
        ),
      );
    }

    // Downloaded but update available - show update button
    if (isDownloaded && hasUpdate) {
      return GestureDetector(
        onTap: () => _updateCourse(course),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.warning,
            borderRadius: AppDecorations.radiusS,
            boxShadow: [
              BoxShadow(
                color: AppColors.warning.withValues(alpha: 0.32),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.sync_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                AppStrings.libraryUpdate,
                style: AppTextStyles.actionSmall(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    // Downloaded and up-to-date - show launch button
    if (isDownloaded) {
      return GestureDetector(
        onTap: () => _openCourse(course),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: AppDecorations.radiusS,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.play_arrow_rounded,
                size: 18,
                color: Colors.white,
              ),
              const SizedBox(width: 4),
              Text(
                AppStrings.libraryLaunch,
                style: AppTextStyles.actionSmall(color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    // Not downloaded - show download button
    return GestureDetector(
      onTap: () => _downloadCourse(course),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: AppDecorations.radiusS,
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.32),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.download_rounded,
              size: 18,
              color: Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              AppStrings.libraryDownload,
              style: AppTextStyles.actionSmall(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
