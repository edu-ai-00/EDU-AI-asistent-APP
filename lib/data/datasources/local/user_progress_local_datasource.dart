import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../../core/sync/sync_status.dart';

/// Local data source for user progress using Drift/SQLite.
/// Wraps existing AppDatabase methods for user_progress table.
class UserProgressLocalDataSource {
  final AppDatabase _db;
  final Uuid _uuid = const Uuid();

  UserProgressLocalDataSource(this._db);

  /// Get progress for a user and course (course-level).
  Future<UserProgressTableData?> getCourseProgress(
      String userId, String courseId) {
    return _db.getCourseProgress(userId, courseId);
  }

  /// Get progress for a user and lesson.
  Future<UserProgressTableData?> getLessonProgress(
      String userId, String lessonId) {
    return _db.getLessonProgress(userId, lessonId);
  }

  /// Get all progress records for a user.
  Future<List<UserProgressTableData>> getAllProgressForUser(String userId) {
    return _db.getAllProgressForUser(userId);
  }

  /// Watch progress for a specific course.
  Stream<UserProgressTableData?> watchCourseProgress(
      String userId, String courseId) {
    return _db.watchCourseProgress(userId, courseId);
  }

  /// Upsert progress record.
  Future<void> upsertProgress({
    required String userId,
    required String courseId,
    String? lessonId,
    int? progressPercent,
    bool? isCompleted,
    int? lastPosition,
    String? progressData,
    int? timeSpentSeconds,
    DateTime? startedAt,
    DateTime? completedAt,
    String? existingId,
  }) async {
    final localId = existingId ?? _uuid.v4();
    final now = DateTime.now();

    await _db.upsertProgress(
      UserProgressTableCompanion(
        id: Value(localId),
        userId: Value(userId),
        courseId: Value(courseId),
        lessonId: Value(lessonId),
        progressPercent: Value(progressPercent ?? 0),
        isCompleted: Value(isCompleted ?? false),
        lastPosition: Value(lastPosition ?? 0),
        progressData: Value(progressData ?? '{}'),
        timeSpentSeconds: Value(timeSpentSeconds ?? 0),
        startedAt: Value(startedAt ?? now),
        completedAt: Value(completedAt),
        syncStatus: Value(SyncStatus.pending.toInt()),
        createdAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  /// Update lesson progress fields for an existing record.
  /// Uses targeted UPDATE (not upsert) since the record must already exist.
  Future<void> updateLessonProgress({
    required String id,
    int? progressPercent,
    bool? isCompleted,
    int? lastPosition,
    String? progressData,
    int? timeSpentSeconds,
    DateTime? completedAt,
  }) async {
    await (_db.update(_db.userProgressTable)
          ..where((p) => p.id.equals(id)))
        .write(
      UserProgressTableCompanion(
        progressPercent: progressPercent != null
            ? Value(progressPercent)
            : const Value.absent(),
        isCompleted: isCompleted != null
            ? Value(isCompleted)
            : const Value.absent(),
        lastPosition: lastPosition != null
            ? Value(lastPosition)
            : const Value.absent(),
        progressData: progressData != null
            ? Value(progressData)
            : const Value.absent(),
        timeSpentSeconds: timeSpentSeconds != null
            ? Value(timeSpentSeconds)
            : const Value.absent(),
        completedAt: completedAt != null
            ? Value(completedAt)
            : const Value.absent(),
        syncStatus: Value(SyncStatus.pending.toInt()),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
