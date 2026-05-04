import 'package:drift/drift.dart';

/// Drift table definition for the sync queue.
/// Stores pending operations to be synced when connectivity is available.
class SyncQueueTable extends Table {
  @override
  String get tableName => 'sync_queue';

  /// Unique identifier for the queue entry.
  IntColumn get id => integer().autoIncrement()();

  /// Table name the operation applies to (courses, lessons, user_progress).
  TextColumn get tableName_ => text().named('table_name')();

  /// Local record ID the operation applies to.
  TextColumn get recordId => text()();

  /// Operation type: create, update, delete.
  TextColumn get operation => text()();

  /// JSON-encoded payload to send to the server.
  TextColumn get payload => text()();

  /// Number of sync attempts.
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// Last error message if sync failed.
  TextColumn get lastError => text().nullable()();

  /// Priority for processing (lower = higher priority).
  IntColumn get priority => integer().withDefault(const Constant(0))();

  /// When the operation was queued.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the operation should next be attempted.
  DateTimeColumn get scheduledAt => dateTime().withDefault(currentDateAndTime)();
}
