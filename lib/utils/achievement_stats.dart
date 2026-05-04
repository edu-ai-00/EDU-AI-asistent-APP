import 'dart:convert';
import 'package:eduai/core/util/silent_log.dart';

/// Count lessons completed, courses completed, and quizzes completed from user courses.
/// Used by AchievementsPage callers to pass accurate stats.
({int lessons, int courses, int quizzes}) countAchievementStats(List<dynamic> userCourses) {
  int lessons = 0;
  int courses = 0;
  int quizzes = 0;
  for (final uc in userCourses) {
    lessons += (uc.completedLessons as int?) ?? 0;
    if (uc.status == 'completed') courses++;
    try {
      final pd = uc.progressDataJson;
      if (pd is String && pd.isNotEmpty && pd != '{}') {
        final data = jsonDecode(pd) as Map<String, dynamic>;
        if (data['quiz_completed'] == true) quizzes++;
      } else if (pd is Map && pd['quiz_completed'] == true) {
        quizzes++;
      }
    } catch (e, st) { silentLog('achievement_stats', e, st); }
  }
  return (lessons: lessons, courses: courses, quizzes: quizzes);
}
