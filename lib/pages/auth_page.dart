import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:eduai/core/util/pin_formatter.dart';

class AuthPage extends ConsumerStatefulWidget {
  /// Callback when user submits email - passes the entered email.
  final void Function(String email) onEmailSubmit;

  /// Callback when PIN login completes successfully (guest user created).
  final void Function()? onPinLoginComplete;

  /// Optional back button callback (shown when guest navigates here to log in).
  final VoidCallback? onBack;

  /// When true, starts directly in email/SSO mode (skips PIN screen).
  final bool startInLoginMode;

  const AuthPage({
    super.key,
    required this.onEmailSubmit,
    this.onPinLoginComplete,
    this.onBack,
    this.startInLoginMode = false,
  });

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> with SingleTickerProviderStateMixin {
  late bool _isSignUpMode = widget.startInLoginMode;
  bool _isLookingUpPin = false;
  String? _pinError;

  /// Inverted UI state: true when user opts OUT of shared-device mode
  /// (i.e. wants to stay permanently logged in). Default false = shared.
  late bool _keepLoggedIn =
      !(ref.read(sessionMetaProvider).pendingSharedDevice);

  late AnimationController _animationController;
  late Animation<double> _heightAnimation;
  late Animation<double> _fadeOutAnimation;
  late Animation<double> _fadeInAnimation;

  final TextEditingController _emailController = TextEditingController();

  final List<TextEditingController> _pinControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());

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
  }

  @override
  void dispose() {
    _animationController.dispose();
    _emailController.dispose();
    for (var controller in _pinControllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  String get _pin => _pinControllers.map((c) => c.text).join();

  void _onPinChanged(int index, String value) {
    // Clear error when user types
    if (_pinError != null) {
      setState(() => _pinError = null);
    }

    if (value.isNotEmpty && index < 5) {
      _focusNodes[index + 1].requestFocus();
    }
    setState(() {});
  }

  void _handleKeyPress(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        _pinControllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
    } else if (event.logicalKey == LogicalKeyboardKey.enter && _pin.length == 6) {
      _handlePinSubmit();
    }
  }

  void _clearPin() {
    for (var controller in _pinControllers) {
      controller.clear();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodes[0].requestFocus();
    });
  }

  Future<void> _handlePinSubmit() async {
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

      // Step 1c: Block guests from logged_only courses
      // Allow if user has an email OR is server-authenticated (student PIN login,
      // detected via local isEmailValidated flag OR Sanctum token presence).
      if (course.data['logged_only'] == true) {
        final activeUser = await db.getActiveUser();
        final hasToken = ref.read(apiClientProvider).isAuthenticated;
        if (activeUser == null ||
            (activeUser.email.isEmpty &&
                !activeUser.isEmailValidated &&
                !hasToken)) {
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

  void _handleOAuthLogin(String provider) {
    // For OAuth, we'll handle differently later - for now just proceed
    widget.onEmailSubmit('oauth_$provider@temp.local');
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
            final containerHeight = screenHeight * _heightAnimation.value;
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
          Text(
            AppStrings.authCodeLabel,
            style: AppTextStyles.bodySmall(color: AppColors.primaryDark64),
          ),
          const SizedBox(height: 12),
          // Alphanumeric code input fields
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(6, (index) {
              return SizedBox(
                width: 48,
                height: 56,
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) => _handleKeyPress(index, event),
                  child: TextField(
                    controller: _pinControllers[index],
                    focusNode: _focusNodes[index],
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    maxLength: 1,
                    inputFormatters: [
                      UpperCaseAlphanumericFormatter(),
                    ],
                    style: AppTextStyles.heading3Alt(),
                    decoration: InputDecoration(
                      counterText: '',
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: AppDecorations.radiusM,
                        borderSide: BorderSide(
                          color: AppColors.primaryDark16,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: AppDecorations.radiusM,
                        borderSide: BorderSide(
                          color: AppColors.primaryDark16,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: AppDecorations.radiusM,
                        borderSide: BorderSide(
                          color: AppColors.primaryDark,
                          width: 1.5,
                        ),
                      ),
                    ),
                    onChanged: (value) => _onPinChanged(index, value),
                  ),
                ),
              );
            }),
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
          // Google OAuth button
          _buildOAuthButton(
            onTap: () => _handleOAuthLogin('google'),
            icon: SvgPicture.asset(
              'assets/icons/google.svg',
              width: 24,
              height: 24,
            ),
            label: AppStrings.authGoogleLogin,
          ),
          const SizedBox(height: 12),
          // Microsoft OAuth button
          _buildOAuthButton(
            onTap: () => _handleOAuthLogin('microsoft'),
            icon: SvgPicture.asset(
              'assets/icons/microsoft.svg',
              width: 24,
              height: 24,
            ),
            label: AppStrings.authMicrosoftLogin,
          ),
          const SizedBox(height: 12),
          // Apple OAuth button
          _buildOAuthButton(
            onTap: () => _handleOAuthLogin('apple'),
            icon: SvgPicture.asset(
              'assets/icons/apple.svg',
              width: 24,
              height: 24,
            ),
            label: AppStrings.authAppleLogin,
          ),
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
                'Zůstat trvale přihlášen — nejedná se o sdílené zařízení',
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

  Widget _buildOAuthButton({
    required VoidCallback onTap,
    required Widget icon,
    required String label,
  }) {
    return GestureDetector(
      onTap: onTap,
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
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTextStyles.bodyLarge(),
            ),
          ],
        ),
      ),
    );
  }
}
