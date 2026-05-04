import 'dart:convert';

import '../datasources/local/user_progress_local_datasource.dart';
import '../../core/database/app_database.dart';
import '../../core/sync/sync_queue.dart';
import 'package:eduai/core/util/silent_log.dart';

/// Repository for user progress operations.
/// Provides high-level methods for tracking lesson/block completion.
/// Syncs lesson-level progress (answers, block states) to the server
/// via the sync queue → POST /api/user/progress.
class UserProgressRepository {
  final UserProgressLocalDataSource _localDataSource;
  final SyncQueue _syncQueue;
  final AppDatabase _db;

  UserProgressRepository({
    required UserProgressLocalDataSource localDataSource,
    required SyncQueue syncQueue,
    required AppDatabase db,
  })  : _localDataSource = localDataSource,
        _syncQueue = syncQueue,
        _db = db;

  /// Get course-level progress.
  Future<UserProgressTableData?> getCourseProgress(
      String userId, String courseId) {
    return _localDataSource.getCourseProgress(userId, courseId);
  }

  /// Get lesson-level progress.
  Future<UserProgressTableData?> getLessonProgress(
      String userId, String lessonId) {
    return _localDataSource.getLessonProgress(userId, lessonId);
  }

  /// Watch course progress as a stream.
  Stream<UserProgressTableData?> watchCourseProgress(
      String userId, String courseId) {
    return _localDataSource.watchCourseProgress(userId, courseId);
  }

  /// Mark a lesson as completed.
  Future<void> markLessonCompleted({
    required String userId,
    required String courseId,
    required String lessonId,
    int timeSpentSeconds = 0,
    Map<String, dynamic>? progressData,
  }) async {
    final existing =
        await _localDataSource.getLessonProgress(userId, lessonId);

    await _localDataSource.upsertProgress(
      userId: userId,
      courseId: courseId,
      lessonId: lessonId,
      progressPercent: 100,
      isCompleted: true,
      timeSpentSeconds: timeSpentSeconds,
      progressData:
          progressData != null ? jsonEncode(progressData) : existing?.progressData,
      completedAt: DateTime.now(),
      existingId: existing?.id,
    );

    // Queue for sync
    final record = await _localDataSource.getLessonProgress(userId, lessonId);
    if (record != null) {
      await _enqueueSync(record);
    }
  }

  /// Save per-block state within a lesson's progress data.
  /// Stores block completion, answers, and correctness inside
  /// the `progressData` JSON field, keyed by blockId.
  Future<void> saveBlockState({
    required String userId,
    required String courseId,
    required String lessonId,
    required String blockId,
    bool? isCompleted,
    String? answer,
    bool? isCorrect,
    bool? isLiked,
  }) async {
    final existing =
        await _localDataSource.getLessonProgress(userId, lessonId);

    Map<String, dynamic> data = {};
    if (existing != null) {
      try {
        data = jsonDecode(existing.progressData) as Map<String, dynamic>;
      } catch (e, st) { silentLog('user_progress_repository', e, st); }
    }

    // Get or create block-level progress map.
    final blocks =
        (data['blocks'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    final blockState =
        (blocks[blockId] as Map<String, dynamic>?) ?? <String, dynamic>{};

    if (isCompleted != null) blockState['isCompleted'] = isCompleted;
    if (answer != null) blockState['answer'] = answer;
    if (isCorrect != null) blockState['isCorrect'] = isCorrect;
    if (isLiked != null) blockState['isLiked'] = isLiked;

    blocks[blockId] = blockState;
    data['blocks'] = blocks;

    if (existing != null) {
      await _localDataSource.updateLessonProgress(
        id: existing.id,
        progressData: jsonEncode(data),
      );
    } else {
      await _localDataSource.upsertProgress(
        userId: userId,
        courseId: courseId,
        lessonId: lessonId,
        progressData: jsonEncode(data),
      );
    }

    // Queue for sync
    final record = await _localDataSource.getLessonProgress(userId, lessonId);
    if (record != null) {
      await _enqueueSync(record);
    }
  }

  /// Get saved block states for a lesson.
  /// Returns a map of blockId -> state map.
  Future<Map<String, Map<String, dynamic>>> getBlockStates({
    required String userId,
    required String lessonId,
  }) async {
    final existing =
        await _localDataSource.getLessonProgress(userId, lessonId);
    if (existing == null) return {};

    try {
      final data =
          jsonDecode(existing.progressData) as Map<String, dynamic>;
      final blocks =
          data['blocks'] as Map<String, dynamic>? ?? {};
      return blocks.map((key, value) =>
          MapEntry(key, Map<String, dynamic>.from(value as Map)));
    } catch (_) {
      return {};
    }
  }

  /// Merge arbitrary key-value pairs into a lesson's progress_data JSON.
  /// Used to persist step_progress and other data alongside existing block
  /// states without overwriting them.
  Future<void> mergeProgressData({
    required String userId,
    required String courseId,
    required String lessonId,
    required Map<String, dynamic> dataToMerge,
  }) async {
    final existing =
        await _localDataSource.getLessonProgress(userId, lessonId);

    Map<String, dynamic> data = {};
    if (existing != null) {
      try {
        data = jsonDecode(existing.progressData) as Map<String, dynamic>;
      } catch (e, st) { silentLog('user_progress_repository', e, st); }
    }

    // Merge new keys into existing data
    data.addAll(dataToMerge);

    if (existing != null) {
      await _localDataSource.updateLessonProgress(
        id: existing.id,
        progressData: jsonEncode(data),
      );
    } else {
      await _localDataSource.upsertProgress(
        userId: userId,
        courseId: courseId,
        lessonId: lessonId,
        progressData: jsonEncode(data),
      );
    }

    // Queue for sync
    final record = await _localDataSource.getLessonProgress(userId, lessonId);
    if (record != null) {
      await _enqueueSync(record);
    }
  }

  /// Update last position (checkpoint) within a lesson.
  Future<void> updateLastPosition({
    required String userId,
    required String courseId,
    required String lessonId,
    required int lastPosition,
  }) async {
    final existing =
        await _localDataSource.getLessonProgress(userId, lessonId);

    if (existing != null) {
      await _localDataSource.updateLessonProgress(
        id: existing.id,
        lastPosition: lastPosition,
      );
    } else {
      await _localDataSource.upsertProgress(
        userId: userId,
        courseId: courseId,
        lessonId: lessonId,
        lastPosition: lastPosition,
      );
    }

    // Queue for sync
    final record = await _localDataSource.getLessonProgress(userId, lessonId);
    if (record != null) {
      await _enqueueSync(record);
    }
  }

  /// Build sync payload and enqueue for server push.
  /// Translates local courseId (UUID) → string course_id for the API.
  Future<void> _enqueueSync(UserProgressTableData record) async {
    // Look up course to get the string identifier the API expects.
    final course = await _db.getCourseById(record.courseId);
    final courseStringId = course?.courseId ?? record.courseId;

    Map<String, dynamic> progressData;
    try {
      progressData = jsonDecode(record.progressData) as Map<String, dynamic>;
    } catch (_) {
      progressData = {};
    }

    await _syncQueue.enqueue(
      tableName: 'user_progress',
      recordId: record.id,
      operation: SyncOperation.update,
      payload: {
        'course_id': courseStringId,
        'lesson_id': record.lessonId ?? '',
        'progress_percent': record.progressPercent,
        'is_completed': record.isCompleted,
        'last_position': record.lastPosition,
        'time_spent_seconds': record.timeSpentSeconds,
        if (record.startedAt != null)
          'started_at': record.startedAt!.toIso8601String(),
        if (record.completedAt != null)
          'completed_at': record.completedAt!.toIso8601String(),
        'progress_data': progressData,
      },
    );
  }
}
