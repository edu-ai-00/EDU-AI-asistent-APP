// Regression test for BR-ZBW7TB: in-progress courses missing from the dashboard
// "Pokračovat" section.
//
// Cause: the dashboard gated the section on `completedLessons > 0`, but
// block/quiz-based courses never increment completedLessons (only lesson
// completion does). Such a genuinely-started course fell through both the
// Pokračovat and the Rychlé kvízy sections and became invisible.
//
// `UserCourse.hasStarted` broadens the "in progress" signal so any recorded
// progress counts, while a finished course never does.
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/sync/sync_status.dart';
import 'package:eduai/data/repositories/user_course_repository.dart';

UserCourse build({
  UserCourseStatus status = UserCourseStatus.downloaded,
  int progressPercent = 0,
  int completedLessons = 0,
  int currentLessonIndex = 0,
  Map<String, dynamic> progressData = const {},
}) {
  final now = DateTime(2026, 1, 1);
  return UserCourse(
    id: 'uc',
    userId: 'user',
    courseId: 'course',
    status: status,
    progressPercent: progressPercent,
    completedLessons: completedLessons,
    totalLessons: 0,
    currentLessonIndex: currentLessonIndex,
    timeSpentSeconds: 0,
    progressData: progressData,
    downloadedVersion: 1,
    syncStatus: SyncStatus.synced,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('UserCourse.hasStarted', () {
    test('fresh download with no progress is not started', () {
      expect(build().hasStarted, isFalse);
    });

    test('lesson course with a completed lesson is started', () {
      expect(build(completedLessons: 1, progressPercent: 20).hasStarted, isTrue);
    });

    test('block/quiz course mid-progress (no completedLessons) is started', () {
      // The BR-ZBW7TB case: quiz_page records only progressData.
      expect(
        build(progressData: const {'quiz_current_index': 2}).hasStarted,
        isTrue,
      );
    });

    test('quiz_in_progress flag counts as started', () {
      expect(
        build(progressData: const {'quiz_in_progress': true}).hasStarted,
        isTrue,
      );
    });

    test('non-empty lessons progress map counts as started', () {
      expect(
        build(progressData: const {
          'lessons': {
            'l1': {'is_completed': true}
          }
        }).hasStarted,
        isTrue,
      );
    });

    test('in_progress status counts as started', () {
      expect(build(status: UserCourseStatus.inProgress).hasStarted, isTrue);
    });

    test('currentLessonIndex advanced counts as started', () {
      expect(build(currentLessonIndex: 3).hasStarted, isTrue);
    });

    test('completed course is never "started" even with progress', () {
      expect(
        build(
          status: UserCourseStatus.completed,
          completedLessons: 5,
          progressPercent: 100,
        ).hasStarted,
        isFalse,
      );
    });
  });
}
