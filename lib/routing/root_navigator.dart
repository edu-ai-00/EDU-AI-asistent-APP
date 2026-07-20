import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../core/database/app_database.dart';
import '../core/network/api_client.dart';
import '../core/oauth/oauth_clients.dart';
import '../core/providers/core_providers.dart';
import '../core/theme/app_theme.dart';
import '../core/widgets/inactivity_watcher.dart';
import '../data/repositories/oauth_repository.dart';
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
              await ref.read(logoutCoordinatorProvider).teardown();
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
              await ref.read(logoutCoordinatorProvider).teardown();
              setState(() {
                _appState = AppState.auth;
              });
            } else {
              // Other error (network issue) - use local data
              _proceedWithLocalUser(activeUser);
            }
          }
        } else if (isOnline) {
          // Online but no token: the session lapsed while the app was closed
          // (expired/revoked). We can't use authenticated features, so route to
          // login rather than stranding the user on cached screens where
          // online-only features (news) would 401.
          await db.logoutUser();
          if (mounted) {
            setState(() {
              _appState = AppState.auth;
            });
          }
        } else {
          // Offline - use local data so the app still works without network.
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

  Future<void> _handleOAuthSuccess(OAuthExchangeResult exchange) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      await apiClient.setAuthToken(exchange.token);
      ref.invalidate(isAuthenticatedProvider);

      // Persist session metadata so inactivity/expiry logic works correctly.
      await ref.read(sessionMetaProvider).applyFromAuthResponse({
        'token': exchange.token,
        'shared_device': exchange.sharedDevice,
        'expires_at': exchange.expiresAt,
        'session_started_at': exchange.sessionStartedAt,
      });

      // Write the authenticated user into the local DB so the app shows their
      // real profile (not the guest "Uživatel") and progress binds to their
      // account. The magic-link flow does the same after /api/user; the OAuth
      // exchange already returns the full user, so no extra request is needed.
      await _persistOAuthUser(exchange.user);

      if (mounted) {
        setState(() {
          _userEmail = exchange.user['email'] as String? ?? '';
          _appState = exchange.profileSetupRequired
              ? AppState.profileSetup
              : AppState.main;
        });
      }

      // Pull server data immediately after OAuth login.
      try {
        ref.read(syncServiceProvider).forceSync();
      } catch (e, st) { silentLog('root_navigator', e, st); }
    } catch (e, st) {
      silentLog('root_navigator', e, st);
    }
  }

  /// Mirror the OAuth-verified user into the local Drift DB.
  ///
  /// [activeUserStreamProvider] (the source for the displayed name/email and
  /// for progress binding) reads the local users table, not the auth response.
  /// A guest with an empty email is upgraded in place (preserving their local
  /// data); a different account creates a fresh active row and migrates any
  /// prior local data onto it.
  Future<void> _persistOAuthUser(Map<String, dynamic> u) async {
    final db = ref.read(appDatabaseProvider);

    final email = (u['email'] as String?) ?? '';
    if (email.isEmpty) return; // backend guarantees a verified email; guard anyway
    final name = (u['name'] as String?) ?? '';
    final avatarIndex = (u['avatar_index'] as int?) ?? 0;
    final rawSubjects = u['selected_subjects'];
    final subjects = rawSubjects is List
        ? jsonEncode(rawSubjects.map((e) => e.toString()).toList())
        : null;

    final activeUser = await db.getActiveUser();
    final isGuestUpgrade = activeUser != null && activeUser.email.isEmpty;

    if (isGuestUpgrade) {
      await db.updateUserEmail(activeUser.id, email);
      await db.markEmailValidated(activeUser.id);
      if (name.isNotEmpty) {
        await db.updateUserProfile(
          userId: activeUser.id,
          name: name,
          avatarIndex: avatarIndex,
          selectedSubjects: subjects,
        );
      }
    } else if (activeUser == null || activeUser.email != email) {
      // No active user, or a different account than the one already active.
      final newUserId = const Uuid().v4();
      await db.createAndActivateUser(
        UsersTableCompanion(
          id: Value(newUserId),
          email: Value(email),
          name: Value(name),
          avatarIndex: Value(avatarIndex),
          selectedSubjects: Value(subjects ?? '[0]'),
          isEmailValidated: const Value(true),
          isActive: const Value(true),
          createdAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ),
      );
      if (activeUser != null && activeUser.id != newUserId) {
        await db.migrateUserData(activeUser.id, newUserId);
      }
    }

    ref.invalidate(activeUserStreamProvider);
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

  void _handleLogout() {
    _forceLogoutToAuth();
  }

  /// Tear down the session (best-effort flush → revoke → local wipe) and return
  /// to the login screen, dropping any pushed routes. Used by the logout
  /// button, the InactivityWatcher, and the start-up expiry check.
  Future<void> _forceLogoutToAuth() async {
    await ref.read(logoutCoordinatorProvider).teardown();
    _resetToAuth();
  }

  /// Pop everything above the root route and show the auth screen. Also invoked
  /// via [forceAuthScreenProvider] when logout is triggered from elsewhere —
  /// a 401 on any endpoint, or a null active user in a pushed page.
  void _resetToAuth() {
    ref.read(oauthNavigatorKeyProvider).currentState?.popUntil((r) => r.isFirst);
    if (!mounted) return;
    setState(() {
      _userEmail = '';
      _appState = AppState.auth;
    });
  }

  @override
  Widget build(BuildContext context) {
    // When logout is triggered from outside this widget (a 401 on any endpoint,
    // or a null active user in a pushed page), return to the login screen.
    ref.listen<int>(forceAuthScreenProvider, (_, _) => _resetToAuth());

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
          onOAuthSuccess: _handleOAuthSuccess,
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
