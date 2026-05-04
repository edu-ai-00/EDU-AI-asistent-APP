import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../connectivity/connectivity_service.dart';
import '../database/app_database.dart';
import '../network/api_client.dart';
import '../network/api_endpoints.dart';
import '../../data/datasources/local/chat_local_datasource.dart';
import '../../data/datasources/remote/chat_remote_datasource.dart';
import '../../data/repositories/chat_repository.dart';
import 'sync_queue.dart';
import 'sync_status.dart';
import 'package:eduai/core/util/silent_log.dart';

/// Current state of the sync service.
enum SyncState {
  /// Not syncing.
  idle,

  /// Currently syncing.
  syncing,

  /// Sync failed.
  error,
}

/// Orchestrates synchronization between local database and remote API.
///
/// Responsibilities:
/// - Process sync queue when connectivity is available
/// - Pull updates from server
/// - Handle conflicts (last-write-wins)
/// - Monitor connectivity changes to trigger sync
class SyncService {
  final AppDatabase _db;
  final ApiClient _apiClient;
  final ConnectivityService _connectivity;
  final SyncQueue _syncQueue;

  StreamSubscription<ConnectivityState>? _connectivitySubscription;
  Timer? _periodicSyncTimer;

  final _stateController = StreamController<SyncState>.broadcast();
  SyncState _currentState = SyncState.idle;
  DateTime? _lastSyncTime;
  bool _syncRequestedWhileBusy = false;

  /// Interval for periodic sync checks (when on WiFi).
  static const Duration periodicSyncInterval = Duration(minutes: 15);

  SyncService({
    required AppDatabase db,
    required ApiClient apiClient,
    required ConnectivityService connectivity,
    SyncQueue? syncQueue,
  })  : _db = db,
        _apiClient = apiClient,
        _connectivity = connectivity,
        _syncQueue = syncQueue ?? SyncQueue(db);

  /// Stream of sync state changes.
  Stream<SyncState> get stateStream => _stateController.stream;

  /// Current sync state.
  SyncState get currentState => _currentState;

  /// When the last successful sync completed.
  DateTime? get lastSyncTime => _lastSyncTime;

  /// When the next periodic sync is expected.
  DateTime? get nextSyncTime =>
      _lastSyncTime?.add(periodicSyncInterval);

  /// Initialize the sync service and start monitoring connectivity.
  void initialize() {
    // Listen for connectivity changes.
    _connectivitySubscription =
        _connectivity.onConnectivityChanged.listen((state) {
      if (state.isOnline) {
        // Trigger sync when any connection becomes available.
        sync();
      }
    });

    // Start periodic sync timer.
    _periodicSyncTimer = Timer.periodic(periodicSyncInterval, (_) async {
      final state = await _connectivity.currentState;
      if (state.isOnline) {
        sync();
      }
    });

    // Initial sync if online.
    _checkAndSync();
  }

  Future<void> _checkAndSync() async {
    final state = await _connectivity.currentState;
    if (state.isOnline) {
      sync();
    }
  }

  /// Perform a full sync: push local changes, then pull remote updates.
  /// If called while already syncing, schedules a follow-up sync so
  /// newly enqueued items (e.g. from lesson completion) are pushed ASAP.
  Future<void> sync() async {
    if (_currentState == SyncState.syncing) {
      _syncRequestedWhileBusy = true;
      return;
    }

    _setState(SyncState.syncing);

    try {
      // 1. Push local changes.
      await _pushChanges();

      // 2. Pull remote updates.
      await _pullUpdates();

      _lastSyncTime = DateTime.now();
      _setState(SyncState.idle);
    } catch (e) {
      _setState(SyncState.error);
    }

    // If sync was requested while we were busy, do another round
    // to push any items that were enqueued during the previous sync.
    if (_syncRequestedWhileBusy) {
      _syncRequestedWhileBusy = false;
      sync();
    }
  }

  /// Push local changes from the sync queue to the server.
  /// Processes in rounds — handlers may enqueue follow-up operations
  /// (e.g. CREATE sets serverId, then queues an UPDATE for unsync'd progress).
  Future<void> _pushChanges() async {
    // Skip push if not authenticated — no point hitting the API without a token
    if (!_apiClient.isAuthenticated) {
      return;
    }

    // Clean up permanently failed entries so they don't block pulls forever.
    await _cleanupDeadEntries();

    const maxRounds = 3;
    for (var round = 0; round < maxRounds; round++) {
      final operations = await _syncQueue.getPendingOperations();
      if (operations.isEmpty) {
        break;
      }

      // Batch ELO interactions into a single request
      await _batchEloInteractions(operations);

      // Process remaining (non-ELO-interaction) operations individually
      final remaining = operations.where((op) => op.tableName_ != 'elo_interactions').toList();
      for (final op in remaining) {
        try {
          final success = await _processOperation(op);
          if (success) {
            await _syncQueue.markSynced(op.id);
          } else {
            // Non-exception failure (e.g. 422) — mark as failed so it
            // doesn't retry endlessly in the same sync cycle
            await _syncQueue.markFailed(op.id, 'Operation returned false');
            // Reset local record's syncStatus so the pull can overwrite it
            // with server data instead of being blocked forever.
            await _resetSyncStatusForRecord(op.tableName_, op.recordId);
          }
        } catch (e) {
          await _syncQueue.markFailed(op.id, e.toString());
          await _resetSyncStatusForRecord(op.tableName_, op.recordId);
        }
      }
    }
  }

  /// Remove permanently failed sync queue entries and reset the corresponding
  /// local records' syncStatus to synced so that _pullUpdates can overwrite them.
  Future<void> _cleanupDeadEntries() async {
    final dead = await _db.removeDeadSyncEntries();
    for (final entry in dead) {
      await _resetSyncStatusForRecord(entry.tableName_, entry.recordId);
    }
  }

  /// Reset a local record's syncStatus to synced after a push failure,
  /// so that _pullUpdates can overwrite it with server data.
  Future<void> _resetSyncStatusForRecord(String tableName, String recordId) async {
    if (tableName == 'user_courses') {
      await _db.updateUserCourseSyncFields(
        id: recordId,
        syncStatus: SyncStatus.synced.toInt(),
      );
    } else if (tableName == 'users') {
      await _db.updateUserSyncStatus(recordId, SyncStatus.synced.toInt());
    } else if (tableName == 'user_stats') {
      await _db.updateUserStatsSyncStatus(recordId, SyncStatus.synced.toInt());
    } else if (tableName == 'user_elo_profiles') {
      await _db.updateEloProfileSyncStatus(recordId, SyncStatus.synced.toInt());
    } else if (tableName == 'chat_sessions') {
      await _db.updateChatSessionSyncStatus(recordId, 'synced');
    } else if (tableName == 'chat_messages') {
      await _db.updateChatMessageSyncStatus(recordId, 'synced');
    }
  }

  /// Registry of sync operation handlers by table name.
  late final _handlers =
      <String, Future<bool> Function(String, SyncOperation, Map<String, dynamic>)>{
    'courses': _processCourseOperation,
    'user_courses': _processUserCourseOperation,
    'users': _processUserProfileOperation,
    'user_stats': _processUserStatsOperation,
    'user_progress': _processUserProgressOperation,
    'content_feedback': _processContentFeedbackOperation,
    'bookmarks': _processBookmarkOperation,
    'user_achievements': _processUserAchievementOperation,
    'user_elo_profiles': _processEloProfileOperation,
    'elo_interactions': _processEloInteractionOperation,
    'chat_messages': _processChatMessageOperation,
    'chat_sessions': _processChatSessionOperation,
  };

  /// Process a single sync queue operation using the handler registry.
  Future<bool> _processOperation(SyncQueueTableData op) async {
    final payload = jsonDecode(op.payload) as Map<String, dynamic>;
    final operation = SyncOperationExtension.fromValue(op.operation);

    final handler = _handlers[op.tableName_];
    if (handler != null) {
      return handler(op.recordId, operation, payload);
    }

    return false;
  }

  /// Process a course sync operation.
  Future<bool> _processCourseOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    switch (operation) {
      case SyncOperation.create:
        final result = await _apiClient.post<Map<String, dynamic>>(
          ApiEndpoints.courses,
          data: payload,
        );

        if (result.isSuccess && result.data != null) {
          // Update local record with server ID.
          final serverId = result.data!['id'] as int;
          await _db.upsertCourse(
            CoursesTableCompanion(
              id: Value(localId),
              serverId: Value(serverId),
              syncStatus: Value(SyncStatus.synced.toInt()),
              serverUpdatedAt: Value(DateTime.parse(
                result.data!['updated_at'] as String,
              )),
            ),
          );
          return true;
        }
        return false;

      case SyncOperation.update:
        final course = await _db.getCourseById(localId);
        if (course == null || course.serverId == null) return false;

        final result = await _apiClient.put<Map<String, dynamic>>(
          ApiEndpoints.course(course.serverId!),
          data: payload,
        );

        if (result.isSuccess) {
          await _db.upsertCourse(
            CoursesTableCompanion(
              id: Value(localId),
              syncStatus: Value(SyncStatus.synced.toInt()),
              serverUpdatedAt: Value(DateTime.parse(
                result.data!['updated_at'] as String,
              )),
            ),
          );
          return true;
        }
        return false;

      case SyncOperation.delete:
        final course = await _db.getCourseById(localId);
        if (course == null || course.serverId == null) {
          // Never synced, just delete locally.
          await _db.deleteCourse(localId);
          return true;
        }

        final result = await _apiClient.delete<Map<String, dynamic>>(
          ApiEndpoints.course(course.serverId!),
        );

        if (result.isSuccess || result.statusCode == 404) {
          // Delete locally even if already deleted on server.
          await _db.deleteCourse(localId);
          return true;
        }
        return false;
    }
  }

  /// Process a user_courses sync operation.
  Future<bool> _processUserCourseOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    switch (operation) {
      case SyncOperation.create:
        final result = await _apiClient.post<Map<String, dynamic>>(
          ApiEndpoints.userCourses,
          data: payload,
        );

        // Course doesn't exist on server (bundled-only) — treat as success
        // so it doesn't retry endlessly.
        if (result.statusCode == 404) return true;

        if (result.isSuccess && result.data != null) {
          final serverData = result.data!['user_course'] as Map<String, dynamic>?
              ?? result.data!;
          final serverId = serverData['id'] as int;

          // Use UPDATE (not upsert) — the record already exists locally,
          // we just need to set serverId and mark as synced.
          await _db.updateUserCourseSyncFields(
            id: localId,
            serverId: serverId,
            syncStatus: SyncStatus.synced.toInt(),
          );

          // After serverId is established, check if there's unsync'd
          // progress that was saved while serverId was still null
          // (e.g. user completed a lesson before the CREATE was pushed).
          final freshRecord = await _db.getUserCourseById(localId);
          if (freshRecord != null && freshRecord.progressPercent > 0) {
            await _syncQueue.enqueue(
              tableName: 'user_courses',
              recordId: localId,
              operation: SyncOperation.update,
              payload: {
                'progress_percent': freshRecord.progressPercent,
                'status': freshRecord.status,
                'completed_lessons': freshRecord.completedLessons,
                'current_lesson_index': freshRecord.currentLessonIndex,
                'time_spent_seconds': freshRecord.timeSpentSeconds,
                'progress_data': jsonDecode(freshRecord.progressDataJson),
              },
            );
            // Mark as pending so _pullUserCourseUpdates won't overwrite
            // local progress before this UPDATE is pushed.
            await _db.updateUserCourseSyncFields(
              id: localId,
              syncStatus: SyncStatus.pending.toInt(),
            );
          }

          return true;
        }
        return false;

      case SyncOperation.update:
        final userCourse = await _db.getUserCourseById(localId);
        if (userCourse == null) {
          return false;
        }

        // Resolve the course's string identifier for the API URL.
        final course = await _db.getCourseById(userCourse.courseId);
        if (course == null) {
          return false;
        }

        final result = await _apiClient.put<Map<String, dynamic>>(
          ApiEndpoints.userCourse(course.courseId),
          data: payload,
        );

        if (result.isSuccess) {
          await _db.updateUserCourseSyncFields(
            id: localId,
            syncStatus: SyncStatus.synced.toInt(),
          );
          return true;
        }
        return false;

      case SyncOperation.delete:
        // For DELETE, the user_course may already be deleted locally.
        // Use course_id from the payload (stored at enqueue time).
        final courseIdentifier = payload['course_id'];
        if (courseIdentifier == null) return true;

        final result = await _apiClient.delete<Map<String, dynamic>>(
          ApiEndpoints.userCourse(courseIdentifier.toString()),
        );

        if (result.isSuccess || result.statusCode == 404) {
          return true;
        }
        return false;
    }
  }

  /// Process a user profile sync operation.
  Future<bool> _processUserProfileOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    // Profile only supports update — we never create/delete users from client.
    if (operation != SyncOperation.update) return false;

    final result = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.updateProfile,
      data: payload,
    );

    if (result.isSuccess) {
      await _db.updateUserSyncStatus(localId, SyncStatus.synced.toInt());
      return true;
    }
    return false;
  }

  /// Process a user_stats sync operation.
  Future<bool> _processUserStatsOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    if (operation != SyncOperation.update) return false;

    final result = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.userStats,
      data: payload,
    );

    if (result.isSuccess) {
      await _db.updateUserStatsSyncStatus(localId, SyncStatus.synced.toInt());
      return true;
    }
    return false;
  }

  /// Process a user_progress sync operation.
  /// Pushes lesson-level progress (answers, block states) to the server.
  Future<bool> _processUserProgressOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    // Only update is supported — progress is created locally and pushed.
    if (operation != SyncOperation.update) return false;

    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.userProgress,
      data: {
        'progress': [payload],
      },
    );

    if (result.isSuccess && result.data != null) {
      // Extract server ID from response
      final progressList = result.data!['progress'] as List<dynamic>? ?? [];
      if (progressList.isNotEmpty) {
        final serverId = (progressList.first as Map<String, dynamic>)['id'] as int?;
        await _db.updateProgressSyncStatus(
          localId,
          SyncStatus.synced.toInt(),
          serverId: serverId,
        );
      } else {
        await _db.updateProgressSyncStatus(localId, SyncStatus.synced.toInt());
      }
      return true;
    }
    return false;
  }

  /// Process content feedback — fire-and-forget POST to server.
  Future<bool> _processContentFeedbackOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    if (operation != SyncOperation.create) return false;

    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.contentFeedback,
      data: payload,
    );

    return result.isSuccess;
  }

  /// Process bookmark sync operations.
  Future<bool> _processBookmarkOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    switch (operation) {
      case SyncOperation.create:
        final result = await _apiClient.post<Map<String, dynamic>>(
          ApiEndpoints.userBookmarks,
          data: payload,
        );
        return result.isSuccess;

      case SyncOperation.delete:
        // POST to /delete endpoint with composite key — app doesn't have server IDs
        final result = await _apiClient.post<Map<String, dynamic>>(
          ApiEndpoints.userBookmarksDelete,
          data: payload,
        );
        return result.isSuccess || result.statusCode == 404;

      case SyncOperation.update:
        // Bookmarks don't have updates — only create/delete
        return true;
    }
  }

  /// Process user achievement sync operations.
  /// Pushes earned achievements to the server (idempotent).
  Future<bool> _processUserAchievementOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    if (operation != SyncOperation.create) return false;

    // API expects {"achievements": [{"id": "...", "earned_at": "..."}]}
    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.userAchievements,
      data: {
        'achievements': [
          {
            'id': payload['achievement_id'],
            'earned_at': payload['earned_at'],
          }
        ],
      },
    );

    if (result.isSuccess) {
      // Mark the local achievement record as synced
      await _db.markAchievementsSynced([localId]);
      return true;
    }
    return false;
  }

  /// Process ELO profile sync — PUT to server.
  Future<bool> _processEloProfileOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    if (operation != SyncOperation.update) return false;

    final result = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.userEloProfile,
      data: payload,
    );

    if (result.isSuccess) {
      await _db.updateEloProfileSyncStatus(localId, SyncStatus.synced.toInt());
      return true;
    }
    return false;
  }

  /// Process ELO interaction log — POST to server (append-only).
  Future<bool> _processEloInteractionOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    if (operation != SyncOperation.create) return false;

    final result = await _apiClient.post<Map<String, dynamic>>(
      ApiEndpoints.eloInteractions,
      data: payload,
    );

    // On success the sync queue auto-cleans the entry.
    return result.isSuccess;
  }

  /// Batch-send all pending ELO interaction operations in a single request.
  /// Returns true if all were handled (batched or individually), false if
  /// some items remain unprocessed and should be retried by the normal loop.
  Future<void> _batchEloInteractions(List<SyncQueueTableData> allOps) async {
    final eloOps = allOps.where((op) => op.tableName_ == 'elo_interactions').toList();
    if (eloOps.isEmpty) return;

    final payloads = <Map<String, dynamic>>[];
    final createOps = <SyncQueueTableData>[];
    for (final op in eloOps) {
      try {
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        final operation = SyncOperationExtension.fromValue(op.operation);
        if (operation == SyncOperation.create) {
          payloads.add(payload);
          createOps.add(op);
        }
      } catch (e, st) { silentLog('sync_service', e, st); }
    }

    if (payloads.isEmpty) return;

    // Use batch endpoint for any number of interactions
    try {
      final result = await _apiClient.post<Map<String, dynamic>>(
        ApiEndpoints.eloInteractionsBatch,
        data: {'interactions': payloads},
      );

      if (result.isSuccess) {
        for (final op in createOps) {
          await _syncQueue.markSynced(op.id);
        }
        return;
      }
    } catch (e, st) { silentLog('sync_service', e, st); }

    // Batch failed — fall back to individual sends
    for (final op in createOps) {
      try {
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        final result = await _apiClient.post<Map<String, dynamic>>(
          ApiEndpoints.eloInteractions,
          data: payload,
        );
        if (result.isSuccess) {
          await _syncQueue.markSynced(op.id);
        }
      } catch (e, st) { silentLog('sync_service', e, st); }
    }
  }

  /// Process chat message sync — UPDATE pushes feedback to server.
  Future<bool> _processChatMessageOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    if (operation != SyncOperation.update) return false;

    // Look up the message to get its serverId.
    final rows = await (_db.select(_db.chatMessagesTable)
          ..where((m) => m.id.equals(localId))
          ..limit(1))
        .get();
    if (rows.isEmpty) return false;
    final message = rows.first;

    if (message.serverId == null) return false;

    final result = await _apiClient.put<Map<String, dynamic>>(
      ApiEndpoints.chatMessageFeedback(message.serverId!),
      data: payload,
    );

    if (result.isSuccess) {
      await _db.updateChatMessageSyncStatus(localId, 'synced');
      return true;
    }
    return false;
  }

  /// Process chat session sync — DELETE removes session on server.
  Future<bool> _processChatSessionOperation(
    String localId,
    SyncOperation operation,
    Map<String, dynamic> payload,
  ) async {
    if (operation != SyncOperation.delete) return false;

    final serverId = payload['server_id'] as int?;
    if (serverId == null) return false;

    final result = await _apiClient.delete<Map<String, dynamic>>(
      ApiEndpoints.chatSession(serverId),
    );

    return result.isSuccess || result.statusCode == 404;
  }

  /// Pull updates from the server.
  /// Each pull is wrapped in try/catch so one failure doesn't block others.
  Future<void> _pullUpdates() async {
    await _safePull(_pullCourseUpdates);
    await _safePull(_pullGamificationConfig);
    // User-specific pulls require authentication
    if (_apiClient.isAuthenticated) {
      await _safePull(_pullUserCourseUpdates);
      await _safePull(_pullUserStatsUpdates);
      await _safePull(_pullUserProgressUpdates);
      await _safePull(_pullBookmarkUpdates);
      await _safePull(_pullUserAchievements);
      await _safePull(_pullEloProfile);
      await _safePull(_pullBlockStats);
      await _safePull(_pullChatUpdates);
    }
  }

  Future<void> _safePull(Future<void> Function() fn) async {
    try {
      await fn();
    } catch (e, st) { silentLog('sync_service', e, st); }
  }

  /// Pull course updates from the server.
  Future<void> _pullCourseUpdates() async {
    // Get the most recent server update timestamp we have.
    final courses = await _db.getAllCourses();
    DateTime? lastUpdate;

    for (final course in courses) {
      if (course.serverUpdatedAt != null) {
        if (lastUpdate == null ||
            course.serverUpdatedAt!.isAfter(lastUpdate)) {
          lastUpdate = course.serverUpdatedAt;
        }
      }
    }

    // Fetch updates from server.
    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.coursesCheckUpdates,
      queryParameters: lastUpdate != null
          ? {'since': lastUpdate.toIso8601String()}
          : null,
    );

    if (result.isSuccess && result.data != null) {
      final updatedCourses = result.data!['data'] as List<dynamic>?;

      if (updatedCourses != null) {
        for (final courseData in updatedCourses) {
          await _mergeServerCourse(courseData as Map<String, dynamic>);
        }
      }
    }
  }

  /// Pull user course updates from the server.
  Future<void> _pullUserCourseUpdates() async {
    final activeUser = await _db.getActiveUser();
    if (activeUser == null) return;

    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.userCourses,
    );

    if (result.isFailure || result.data == null) return;

    final userCoursesJson =
        result.data!['user_courses'] as List<dynamic>? ?? [];

    for (final json in userCoursesJson) {
      final remoteData = json as Map<String, dynamic>;
      final serverId = remoteData['id'] as int;

      // API now returns course_id as string identifier and server_id as numeric FK.
      // Handle both old (numeric course_id) and new formats for backwards compatibility.
      final courseIdRaw = remoteData['course_id'];
      final courseNumericId = remoteData['server_id'] as int?
          ?? (courseIdRaw is int ? courseIdRaw : null);
      final courseStringId = courseIdRaw is String ? courseIdRaw : null;

      // Find the local course — try numeric server ID first, then string course_id.
      CoursesTableData? localCourse;
      if (courseNumericId != null) {
        localCourse = await _db.getCourseByServerId(courseNumericId);
      }
      localCourse ??= courseStringId != null
          ? await _db.getCourseByFieldCourseId(courseStringId)
          : null;
      if (localCourse == null) continue;

      // Repair the local courses row from the embedded `course` payload —
      // this fixes legacy rows where `name` was poisoned with the raw code
      // and keeps title/version/status in sync without waiting for the next
      // /courses pull.
      final embeddedCourse =
          remoteData['course'] as Map<String, dynamic>?;
      if (embeddedCourse != null && localCourse.syncStatus != SyncStatus.pending.toInt()) {
        final embeddedName = (embeddedCourse['name'] as String?)?.trim();
        final embeddedCourseId = (embeddedCourse['course_id'] as String?)?.trim();
        final embeddedVersion = embeddedCourse['version'] as int?;
        final embeddedStatus = embeddedCourse['status'] as String?;
        final embeddedLanguage = embeddedCourse['language'] as String?;

        // Only update if the catalog payload would change something, to
        // avoid noisy writes on every sync.
        final nameChanged = embeddedName != null &&
            embeddedName.isNotEmpty &&
            embeddedName != localCourse.name;
        final courseIdChanged = embeddedCourseId != null &&
            embeddedCourseId.isNotEmpty &&
            embeddedCourseId != localCourse.courseId;
        final versionChanged =
            embeddedVersion != null && embeddedVersion != localCourse.version;
        final statusChanged =
            embeddedStatus != null && embeddedStatus != localCourse.status;
        final langChanged =
            embeddedLanguage != null && embeddedLanguage != localCourse.language;

        if (nameChanged || courseIdChanged || versionChanged || statusChanged || langChanged) {
          await _db.upsertCourse(
            CoursesTableCompanion(
              id: Value(localCourse.id),
              serverId: Value(courseNumericId ?? localCourse.serverId),
              courseId: courseIdChanged
                  ? Value(embeddedCourseId)
                  : const Value.absent(),
              name: nameChanged ? Value(embeddedName) : const Value.absent(),
              version: versionChanged
                  ? Value(embeddedVersion)
                  : const Value.absent(),
              status: statusChanged
                  ? Value(embeddedStatus)
                  : const Value.absent(),
              language: langChanged
                  ? Value(embeddedLanguage)
                  : const Value.absent(),
              syncStatus: Value(SyncStatus.synced.toInt()),
              updatedAt: Value(DateTime.now()),
            ),
          );
          // Re-read so the rest of the loop sees the patched row.
          localCourse = await _db.getCourseById(localCourse.id) ?? localCourse;
        }
      }

      // Find existing local user course — first by server ID, then by
      // userId+courseId (handles code-entry records that don't have serverId yet).
      var existingLocal = await _db.getUserCourseByServerId(serverId);
      existingLocal ??= await _db.getUserCourseByUserAndCourse(
        activeUser.id,
        localCourse.id,
      );

      // Skip records with pending local changes.
      if (existingLocal != null &&
          existingLocal.syncStatus == SyncStatus.pending.toInt()) {
        continue;
      }

      final remoteProgress = remoteData['progress_percent'] as int? ?? 0;
      final remoteCompleted = remoteData['completed_lessons'] as int? ?? 0;
      final localProgress = existingLocal?.progressPercent ?? 0;
      final localCompleted = existingLocal?.completedLessons ?? 0;

      // Never regress progress — take the higher value between local and remote.
      final mergedProgress = remoteProgress >= localProgress
          ? remoteProgress : localProgress;
      final mergedCompleted = remoteCompleted >= localCompleted
          ? remoteCompleted : localCompleted;

      // Determine status — never downgrade from 'completed'.
      final remoteStatus = remoteData['status'] as String? ?? 'downloaded';
      final localStatus = existingLocal?.status;
      final mergedStatus = localStatus == 'completed' && remoteStatus != 'completed'
          ? 'completed' : remoteStatus;

      // For progressDataJson: if server returns null/missing, keep local data.
      // If both exist, prefer the one with more entries (more complete).
      final Value<String> mergedProgressDataJson;
      if (remoteData['progress_data'] != null) {
        final remoteJson = jsonEncode(remoteData['progress_data']);
        final localJson = existingLocal?.progressDataJson ?? '{}';
        // If local has richer data (more keys), keep it.
        // Server may return progress_data as a List or Map — only compare
        // lengths when both sides are Maps.
        final remoteRaw = remoteData['progress_data'];
        final remoteMap = remoteRaw is Map<String, dynamic> ? remoteRaw : null;
        final localDecoded = localJson != '{}' ? jsonDecode(localJson) : null;
        final localMap = localDecoded is Map<String, dynamic> ? localDecoded : null;
        if (remoteMap != null && localMap != null && localMap.length > remoteMap.length) {
          mergedProgressDataJson = Value(localJson);
        } else {
          mergedProgressDataJson = Value(remoteJson);
        }
      } else {
        // Server didn't return progress_data — keep whatever we have locally.
        if (existingLocal != null) {
          mergedProgressDataJson = const Value.absent();
        } else {
          mergedProgressDataJson = const Value('{}');
        }
      }

      // Keep local currentLessonIndex/timeSpent if they're ahead.
      final remoteIndex = remoteData['current_lesson_index'] as int? ?? 0;
      final localIndex = existingLocal?.currentLessonIndex ?? 0;
      final remoteTime = remoteData['time_spent_seconds'] as int? ?? 0;
      final localTime = existingLocal?.timeSpentSeconds ?? 0;

      if (mergedProgress > remoteProgress || mergedCompleted > remoteCompleted) {
      }

      // Preserve "last user interaction" semantics for ordering. The local
      // updateUserCourseProgress path stamps updatedAt = DateTime.now() on
      // real user actions; we MUST NOT clobber that on every periodic pull.
      // Use the max of local updatedAt and the server-reported updated_at
      // (which itself reflects the last activity persisted server-side).
      DateTime? remoteUpdatedAt;
      try {
        final raw = remoteData['updated_at'];
        if (raw is String && raw.isNotEmpty) {
          remoteUpdatedAt = DateTime.parse(raw).toUtc();
        }
      } catch (_) {}
      final DateTime resolvedUpdatedAt;
      if (existingLocal == null) {
        resolvedUpdatedAt = remoteUpdatedAt ?? DateTime.now();
      } else if (remoteUpdatedAt != null &&
          remoteUpdatedAt.isAfter(existingLocal.updatedAt)) {
        resolvedUpdatedAt = remoteUpdatedAt;
      } else {
        resolvedUpdatedAt = existingLocal.updatedAt;
      }

      await _db.upsertUserCourse(
        UserCoursesTableCompanion(
          id: Value(existingLocal?.id ?? _generateLocalId()),
          serverId: Value(serverId),
          userId: Value(activeUser.id),
          courseId: Value(localCourse.id),
          status: Value(mergedStatus),
          progressPercent: Value(mergedProgress),
          completedLessons: Value(mergedCompleted),
          totalLessons: Value(remoteData['total_lessons'] as int? ?? 0),
          currentLessonIndex: Value(remoteIndex >= localIndex ? remoteIndex : localIndex),
          timeSpentSeconds: Value(remoteTime >= localTime ? remoteTime : localTime),
          progressDataJson: mergedProgressDataJson,
          // downloadedVersion=0 means synced from server but full course
          // data not yet downloaded from R2. The knihovna page uses this
          // to show a download button instead of "Staženo".
          downloadedVersion: existingLocal != null
              ? const Value.absent()
              : const Value(0),
          syncStatus: Value(SyncStatus.synced.toInt()),
          updatedAt: Value(resolvedUpdatedAt),
        ),
      );
    }
  }

  /// Pull user stats updates from the server.
  Future<void> _pullUserStatsUpdates() async {
    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.userStats,
    );

    if (result.isFailure || result.data == null) return;

    final statsJson =
        result.data!['stats'] as Map<String, dynamic>?;
    if (statsJson == null) return;

    final serverId = statsJson['id'] as int;
    final activeUser = await _db.getActiveUser();
    if (activeUser == null) return;

    final existingStats = await _db.getUserStats(activeUser.id);

    // Skip if local has pending changes.
    if (existingStats != null &&
        existingStats.syncStatus == SyncStatus.pending.toInt()) {
      return;
    }

    await _db.upsertUserStats(
      UserStatsTableCompanion(
        id: Value(existingStats?.id ?? _generateLocalId()),
        serverId: Value(serverId),
        userId: Value(activeUser.id),
        level: Value(statsJson['level'] as int? ?? 1),
        xpPoints: Value(statsJson['xp_points'] as int? ?? 0),
        coursesCount: Value(statsJson['courses_count'] as int? ?? 0),
        streakDays: Value(statsJson['streak_days'] as int? ?? 0),
        achievementsCount:
            Value(statsJson['achievements_count'] as int? ?? 0),
        lastStreakDate: Value(
          statsJson['last_streak_date'] != null
              ? DateTime.parse(statsJson['last_streak_date'] as String)
              : null,
        ),
        dailyXpDate: Value(
          statsJson['daily_xp_date'] != null
              ? DateTime.parse(statsJson['daily_xp_date'] as String)
              : null,
        ),
        dailyXpAmount: Value(statsJson['daily_xp_amount'] as int? ?? 0),
        syncStatus: Value(SyncStatus.synced.toInt()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Pull user progress (lesson-level answers/block states) from server.
  Future<void> _pullUserProgressUpdates() async {
    final activeUser = await _db.getActiveUser();
    if (activeUser == null) return;

    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.userProgress,
    );

    if (result.isFailure || result.data == null) return;

    final progressList =
        result.data!['progress'] as List<dynamic>? ?? [];

    for (final json in progressList) {
      final remote = json as Map<String, dynamic>;
      final serverId = remote['id'] as int;
      final remoteCourseId = remote['course_id'] as String;
      final remoteLessonId = remote['lesson_id'] as String;

      // Resolve string course_id → local courseId (UUID).
      final course = await _db.getCourseByFieldCourseId(remoteCourseId);
      if (course == null) continue; // Course not downloaded locally yet

      // Check if we already have this lesson's progress locally.
      final existing = await _db.getLessonProgress(activeUser.id, remoteLessonId);

      // Skip if local has pending changes.
      if (existing != null &&
          existing.syncStatus == SyncStatus.pending.toInt()) {
        continue;
      }

      // Never regress progress — keep local data if it's more complete.
      final remotePercent = remote['progress_percent'] as int? ?? 0;
      final localPercent = existing?.progressPercent ?? 0;
      final remoteCompleted = remote['is_completed'] as bool? ?? false;
      final localCompleted = existing?.isCompleted ?? false;

      // For progressData: keep local if server returns null or local has more data.
      final Value<String> mergedProgressData;
      if (remote['progress_data'] != null) {
        final remoteJson = jsonEncode(remote['progress_data']);
        final localJson = existing?.progressData ?? '{}';
        // Server may return progress_data as a List or Map — only compare
        // lengths when both sides are Maps.
        final remoteRaw = remote['progress_data'];
        final remoteMap = remoteRaw is Map<String, dynamic> ? remoteRaw : null;
        final localDecoded = localJson != '{}' ? jsonDecode(localJson) : null;
        final localMap = localDecoded is Map<String, dynamic> ? localDecoded : null;
        mergedProgressData = (remoteMap != null && localMap != null && localMap.length > remoteMap.length)
            ? Value(localJson)
            : Value(remoteJson);
      } else if (existing != null) {
        mergedProgressData = const Value.absent();
      } else {
        mergedProgressData = const Value('{}');
      }

      await _db.upsertProgress(
        UserProgressTableCompanion(
          id: Value(existing?.id ?? _generateLocalId()),
          serverId: Value(serverId),
          userId: Value(activeUser.id),
          courseId: Value(course.id),
          lessonId: Value(remoteLessonId),
          progressPercent: Value(remotePercent >= localPercent ? remotePercent : localPercent),
          isCompleted: Value(remoteCompleted || localCompleted),
          lastPosition: Value(remote['last_position'] as int? ?? existing?.lastPosition ?? 0),
          timeSpentSeconds: Value(remote['time_spent_seconds'] as int? ?? existing?.timeSpentSeconds ?? 0),
          progressData: mergedProgressData,
          startedAt: Value(
            remote['started_at'] != null
                ? DateTime.parse(remote['started_at'] as String)
                : existing?.startedAt,
          ),
          completedAt: Value(
            remote['completed_at'] != null
                ? DateTime.parse(remote['completed_at'] as String)
                : existing?.completedAt,
          ),
          syncStatus: Value(SyncStatus.synced.toInt()),
          updatedAt: Value(DateTime.now()),
        ),
      );
    }
  }

  /// Pull bookmark updates from the server.
  /// Full replace: server is the source of truth for bookmarks.
  Future<void> _pullBookmarkUpdates() async {
    final activeUser = await _db.getActiveUser();
    if (activeUser == null) return;

    final result = await _apiClient.get<Map<String, dynamic>>(
      ApiEndpoints.userBookmarks,
    );

    if (result.isFailure || result.data == null) return;

    final bookmarksList =
        result.data!['data'] as List<dynamic>? ?? [];

    // Collect server bookmark keys for diffing
    final serverKeys = <String>{};

    for (final json in bookmarksList) {
      final remote = json as Map<String, dynamic>;
      final courseId = remote['course_id'] as String? ?? '';
      final blockId = remote['block_id'] as String? ?? '';
      final lessonId = remote['lesson_id'] as String? ?? '';

      if (courseId.isEmpty || blockId.isEmpty) continue;
      serverKeys.add('$courseId:$blockId');

      // Check if we already have this bookmark locally
      final exists = await _db.isBookmarked(activeUser.id, courseId, blockId);
      if (!exists) {
        await _db.addBookmark(
          BookmarksTableCompanion(
            id: Value(_generateLocalId()),
            userId: Value(activeUser.id),
            courseId: Value(courseId),
            blockId: Value(blockId),
            lessonId: Value(lessonId),
          ),
        );
      }
    }

    // Remove local bookmarks not on server
    final localBookmarks = await _db.getAllBookmarks(activeUser.id);
    for (final local in localBookmarks) {
      final key = '${local.courseId}:${local.blockId}';
      if (!serverKeys.contains(key)) {
        await _db.removeBookmark(activeUser.id, local.courseId, local.blockId);
      }
    }
  }

  /// Pull gamification config from server (public endpoint).
  Future<void> _pullGamificationConfig() async {
    try {
      final result = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.gamificationConfig,
      );

      if (result.isSuccess && result.data != null) {
        final data = result.data!;
        final version = data['version'] as int? ?? 1;

        // Check if we already have this version cached.
        final cached = await _db.getGamificationConfig();
        if (cached != null && cached.version >= version) {
          return; // Already up to date
        }

        await _db.saveGamificationConfig(
          version: version,
          configJson: jsonEncode(data),
        );
      }
    } catch (e, st) { silentLog('sync_service', e, st); }
  }

  /// Pull user's earned achievements from the server.
  Future<void> _pullUserAchievements() async {
    final activeUser = await _db.getActiveUser();
    if (activeUser == null) return;

    try {
      final result = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.userAchievements,
      );

      if (result.isFailure || result.data == null) return;

      final achievementsList =
          result.data!['achievements'] as List<dynamic>? ?? [];

      for (final json in achievementsList) {
        final remote = json as Map<String, dynamic>;
        final achievementId = remote['achievement_id'] as String? ?? '';
        if (achievementId.isEmpty) continue;

        final earnedAtStr = remote['earned_at'] as String?;
        final earnedAt = earnedAtStr != null
            ? DateTime.tryParse(earnedAtStr) ?? DateTime.now()
            : DateTime.now();

        // Insert — will be a no-op if already exists (UNIQUE constraint).
        await _db.insertAchievement(
          id: _generateLocalId(),
          userId: activeUser.id,
          achievementId: achievementId,
          earnedAt: earnedAt,
          syncStatus: 0, // Already on server
        );
      }

    } catch (e, st) { silentLog('sync_service', e, st); }
  }

  /// Pull the user's ELO profile from the server.
  /// Skips if local profile has pending changes (to avoid overwriting unsent updates).
  Future<void> _pullEloProfile() async {
    final activeUser = await _db.getActiveUser();
    if (activeUser == null) return;

    try {
      final result = await _apiClient.get<Map<String, dynamic>>(
        ApiEndpoints.userEloProfile,
      );

      if (result.isFailure || result.data == null) return;

      final serverData = result.data!;
      final serverElo = serverData['profil_elo'];
      final serverPocet = serverData['profil_pocet'];

      // Server might return null if no profile exists yet
      if (serverElo == null || serverPocet == null) return;

      // Check if local profile has pending changes — don't overwrite
      final localRows = await (_db.select(_db.userEloProfileTable)
            ..where((t) => t.userId.equals(activeUser.id)))
          .get();

      if (localRows.isNotEmpty &&
          localRows.first.syncStatus == SyncStatus.pending.toInt()) {
        return;
      }

      final now = DateTime.now();
      final eloJson = jsonEncode(serverElo);
      final pocetJson = jsonEncode(serverPocet);

      if (localRows.isNotEmpty) {
        // Update existing profile with server data
        await (_db.update(_db.userEloProfileTable)
              ..where((t) => t.id.equals(localRows.first.id)))
            .write(UserEloProfileTableCompanion(
          profilElo: Value(eloJson),
          profilPocet: Value(pocetJson),
          syncStatus: Value(SyncStatus.synced.toInt()),
          updatedAt: Value(now),
        ));
      } else {
        // Create new local profile from server data
        await _db.into(_db.userEloProfileTable).insert(
          UserEloProfileTableCompanion(
            id: Value(_generateLocalId()),
            userId: Value(activeUser.id),
            profilElo: Value(eloJson),
            profilPocet: Value(pocetJson),
            syncStatus: Value(SyncStatus.synced.toInt()),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
      }

    } catch (e, st) { silentLog('sync_service', e, st); }
  }

  /// Pull block stats (item_pocet + elo_vector) from the server for blocks
  /// the user has interacted with. Caches locally for offline ELO computation.
  Future<void> _pullBlockStats() async {
    try {
      // Get all locally cached block IDs to request updates
      final localStats = await _db.select(_db.blockStatsTable).get();
      if (localStats.isEmpty) return;

      final blockIds = localStats.map((r) => r.blockId).join(',');
      final result = await _apiClient.get<Map<String, dynamic>>(
        '${ApiEndpoints.blockStats}?block_ids=$blockIds',
      );

      if (result.isFailure || result.data == null) return;

      final data = result.data!;
      final stats = data['data'] as List<dynamic>?;
      if (stats == null) return;

      for (final stat in stats) {
        if (stat is! Map<String, dynamic>) continue;
        final blockId = stat['block_id'] as String?;
        if (blockId == null) continue;

        final itemPocet = stat['item_pocet'];
        final eloVector = stat['elo_vector'];
        if (itemPocet == null || eloVector == null) continue;

        await _db.upsertBlockStats(
          blockId: blockId,
          itemPocet: jsonEncode(itemPocet),
          eloVector: jsonEncode(eloVector),
        );
      }
    } catch (e, st) { silentLog('sync_service', e, st); }
  }

  /// Pull chat session and message history from server.
  Future<void> _pullChatUpdates() async {
    try {
      final user = await _db.getActiveUser();
      if (user == null) return;

      final chatRepo = ChatRepository(
        localDataSource: ChatLocalDataSource(_db),
        remoteDataSource: ChatRemoteDataSource(_apiClient),
        connectivity: _connectivity,
        syncQueue: _syncQueue,
      );

      await chatRepo.pullHistory(user.id);
    } catch (e) {
      print('[SyncService] Chat pull failed: $e');
    }
  }

  /// Merge a server course with local data.
  /// Only updates metadata (name, version, status, language).
  /// NEVER touches the `data` column — course content (blocks/lessons)
  /// is exclusively managed by downloadFullCourseJson() from R2.
  /// Sync only handles metadata + user state.
  Future<void> _mergeServerCourse(Map<String, dynamic> serverData) async {
    final serverId = serverData['id'] as int;
    final serverUpdatedAt = DateTime.parse(serverData['updated_at'] as String);

    // Find local record by server ID, or by course_id string (for bundled courses
    // that were imported without a serverId).
    final courseIdStr = serverData['course_id'] as String;
    var localCourse = await _db.getCourseByServerId(serverId);
    localCourse ??= await _db.getCourseByFieldCourseId(courseIdStr);

    if (localCourse == null) {
      // New course from server — create a catalog entry with metadata only.
      // Full course data (blocks/lessons) will be downloaded from R2
      // when the user adds the course from the library (knihovna).
      await _db.upsertCourse(
        CoursesTableCompanion(
          id: Value(_generateLocalId()),
          serverId: Value(serverId),
          courseId: Value(courseIdStr),
          // Use generic placeholder when API has no name — never the
          // raw course_id, which leaks the internal code into UI.
          name: Value(
            (serverData['name'] as String?)?.trim().isNotEmpty == true
                ? serverData['name'] as String
                : 'Kurz',
          ),
          version: Value(serverData['version'] as int? ?? 1),
          status: Value(serverData['status'] as String? ?? 'published'),
          language: Value(serverData['language'] as String? ?? 'en'),
          // data: left as default '{}' — will be populated by R2 download
          syncStatus: Value(SyncStatus.synced.toInt()),
          serverUpdatedAt: Value(serverUpdatedAt),
          updatedAt: Value(serverUpdatedAt),
        ),
      );
    } else {
      // Existing course — only update metadata, never touch data column.
      if (localCourse.syncStatus == SyncStatus.pending.toInt()) {
        if (serverUpdatedAt.isAfter(localCourse.updatedAt)) {
          // Server wins for metadata only.
          final serverName = serverData['name'] as String?;
          await _db.upsertCourse(
            CoursesTableCompanion(
              id: Value(localCourse.id),
              serverId: Value(serverId),
              courseId: Value(serverData['course_id'] as String),
              name: serverName != null ? Value(serverName) : const Value.absent(),
              version: Value(serverData['version'] as int? ?? 1),
              status: Value(serverData['status'] as String? ?? 'published'),
              language: serverData['language'] != null
                  ? Value(serverData['language'] as String)
                  : const Value.absent(),
              syncStatus: Value(SyncStatus.synced.toInt()),
              serverUpdatedAt: Value(serverUpdatedAt),
              updatedAt: Value(serverUpdatedAt),
            ),
          );
          await _syncQueue.clearForRecord('courses', localCourse.id);
        }
      } else {
        // No local pending changes — update metadata only.
        final serverName = serverData['name'] as String?;
        await _db.upsertCourse(
          CoursesTableCompanion(
            id: Value(localCourse.id),
            serverId: Value(serverId),
            courseId: Value(serverData['course_id'] as String),
            name: serverName != null ? Value(serverName) : const Value.absent(),
            version: Value(serverData['version'] as int? ?? 1),
            status: Value(serverData['status'] as String? ?? 'published'),
            language: serverData['language'] != null
                ? Value(serverData['language'] as String)
                : const Value.absent(),
            syncStatus: Value(SyncStatus.synced.toInt()),
            serverUpdatedAt: Value(serverUpdatedAt),
            updatedAt: Value(serverUpdatedAt),
          ),
        );
      }
    }
  }

  static const _uuid = Uuid();

  /// Generate a collision-resistant local ID for offline-created entities.
  String _generateLocalId() => 'local-${_uuid.v4()}';

  void _setState(SyncState state) {
    _currentState = state;
    _stateController.add(state);
  }

  /// Force a sync now, regardless of connectivity.
  Future<void> forceSync() async {
    await sync();
  }

  /// Get the count of pending sync operations.
  Future<int> getPendingCount() {
    return _syncQueue.getPendingCount();
  }

  /// Check if there are pending sync operations.
  Future<bool> hasPendingChanges() {
    return _syncQueue.hasPendingOperations();
  }

  /// Dispose of the service.
  void dispose() {
    _connectivitySubscription?.cancel();
    _periodicSyncTimer?.cancel();
    _stateController.close();
  }
}
