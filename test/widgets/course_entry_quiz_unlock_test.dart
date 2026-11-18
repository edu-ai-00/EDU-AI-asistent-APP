// BR-MKFPU6 — a passed entry quiz locked the course again on the next visit.
//
// A `starts_with_quiz` course locks every lesson until its entry quiz is done.
// The course page only learnt the quiz was done from the quiz page it had just
// pushed returning true; the `quiz_completed` flag the quiz stores in
// progressData was never read. Any later visit — a reload, opening the course
// from the list again — offered "Začít kvíz" with every lesson locked.
//
// The page now takes the stored flag. It keeps the lessons open while a retake
// is under way (`quiz_in_progress` true again), which is the state the stage
// server held after the reporter's second run.
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

/// DEMOKURZ02's shape: an entry quiz, then three sequential lessons.
final Map<String, dynamic> _courseData = {
  'course_id': 'DEMOKURZ02',
  'name': 'Demo kurz – začíná kvízem',
  'starts_with_quiz': true,
  'blocks': [
    for (var i = 0; i < 6; i++)
      {
        'block_id': 'b-$i',
        'type': 'question',
        'question': '$i + 1?',
        'options': ['$i', '${i + 1}'],
        'correct_answer': 1,
      },
  ],
  'lessons': [
    for (var l = 0; l < 3; l++)
      {
        'lesson_id': 'L${l + 1}',
        'name': 'Lekce ${l + 1}',
        'blocks': [
          for (var b = 0; b < 2; b++) {'block_id': 'b-${l * 2 + b}', 'order': b},
        ],
      },
  ],
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
  required Map<String, dynamic> progressData,
  Finder? until,
}) async {
  _ignoreOverflow();
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(400, 2400);
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);

  await tester.runAsync(() async {
    await db.upsertCourse(CoursesTableCompanion(
      id: const Value(_courseId),
      courseId: const Value('DEMOKURZ02'),
      name: const Value('Demo kurz – začíná kvízem'),
      data: Value(jsonEncode(_courseData)),
    ));
    await db.upsertUserCourse(UserCoursesTableCompanion(
      id: const Value(_userCourseId),
      userId: const Value('u-1'),
      courseId: const Value(_courseId),
      status: const Value('downloaded'),
      progressDataJson: Value(jsonEncode(progressData)),
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
          course: Course.fromJsonData(id: _courseId, data: _courseData),
          userCourseId: _userCourseId,
        ),
      ),
    ),
  );
  // The page reads progress out of the database after its first frame. Give
  // that read real time, stopping early once [until] shows up.
  for (var i = 0; i < 50; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
    if (until != null && until.evaluate().isNotEmpty) break;
  }
}

void main() {
  late HttpOverrides? previousHttpOverrides;
  setUp(() {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _SilentHttpOverrides();
  });
  tearDown(() => HttpOverrides.global = previousHttpOverrides);

  testWidgets('entry quiz not done yet: quiz offered, every lesson locked',
      (tester) async {
    await _pumpCourse(tester, progressData: const {});

    expect(find.text(AppStrings.courseStartQuiz), findsWidgets);
    expect(find.text(AppStrings.courseCurrent), findsNothing);
  });

  testWidgets('entry quiz passed earlier: lesson 1 open on a fresh visit',
      (tester) async {
    await _pumpCourse(
      tester,
      progressData: const {
        'quiz_completed': true,
        'quiz_in_progress': false,
        'quiz_score': 100,
      },
      until: find.text(AppStrings.courseCurrent),
    );

    expect(find.text(AppStrings.courseStartQuiz), findsNothing);
    expect(find.text(AppStrings.courseCurrent), findsOneWidget);
  });

  testWidgets('a retake under way keeps the lessons the first pass opened',
      (tester) async {
    // What the stage server held after the reporter's second run.
    await _pumpCourse(
      tester,
      progressData: const {
        'quiz_in_progress': true,
        'quiz_current_index': 2,
        'quiz_completed': true,
        'quiz_completed_at': '2026-11-11T15:08:06.520Z',
      },
      until: find.text(AppStrings.courseCurrent),
    );

    expect(find.text(AppStrings.courseStartQuiz), findsNothing);
    expect(find.text(AppStrings.courseCurrent), findsOneWidget);
  });
}
