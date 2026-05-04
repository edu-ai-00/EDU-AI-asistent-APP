import 'package:drift/drift.dart';

/// Drift table for practice review logs.
/// One row per review event — append-only locally, batch-synced to server.
class ReviewLogsTable extends Table {
  @override
  String get tableName => 'review_logs';

  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get cardId => text()();
  TextColumn get userId => text()();
  IntColumn get rating => integer()();
  DateTimeColumn get shownAt => dateTime()();
  DateTimeColumn get reviewedAt => dateTime()();
  IntColumn get responseTimeSec => integer()();
  IntColumn get repetitionNumber => integer()();
  RealColumn get stabilityAfter => real()();
  RealColumn get difficultyAfter => real()();
  DateTimeColumn get nextDueDate => dateTime()();
  IntColumn get intervalDays => integer()();
  TextColumn get userFeedback => text().nullable()();
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
