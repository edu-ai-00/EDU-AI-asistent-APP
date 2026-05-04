import 'package:drift/drift.dart';

/// Drift table definition for user ELO profiles.
///
/// Stores the student's adaptive-learning ELO ratings and task counts
/// across all 35 GPF subconstructs.  Both vectors are serialised as JSON
/// strings so that the schema stays flat.
///
/// NOTE: This table is NOT yet registered in app_database.dart.
/// Schema migration must be handled separately.
class UserEloProfileTable extends Table {
  @override
  String get tableName => 'user_elo_profiles';

  /// Local unique identifier (UUID).
  TextColumn get id => text()();

  /// The user who owns this profile.
  TextColumn get userId => text()();

  /// JSON-encoded list of 35 doubles (nullable per element) — student ELO.
  TextColumn get profilElo => text()();

  /// JSON-encoded list of 35 ints — per-subconstruct task counts.
  TextColumn get profilPocet => text()();

  /// Sync status: 0=synced, 1=pending, 2=conflict.
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();

  /// When the record was created locally.
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the record was last updated (local or remote).
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
