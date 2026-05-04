import 'package:drift/drift.dart';

/// Drift table for FSRS practice cards.
/// One card per student per block — tracks spaced repetition state.
class PracticeCardsTable extends Table {
  @override
  String get tableName => 'practice_cards';

  TextColumn get id => text()();
  TextColumn get serverId => text().nullable()();
  TextColumn get userId => text()();
  TextColumn get courseId => text()();
  TextColumn get lessonId => text()();
  TextColumn get blockId => text()();
  TextColumn get sourceType => text()();
  IntColumn get state => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueDate => dateTime().withDefault(currentDateAndTime)();
  RealColumn get stability => real().withDefault(const Constant(0.0))();
  RealColumn get difficulty => real().withDefault(const Constant(0.0))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  IntColumn get scheduledDays => integer().withDefault(const Constant(0))();
  IntColumn get elapsedDays => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastReview => dateTime().nullable()();
  RealColumn get weight => real().withDefault(const Constant(5.0))();
  IntColumn get avgTimeSec => integer().withDefault(const Constant(20))();
  TextColumn get skipCondition => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
