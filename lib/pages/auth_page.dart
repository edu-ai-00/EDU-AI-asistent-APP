import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../core/database/app_database.dart' show UsersTableCompanion;
import '../core/theme/app_theme.dart';
import '../core/providers/core_providers.dart';
import '../data/repositories/course_repository.dart';
import '../models/course_model.dart' as models;
import 'course_detail_page.dart';
import '../core/network/api_endpoints.dart';
import '../core/strings/app_strings.dart';
import 'package:eduai/core/util/silent_log.dart';
import 'package:eduai/core/widgets/code_input_field.dart';
import '../routing/deep_link.dart';
import '../core/oauth/oauth_clients.dart';
import '../core/oauth/google_web_button.dart';
import '../data/repositories/oauth_repository.dart';

class AuthPage extends ConsumerStatefulWidget {
  /// Callback when user submits email - passes the entered email.
  final void Function(String email) onEmailSubmit;

  /// Callback when PIN login completes successfully (guest user created).
  final void Function()? onPinLoginComplete;

  /// Optional back button callback (shown when guest navigates here to log in).
  final VoidCallback? onBack;

  /// When true, starts directly in email/SSO mode (skips PIN screen).
  final bool startInLoginMode;

  /// Callback when OAuth sign-in completes successfully.
  final ValueChanged<OAuthExchangeResult>? onOAuthSuccess;

  const AuthPage({
    super.key,
    required this.onEmailSubmit,
    this.onPinLoginComplete,
    this.onBack,
    this.startInLoginMode = false,
    this.onOAuthSuccess,
  });

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> with SingleTickerProviderStateMixin {
  late bool _isSignUpMode = widget.startInLoginMode;
  bool _isLookingUpPin = false;
  bool _isOAuthInProgress = false;
  String? _pinError;

  /// Web-only: the GIS button drives Google sign-in and results arrive on this
  /// subscription. [_googleWebReady] gates rendering the button until the SDK
  /// is initialized. Both stay null/false on native.
  StreamSubscription<OAuthClientResult>? _googleWebSub;
  bool _googleWebReady = false;

  /// Guards the one-shot deep-link auto-submit so it fires at most once.
  bool _deepLinkConsumed = false;

  /// Inverted UI state: true when user opts OUT of shared-device mode
  /// (i.e. wants to stay permanently logged in). Default false = shared.
  late bool _keepLoggedIn =
      !(ref.read(sessionMetaProvider).pendingSharedDevice);

  late AnimationController _animationController;
  late Animation<double> _heightAnimation;
  late Animation<double> _fadeOutAnimation;
  late Animation<double> _fadeInAnimation;

  final TextEditingController _emailController = TextEditingController();

  final CodeInputController _codeController = CodeInputController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _heightAnimation = Tween<double>(begin: 0.52, end: 0.72).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOutCubic),
    );

    _fadeOutAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    _fadeInAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeIn),
      ),
    );

    // If starting in login mode, jump animation to end state immediately
    if (widget.startInLoginMode) {
      _animationController.value = 1.0;
    }

    // A /course/:code or /pin/:code deep link opened straight onto this login
    // screen (logged-out visitor). DeepLinkEntry parked the code; pick it up
    // and resolve it through the normal guest PIN flow so the course opens
    // without the user re-typing the code they already clicked.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeConsumeDeepLink());

    // Web: Google sign-in can't be triggered imperatively — a GIS button
    // renders it and results arrive on the event stream. Subscribe once and
    // initialize the SDK so the button can render.
    if (kIsWeb) {
      final client = ref.read(googleOAuthClientProvider);
      _googleWebSub = client.signInResults().listen(_completeOAuth);
      client.ensureInitialized().then((_) {
        if (mounted) setState(() => _googleWebReady = true);
      });
    }
  }

  /// If a deep-link code is pending and we're on the PIN screen, prefill it and
  /// auto-submit. Clearing the provider here also stops MainScreen from opening
  /// the same course a second time after login completes.
  void _maybeConsumeDeepLink() {
    if (_deepLinkConsumed || !mounted) return;
    // Only the PIN screen can resolve a code; skip when forced into login mode.
    if (widget.startInLoginMode) return;

    final code = ref.read(pendingDeepLinkCodeProvider);
    if (code == null || code.length != 6) return;

    _deepLinkConsumed = true;
    ref.read(pendingDeepLinkCodeProvider.notifier).state = null;

    setState(() => _codeController.code = code);
    _handlePinSubmit();
  }

  @override
  void dispose() {
    _googleWebSub?.cancel();
    _animationController.dispose();
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  String get _pin => _codeController.code;

  void _onCodeChanged(String value) {
    // Clear any prior error and rebuild so the submit button reflects length.
    // Only clear the error while the user is actively typing a new code. A
    // programmatic clear after an invalid submit empties the field and fires
    // onChanged('') synchronously — it must NOT wipe the just-set error, or the
    // code silently disappears with no feedback (BR-ANKRJP).
    if (value.isEmpty) return;
    if (_pinError != null) {
      setState(() => _pinError = null);
    }
  }

  void _clearPin() => _codeController.clear();

  Future<void> _handlePinSubmit() async {
    // Re-entrancy guard: a submit is already in flight. Without this the
    // deep-link auto-consume opens the course twice — setting the code fires
    // CodeInputField.onCompleted (→ submit #1) and _maybeConsumeDeepLink then
    // calls submit #2 directly, each pushing its own CourseDetailPage.
    if (_isLookingUpPin) return;
    if (_pin.length != 6) return;

    setState(() {
      _isLookingUpPin = true;
      _pinError = null;
    });

    // Persist user's session-mode choice. The auth response will overwrite
    // session_shared_device with what the server actually issued.
    final shared = !_keepLoggedIn;
    await ref.read(sessionMetaProvider).setPendingSharedDevice(shared);

    try {
      final courseRepo = ref.read(courseRepositoryProvider);
      final userCourseRepo = ref.read(userCourseRepositoryProvider);
      final db = ref.read(appDatabaseProvider);

      // Step 1: Check bundled / local courses first (offline-first)
      var course = await courseRepo.findCourseByCode(_pin);

      // Step 1b: If not found locally, call unified resolve-code API.
      // One call resolves both course PINs and student login codes.
      if (course == null) {
        final guestAuthService = ref.read(guestAuthServiceProvider);
        try {
          final resolved = await guestAuthService
              .resolveCode(_pin, sharedDevice: shared)
              .timeout(const Duration(seconds: 15));

          if (resolved != null && resolved.isUser) {
            // Student login code — save user and complete login
            final name = resolved.name ?? AppStrings.authDefaultStudentName;

            // BR-ZDXP7C: A student login code adopts a specific server-side
            // identity. If the currently-active local user is a *different*
            // person (a leftover guest, or another student on a shared
            // device), wipe local data first so their practice cards,
            // progress and bookmarks don't leak into the "clean" account.
            // Same-person re-login (matching email) keeps local data intact.
            final current = await db.getActiveUser();
            final samePerson = current != null &&
                current.email.isNotEmpty &&
                resolved.email != null &&
                current.email.toLowerCase() ==
                    resolved.email!.trim().toLowerCase();
            if (!samePerson) {
              await db.clearAllData();
            }

            var user = await db.getActiveUser();
            if (user == null) {
              final guestId = await db.createGuestUser();
              user = await db.getUserById(guestId);
            }
            if (user != null) {
              await db.updateUserProfile(userId: user.id, name: name);
              if (resolved.email != null) {
                await db.updateUserEmail(user.id, resolved.email!);
              }
              // Server-authenticated user — mark email as validated
              // so the "register for full access" banner doesn't show.
              await (db.update(db.usersTable)
                    ..where((u) => u.id.equals(user!.id)))
                  .write(const UsersTableCompanion(
                    isEmailValidated: Value(true),
                  ));
            }
            ref.invalidate(isAuthenticatedProvider);
            setState(() => _isLookingUpPin = false);
            widget.onPinLoginComplete?.call();
            return;
          }

          if (resolved != null && resolved.isCourse) {
            // API found a course — import it locally and continue
            course = await courseRepo.importFromResolvedCode(_pin, resolved.courseData!);
          }
        } catch (e, st) { silentLog('auth_page', e, st); }

        if (course == null) {
          setState(() {
            _isLookingUpPin = false;
            _pinError = AppStrings.codeNotFound(_pin);
          });
          _clearPin();
          return;
        }
      }

      // Step 1c: Block guests from logged_only courses.
      // Allow only real accounts: a user with an email OR a server-authenticated
      // student PIN login (flagged locally via isEmailValidated). Guests hold a
      // Sanctum token too, so token presence must NOT count as logged in
      // (BR-N2ENN4).
      if (course.data['logged_only'] == true) {
        final activeUser = await db.getActiveUser();
        if (activeUser == null ||
            (activeUser.email.isEmpty && !activeUser.isEmailValidated)) {
          setState(() {
            _isLookingUpPin = false;
            _pinError = AppStrings.authLoginRequired;
          });
          _clearPin();
          return;
        }
      }

      // Step 2: Create or get guest user
      var user = await db.getActiveUser();
      if (user == null) {
        // Create guest user
        final guestId = await db.createGuestUser();
        user = await db.getUserById(guestId);
      }

      if (user == null) {
        setState(() {
          _isLookingUpPin = false;
          _pinError = AppStrings.authUserCreateError;
        });
        _clearPin();
        return;
      }

      // Step 2b: Register guest on server to get auth token.
      // The token is needed for subsequent authenticated API calls.
      // 15s timeout handles Railway cold starts (can take 10-12s).
      final apiClient = ref.read(apiClientProvider);
      if (!apiClient.isAuthenticated) {
        final guestAuthService = ref.read(guestAuthServiceProvider);
        try {
          final registerResult = await guestAuthService
              .registerGuest(sharedDevice: shared)
              .timeout(const Duration(seconds: 15));
          if (registerResult != null) {
            // Invalidate cached auth state so providers see the new token.
            ref.invalidate(isAuthenticatedProvider);
            await db.updateUserProfile(
              userId: user.id,
              name: registerResult.name,
            );
          } else {
          }
        } catch (e) {
          // Timeout or network error — proceed without token.
          // Bundled courses work offline; token will be obtained on next sync.
        }
      } else {
      }

      // Step 3: Add course to user's library
      await userCourseRepo.startCourse(
        userId: user.id,
        courseId: course.id,
      );

      // Step 4: Download full course JSON from R2
      final downloadSuccess = await courseRepo.downloadFullCourseJson(course.id);

      // Step 5: Get the full course data for navigation
      final fullCourse = await courseRepo.getCourseById(course.id);
      if (fullCourse == null) {
        setState(() {
          _isLookingUpPin = false;
          _pinError = AppStrings.authCourseLoadError;
        });
        _clearPin();
        return;
      }

      // Step 5b: Validate course has actual content (blocks inside lessons)
      final courseData = fullCourse.data;
      final lessons = courseData['lessons'] as List<dynamic>?;
      final hasBlocks = lessons != null &&
          lessons.isNotEmpty &&
          lessons.first is Map<String, dynamic> &&
          (lessons.first as Map<String, dynamic>)['blocks'] is List;

      if (!downloadSuccess && !hasBlocks) {
        // Mark course as not-downloaded so knihovna will re-download later
        final userCourse = await db.getUserCourseByUserAndCourse(user.id, course.id);
        if (userCourse != null) {
          await db.updateUserCourseDownloadedVersion(
            id: userCourse.id,
            downloadedVersion: 0,
          );
        }

        setState(() {
          _isLookingUpPin = false;
          _pinError = AppStrings.authCourseDownloadError;
        });
        _clearPin();
        // Still complete login so the user lands in the app
        widget.onPinLoginComplete?.call();
        return;
      }

      // Step 6: Get user course for progress tracking
      final userCourse = await db.getUserCourseByUserAndCourse(user.id, course.id);

      // Step 6.5: Block re-entry for only_once completed courses
      if (fullCourse.data['only_once'] == true) {
        // Check locally first
        if (userCourse != null && userCourse.status == 'completed') {
          setState(() {
            _isLookingUpPin = false;
            _pinError = AppStrings.libraryCourseAlreadyCompleted;
          });
          _clearPin();
          return;
        }

        // Check server — local data may have been cleared
        if (apiClient.isAuthenticated) {
          try {
            final result = await apiClient.get<Map<String, dynamic>>(
              ApiEndpoints.userCourses,
            ).timeout(const Duration(seconds: 10));
            if (result.isSuccess && result.data != null) {
              final serverCourses = result.data!['user_courses'] as List<dynamic>? ?? [];
              // Server returns course_id as string OR numeric — match both
              final courseStringId = fullCourse.courseId;
              final courseNumericId = fullCourse.serverId;
              final alreadyCompleted = serverCourses.any((uc) {
                if (uc is! Map<String, dynamic>) return false;
                if (uc['status'] != 'completed') return false;
                final remoteCourseId = uc['course_id'];
                return remoteCourseId == courseStringId ||
                    remoteCourseId == courseNumericId;
              });
              if (alreadyCompleted) {
                setState(() {
                  _isLookingUpPin = false;
                  _pinError = AppStrings.libraryCourseAlreadyCompleted;
                });
                _clearPin();
                return;
              }
            }
          } catch (_) {
            // Network error — allow entry (offline-first, local check already passed)
          }
        }
      }

      setState(() => _isLookingUpPin = false);

      // Step 7: Navigate to course detail, then switch to main app on return
      if (mounted) {
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

        // Step 8: After returning from course, switch to main app
        if (mounted) {
          widget.onPinLoginComplete?.call();
        }
      }
    } catch (e) {
      setState(() {
        _isLookingUpPin = false;
        _pinError = AppStrings.genericError('$e');
      });
      _clearPin();
    }
  }

  void _handleLogin() async {
    final email = _emailController.text.trim();
    // Persist user's session-mode choice for downstream verify/registerVerified.
    await ref.read(sessionMetaProvider).setPendingSharedDevice(!_keepLoggedIn);
    if (email.isEmpty) {
      // Show error if email is empty
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.authEmptyEmailError),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    // Basic email validation
    if (!email.contains('@') || !email.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppStrings.authInvalidEmailError),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    // Just proceed to verification page - it will handle sending the code
    widget.onEmailSubmit(email);
  }

  /// Native (iOS/Android) button handler: obtain the provider credential
  /// imperatively, then exchange it. Web Google sign-in does not use this —
  /// its GIS button feeds [_completeOAuth] via the event subscription.
  Future<void> _handleOAuthLogin(String provider) async {
    setState(() => _isOAuthInProgress = true);

    final OAuthClientResult? clientResult;
    try {
      clientResult = await switch (provider) {
        'apple' => ref.read(appleOAuthClientProvider).signIn(),
        'google' => ref.read(googleOAuthClientProvider).signIn(),
        'microsoft' => ref.read(microsoftOAuthClientProvider).signIn(),
        _ => Future<OAuthClientResult?>.value(null),
      };
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.genericError('$e')),
          backgroundColor: AppColors.error,
        ));
        setState(() => _isOAuthInProgress = false);
      }
      return;
    }

    if (clientResult == null) {
      if (mounted) setState(() => _isOAuthInProgress = false);
      return; // user cancelled
    }

    await _completeOAuth(clientResult);
  }

  /// Exchange a provider credential for a session and notify the parent.
  /// Shared by the native handler and the web Google event subscription.
  Future<void> _completeOAuth(OAuthClientResult clientResult) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _isOAuthInProgress = true);

    try {
      await ref.read(sessionMetaProvider).setPendingSharedDevice(!_keepLoggedIn);
      final exchange = await ref.read(oauthRepositoryProvider).exchange(
            clientResult,
            sharedDevice: !_keepLoggedIn,
          );

      widget.onOAuthSuccess?.call(exchange);
    } on OAuthExchangeException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(AppStrings.genericError(e.message)),
          backgroundColor: AppColors.error,
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(AppStrings.genericError('$e')),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _isOAuthInProgress = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _isSignUpMode = !_isSignUpMode;
    });
    if (_isSignUpMode) {
      _animationController.forward();
    } else {
      _animationController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: AppColors.authGradient,
        ),
        child: AnimatedBuilder(
          animation: _animationController,
          builder: (context, child) {
            // Cap the card height so its top never rises above the top safe-area
            // inset. When the keyboard opens, Scaffold's default
            // resizeToAvoidBottomInset shrinks the body, but the card height is
            // computed from the full screen height — without this clamp the card
            // overflows upward and the header/back button slide under the status
            // bar (BR-PXB3N3).
            final mq = MediaQuery.of(context);
            final maxContainerHeight =
                mq.size.height - mq.viewInsets.bottom - mq.padding.top;
            final containerHeight = maxContainerHeight <= 0
                ? screenHeight * _heightAnimation.value
                : (screenHeight * _heightAnimation.value)
                    .clamp(0.0, maxContainerHeight)
                    .toDouble();
            final logoBottom = containerHeight + 60;
            final bgBottom = containerHeight - 20;

            return Stack(
              children: [
                // Background decorative image
                Positioned(
                  bottom: bgBottom,
                  left: 0,
                  right: 0,
                  child: Image.asset(
                    'assets/images/login_bg.png',
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
                // Logo
                Positioned(
                  bottom: logoBottom,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Image.asset(
                      'assets/images/login_logo.png',
                      width: 276,
                    ),
                  ),
                ),
                // White form container
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: containerHeight,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                    ),
                    child: SafeArea(
                      top: false,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 400),
                            child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header with back button
                            if (_isSignUpMode || widget.onBack != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: GestureDetector(
                                  onTap: _isSignUpMode
                                      ? (widget.onBack ?? _toggleMode)
                                      : widget.onBack,
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: AppColors.primaryDark08,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.arrow_back,
                                      color: AppColors.primaryDark,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                            // Headline
                            Text(
                              AppStrings.authHeadline,
                              style: AppTextStyles.heading1().copyWith(
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Content based on mode
                            _isSignUpMode
                                ? _buildSignUpContent()
                                : _buildWelcomeContent(),
                          ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildWelcomeContent() {
    return FadeTransition(
      opacity: _fadeOutAnimation.value == 0
          ? const AlwaysStoppedAnimation(0)
          : _fadeOutAnimation,
      child: Column(
        children: [
          // Code input label
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppStrings.authCodeLabel,
              textAlign: TextAlign.left,
              style: AppTextStyles.bodyLarge(color: AppColors.primaryDark64),
            ),
          ),
          const SizedBox(height: 12),
          // Alphanumeric code input — single field rendered as 6 boxes
          CodeInputField(
            length: 6,
            controller: _codeController,
            hasError: _pinError != null,
            onChanged: _onCodeChanged,
            onCompleted: (_) {
              if (!_isLookingUpPin) _handlePinSubmit();
            },
          ),
          // Error message
          if (_pinError != null) ...[
            const SizedBox(height: 8),
            Text(
              _pinError!,
              style: AppTextStyles.caption(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          _buildKeepLoggedInCheckbox(),
          const SizedBox(height: 16),
          // Access Free Courses button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (_pin.length == 6 && !_isLookingUpPin) ? _handlePinSubmit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.primaryDark48,
                disabledForegroundColor: Colors.white.withAlpha(179),
                shape: RoundedRectangleBorder(
                  borderRadius: AppDecorations.radiusM,
                ),
                elevation: 0,
              ),
              child: _isLookingUpPin
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          AppStrings.authVerifyingCode,
                          style: AppTextStyles.buttonLarge(color: Colors.white),
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          AppStrings.authContinue,
                          style: AppTextStyles.buttonLarge(color: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.arrow_forward, size: 20),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 24),
          // Divider with "or"
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  color: AppColors.primaryDark12,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppStrings.authOr,
                  style: AppTextStyles.bodySmall(color: AppColors.primaryDark48),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  color: AppColors.primaryDark12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Log In / Sign Up button
          GestureDetector(
            onTap: _toggleMode,
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                border: Border.all(
                  color: AppColors.primaryDark16,
                  width: 1,
                ),
                borderRadius: AppDecorations.radiusM,
              ),
              child: Center(
                child: Text(
                  AppStrings.authLoginSignUp,
                  style: AppTextStyles.bodyLarge(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Terms and Privacy Policy
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () {},
                  child: Text(
                    AppStrings.authTerms,
                    style: AppTextStyles.caption(color: AppColors.primaryDark48).copyWith(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                GestureDetector(
                  onTap: () {},
                  child: Text(
                    AppStrings.authPrivacy,
                    style: AppTextStyles.caption(color: AppColors.primaryDark48).copyWith(
                      decoration: TextDecoration.underline,
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

  Widget _buildSignUpContent() {
    return FadeTransition(
      opacity: _fadeInAnimation,
      child: Column(
        children: [
          // Email input
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: AppColors.primaryDark16,
                width: 1,
              ),
              borderRadius: AppDecorations.radiusM,
            ),
            child: TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _handleLogin(),
              style: AppTextStyles.bodyLarge(),
              decoration: InputDecoration(
                hintText: AppStrings.authEmailHint,
                hintStyle: AppTextStyles.bodyLarge(color: AppColors.primaryDark48),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _buildKeepLoggedInCheckbox(),
          const SizedBox(height: 16),
          // Login button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: AppDecorations.radiusM,
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppStrings.authLogin,
                    style: AppTextStyles.buttonLarge(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Divider with "Nebo"
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  color: AppColors.primaryDark12,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  AppStrings.authOrCzech,
                  style: AppTextStyles.bodySmall(color: AppColors.primaryDark48),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  color: AppColors.primaryDark12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // Google OAuth button. Web must use the GIS-rendered button (no
          // imperative authenticate() on web); native uses the custom button.
          if (kIsWeb)
            SizedBox(
              height: 48,
              child: Center(
                child: _googleWebReady
                    ? googleRenderedSignInButton()
                    : const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
              ), // GIS button once SDK ready; spinner while initializing
            )
          else
            _buildOAuthButton(
              onTap: _isOAuthInProgress ? null : () => _handleOAuthLogin('google'),
              icon: SvgPicture.asset(
                'assets/icons/google.svg',
                width: 24,
                height: 24,
              ),
              label: AppStrings.authGoogleLogin,
            ),
          const SizedBox(height: 12),
          // Microsoft OAuth button — constrained to the GIS button's width on
          // web so all three social buttons align.
          _constrainSocialWeb(_buildOAuthButton(
            onTap: _isOAuthInProgress ? null : () => _handleOAuthLogin('microsoft'),
            icon: SvgPicture.asset(
              'assets/icons/microsoft.svg',
              width: 24,
              height: 24,
            ),
            label: AppStrings.authMicrosoftLogin,
          )),
          // Apple OAuth button — only on Apple devices. Web/Android would need
          // the Apple Services ID web flow, which isn't set up, so hide it there.
          if (_showAppleSignIn) ...[
            const SizedBox(height: 12),
            _constrainSocialWeb(_buildOAuthButton(
              onTap: _isOAuthInProgress ? null : () => _handleOAuthLogin('apple'),
              icon: SvgPicture.asset(
                'assets/icons/apple.svg',
                width: 24,
                height: 24,
              ),
              label: AppStrings.authAppleLogin,
            )),
          ],
          const SizedBox(height: 24),
          // Terms and Privacy Policy
          Center(
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: AppTextStyles.caption(color: AppColors.primaryDark48),
                children: [
                  TextSpan(text: AppStrings.authTermsNotice),
                  TextSpan(
                    text: AppStrings.authTermsAndPrivacy,
                    style: AppTextStyles.caption(color: AppColors.primaryDark64).copyWith(
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Opt-out checkbox: when checked, the new session is persistent (no
  /// inactivity logout). Default unchecked = shared device, auto-logout
  /// after 15 min idle / 8 h hard cap.
  Widget _buildKeepLoggedInCheckbox() {
    return InkWell(
      onTap: () {
        setState(() => _keepLoggedIn = !_keepLoggedIn);
      },
      borderRadius: AppDecorations.radiusS,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _keepLoggedIn,
                onChanged: (v) =>
                    setState(() => _keepLoggedIn = v ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.authKeepLoggedInLabel,
                style: AppTextStyles.bodySmall(
                  color: AppColors.primaryDark64,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Apple Sign In is only offered on Apple platforms. On web and Android it
  /// would require the Apple Services ID web OAuth flow (not configured), so
  /// the button is hidden there.
  bool get _showAppleSignIn =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// On web the Google button is GIS-rendered and capped near 400px wide;
  /// constrain the other social buttons to match so the column aligns. No-op
  /// on native, where all social buttons are full-width custom buttons.
  Widget _constrainSocialWeb(Widget child) {
    if (!kIsWeb) return child;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: child,
      ),
    );
  }

  Widget _buildOAuthButton({
    required VoidCallback? onTap,
    required Widget icon,
    required String label,
  }) {
    // On web the Google button is Google-rendered (fixed ~40px tall, ~4px
    // corners, logo pinned left, text centered, regular weight). Match the
    // custom social buttons to it so the set looks uniform.
    final bool matchGis = kIsWeb;

    final Widget content = matchGis
        // GIS layout: icon pinned left, label centered across the full width.
        ? Stack(
            alignment: Alignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: icon,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge().copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 12),
              Text(label, style: AppTextStyles.bodyLarge()),
            ],
          );

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: matchGis ? 40 : 56,
        decoration: BoxDecoration(
          border: Border.all(
            color: AppColors.primaryDark16,
            width: 1,
          ),
          borderRadius:
              matchGis ? BorderRadius.circular(4) : AppDecorations.radiusM,
        ),
        child: content,
      ),
    );
  }
}
