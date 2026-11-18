// BR-W6V77D — the desktop rail's "Pokračuj v lekci" card said "Všechny lekce
// máš hotové" for a course whose lessons were all still to do.
//
// The card looked for the first lesson with blocks left, but counted each
// lesson's blocks off `Lesson.blocks` — which `Course.fromJsonData` always
// leaves empty (blocks load when the lesson opens). Every lesson read as
// 0 of 0, every lesson was skipped, and the card fell through to its
// "everything is finished" variant for any started course.
//
// The lesson is now found from the course JSON's block bindings, and only the
// blocks the lesson still holds count as done (BR-PTH76K). Lessons the course
// page keeps locked — before the entry quiz is passed, or while a newer
// version waits — are not offered either (rule 6.1), and the fallback card
// says why instead of claiming everything is done.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/providers/navigation_providers.dart';
import 'package:eduai/core/providers/practice_providers.dart';
import 'package:eduai/core/services/practice_filter_store.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_status.dart';
import 'package:eduai/data/repositories/user_course_repository.dart';
import 'package:eduai/pages/course_detail_page.dart';
import 'package:eduai/pages/prehled_page.dart';
import 'package:eduai/pages/quiz_page.dart' show QuizProgress;
import 'package:eduai/widgets/side_nav.dart';

/// The test-only Ahem font is far wider than the real one, so labels overflow
/// their rows. Cosmetic and test-only — same suppression the other dashboard
/// tests use.
void _ignoreOverflow() {
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);
}

Map<String, dynamic> _lesson(String id, String name, List<String> blockIds) => {
      'lesson_id': id,
      'name': name,
      'blocks': [
        for (var i = 0; i < blockIds.length; i++)
          {'block_id': blockIds[i], 'order': i + 1},
      ],
    };

/// DEMOKURZ02's shape: an entry quiz, then three lessons unlocked in order.
Map<String, dynamic> _courseData({
  bool startsWithQuiz = true,
  bool onlyQuiz = false,
}) =>
    {
      'course_id': 'DEMOKURZ02',
      'name': 'Demo kurz – začíná kvízem, lekce postupně',
      if (startsWithQuiz) 'starts_with_quiz': true,
      if (onlyQuiz) 'only_quiz': true,
      'open_all_lessons': false,
      'lessons': [
        _lesson('DK2_L1', 'Úvod', ['DK2L1B01', 'DK2L1B02', 'DK2L1B03']),
        _lesson('DK2_L2', 'Otázky', ['DK2L2B01', 'DK2L2B02']),
        _lesson('DK2_L3', 'Konec', ['DK2L3B01']),
      ],
      'blocks': const [],
    };

UserCourse _userCourse({
  required Map<String, dynamic> courseData,
  required Map<String, dynamic> progressData,
  int completedLessons = 0,
  int? currentCourseVersion,
}) {
  final now = DateTime(2026, 11, 11);
  return UserCourse(
    id: 'uc',
    userId: 'user',
    courseId: 'course',
    status: UserCourseStatus.inProgress,
    progressPercent: 0,
    completedLessons: completedLessons,
    totalLessons: 3,
    currentLessonIndex: 0,
    timeSpentSeconds: 0,
    progressData: progressData,
    downloadedVersion: 1,
    currentCourseVersion: currentCourseVersion,
    syncStatus: SyncStatus.synced,
    createdAt: now,
    updatedAt: now,
    courseName: courseData['name'] as String,
    courseData: courseData,
  );
}

const _quizPassed = {'quiz_completed': true, 'quiz_in_progress': false};

Future<List<Override>> _overrides(List<UserCourse> courses) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  // The dashboard reads the course table directly (the JPZ banner asks whether
  // that course has arrived), so it needs a database.
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    appDatabaseProvider.overrideWithValue(db),
    activeUserStreamProvider.overrideWith((ref) => Stream.value(null)),
    userStatsStreamProvider.overrideWith((ref) => Stream.value(null)),
    userCoursesStreamProvider.overrideWith((ref) => Stream.value(courses)),
    dueCardsCountProvider.overrideWith((ref) async => 0),
    practiceFilterProvider
        .overrideWith((ref) => PracticeFilterNotifier(PracticeFilterStore(
              prefs,
            ))),
  ];
}

/// Desktop width: the card lives in the right-hand rail.
Future<void> _pumpDashboard(WidgetTester tester, UserCourse course) async {
  _ignoreOverflow();
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 2400);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: await _overrides([course]),
      child: const MaterialApp(
        home: Scaffold(
          body: PrehledPage(quizProgressCache: <String, QuizProgress>{}),
        ),
      ),
    ),
  );
  await tester.pump();
}

String _lessonLabel(int index, String name) =>
    '${AppStrings.lessonFallbackName(index + 1)}: $name';

final _allDone = find.text(AppStrings.continueLessonAllDone);
final _quizFirst = find.text(AppStrings.continueLessonQuizOnly);
final _openCourse = find.text(AppStrings.continueLessonOpenCourse);

void main() {
  testWidgets(
      'entry quiz passed, no lesson done: the card offers lesson 1, not '
      '"all done"', (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(courseData: _courseData(), progressData: _quizPassed),
    );

    expect(find.text(_lessonLabel(0, 'Úvod')), findsOneWidget);
    expect(find.text(AppStrings.continueLessonSteps(0, 3)), findsOneWidget);
    expect(find.text(AppStrings.continueLessonButton), findsOneWidget);
    expect(_allDone, findsNothing);
  });

  testWidgets('a lesson half done resumes there with its step count',
      (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(courseData: _courseData(), progressData: {
        ..._quizPassed,
        'lessons': {
          'DK2_L1': {
            'completed_blocks': ['DK2L1B01'],
          },
        },
      }),
    );

    expect(find.text(_lessonLabel(0, 'Úvod')), findsOneWidget);
    expect(find.text(AppStrings.continueLessonSteps(1, 3)), findsOneWidget);
  });

  testWidgets('a finished lesson is skipped for the next one', (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(
        courseData: _courseData(),
        completedLessons: 1,
        progressData: {
          ..._quizPassed,
          'lessons': {
            'DK2_L1': {
              'is_completed': true,
              'completed_blocks': ['DK2L1B01', 'DK2L1B02', 'DK2L1B03'],
            },
          },
        },
      ),
    );

    expect(find.text(_lessonLabel(1, 'Otázky')), findsOneWidget);
    expect(find.text(AppStrings.continueLessonSteps(0, 2)), findsOneWidget);
  });

  testWidgets(
      'blocks the lesson no longer holds do not make it look finished '
      '(BR-PTH76K)', (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(courseData: _courseData(), progressData: {
        ..._quizPassed,
        'lessons': {
          // As many ids as the lesson has blocks, but all from an older
          // version of the course.
          'DK2_L1': {
            'completed_blocks': ['OLD_1', 'OLD_2', 'OLD_3'],
          },
        },
      }),
    );

    expect(find.text(_lessonLabel(0, 'Úvod')), findsOneWidget);
    expect(find.text(AppStrings.continueLessonSteps(0, 3)), findsOneWidget);
  });

  testWidgets('every lesson done: the card says so and opens the course',
      (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(
        courseData: _courseData(),
        completedLessons: 3,
        progressData: {
          ..._quizPassed,
          'lessons': {
            'DK2_L1': {
              'completed_blocks': ['DK2L1B01', 'DK2L1B02', 'DK2L1B03'],
            },
            'DK2_L2': {
              'completed_blocks': ['DK2L2B01', 'DK2L2B02'],
            },
            'DK2_L3': {
              'completed_blocks': ['DK2L3B01'],
            },
          },
        },
      ),
    );

    expect(_allDone, findsOneWidget);
    expect(_openCourse, findsOneWidget);
  });

  testWidgets(
      '"Otevřít kurz" opens the course inside Kurzy, so the sidebar lights '
      'Kurzy and "Zpět na všechny kurzy" lands there (BR-HVUEFS)',
      (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(
        courseData: _courseData(),
        progressData: const {'quiz_in_progress': true},
      ),
    );
    final container =
        ProviderScope.containerOf(tester.element(find.byType(PrehledPage)));
    expect(container.read(mainTabIndexProvider), 0);

    await tester.tap(_openCourse);
    // The course page loads from the DB and never settles in a widget test;
    // its cross-fade is 120 ms.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(CourseDetailPage), findsOneWidget);
    expect(container.read(mainTabIndexProvider), kKurzyTabIndex);
    await tester.pump();
    expect(
      tester.widget<SideNav>(find.byType(SideNav)).selectedIndex,
      kKurzyTabIndex,
    );
  });

  testWidgets(
      'entry quiz not passed yet: no lesson is offered past the locked quiz '
      '(rule 6.1)', (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(
        courseData: _courseData(),
        progressData: const {'quiz_in_progress': true},
      ),
    );

    expect(find.text(_lessonLabel(0, 'Úvod')), findsNothing);
    expect(_quizFirst, findsOneWidget);
    expect(_openCourse, findsOneWidget);
    expect(_allDone, findsNothing);
  });

  testWidgets('a quiz-only course mid-quiz is not "all lessons done"',
      (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(
        // Its questions sit in a lesson of the JSON, so it has a lesson count.
        courseData: _courseData(onlyQuiz: true),
        progressData: const {'quiz_in_progress': true},
      ),
    );

    expect(_quizFirst, findsOneWidget);
    expect(_allDone, findsNothing);
  });

  testWidgets(
      'a newer course version waiting: the course page locks its lessons, so '
      'the card opens the course', (tester) async {
    await _pumpDashboard(
      tester,
      _userCourse(
        courseData: _courseData(),
        progressData: _quizPassed,
        currentCourseVersion: 2,
      ),
    );

    expect(find.text(_lessonLabel(0, 'Úvod')), findsNothing);
    expect(find.text(AppStrings.courseUpdateAvailable), findsOneWidget);
    expect(_openCourse, findsOneWidget);
    expect(_allDone, findsNothing);
  });
}
