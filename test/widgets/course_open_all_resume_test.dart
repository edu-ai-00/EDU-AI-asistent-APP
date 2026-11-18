// BR-XAWEND — in a course with every lesson open, the course page showed no
// sign of where the student had worked.
//
// The reporter worked through part of lesson 2 of an open-all course, left and
// came back: all four lessons looked the same. Every unfinished lesson of an
// open-all course is inProgress, so the page dropped the "current lesson"
// marking altogether (BR-K47WYE) — and with it the only thing that set the
// lesson in progress apart.
//
// The lesson the student worked in now gets the marking a sequential course
// gives its current lesson: the AKTUÁLNÍ badge on a phone, the highlighted row
// with "Pokračovat" on a desktop. Lessons merely opened stay unmarked.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/main.dart' show routeObserver;
import 'package:eduai/models/course_model.dart';
import 'package:eduai/pages/course_detail_page.dart' show CourseDetailPage;

const _courseId = 'c-1';
const _userCourseId = 'uc-1';

/// Four lessons of three questions, like the reporter's "Rovnice 1, 2,
/// Nerovnice 1, 2".
Map<String, dynamic> _courseData({required bool openAll}) => {
      'course_id': 'A2-Rovnice_c1',
      'name': '(Ne)rovnice',
      'open_all_lessons': openAll,
      'blocks': [
        for (var i = 0; i < 12; i++)
          {
            'block_id': 'b-$i',
            'type': 'question',
            'question': '$i + 1?',
            'options': ['$i', '${i + 1}'],
            'correct_answer': 1,
          },
      ],
      'lessons': [
        for (var l = 0; l < 4; l++)
          {
            'lesson_id': 'L${l + 1}',
            'name': 'Lekce ${l + 1}',
            'blocks': [
              for (var b = 0; b < 3; b++)
                {'block_id': 'b-${l * 3 + b}', 'order': b},
            ],
          },
      ],
    };

/// Part of lesson 2 done; lesson 1 opened and left straight away.
const _workedInLesson2 = {
  'L1': {'completed_blocks': <String>[], 'current_block_index': 0},
  'L2': {
    'completed_blocks': ['b-3', 'b-4'],
    'current_block_index': 2,
  },
};

/// No network: the page's update check stops before calling the API.
class _Offline implements ConnectivityService {
  @override
  Future<bool> get isOnline async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Keeps every HTTP request pending, so google_fonts' runtime fetches (let
/// through by `runAsync`) neither land nor fail the test.
class _SilentHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _SilentHttpClient();
}

class _SilentHttpClient implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// The test-only Ahem font is far wider than the real one, so labels overflow
/// their rows. Cosmetic and test-only.
void _ignoreOverflow() {
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);
}

Future<void> _pumpCourse(
  WidgetTester tester, {
  required double width,
  bool openAll = true,
  Map<String, dynamic> lessonsProgress = _workedInLesson2,
  int completedLessons = 0,
  Finder? until,
}) async {
  _ignoreOverflow();
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 2400);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  final data = _courseData(openAll: openAll);
  await tester.runAsync(() async {
    await db.upsertCourse(CoursesTableCompanion(
      id: const Value(_courseId),
      courseId: const Value('A2-Rovnice_c1'),
      name: const Value('(Ne)rovnice'),
      data: Value(jsonEncode(data)),
    ));
    await db.upsertUserCourse(UserCoursesTableCompanion(
      id: const Value(_userCourseId),
      userId: const Value('u-1'),
      courseId: const Value(_courseId),
      status: const Value('in_progress'),
      currentLessonIndex: const Value(1),
      completedLessons: Value(completedLessons),
      progressDataJson: Value(jsonEncode({'lessons': lessonsProgress})),
    ));
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appDatabaseProvider.overrideWithValue(db),
        authTokenStorageProvider
            .overrideWithValue(AuthTokenStorage(prefs: prefs)),
        connectivityServiceProvider.overrideWithValue(_Offline()),
        activeUserStreamProvider.overrideWith((ref) => Stream.value(null)),
        userStatsStreamProvider.overrideWith((ref) => Stream.value(null)),
      ],
      child: MaterialApp(
        navigatorObservers: [routeObserver],
        home: CourseDetailPage(
          course: Course.fromJsonData(id: _courseId, data: data),
          userCourseId: _userCourseId,
        ),
      ),
    ),
  );
  // The page reads progress out of the database after its first frame. Under
  // a loaded full-suite run that read can outlast a few bare frames, so give it
  // real time, stopping early once [until] shows up.
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    if (until != null && until.evaluate().isNotEmpty) break;
  }
}

/// [label] inside the tappable card or row of the lesson titled [lesson].
Finder _inLesson(String lesson, String label) => find.descendant(
      of: find
          .ancestor(of: find.text(lesson), matching: find.byType(GestureDetector))
          .first,
      matching: find.text(label),
    );

void main() {
  late HttpOverrides? previousHttpOverrides;
  setUp(() {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _SilentHttpOverrides();
  });
  tearDown(() => HttpOverrides.global = previousHttpOverrides);

  group('open-all course, part of lesson 2 done', () {
    testWidgets('phone: lesson 2 carries the AKTUÁLNÍ badge, no other does',
        (tester) async {
      await _pumpCourse(tester,
          width: 400, until: _inLesson('Lekce 2', AppStrings.courseCurrent));

      expect(find.text(AppStrings.courseCurrent), findsOneWidget);
      expect(_inLesson('Lekce 2', AppStrings.courseCurrent), findsOneWidget);
    });

    testWidgets('desktop: lesson 2 offers Pokračovat, the rest Otevřít',
        (tester) async {
      await _pumpCourse(tester,
          width: 1536,
          until: _inLesson('Lekce 2', AppStrings.courseCardContinue));

      expect(find.text(AppStrings.courseCardContinue), findsOneWidget);
      expect(_inLesson('Lekce 2', AppStrings.courseCardContinue),
          findsOneWidget);
      for (final other in ['Lekce 1', 'Lekce 3', 'Lekce 4']) {
        expect(_inLesson(other, AppStrings.courseOpenLesson), findsOneWidget,
            reason: '$other was not worked in');
      }
    });

    testWidgets('nothing worked in yet: no lesson is marked', (tester) async {
      await _pumpCourse(tester, width: 400, lessonsProgress: const {});

      expect(find.text(AppStrings.courseCurrent), findsNothing);
    });
  });

  testWidgets('sequential course: the current lesson is still badged',
      (tester) async {
    await _pumpCourse(
      tester,
      width: 400,
      openAll: false,
      completedLessons: 1,
      lessonsProgress: {
        'L1': {'is_completed': true, 'completed_blocks': ['b-0', 'b-1', 'b-2']},
      },
      // Before progress loads, lesson 1 is the one badged.
      until: _inLesson('Lekce 2', AppStrings.courseCurrent),
    );

    expect(find.text(AppStrings.courseCurrent), findsOneWidget);
    expect(_inLesson('Lekce 2', AppStrings.courseCurrent), findsOneWidget);
  });
}
