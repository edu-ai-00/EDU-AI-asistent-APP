import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_token_storage.dart';
import '../services/guest_auth_service.dart';
import '../services/session_meta.dart';
import '../../data/datasources/local/course_local_datasource.dart';
import '../../data/datasources/local/user_progress_local_datasource.dart';
import '../../data/datasources/local/user_stats_local_datasource.dart';
import '../../data/datasources/remote/course_remote_datasource.dart';
import '../../data/datasources/remote/user_stats_remote_datasource.dart';
import '../../data/datasources/local/chat_local_datasource.dart';
import '../../data/datasources/remote/chat_remote_datasource.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/repositories/course_repository.dart';
import '../../data/repositories/elo_repository.dart';
import '../../models/skill_display_model.dart';
import '../elo/skill_display_service.dart';
import '../network/api_endpoints.dart';
import '../../data/repositories/gamification_config_repository.dart';
import '../../data/repositories/user_course_repository.dart';
import '../../data/repositories/user_progress_repository.dart';
import '../../data/repositories/user_stats_repository.dart';
import '../../models/gamification_config_model.dart';
import '../connectivity/connectivity_service.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../sync/sync_queue.dart';
import '../sync/sync_service.dart';
import 'package:eduai/core/util/silent_log.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Core Infrastructure Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for SharedPreferences.
/// Must be overridden with the actual instance during app initialization.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with the actual instance',
  );
});

/// Provider for the Drift database.
/// Singleton instance for the app lifetime.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(() => db.close());
  return db;
});

/// Provider for the auth-token storage (secure).
/// Must be overridden with the actual instance during app initialization.
final authTokenStorageProvider = Provider<AuthTokenStorage>((ref) {
  throw UnimplementedError(
    'authTokenStorageProvider must be overridden with the actual instance',
  );
});

/// Provider for the session metadata (shared_device flag, expiry,
/// last-active timestamp). Backed by SharedPreferences.
final sessionMetaProvider = Provider<SessionMeta>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SessionMeta(prefs);
});

/// Provider for the API client.
final apiClientProvider = Provider<ApiClient>((ref) {
  final tokens = ref.watch(authTokenStorageProvider);
  final session = ref.watch(sessionMetaProvider);
  return ApiClient(tokens, session: session, enableLogging: true);
});

/// Provider for the connectivity service.
final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(() => service.dispose());
  return service;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Guest Auth Service Provider
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the guest authentication service.
final guestAuthServiceProvider = Provider<GuestAuthService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  return GuestAuthService(apiClient: apiClient, prefs: prefs);
});

// ═══════════════════════════════════════════════════════════════════════════════
// Sync Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the sync queue.
final syncQueueProvider = Provider<SyncQueue>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncQueue(db);
});

/// Provider for the sync service.
final syncServiceProvider = Provider<SyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final syncQueue = ref.watch(syncQueueProvider);

  final service = SyncService(
    db: db,
    apiClient: apiClient,
    connectivity: connectivity,
    syncQueue: syncQueue,
  );

  // Initialize the sync service to start listening for connectivity changes.
  service.initialize();

  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream provider for sync state changes.
final syncStateProvider = StreamProvider<SyncState>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.stateStream;
});

/// Provider for pending sync count.
final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.getPendingCount();
});

// ═══════════════════════════════════════════════════════════════════════════════
// Data Source Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the local course data source.
final courseLocalDataSourceProvider = Provider<CourseLocalDataSource>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return CourseLocalDataSource(db);
});

/// Provider for the remote course data source.
final courseRemoteDataSourceProvider = Provider<CourseRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CourseRemoteDataSource(apiClient);
});

// ═══════════════════════════════════════════════════════════════════════════════
// Repository Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the course repository.
final courseRepositoryProvider = Provider<CourseRepository>((ref) {
  final localDataSource = ref.watch(courseLocalDataSourceProvider);
  final remoteDataSource = ref.watch(courseRemoteDataSourceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final syncQueue = ref.watch(syncQueueProvider);

  return CourseRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    connectivity: connectivity,
    syncQueue: syncQueue,
  );
});

// ═══════════════════════════════════════════════════════════════════════════════
// Connectivity Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Stream provider for connectivity state changes.
final connectivityStateProvider = StreamProvider<ConnectivityState>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  return connectivity.onConnectivityChanged;
});

/// Provider for current connectivity state.
final currentConnectivityProvider = FutureProvider<ConnectivityState>((ref) {
  final connectivity = ref.watch(connectivityServiceProvider);
  return connectivity.currentState;
});

/// Provider for whether the device is online.
final isOnlineProvider = FutureProvider<bool>((ref) async {
  final connectivity = ref.watch(connectivityServiceProvider);
  return connectivity.isOnline;
});

// ═══════════════════════════════════════════════════════════════════════════════
// Course Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Stream provider for all courses.
final coursesStreamProvider = StreamProvider<List<Course>>((ref) {
  final repository = ref.watch(courseRepositoryProvider);
  return repository.watchAllCourses();
});

/// Future provider for all courses (one-time fetch).
final coursesProvider = FutureProvider<List<Course>>((ref) async {
  final repository = ref.watch(courseRepositoryProvider);
  return repository.getAllCourses();
});

/// Provider family for a single course by ID.
final courseByIdProvider = FutureProvider.family<Course?, String>((ref, id) async {
  final repository = ref.watch(courseRepositoryProvider);
  return repository.getCourseById(id);
});

// ═══════════════════════════════════════════════════════════════════════════════
// Auth State Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for authentication state.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.isAuthenticated;
});

/// Provider for the current auth token.
final authTokenProvider = Provider<String?>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getAuthToken();
});

// ═══════════════════════════════════════════════════════════════════════════════
// User Providers
// ═══════════════════════════════════════════════════════════════════════════════

/// Provider for the currently active user.
final activeUserProvider = FutureProvider<UsersTableData?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.getActiveUser();
});

/// Stream provider for active user changes.
final activeUserStreamProvider = StreamProvider<UsersTableData?>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.watchActiveUser();
});

/// Provider for checking if a user is logged in locally.
final isUserLoggedInProvider = FutureProvider<bool>((ref) async {
  final user = await ref.watch(activeUserProvider.future);
  return user != null;
});

// ═══════════════════════════════════════════════════════════════════════════
// User Course Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the user course repository.
final userCourseRepositoryProvider = Provider<UserCourseRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final syncQueue = ref.watch(syncQueueProvider);

  return UserCourseRepository(
    db: db,
    apiClient: apiClient,
    connectivity: connectivity,
    syncQueue: syncQueue,
  );
});

/// Stream provider for user's courses.
/// Automatically watches the active user and their courses.
final userCoursesStreamProvider = StreamProvider<List<UserCourse>>((ref) {
  final userAsync = ref.watch(activeUserStreamProvider);
  final repository = ref.watch(userCourseRepositoryProvider);

  // If no user, return empty stream.
  final user = userAsync.valueOrNull;
  if (user == null) {
    return Stream.value(<UserCourse>[]);
  }

  // Return the user's courses stream.
  return repository.watchUserCourses(user.id);
});

/// Future provider for user's courses (one-time fetch).
final userCoursesProvider = FutureProvider<List<UserCourse>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final repository = ref.watch(userCourseRepositoryProvider);

  final user = await db.getActiveUser();
  if (user == null) return [];

  return repository.getUserCourses(user.id);
});

/// Provider family for checking if user has a specific course.
final hasUserCourseProvider = FutureProvider.family<bool, String>((ref, courseId) async {
  final db = ref.watch(appDatabaseProvider);
  final repository = ref.watch(userCourseRepositoryProvider);

  final user = await db.getActiveUser();
  if (user == null) return false;

  return repository.hasUserCourse(user.id, courseId);
});

// ═══════════════════════════════════════════════════════════════════════════
// User Progress Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the user progress local data source.
final userProgressLocalDataSourceProvider = Provider<UserProgressLocalDataSource>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return UserProgressLocalDataSource(db);
});

/// Provider for the user progress repository.
final userProgressRepositoryProvider = Provider<UserProgressRepository>((ref) {
  final localDataSource = ref.watch(userProgressLocalDataSourceProvider);
  final syncQueue = ref.watch(syncQueueProvider);
  final db = ref.watch(appDatabaseProvider);
  return UserProgressRepository(
    localDataSource: localDataSource,
    syncQueue: syncQueue,
    db: db,
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// User Stats Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the user stats local data source.
final userStatsLocalDataSourceProvider = Provider<UserStatsLocalDataSource>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return UserStatsLocalDataSource(db);
});

/// Provider for the user stats remote data source.
final userStatsRemoteDataSourceProvider = Provider<UserStatsRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return UserStatsRemoteDataSource(apiClient);
});

/// Provider for the user stats repository.
final userStatsRepositoryProvider = Provider<UserStatsRepository>((ref) {
  final localDataSource = ref.watch(userStatsLocalDataSourceProvider);
  final remoteDataSource = ref.watch(userStatsRemoteDataSourceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final syncQueue = ref.watch(syncQueueProvider);

  return UserStatsRepository(
    localDataSource: localDataSource,
    remoteDataSource: remoteDataSource,
    connectivity: connectivity,
    syncQueue: syncQueue,
  );
});

/// Stream provider for active user's stats.
/// Automatically watches the active user and their stats.
final userStatsStreamProvider = StreamProvider<UserStats?>((ref) {
  final userAsync = ref.watch(activeUserStreamProvider);
  final repository = ref.watch(userStatsRepositoryProvider);

  // If no user, return null stream.
  final user = userAsync.valueOrNull;
  if (user == null) {
    return Stream.value(null);
  }

  // Return the user's stats stream.
  return repository.watchUserStats(user.id);
});

/// Future provider for user's stats (one-time fetch).
final userStatsProvider = FutureProvider<UserStats?>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final repository = ref.watch(userStatsRepositoryProvider);

  final user = await db.getActiveUser();
  if (user == null) return null;

  return repository.getOrCreateUserStats(user.id);
});

// ═══════════════════════════════════════════════════════════════════════════
// Gamification Config & Achievements Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the gamification config repository.
final gamificationConfigRepositoryProvider = Provider<GamificationConfigRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final apiClient = ref.watch(apiClientProvider);
  return GamificationConfigRepository(db: db, apiClient: apiClient);
});

/// Future provider for the gamification config.
final gamificationConfigProvider = FutureProvider<GamificationConfig?>((ref) {
  final repository = ref.watch(gamificationConfigRepositoryProvider);
  return repository.getConfig();
});

/// Stream provider for the active user's earned achievement IDs.
final earnedAchievementsProvider = StreamProvider<List<String>>((ref) {
  final userAsync = ref.watch(activeUserStreamProvider);
  final db = ref.watch(appDatabaseProvider);

  final user = userAsync.valueOrNull;
  if (user == null) return Stream.value(<String>[]);

  return db.watchEarnedAchievements(user.id).map(
    (list) => list.map((a) => a.achievementId).toList(),
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// ELO / Adaptive Learning Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the ELO repository (student adaptive-learning profile).
final eloRepositoryProvider = Provider<EloRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return EloRepository(db: db);
});

/// Provider for computed skill cards from the user's ELO profile.
/// Tries local DB first; if no local profile, fetches from API directly.
/// Callers should use `ref.refresh(skillDisplayProvider)` before reading
/// to ensure fresh data (e.g. after sync or on page open).
final skillDisplayProvider = FutureProvider<List<SkillDisplay>>((ref) async {
  final user = await ref.watch(activeUserProvider.future);
  if (user == null) return [];

  final eloRepo = ref.watch(eloRepositoryProvider);

  // Try local DB first.
  var profile = await eloRepo.getProfile(user.id);

  // If no local profile, try fetching from API directly.
  if (profile == null) {
    try {
      final apiClient = ref.read(apiClientProvider);
      final result = await apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.userEloProfile,
      );
      if (result.isSuccess && result.data != null) {
        final data = result.data!;
        final serverElo = data['profil_elo'] as List<dynamic>?;
        final serverPocet = data['profil_pocet'] as List<dynamic>?;
        if (serverElo != null && serverPocet != null) {
          final profilElo = serverElo
              .map((e) => e == null ? null : (e as num).toDouble())
              .toList();
          final profilPocet =
              serverPocet.map((e) => (e as num).toInt()).toList();
          // Persist locally for future use.
          await eloRepo.saveProfile(user.id, profilElo, profilPocet);
          return SkillDisplayService.computeSkills(
            profilElo: profilElo,
            profilPocet: profilPocet,
          );
        }
      }
    } catch (e, st) { silentLog('core_providers', e, st); }
    return [];
  }

  return SkillDisplayService.computeSkills(
    profilElo: profile.profilElo,
    profilPocet: profile.profilPocet,
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// Chat Providers
// ═══════════════════════════════════════════════════════════════════════════

/// Provider for the chat local data source.
final chatLocalDataSourceProvider = Provider<ChatLocalDataSource>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ChatLocalDataSource(db);
});

/// Provider for the chat remote data source.
final chatRemoteDataSourceProvider = Provider<ChatRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return ChatRemoteDataSource(apiClient);
});

/// Provider for the chat repository.
final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final local = ref.watch(chatLocalDataSourceProvider);
  final remote = ref.watch(chatRemoteDataSourceProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final syncQueue = ref.watch(syncQueueProvider);
  return ChatRepository(
    localDataSource: local,
    remoteDataSource: remote,
    connectivity: connectivity,
    syncQueue: syncQueue,
  );
});

/// Stream of chat sessions for the active user.
final chatSessionsStreamProvider = StreamProvider<List<ChatSessionsTableData>>((ref) {
  final userAsync = ref.watch(activeUserStreamProvider);
  final local = ref.watch(chatLocalDataSourceProvider);
  final user = userAsync.valueOrNull;
  if (user == null) return Stream.value([]);
  return local.watchSessions(user.id);
});

/// Stream of messages for a specific chat session.
final chatMessagesStreamProvider =
    StreamProvider.family<List<ChatMessagesTableData>, String>((ref, sessionId) {
  final local = ref.watch(chatLocalDataSourceProvider);
  return local.watchMessages(sessionId);
});
