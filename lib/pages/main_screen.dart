import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/providers/core_providers.dart';
import '../core/providers/bookmark_provider.dart';
import '../core/services/course_enroll_service.dart';
import '../routing/deep_link.dart';
import 'course_detail_page.dart';
import '../data/repositories/user_stats_repository.dart';
import '../features/email_validation/presentation/email_validation_banner.dart';
import '../features/email_validation/providers/email_validation_providers.dart';
import '../utils/achievement_stats.dart';
import '../widgets/custom_bottom_nav.dart';
import '../widgets/shared_device_banner.dart';
import 'about_page.dart';
import 'achievements_page.dart';
import 'auth_page.dart';
import 'chaty_page.dart';
import 'edit_profile_page.dart';
import 'knihovna_page.dart';
import 'kurzy_page.dart';
import 'novinky_page.dart';
import 'prehled_page.dart';
import 'privacy_page.dart';
import 'profile_page.dart';
import 'quiz_page.dart';
import 'terms_page.dart';
import 'theme_selector_page.dart';

class MainScreen extends ConsumerStatefulWidget {
  final VoidCallback? onLogout;
  final void Function(String email)? onGuestLogin;

  const MainScreen({super.key, this.onLogout, this.onGuestLogin});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Quiz progress cache keyed by courseId — survives quiz page pop/re-push.
  final Map<String, QuizProgress> _quizProgressCache = {};

  /// Index of the Novinky (news) tab in [pages] / the bottom nav.
  static const int _newsTabIndex = 4;

  /// How often to poll the server for news while the app is in the foreground.
  /// Lightweight stand-in for push until real notifications exist.
  static const Duration _newsPollInterval = Duration(seconds: 60);

  Timer? _newsPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initBookmarks();
    _seedBundledCourses();
    // Populate the news badge on launch.
    ref.read(unreadNewsCountProvider.notifier).refresh();
    _startNewsPolling();
    // Open a course that arrived via a /course|/pin deep link, now that the app
    // is authenticated and on the main screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumePendingDeepLink());
  }

  @override
  void dispose() {
    _newsPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Foreground again — pull the latest news and resume polling.
      _refreshNews();
      _startNewsPolling();
    } else if (state == AppLifecycleState.paused) {
      // Backgrounded — stop polling to avoid needless requests.
      _newsPollTimer?.cancel();
    }
  }

  /// (Re)start the foreground news poll timer.
  void _startNewsPolling() {
    _newsPollTimer?.cancel();
    _newsPollTimer = Timer.periodic(_newsPollInterval, (_) => _refreshNews());
  }

  /// Refresh news state: update the unread badge (works on any tab) and
  /// invalidate the cached list so a visible Novinky tab refetches.
  void _refreshNews() {
    if (!mounted) return;
    ref.read(unreadNewsCountProvider.notifier).refresh();
    ref.invalidate(newsListProvider);
  }

  Future<void> _consumePendingDeepLink() async {
    final code = ref.read(pendingDeepLinkCodeProvider);
    if (code == null || code.isEmpty) return;
    // Consume once so it doesn't reopen on later rebuilds.
    ref.read(pendingDeepLinkCodeProvider.notifier).state = null;

    final outcome = await enrollCourseByCode(ref, code);
    if (!mounted) return;

    if (!outcome.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_deepLinkErrorText(outcome))),
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CourseDetailPage(
          course: outcome.course!,
          userCourseId: outcome.userCourseId,
        ),
      ),
    );
  }

  String _deepLinkErrorText(EnrollOutcome outcome) {
    switch (outcome.error) {
      case EnrollErrorKind.notFound:
        return AppStrings.libraryCodeNotFound(outcome.code);
      case EnrollErrorKind.loginRequired:
        return AppStrings.libraryLoginRequired;
      case EnrollErrorKind.alreadyCompleted:
        return AppStrings.libraryCourseAlreadyCompleted;
      case EnrollErrorKind.loadError:
        return AppStrings.libraryLoadError;
      case EnrollErrorKind.codeShort:
        return AppStrings.libraryCodeShort;
      case EnrollErrorKind.generic:
      case null:
        return AppStrings.genericError(outcome.message ?? '');
    }
  }

  Future<void> _initBookmarks() async {
    final db = ref.read(appDatabaseProvider);
    final user = await db.getActiveUser();
    if (user != null) {
      ref.read(bookmarkProvider.notifier).initForUser(user.id);
    }
  }

  Future<void> _seedBundledCourses() async {
    final courseRepo = ref.read(courseRepositoryProvider);
    final courses = await courseRepo.ensureBundledCoursesLoaded();

    // Auto-enroll the active user in bundled courses so they appear in Kurzy.
    final db = ref.read(appDatabaseProvider);
    final user = await db.getActiveUser();
    if (user == null || courses.isEmpty) return;

    final userCourseRepo = ref.read(userCourseRepositoryProvider);
    for (final course in courses) {
      final alreadyEnrolled = await userCourseRepo.hasUserCourse(user.id, course.id);
      if (!alreadyEnrolled) {
        await userCourseRepo.startCourse(userId: user.id, courseId: course.id);
      }
    }
  }

  void _onItemTapped(int index) {
    // Opening the Novinky tab: drop the cached list so it refetches and shows
    // anything published since the last fetch.
    if (index == _newsTabIndex) {
      _refreshNews();
    }
    setState(() {
      _selectedIndex = index;
    });
  }

  void openProfile() {
    final userAsync = ref.read(activeUserStreamProvider);
    final userName = userAsync.valueOrNull?.name ?? AppStrings.defaultUserName;
    final userEmail = userAsync.valueOrNull?.email ?? '';
    final avatarIndex = userAsync.valueOrNull?.avatarIndex ?? 0;
    final navigator = Navigator.of(context);

    // Get user stats from provider.
    final statsAsync = ref.read(userStatsStreamProvider);
    final stats = statsAsync.valueOrNull;

    navigator.push(
      PageRouteBuilder(
        pageBuilder: (ctx, animation, secondaryAnimation) => ProfilePage(
          userName: userName,
          userEmail: userEmail,
          avatarIndex: avatarIndex,
          isGuest: userEmail.isEmpty,
          level: stats?.level ?? 1,
          xpPoints: stats?.xpPoints ?? 0,
          coursesCount: stats?.coursesCount ?? 0,
          streakDays: stats?.streakDays ?? 1,
          achievementsCount: stats?.achievementsCount ?? 0,
          onBack: () => navigator.pop(),
          onAchievementsTap: () {
            _navigateToAchievements(navigator, stats);
          },
          onLibraryTap: () {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => const KnihovnaPage(),
              ),
            );
          },
          onAboutTap: () {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => AboutPage(
                  onFactoryReset: widget.onLogout,
                ),
              ),
            );
          },
          onTermsTap: () {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => const TermsPage(),
              ),
            );
          },
          onPrivacyTap: () {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => const PrivacyPage(),
              ),
            );
          },
          onEditProfileTap: () async {
            final result = await navigator.push<String>(
              MaterialPageRoute(
                builder: (_) => EditProfilePage(
                  userName: userName,
                  userEmail: userEmail,
                ),
              ),
            );
            return result;
          },
          onThemeTap: () {
            navigator.push(
              MaterialPageRoute(
                builder: (_) => ThemeSelectorPage(
                  onBack: () => navigator.pop(),
                ),
              ),
            );
          },
          onLogoutTap: () {
            if (userEmail.isEmpty) {
              // Guest/student — push auth page with back button
              // Student (isEmailValidated) → email/SSO form
              // Pure guest → PIN screen (can switch to email from there)
              final isStudent = userAsync.valueOrNull?.isEmailValidated ?? false;
              navigator.push(
                MaterialPageRoute(
                  builder: (_) => AuthPage(
                    startInLoginMode: isStudent,
                    onEmailSubmit: (email) {
                      // Pop all routes, then trigger email verification flow
                      navigator.popUntil((route) => route.isFirst);
                      widget.onGuestLogin?.call(email);
                    },
                    onPinLoginComplete: () {
                      navigator.popUntil((route) => route.isFirst);
                    },
                    onBack: () => navigator.pop(),
                  ),
                ),
              );
            } else {
              navigator.pop();
              widget.onLogout?.call();
            }
          },
        ),
        transitionsBuilder: (ctx, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  }

  void _navigateToAchievements(NavigatorState navigator, UserStats? stats) async {
    final config = ref.read(gamificationConfigProvider).valueOrNull;
    final earnedIds = ref.read(earnedAchievementsProvider).valueOrNull ?? <String>[];

    // Refresh skills to get latest data (may fetch from API if not synced yet).
    ref.invalidate(skillDisplayProvider);
    final skills = await ref.read(skillDisplayProvider.future);

    // Count lessons/courses/quizzes from user courses
    final userCourses = ref.read(userCoursesStreamProvider).valueOrNull ?? [];
    final counts = countAchievementStats(userCourses);

    if (!mounted) return;
    navigator.push(
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
  Widget build(BuildContext context) {
    final showBanner = ref.watch(showEmailValidationBannerProvider);
    final userAsync = ref.watch(activeUserStreamProvider);
    final userName = userAsync.valueOrNull?.name;
    final isShared = ref.watch(sessionMetaProvider).sharedDevice;

    final List<Widget> pages = [
      PrehledPage(onOpenDrawer: openProfile, userName: userName, quizProgressCache: _quizProgressCache),
      const ChatyPage(),
      KnihovnaPage(onBack: () => setState(() => _selectedIndex = 0)),
      const KurzyPage(),
      const NovinkyPage(),
    ];

    return PopScope(
      // Only allow system pop (exit) when on the home tab.
      // On other tabs, intercept and switch to home first.
      canPop: _selectedIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          // Not on home tab — go to home instead of exiting
          setState(() => _selectedIndex = 0);
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        body: Column(
          children: [
            // const SyncStatusBanner(),
            SizedBox(height: MediaQuery.of(context).padding.top),
            if (isShared)
              SharedDeviceBanner(
                onLogout: () => widget.onLogout?.call(),
                // Rebuild so the banner re-reads the now-cleared shared flag
                // and hides itself after "this is my device".
                onConverted: () {
                  if (mounted) setState(() {});
                },
              ),
            if (showBanner) const EmailValidationBanner(),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: pages[_selectedIndex],
              ),
            ),
          ],
        ),
        extendBody: true,
        bottomNavigationBar: CustomBottomNav(
          selectedIndex: _selectedIndex,
          onItemTapped: _onItemTapped,
        ),
      ),
    );
  }
}

