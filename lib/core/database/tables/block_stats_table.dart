import 'package:drift/drift.dart';

/// Caches per-block ELO statistics (item solve counts and server-canonical
/// ELO vectors) locally for offline-first adaptive learning.
class BlockStatsTable extends Table {
  @override
  String get tableName => 'block_stats';

  TextColumn get blockId => text()();
  TextColumn get itemPocet => text()();
  TextColumn get eloVector => text()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {blockId};
}
