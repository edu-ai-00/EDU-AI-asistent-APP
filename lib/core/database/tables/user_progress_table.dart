import 'package:drift/drift.dart';

/// Drift table definition for user progress.
/// Tracks user completion and progress across courses and lessons.
class UserProgressTable extends Table {
  @override
  String get tableName => 'user_progress';

  /// Local unique identifier (UUID).
  TextColumn get id => text()();

  /// Server-side ID (null if created offline).
  IntColumn get serverId => integer().nullable()();

  /// User ID (from auth system).
  TextColumn get userId => text()();

  /// Reference to the course (local ID).
  TextColumn get courseId => text()();

  /// Reference to the lesson (local ID, nullable for course-level progress).
  TextColumn get lessonId => text().nullable()();

  /// Progress percentage (0-100).
  IntColumn get progressPercent => integer().withDefault(const Constant(0))();

  /// Whether the item is completed.
  BoolColumn get isCompleted =>
      boolean().withDefault(const Constant(false))();

  /// Last position/checkpoint within content (e.g., question index).
  IntColumn get lastPosition => integer().withDefault(const Constant(0))();

  /// JSON-encoded additional progress data (answers, scores, etc.).
  TextColumn get progressData => text().withDefault(const Constant('{}'))();

  /// Time spent in seconds.
  IntColumn get timeSpentSeconds => integer().withDefault(const Constant(0))();

  /// When the user started this item.
  DateTimeColumn get startedAt => dateTime().nullable()();

  /// When the user completed this item.
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Sync status: 0=synced, 1=pending, 2=conflict.
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  /// When the record was created locally.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the record was last updated.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
