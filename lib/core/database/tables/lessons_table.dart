import 'package:drift/drift.dart';

/// Drift table definition for lessons.
/// Stores individual lesson content within courses.
class LessonsTable extends Table {
  @override
  String get tableName => 'lessons';

  /// Local unique identifier (UUID).
  TextColumn get id => text()();

  /// Server-side ID (null if created offline).
  IntColumn get serverId => integer().nullable()();

  /// Reference to the parent course (local ID).
  TextColumn get courseId => text()();

  /// Lesson identifier string.
  TextColumn get lessonId => text()();

  /// Lesson title.
  TextColumn get title => text()();

  /// Lesson description/summary.
  TextColumn get description => text().withDefault(const Constant(''))();

  /// Order within the course.
  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  /// JSON-encoded lesson content.
  TextColumn get content => text().withDefault(const Constant('{}'))();

  /// Duration in minutes (estimated).
  IntColumn get durationMinutes => integer().withDefault(const Constant(0))();

  /// Sync status: 0=synced, 1=pending, 2=conflict.
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  /// When the record was created locally.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the record was last updated.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
