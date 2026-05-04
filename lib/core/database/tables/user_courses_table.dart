import 'package:drift/drift.dart';

/// Drift table definition for user courses.
/// Tracks which courses a user has downloaded and their progress.
class UserCoursesTable extends Table {
  @override
  String get tableName => 'user_courses';

  /// Local unique identifier (UUID).
  TextColumn get id => text()();

  /// Server-side ID (null if created offline and not yet synced).
  IntColumn get serverId => integer().nullable()();

  /// The user who owns this course enrollment.
  TextColumn get userId => text()();

  /// The course ID (references courses table).
  TextColumn get courseId => text()();

  /// Status: downloaded, in_progress, completed.
  TextColumn get status => text().withDefault(const Constant('downloaded'))();

  /// Overall progress percentage (0-100).
  IntColumn get progressPercent => integer().withDefault(const Constant(0))();

  /// Number of lessons completed.
  IntColumn get completedLessons => integer().withDefault(const Constant(0))();

  /// Total number of lessons in the course.
  IntColumn get totalLessons => integer().withDefault(const Constant(0))();

  /// Index of the current lesson (for resume functionality).
  IntColumn get currentLessonIndex => integer().withDefault(const Constant(0))();

  /// Total time spent on this course in seconds.
  IntColumn get timeSpentSeconds => integer().withDefault(const Constant(0))();

  /// JSON-encoded lesson-by-lesson progress data.
  TextColumn get progressDataJson => text().withDefault(const Constant('{}'))();

  /// The version of the course that was downloaded.
  /// Used to detect when a newer version is available on the server.
  IntColumn get downloadedVersion => integer().withDefault(const Constant(1))();

  /// When the user started this course.
  DateTimeColumn get startedAt => dateTime().nullable()();

  /// When the user completed this course.
  DateTimeColumn get completedAt => dateTime().nullable()();

  /// Sync status: 0=synced, 1=pending, 2=conflict.
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  /// When the record was created locally.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the record was last updated (local or remote).
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Server's last update timestamp (for conflict detection).
  DateTimeColumn get serverUpdatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
