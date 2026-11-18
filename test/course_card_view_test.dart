// Spec test for the shared course-card derivation (BR-NS3UBD): the Kurzy tab
// and the dashboard render the same course, so they must read the same numbers
// out of it. Before this model each page derived its own and they disagreed.
//
// Pure functions — no database, no widgets:
//   flutter test test/course_card_view_test.dart
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_status.dart';
import 'package:eduai/data/repositories/user_course_repository.dart';
import 'package:eduai/models/course_card_view.dart';
import 'package:eduai/models/course_model.dart' show Course;
import 'package:eduai/widgets/kurzy_course_card.dart' show CourseStatus;

UserCourse _course({
  UserCourseStatus status = UserCourseStatus.downloaded,
  Map<String, dynamic> progressData = const {},
  Map<String, dynamic>? courseData,
  String? courseName,
  int totalLessons = 0,
  int completedLessons = 0,
}) {
  final now = DateTime(2026, 1, 1);
  return UserCourse(
    id: 'uc-1',
    userId: 'u-1',
    courseId: 'c-1',
    status: status,
    progressPercent: 0,
    completedLessons: completedLessons,
    totalLessons: totalLessons,
    currentLessonIndex: 0,
    timeSpentSeconds: 0,
    progressData: progressData,
    downloadedVersion: 1,
    syncStatus: SyncStatus.synced,
    createdAt: now,
    updatedAt: now,
    courseName: courseName,
    courseData: courseData,
  );
}

/// A lesson binding [count] blocks, ids `<id>_0` … `<id>_<count-1>`.
Map<String, dynamic> _lesson(String id, int count) => {
      'lesson_id': id,
      'blocks': [
        for (var i = 0; i < count; i++) {'block_id': '${id}_$i'},
      ],
    };

void main() {
  group('CourseCardView.of', () {
    test('sums blocks across lessons for progress', () {
      final view = CourseCardView.of(_course(
        status: UserCourseStatus.inProgress,
        courseData: {
          'name': 'Výrazy',
          'emoji': '🧮',
          'lessons': [
            _lesson('L1', 4),
            _lesson('L2', 6),
          ],
        },
        progressData: {
          'lessons': {
            'L1': {'completed_blocks': ['L1_0', 'L1_1', 'L1_2']},
            'L2': {'completed_blocks': ['L2_0']},
          },
        },
      ));

      expect(view.title, 'Výrazy');
      expect(view.emoji, '🧮');
      expect(view.lessonCount, 2);
      expect(view.currentProgress, 4);
      expect(view.totalProgress, 10);
      expect(view.status, CourseStatus.inProgress);
      expect(view.needsHydration, isFalse);
    });

    // BR-PTH76K: "Poměry a úměrnosti" read 140/129 — records of lessons the
    // author had since deleted or renamed were summed with the live ones.
    test('counts only blocks the course still holds, never above the total',
        () {
      final view = CourseCardView.of(_course(
        status: UserCourseStatus.inProgress,
        courseData: {
          'name': 'Poměry a úměrnosti',
          'lessons': [
            _lesson('L1', 4),
            _lesson('L2', 6),
          ],
        },
        progressData: {
          'lessons': {
            'L1': {
              'completed_blocks': ['L1_0', 'L1_1', 'L1_2', 'L1_3', 'L1_gone'],
            },
            'L2-renamed': {
              'completed_blocks': [for (var i = 0; i < 6; i++) 'L2_$i'],
            },
            'L2': {'completed_blocks': ['L2_0', 'L2_1']},
            'L3-deleted': {
              'completed_blocks': [for (var i = 0; i < 8; i++) 'L3_$i'],
            },
          },
        },
      ));

      expect(view.currentProgress, 6);
      expect(view.totalProgress, 10);
    });

    // The dashboard used to miss this and showed 0 % for a quiz the Kurzy tab
    // already reported as finished.
    test('reports a finished only_quiz course as complete at 1/1', () {
      final view = CourseCardView.of(_course(
        courseData: {'name': 'Rychlý kvíz', 'only_quiz': true, 'lessons': []},
        progressData: {'quiz_completed': true},
      ));

      expect(view.status, CourseStatus.completed);
      expect(view.currentProgress, 1);
      expect(view.totalProgress, 1);
    });

    test('an unfinished only_quiz course sits at 0/1', () {
      final view = CourseCardView.of(_course(
        courseData: {'name': 'Rychlý kvíz', 'only_quiz': true, 'lessons': []},
      ));

      expect(view.status, CourseStatus.notStarted);
      expect(view.currentProgress, 0);
      expect(view.totalProgress, 1);
    });

    test('asks for hydration and falls back when the payload is missing', () {
      final view = CourseCardView.of(_course(totalLessons: 7));

      expect(view.needsHydration, isTrue);
      expect(view.lessonCount, 7);
      expect(view.emoji, '📖');
    });
  });

  // The card used to guess 20 min per lesson rounded up to whole hours, so the
  // onboarding course read "4 lekcí · 2 hod" on the card and "4 lekcí · 25 min"
  // in the detail (BR-JS4P3H). Both now sum the block durations.
  group('CourseCardView duration', () {
    UserCourse onboardingLike() => _course(
          courseData: {
            'name': 'Co umí EDU AI asistent',
            'lessons': [
              for (var lesson = 0; lesson < 4; lesson++)
                {
                  'blocks': [
                    {'block_id': 'b${lesson}a'},
                    {'block_id': 'b${lesson}b'},
                  ],
                },
            ],
            'blocks': [
              for (var lesson = 0; lesson < 4; lesson++) ...[
                {'block_id': 'b${lesson}a', 'duration': '5 min'},
                {'block_id': 'b${lesson}b', 'duration': '5 min'},
              ],
            ],
          },
        );

    test('sums the block durations, matching the course detail header', () {
      final data = onboardingLike().courseData!;
      final view = CourseCardView.of(onboardingLike());

      expect(view.durationMinutes, Course.totalCourseMinutes(data));
      expect(view.durationMinutes, 40);
      expect(view.durationLabel, '40 min');
    });

    // The invariant the whole fix rests on: one computation, two screens.
    test('prints exactly what the course detail header prints', () {
      final data = onboardingLike().courseData!;
      final detail = Course.fromJsonData(id: 'c-1', data: data);
      final view = CourseCardView.of(onboardingLike());

      expect(
        view.durationLabel,
        AppStrings.durationSmart(detail.durationMinutes),
      );
    });

    test('keeps the hour estimate only while the payload is missing', () {
      final view = CourseCardView.of(_course(totalLessons: 4));

      expect(view.durationMinutes, 0);
      expect(view.durationLabel, '2 hod');
    });

    test('uses the catalog estimate for a row with no blocks yet', () {
      final view = CourseCardView.of(_course(
        courseData: {
          'name': 'Zlomky',
          'lessons': List.filled(4, const <String, dynamic>{}),
          'estimated_minutes': 75,
        },
      ));

      expect(view.durationMinutes, 75);
      expect(view.durationLabel, '1 hod 15 min');
    });
  });

  group('resolveKnownCourseTitle', () {
    test('prefers the payload name over the local one', () {
      expect(
        resolveKnownCourseTitle(_course(
          courseName: 'Kurz',
          courseData: {'name': 'Zlomky'},
        )),
        'Zlomky',
      );
    });

    test('rejects placeholders left by sync', () {
      expect(resolveKnownCourseTitle(_course(courseName: 'Kurz')), isNull);
      expect(resolveKnownCourseTitle(_course(courseName: 'Course')), isNull);
      expect(resolveKnownCourseTitle(_course(courseName: '  ')), isNull);
      expect(resolveKnownCourseTitle(_course(courseName: 'c-1')), isNull);
    });

    test('accepts a real local name', () {
      expect(resolveKnownCourseTitle(_course(courseName: 'Zlomky')), 'Zlomky');
    });
  });
}
