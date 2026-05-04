import '../../models/gamification_config_model.dart';

/// Pure function evaluator that checks achievement conditions against user stats.
///
/// Returns a list of achievement IDs that are newly earned (not in [alreadyEarned]).
class AchievementEvaluator {
  const AchievementEvaluator._();

  /// Check all achievements and return newly earned IDs.
  ///
  /// [config] — the gamification config with all achievement definitions.
  /// [alreadyEarned] — set of achievement IDs already earned by the user.
  /// [totalXp] — user's total XP points.
  /// [streakDays] — user's current streak in days.
  /// [lessonsCompleted] — total lessons completed across all courses.
  /// [coursesCompleted] — total courses completed.
  /// [quizzesCompleted] — total quizzes completed.
  /// [level] — user's current level.
  static List<String> evaluate({
    required GamificationConfig config,
    required Set<String> alreadyEarned,
    required int totalXp,
    required int streakDays,
    required int lessonsCompleted,
    required int coursesCompleted,
    required int quizzesCompleted,
    required int level,
  }) {
    final newlyEarned = <String>[];

    for (final achievement in config.allAchievements) {
      if (alreadyEarned.contains(achievement.id)) continue;

      if (_checkCondition(
        condition: achievement.condition,
        totalXp: totalXp,
        streakDays: streakDays,
        lessonsCompleted: lessonsCompleted,
        coursesCompleted: coursesCompleted,
        quizzesCompleted: quizzesCompleted,
        level: level,
      )) {
        newlyEarned.add(achievement.id);
      }
    }

    return newlyEarned;
  }

  /// Evaluate current progress toward an achievement condition.
  /// Returns (current, target) for progress display.
  static (int current, int target) getProgress({
    required AchievementCondition condition,
    required int totalXp,
    required int streakDays,
    required int lessonsCompleted,
    required int coursesCompleted,
    required int quizzesCompleted,
    required int level,
  }) {
    final current = _getCurrentValue(
      condition: condition,
      totalXp: totalXp,
      streakDays: streakDays,
      lessonsCompleted: lessonsCompleted,
      coursesCompleted: coursesCompleted,
      quizzesCompleted: quizzesCompleted,
      level: level,
    );
    return (current, condition.value);
  }

  static bool _checkCondition({
    required AchievementCondition condition,
    required int totalXp,
    required int streakDays,
    required int lessonsCompleted,
    required int coursesCompleted,
    required int quizzesCompleted,
    required int level,
  }) {
    final current = _getCurrentValue(
      condition: condition,
      totalXp: totalXp,
      streakDays: streakDays,
      lessonsCompleted: lessonsCompleted,
      coursesCompleted: coursesCompleted,
      quizzesCompleted: quizzesCompleted,
      level: level,
    );
    return current >= condition.value;
  }

  static int _getCurrentValue({
    required AchievementCondition condition,
    required int totalXp,
    required int streakDays,
    required int lessonsCompleted,
    required int coursesCompleted,
    required int quizzesCompleted,
    required int level,
  }) {
    switch (condition.type) {
      case 'total_xp':
        return totalXp;
      case 'streak_days':
        return streakDays;
      case 'lessons_completed':
        return lessonsCompleted;
      case 'courses_completed':
        return coursesCompleted;
      case 'quizzes_completed':
        return quizzesCompleted;
      case 'level':
        return level;
      default:
        return 0;
    }
  }
}
