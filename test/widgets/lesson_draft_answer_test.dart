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
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/data/repositories/gamification_config_repository.dart';
import 'package:eduai/models/course_model.dart';
import 'package:eduai/models/gamification_config_model.dart';
import 'package:eduai/pages/lesson_detail_page.dart';

// BR-PW5EQK — an answer filled in but not yet checked vanished once the
// student scrolled up to the blocks before it, and again after leaving the
// lesson. Rule 6.2: typed text is never lost.
//
// The lesson below has three long text blocks already done and the question
// after them, which is where the student is. Scrolling to the top takes the
// question far enough out of the lazy list that its engine is torn down.

const _userId = 'user-1';
const _userCourseId = 'uc-1';
const _draft = 'Rozepsaná odpověď';

final _longText = List.filled(60, 'Výklad k látce, odstavec za odstavcem.')
    .join('\n\n');

Map<String, dynamic> _courseData() => {
      'course_id': 'C-DRAFT',
      'name': 'Kurz',
      'language': 'cs',
      'lessons': [
        {
          'lesson_id': 'L1',
          'name': 'Lekce 1',
          'order': 1,
          'blocks': [
            for (var i = 1; i <= 3; i++) {'block_id': 'T$i', 'order': i},
            {'block_id': 'Q', 'order': 4},
          ],
        },
      ],
      'blocks': [
        for (var i = 1; i <= 3; i++)
          {
            'block_id': 'T$i',
            'type': 'text',
            'steps': [
              {
                'id': 's1',
                'type': 'text',
                'order': 1,
                'content': _longText,
              },
            ],
          },
        {
          'block_id': 'Q',
          'type': 'exercise',
          'steps': [
            {
              'id': 's1',
              'type': 'question',
              'order': 1,
              'text': 'Vysvětli vlastními slovy.',
              'question': {'type': 'open', 'correct_answer': 'cokoli'},
            },
          ],
        },
      ],
    };

class _NoSync implements SyncService {
  @override
  Future<void> sync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Offline implements ConnectivityService {
  @override
  Future<bool> get isOnline async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoGamificationConfig implements GamificationConfigRepository {
  @override
  Future<GamificationConfig?> getConfig() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// google_fonts fetches its fonts over HTTP; see quiz_elo_timing_test.dart.
class _SilentHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _NeverAnswering();
}

class _NeverAnswering implements HttpClient {
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      Completer<HttpClientRequest>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;
  late HttpOverrides? previousHttpOverrides;

  setUp(() async {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _SilentHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await db.upsertUser(const UsersTableCompanion(
      id: Value(_userId),
      name: Value('Tester'),
      email: Value(''),
      isActive: Value(true),
    ));
    await db.upsertUserCourse(UserCoursesTableCompanion(
      id: const Value(_userCourseId),
      userId: const Value(_userId),
      courseId: const Value('local-1'),
      status: const Value('in_progress'),
      totalLessons: const Value(1),
      progressDataJson: Value(jsonEncode({
        'lessons': {
          'L1': {
            'completed_blocks': ['T1', 'T2', 'T3'],
            'current_block_index': 3,
          },
        },
      })),
    ));
  });

  // Not awaited: the page's drift watches close on zero-delay timers, and
  // once the container is disposed in teardown nothing pumps them any more,
  // so an awaited close never returns.
  tearDown(() {
    HttpOverrides.global = previousHttpOverrides;
    db.close();
  });

  Future<ProviderContainer> pumpLesson(WidgetTester tester,
      {ProviderContainer? reuse}) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = reuse ??
        ProviderContainer(overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          authTokenStorageProvider
              .overrideWithValue(AuthTokenStorage(prefs: prefs)),
          workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
          syncServiceProvider.overrideWithValue(_NoSync()),
          connectivityServiceProvider.overrideWithValue(_Offline()),
          gamificationConfigRepositoryProvider
              .overrideWithValue(_NoGamificationConfig()),
        ]);
    if (reuse == null) {
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(activeUserProvider.future));
    }

    final course = Course.fromJsonData(id: 'local-1', data: _courseData());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: LessonDetailPage(
            course: course,
            lesson: course.lessons.first,
            lessonIndex: 0,
            userCourseId: _userCourseId,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Saved progress loads after the first frame and scrolls to the current
    // block from a delayed future, which pumpAndSettle does not wait for.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    return container;
  }

  Finder answerField() => find.byType(TextField);

  ScrollController lessonScroll(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView).first).controller!;

  Future<void> typeDraft(WidgetTester tester) async {
    await tester.ensureVisible(answerField());
    await tester.pumpAndSettle();
    await tester.enterText(answerField(), _draft);
    await tester.pumpAndSettle();
    // Off the field, as when the student taps elsewhere: a focused field
    // keeps its list item alive and would hide the bug.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
  }

  testWidgets('a typed answer survives scrolling up to earlier blocks',
      (tester) async {
    await pumpLesson(tester);
    await typeDraft(tester);

    lessonScroll(tester).jumpTo(0);
    await tester.pumpAndSettle();
    expect(answerField(), findsNothing,
        reason: 'the question must really leave the list for this to test it');

    final scroll = lessonScroll(tester);
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(answerField(), findsOneWidget);
    expect(tester.widget<TextField>(answerField()).controller!.text, _draft);
  });

  testWidgets('a typed answer is saved and back after leaving the lesson',
      (tester) async {
    final container = await pumpLesson(tester);
    await typeDraft(tester);

    // The save waits for the student to pause typing.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    final row = (await tester.runAsync(() => db.getUserCourseById(_userCourseId)))!;
    final progress = jsonDecode(row.progressDataJson) as Map<String, dynamic>;
    final answer = progress['lessons']['L1']['step_progress']['Q']
        ['stepAnswers']['s1'] as Map<String, dynamic>;
    expect(answer['textAnswer'], _draft);
    expect(answer['isAnswered'], isFalse);

    // Leave, then open the lesson again.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpLesson(tester, reuse: container);

    await tester.ensureVisible(answerField());
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(answerField()).controller!.text, _draft);
  });
}
