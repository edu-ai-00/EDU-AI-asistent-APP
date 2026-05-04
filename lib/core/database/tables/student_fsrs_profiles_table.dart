import 'package:drift/drift.dart';

/// Drift table for student FSRS profiles.
/// Per-student preferences — synced from server, used locally by scheduler.
class StudentFsrsProfilesTable extends Table {
  @override
  String get tableName => 'student_fsrs_profiles';

  TextColumn get id => text()();
  TextColumn get userId => text().unique()();
  RealColumn get desiredRetention => real().withDefault(const Constant(0.9))();
  IntColumn get maximumInterval => integer().withDefault(const Constant(90))();
  BoolColumn get enableFuzz => boolean().withDefault(const Constant(true))();
  BoolColumn get enableShortTerm => boolean().withDefault(const Constant(true))();
  TextColumn get learningSteps => text().withDefault(const Constant('["1m","10m"]'))();
  TextColumn get relearningSteps => text().withDefault(const Constant('["10m"]'))();
  TextColumn get fsrsWeights => text().withDefault(const Constant('default'))();
  IntColumn get profileVersion => integer().withDefault(const Constant(1))();
  IntColumn get dailyNewLimit => integer().withDefault(const Constant(10))();
  IntColumn get dailyReviewLimit => integer().withDefault(const Constant(50))();
  IntColumn get sessionExpirationSec => integer().withDefault(const Constant(7200))();
  IntColumn get syncStatus => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
