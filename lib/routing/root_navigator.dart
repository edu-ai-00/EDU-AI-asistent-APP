import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/database/app_database.dart';
import '../core/network/api_client.dart';
import '../core/network/api_endpoints.dart';
import '../core/providers/core_providers.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/inactivity_watcher.dart';
import '../pages/auth_page.dart';
import '../pages/email_verification_page.dart';
import '../pages/main_screen.dart';
import '../pages/profile_setup_page.dart';
import 'package:eduai/core/util/silent_log.dart';

class AuthWrapper extends ConsumerStatefulWidget {
  const AuthWrapper({super.key});

  @override
  ConsumerState<AuthWrapper> createState() => _AuthWrapperState();
}

enum AppState { loading, auth, emailVerification, profileSetup, main }

class _AuthWrapperState extends ConsumerState<AuthWrapper> {
  AppState _appState = AppState.loading;
  String _userEmail = '';
  bool _isEmailValidated = false; // Track if email was validated (false if skipped offline)
  bool _isGuestUpgrade = false; // Track when guest is upgrading to full account

  @override
  void initState() {
    super.initState();
    _checkExistingAuth();
  }

  /// Check if user is already logged in on app startup
  Future<void> _checkExistingAuth() async {
    try {
      final db = ref.read(appDatabaseProvider);
      final apiClient = ref.read(apiClientProvider);
      final connectivity = ref.read(connectivityServiceProvider);
      final session = ref.read(sessionMetaProvider);

      // Shared-device sessions: if app was backgrounded past the inactivity
      // limit or hard cap, log out before any API calls so we don't briefly
      // flash the main UI to a previous student.
      if (session.sharedDevice &&
          (session.isInactivityExpired() || session.isHardCapExceeded())) {
        await _forceLogoutToAuth();
        return;
      }

      final activeUser = await db.getActiveUser();

      if (activeUser != null) {
        _userEmail = activeUser.email;

        // If online, verify with the API server
        final isOnline = await connectivity.isOnline;
        if (isOnline && apiClient.isAuthenticated) {
          try {
            final response = await apiClient.get('/api/user')
                .timeout(const Duration(seconds: 10), onTimeout: () {
              return ApiResult.failure('timeout');
            });
            if (response.statusCode == 200) {
              final userData = response.data as Map<String, dynamic>;
              final serverName = userData['name'] as String? ?? '';
              final serverAvatarIndex = userData['avatar_index'] as int? ?? 0;
              final serverSubjects = userData['selected_subjects'];

              // Convert subjects to string for storage
              String? subjectsString;
              if (serverSubjects != null) {
                if (serverSubjects is List) {
                  subjectsString = serverSubjects.map((e) => e.toString()).join(',');
                } else if (serverSubjects is String) {
                  subjectsString = serverSubjects;
                }
              }


              // Update local user data from server
              await db.updateUserProfile(
                userId: activeUser.id,
                name: serverName.isNotEmpty ? serverName : null,
                avatarIndex: serverAvatarIndex,
                selectedSubjects: subjectsString,
              );

              // Check if profile is complete
              if (serverName.isNotEmpty) {
                setState(() {
                  _appState = AppState.main;
                });
              } else {
                setState(() {
                  _isEmailValidated = activeUser.isEmailValidated;
                  _appState = AppState.profileSetup;
                });
              }
            } else if (response.statusCode == 401 || response.statusCode == 403) {
              // Token is definitely invalid — log out
              await db.logoutUser();
              setState(() {
                _appState = AppState.auth;
              });
            } else {
              // Other status (null/timeout, 500, etc.) — use local data
              _proceedWithLocalUser(activeUser);
            }
          } catch (apiError) {
            // API call failed - check if it's 401 unauthorized
            if (apiError.toString().contains('401')) {
              // Token is invalid - log out
              await db.logoutUser();
              setState(() {
                _appState = AppState.auth;
              });
            } else {
              // Other error (network issue) - use local data
              _proceedWithLocalUser(activeUser);
            }
          }
        } else {
          // Offline or no token - use local data
          _proceedWithLocalUser(activeUser);
        }
      } else {
        // No user - show auth screen
        setState(() {
          _appState = AppState.auth;
        });
      }
    } catch (e) {
      setState(() {
        _appState = AppState.auth;
      });
    }
  }

  /// Proceed with local user data (used when offline)
  void _proceedWithLocalUser(UsersTableData activeUser) {
    if (activeUser.name.isNotEmpty) {
      setState(() {
        _appState = AppState.main;
      });
    } else {
      setState(() {
        _isEmailValidated = activeUser.isEmailValidated;
        _appState = AppState.profileSetup;
      });
    }
  }

  void _handleEmailSubmit(String email) {
    setState(() {
      _userEmail = email;
      _isGuestUpgrade = false;
      _appState = AppState.emailVerification;
    });
  }

  void _handleGuestLogin(String email) {
    setState(() {
      _userEmail = email;
      _isGuestUpgrade = true;
      _appState = AppState.emailVerification;
    });
  }

  void _handleVerificationComplete(bool needsProfileSetup, bool isEmailValidated) {
    setState(() {
      _isEmailValidated = isEmailValidated;
      _appState = needsProfileSetup ? AppState.profileSetup : AppState.main;
    });
  }

  void _handleProfileComplete() {
    setState(() {
      _appState = AppState.main;
    });
  }

  void _handleBackToAuth() {
    setState(() {
      _userEmail = '';
      if (_isGuestUpgrade) {
        _isGuestUpgrade = false;
        _appState = AppState.main;
      } else {
        _appState = AppState.auth;
      }
    });
  }

  void _handlePinLoginComplete() {
    // Guest user was created by AuthPage, switch to main app
    setState(() {
      _appState = AppState.main;
    });

    // Pull server data (progress, bookmarks, stats, achievements) immediately.
    // Critical for new-device login where local DB is empty.
    try {
      ref.read(syncServiceProvider).forceSync();
    } catch (e, st) { silentLog('root_navigator', e, st); }
  }

  void _handleLogout() async {
    await _performLogout();
    if (mounted) {
      setState(() {
        _userEmail = '';
        _appState = AppState.auth;
      });
    }
  }

  /// Logout that doesn't depend on widget state — used at start-up before
  /// the first frame and by the InactivityWatcher.
  Future<void> _forceLogoutToAuth() async {
    await _performLogout();
    if (!mounted) return;
    setState(() {
      _userEmail = '';
      _appState = AppState.auth;
    });
  }

  Future<void> _performLogout() async {
    final apiClient = ref.read(apiClientProvider);
    final session = ref.read(sessionMetaProvider);
    final guest = ref.read(guestAuthServiceProvider);
    final db = ref.read(appDatabaseProvider);

    // Best-effort server token revoke. Network failure must not block local
    // logout — a forgotten shared-device token still expires server-side via
    // its TTL/hard cap.
    try {
      if (apiClient.isAuthenticated) {
        await apiClient.post(ApiEndpoints.logout);
      }
    } catch (e, st) { silentLog('root_navigator', e, st); }

    try { await session.clear(); } catch (e, st) { silentLog('root_navigator', e, st); }
    try { guest.markForceNewGuest(); } catch (e, st) { silentLog('root_navigator', e, st); }
    try { await apiClient.clearAuthToken(); } catch (e, st) { silentLog('root_navigator', e, st); }
    try { await db.logoutUser(); } catch (e, st) { silentLog('root_navigator', e, st); }
  }

  @override
  Widget build(BuildContext context) {
    final Widget screen;
    switch (_appState) {
      case AppState.loading:
        screen = Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              color: AppColors.primary,
            ),
          ),
        );
        break;
      case AppState.auth:
        screen = AuthPage(
          onEmailSubmit: _handleEmailSubmit,
          onPinLoginComplete: _handlePinLoginComplete,
        );
        break;
      case AppState.emailVerification:
        screen = EmailVerificationPage(
          email: _userEmail,
          onVerified: _handleVerificationComplete,
          onBack: _handleBackToAuth,
        );
        break;
      case AppState.profileSetup:
        screen = ProfileSetupPage(
          email: _userEmail,
          isEmailValidated: _isEmailValidated,
          onComplete: _handleProfileComplete,
        );
        break;
      case AppState.main:
        screen = MainScreen(
          onLogout: _handleLogout,
          onGuestLogin: _handleGuestLogin,
        );
        break;
    }

    return InactivityWatcher(
      onLogout: _forceLogoutToAuth,
      child: screen,
    );
  }
}
