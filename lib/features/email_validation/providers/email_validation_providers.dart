import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/providers/core_providers.dart';
import '../data/email_validation_repository.dart';
import 'package:eduai/core/util/silent_log.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Repository Provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the email validation repository.
final emailValidationRepositoryProvider = Provider<EmailValidationRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final database = ref.watch(appDatabaseProvider);

  return EmailValidationRepository(
    apiClient: apiClient,
    database: database,
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// Verification State
// ═══════════════════════════════════════════════════════════════════════════════

/// State for the email verification flow.
sealed class EmailVerificationState {
  const EmailVerificationState();
}

/// Initial state - waiting to start verification.
class EmailVerificationInitial extends EmailVerificationState {
  const EmailVerificationInitial();
}

/// Loading state - API call in progress.
class EmailVerificationLoading extends EmailVerificationState {
  final String message;
  const EmailVerificationLoading([this.message = '']);
}

/// Code sent successfully - ready for user input.
class EmailVerificationCodeSent extends EmailVerificationState {
  final int expiresIn;
  const EmailVerificationCodeSent({required this.expiresIn});
}

/// Verification successful.
class EmailVerificationSuccess extends EmailVerificationState {
  /// Whether the user is new (needs profile setup) or existing.
  final bool isNewUser;

  /// The user data if existing user.
  final RegisteredUser? user;

  const EmailVerificationSuccess({
    this.isNewUser = true,
    this.user,
  });

  /// Whether profile setup is needed (new user or existing user without name).
  bool get needsProfileSetup => isNewUser || user?.name == null || user!.name.isEmpty;
}

/// Verification failed with error.
class EmailVerificationError extends EmailVerificationState {
  final EmailVerificationErrorType type;
  final String message;

  const EmailVerificationError({
    required this.type,
    required this.message,
  });
}

/// Error types for email verification.
enum EmailVerificationErrorType {
  invalidCode,
  codeExpired,
  rateLimited,
  networkError,
  unknown,
}

// ═══════════════════════════════════════════════════════════════════════════════
// State Notifier
// ═══════════════════════════════════════════════════════════════════════════════

/// Notifier for managing email verification flow.
class EmailVerificationNotifier extends StateNotifier<EmailVerificationState> {
  final EmailValidationRepository _repository;
  final Ref _ref;
  String? _currentEmail;

  EmailVerificationNotifier(this._repository, this._ref)
      : super(const EmailVerificationInitial());

  /// Get the current email being verified.
  String? get currentEmail => _currentEmail;

  /// Send verification code to the specified email.
  Future<bool> sendCode(String email) async {
    _currentEmail = email;
    state = const EmailVerificationLoading('Odesílám kód...');

    final result = await _repository.sendVerificationCode(email);

    if (result.isSuccess && result.data != null) {
      state = EmailVerificationCodeSent(expiresIn: result.data!.expiresIn);
      return true;
    }

    state = EmailVerificationError(
      type: EmailVerificationErrorType.networkError,
      message: result.error ?? 'Nepodařilo se odeslat kód',
    );
    return false;
  }

  /// Verify the code entered by the user.
  /// After code verification, checks if user exists and has a profile.
  Future<bool> verifyCode(String code) async {
    if (_currentEmail == null) {
      state = const EmailVerificationError(
        type: EmailVerificationErrorType.unknown,
        message: 'E-mail nebyl zadán',
      );
      return false;
    }

    state = const EmailVerificationLoading('Ověřuji kód...');

    final shared = _ref.read(sessionMetaProvider).pendingSharedDevice;
    final result = await _repository.verifyCode(
      _currentEmail!,
      code,
      sharedDevice: shared,
    );

    // Debug log the raw API response

    if (result.isSuccess && result.data?.valid == true) {
      final verifyToken = result.data!.token;

      final db = _ref.read(appDatabaseProvider);
      final activeUser = await db.getActiveUser();
      final isGuestUpgrade = activeUser != null && activeUser.email.isEmpty;

      // If verify returned a token, user already exists - fetch their profile
      if (verifyToken != null && verifyToken.isNotEmpty) {
        state = const EmailVerificationLoading('Načítám profil...');

        // Save token + session metadata so the rotation interceptor and
        // inactivity watcher pick up the new session.
        final apiClient = _ref.read(apiClientProvider);
        await apiClient.setAuthToken(verifyToken);
        await _ref.read(sessionMetaProvider).applyFromAuthResponse(
              result.data!.sessionPayload(),
            );

        // Fetch existing user data from /api/user
        try {
          final userResponse = await apiClient.get('/api/user');
          if (userResponse.statusCode == 200 && userResponse.data != null) {
            final userData = userResponse.data as Map<String, dynamic>;
            final serverName = userData['name'] as String? ?? '';
            final serverAvatarIndex = userData['avatar_index'] as int? ?? 0;
            final serverSubjects = userData['selected_subjects'];

            // Convert subjects to list
            List<String>? subjectsList;
            if (serverSubjects is List) {
              subjectsList = serverSubjects.map((e) => e.toString()).toList();
            }

            final user = RegisteredUser(
              id: userData['id'] as int,
              name: serverName,
              email: userData['email'] as String,
              avatarIndex: serverAvatarIndex,
              selectedSubjects: subjectsList,
            );

            if (isGuestUpgrade) {
              // Upgrade existing guest user instead of creating a new one
              await _upgradeGuestUser(activeUser.id, user);
            } else {
              // Save user to local database
              await _saveExistingUserToDatabase(user, verifyToken);
            }

            state = EmailVerificationSuccess(
              isNewUser: false,
              user: user,
            );
            await _triggerForceSync();
            return true;
          }
        } catch (e, st) { silentLog('email_validation_providers', e, st); }
      }

      // No token or fetch failed — new email registration
      if (isGuestUpgrade) {
        // Upgrade guest: set email and mark as validated locally
        await db.updateUserEmail(activeUser.id, _currentEmail!);
        await db.markEmailValidated(activeUser.id);

        // Also claim the guest on the server (upgrade server-side identity)
        final apiClient = _ref.read(apiClientProvider);
        if (apiClient.isAuthenticated) {
          final guestAuth = _ref.read(guestAuthServiceProvider);
          await guestAuth.claimGuest(_currentEmail!, name: activeUser.name);
        }

        _ref.invalidate(activeUserStreamProvider);
      }

      state = const EmailVerificationSuccess(isNewUser: true);
      await _triggerForceSync();
      return true;
    }

    // Handle specific error types
    final errorType = _parseErrorType(result.error);
    final errorMessage = _getErrorMessage(errorType);

    state = EmailVerificationError(
      type: errorType,
      message: errorMessage,
    );
    return false;
  }

  /// Upgrade a guest user with verified email and server profile data.
  Future<void> _upgradeGuestUser(String localUserId, RegisteredUser serverUser) async {
    final db = _ref.read(appDatabaseProvider);

    await db.updateUserEmail(localUserId, serverUser.email);
    await db.markEmailValidated(localUserId);

    // Merge server profile if available
    if (serverUser.name.isNotEmpty) {
      await db.updateUserProfile(
        userId: localUserId,
        name: serverUser.name,
        avatarIndex: serverUser.avatarIndex,
        selectedSubjects: serverUser.selectedSubjects != null
            ? jsonEncode(serverUser.selectedSubjects)
            : null,
      );
    }

    _ref.invalidate(activeUserStreamProvider);
  }

  /// Save existing user data to local database.
  /// Migrates any data from the previously active user (e.g. guest) to the
  /// new user record so course progress, stats, and bookmarks are preserved.
  Future<void> _saveExistingUserToDatabase(RegisteredUser user, String token) async {
    final db = _ref.read(appDatabaseProvider);

    // Capture old active user before it gets deactivated
    final oldUser = await db.getActiveUser();

    final newUserId = _generateUuid();
    await db.createAndActivateUser(
      UsersTableCompanion(
        id: Value(newUserId),
        email: Value(user.email),
        name: Value(user.name.isNotEmpty ? user.name : ''),
        avatarIndex: Value(user.avatarIndex ?? 0),
        selectedSubjects: Value(
          user.selectedSubjects != null
              ? jsonEncode(user.selectedSubjects)
              : '[0]',
        ),
        isEmailValidated: const Value(true),
        isActive: const Value(true),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );

    // Migrate data from old user to new user
    if (oldUser != null && oldUser.id != newUserId) {
      await db.migrateUserData(oldUser.id, newUserId);
    }

    _ref.invalidate(activeUserStreamProvider);
  }

  /// Save user data to local database.
  Future<void> _saveUserToDatabase(RegisterVerifiedResponse data) async {
    final db = _ref.read(appDatabaseProvider);
    final user = data.user;

    await db.createAndActivateUser(
      UsersTableCompanion(
        id: Value(_generateUuid()),
        email: Value(user.email),
        name: Value(user.name.isNotEmpty ? user.name : user.email.split('@').first),
        avatarIndex: Value(user.avatarIndex ?? 0),
        selectedSubjects: Value(
          user.selectedSubjects != null
              ? jsonEncode(user.selectedSubjects)
              : '[0]',
        ),
        isEmailValidated: const Value(true),
        isActive: const Value(true),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  String _generateUuid() {
    // Simple UUID v4 generation
    final random = DateTime.now().millisecondsSinceEpoch;
    return 'user-$random-${random.hashCode.abs()}';
  }

  /// Sync user with server after profile setup is complete.
  /// Call this from ProfileSetupPage after user is created locally.
  Future<bool> syncUserWithServer() async {
    final activeUser = await _ref.read(appDatabaseProvider).getActiveUser();
    if (activeUser == null) {
      return false;
    }

    // Parse selected subjects from JSON string to List<String>
    List<String>? selectedSubjects;
    try {
      final decoded = jsonDecode(activeUser.selectedSubjects) as List;
      selectedSubjects = decoded.map((e) => e.toString()).toList();
    } catch (_) {
      selectedSubjects = ['0'];
    }

    // Register/sync with server
    final shared = _ref.read(sessionMetaProvider).pendingSharedDevice;
    final registerResult = await _repository.registerVerified(
      email: activeUser.email,
      name: activeUser.name,
      avatarIndex: activeUser.avatarIndex,
      selectedSubjects: selectedSubjects,
      sharedDevice: shared,
    );

    if (registerResult.isSuccess && registerResult.data != null) {
      final response = registerResult.data!;

      // Store auth token + session meta
      final apiClient = _ref.read(apiClientProvider);
      await apiClient.setAuthToken(response.token);
      await _ref.read(sessionMetaProvider).applyFromAuthResponse(
            response.sessionPayload(),
          );

      // If existing user, sync data from server
      if (!response.isNewUser) {
        final serverUser = response.user;
        await _ref.read(appDatabaseProvider).updateUserProfile(
          userId: activeUser.id,
          name: serverUser.name,
          avatarIndex: serverUser.avatarIndex,
          selectedSubjects: serverUser.selectedSubjects != null
              ? jsonEncode(serverUser.selectedSubjects)
              : null,
        );
      }

      // Invalidate providers to trigger UI updates
      _ref.invalidate(activeUserStreamProvider);
      _ref.invalidate(isAuthenticatedProvider);

      // Push local data (course progress, bookmarks, stats) to server
      await _triggerForceSync();

      return true;
    }

    return false;
  }

  /// Trigger a force sync to push local data to the server.
  /// Wrapped in try/catch so sync failures don't block the login flow.
  Future<void> _triggerForceSync() async {
    try {
      final syncService = _ref.read(syncServiceProvider);
      await syncService.forceSync();
    } catch (e, st) { silentLog('email_validation_providers', e, st); }
  }

  /// Resend the verification code.
  Future<bool> resendCode() async {
    if (_currentEmail == null) return false;
    return sendCode(_currentEmail!);
  }

  /// Reset to initial state.
  void reset() {
    _currentEmail = null;
    state = const EmailVerificationInitial();
  }

  EmailVerificationErrorType _parseErrorType(String? error) {
    return switch (error) {
      'invalid_code' => EmailVerificationErrorType.invalidCode,
      'code_expired' => EmailVerificationErrorType.codeExpired,
      'rate_limited' => EmailVerificationErrorType.rateLimited,
      _ => EmailVerificationErrorType.unknown,
    };
  }

  String _getErrorMessage(EmailVerificationErrorType type) {
    return switch (type) {
      EmailVerificationErrorType.invalidCode => 'Neplatný kód',
      EmailVerificationErrorType.codeExpired => 'Kód vypršel',
      EmailVerificationErrorType.rateLimited => 'Počkejte před dalším odesláním',
      EmailVerificationErrorType.networkError => 'Chyba připojení',
      EmailVerificationErrorType.unknown => 'Nastala neočekávaná chyba',
    };
  }
}

/// Provider for the email verification state notifier.
final emailVerificationProvider =
    StateNotifierProvider<EmailVerificationNotifier, EmailVerificationState>((ref) {
  final repository = ref.watch(emailValidationRepositoryProvider);
  return EmailVerificationNotifier(repository, ref);
});

// ═══════════════════════════════════════════════════════════════════════════════
// Banner Visibility Provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for determining if the email validation banner should be shown.
/// Returns true if the user is logged in but email is not validated.
/// Banner shows even when offline to remind user to verify when back online.
final showEmailValidationBannerProvider = Provider<bool>((ref) {
  final userAsync = ref.watch(activeUserStreamProvider);

  return userAsync.when(
    data: (user) => user != null && !user.isEmailValidated,
    loading: () => false,
    error: (_, __) => false,
  );
});
