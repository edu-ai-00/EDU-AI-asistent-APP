import 'package:drift/drift.dart';

/// Drift table definition for courses.
/// Stores course metadata and content for offline access.
class CoursesTable extends Table {
  @override
  String get tableName => 'courses';

  /// Local unique identifier (UUID).
  TextColumn get id => text()();

  /// Server-side ID (null if created offline and not yet synced).
  IntColumn get serverId => integer().nullable()();

  /// Course identifier string (e.g., "course-001").
  TextColumn get courseId => text()();

  /// Course name/title.
  TextColumn get name => text()();

  /// Version number for conflict detection.
  IntColumn get version => integer().withDefault(const Constant(1))();

  /// Publication status: draft, published, archived.
  TextColumn get status => text().withDefault(const Constant('draft'))();

  /// Course language code (e.g., "en", "cs").
  TextColumn get language => text().withDefault(const Constant('en'))();

  /// JSON-encoded course data (lessons, exercises, etc.).
  TextColumn get data => text().withDefault(const Constant('{}'))();

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
