import 'package:drift/drift.dart';

/// Activity heartbeats used to measure active working time (BR-9SAH2R).
///
/// One row is written roughly every 60s while the user is genuinely active on
/// a learning screen. Rows are append-only telemetry: they sync to the API in
/// batches and are deleted locally once accepted. `clientUuid` is the
/// server-side idempotency key.
class WorkHeartbeatsTable extends Table {
  @override
  String get tableName => 'work_heartbeats';

  /// Local + server idempotency key (UUID v4).
  TextColumn get clientUuid => text()();

  /// Course the user was working in.
  TextColumn get courseId => text()();

  /// Lesson within the course, if known.
  TextColumn get lessonId => text().nullable()();

  /// Where the user was (e.g. 'lesson', 'quiz', 'chat', 'video').
  TextColumn get context => text().nullable()();

  /// When the heartbeat fired (device clock, UTC).
  DateTimeColumn get occurredAt => dateTime()();

  /// False until the API has accepted this row.
  BoolColumn get synced => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {clientUuid};
}
