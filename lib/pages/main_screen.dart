import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';
import '../core/providers/core_providers.dart';
import '../core/providers/bookmark_provider.dart';
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

class _MainScreenState extends ConsumerState<MainScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Quiz progress cache keyed by courseId — survives quiz page pop/re-push.
  final Map<String, QuizProgress> _quizProgressCache = {};

  @override
  void initState() {
    super.initState();
    _initBookmarks();
    _seedBundledCourses();
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
            if (isShared)
              SharedDeviceBanner(
                onLogout: () => widget.onLogout?.call(),
              )
            else if (showBanner)
              const EmailValidationBanner()
            else
              SizedBox(height: MediaQuery.of(context).padding.top),
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

