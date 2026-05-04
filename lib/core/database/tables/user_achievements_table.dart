import 'package:drift/drift.dart';

/// Tracks which trophies/goals/challenges the user has earned.
class UserAchievementsTable extends Table {
  @override
  String get tableName => 'user_achievements';

  /// Local unique identifier (UUID).
  TextColumn get id => text()();

  /// The user who earned this achievement.
  TextColumn get userId => text()();

  /// Matches trophy/goal/challenge ID from the gamification config.
  TextColumn get achievementId => text()();

  /// When the achievement was earned.
  DateTimeColumn get earnedAt => dateTime().withDefault(currentDateAndTime)();

  /// Sync status: 0=synced, 1=pending.
  IntColumn get syncStatus => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {userId, achievementId},
  ];
}
