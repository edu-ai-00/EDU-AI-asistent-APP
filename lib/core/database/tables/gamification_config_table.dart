import 'package:drift/drift.dart';

/// Single-row cache of the latest gamification config from the server.
/// Always uses id="config" as the PK.
class GamificationConfigTable extends Table {
  @override
  String get tableName => 'gamification_config';

  /// Fixed PK — always "config".
  TextColumn get id => text()();

  /// Config version from server (used for staleness checks).
  IntColumn get version => integer().withDefault(const Constant(0))();

  /// Full JSON string of the config payload.
  TextColumn get configJson => text().withDefault(const Constant('{}'))();

  /// When the config was last downloaded.
  DateTimeColumn get downloadedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
