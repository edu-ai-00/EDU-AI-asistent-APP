import 'package:drift/drift.dart';

/// Drift table definition for user bookmarks.
/// Stores lightweight references to bookmarked blocks within courses.
class BookmarksTable extends Table {
  @override
  String get tableName => 'bookmarks';

  /// Local unique identifier (UUID).
  TextColumn get id => text()();

  /// The user who owns this bookmark.
  TextColumn get userId => text()();

  /// The course containing the bookmarked block.
  TextColumn get courseId => text()();

  /// The block ID within the course.
  TextColumn get blockId => text()();

  /// The lesson containing the bookmarked block.
  TextColumn get lessonId => text().withDefault(const Constant(''))();

  /// When the bookmark was created.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
