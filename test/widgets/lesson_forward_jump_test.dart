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
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/data/repositories/gamification_config_repository.dart';
import 'package:eduai/models/gamification_config_model.dart';
import 'package:eduai/models/course_model.dart';
import 'package:eduai/pages/lesson_detail/lesson_header.dart';
import 'package:eduai/pages/lesson_detail_page.dart';

// BR-4XS5FD — a lesson whose author sends the student forward past a block
// could never be finished. It sat on 4/6 for good: no lesson completion, no XP.
//
// Two things went wrong on the way to the jump target, and they cost one block
// each:
//   * the block the go_to fired from was dropped. The engine signals the jump
//     straight away but reports the completion in a post-frame callback, by
//     which time _currentBlockIndex sits on the target and _confirmBlock's
//     stale-callback guard refuses it;
//   * the blocks jumped over were never touched at all, so _allBlocksCompleted
//     could not hold however far the student got.

const _userId = 'user-1';
const _userCourseId = 'uc-1';

/// One lesson of four blocks. B1 asks whether to skip ahead: the first answer
/// jumps to B3 (over B2), the second walks on normally. B2–B4 are one-bubble
/// display blocks, worth 1 XP each; B1, answered right, is worth 8.
///
/// With [lastJumpsBack], B4 is a question instead whose answer sends the
/// student back to B1 (BR-UM42RU).
Map<String, dynamic> _courseData({bool lastJumpsBack = false}) => {
      'course_id': 'C-JUMP',
      'name': 'Navigace',
      'language': 'cs',
      'max_xp': 1000,
      // As DEMOKURZ01 has it: the answer is graded on screen, so confirming a
      // question takes "Zkontrolovat" and then ✓ — and it is that ✓ which
      // resolves the go_to.
      'quiz_evaluate': true,
      'lessons': [
        {
          'lesson_id': 'L1',
          'name': 'Navigace mezi bloky',
          'order': 1,
          'blocks': [
            for (var i = 1; i <= 4; i++) {'block_id': 'B$i', 'order': i},
          ],
        },
      ],
      'blocks': [
        {
          'block_id': 'B1',
          'type': 'question',
          'steps': [
            {
              'id': 's1',
              'type': 'question',
              'order': 1,
              'question': {
                'type': 'multiple_choice',
                'question': 'Chces preskocit dalsi blok?',
                'options': [
                  {
                    'id': 'a',
                    'text': 'Ano, preskocit',
                    'is_correct': true,
                    'go_to': 'B3',
                  },
                  {
                    'id': 'b',
                    'text': 'Ne, pokracovat',
                    'is_correct': true,
                    'go_to': 'NEXT_STEP',
                  },
                ],
              },
            },
          ],
        },
        for (final block in [
          const ['B2', 'Preskakovany blok'],
          const ['B3', 'Cil skoku'],
          if (!lastJumpsBack) const ['B4', 'Posledni blok'],
        ])
          {
            'block_id': block[0],
            'type': 'display',
            'steps': [
              {
                'id': 's1',
                'type': 'text',
                'order': 1,
                'content': block[1],
              },
            ],
          },
        if (lastJumpsBack)
          {
            'block_id': 'B4',
            'type': 'question',
            'steps': [
              {
                'id': 's1',
                'type': 'question',
                'order': 1,
                'question': {
                  'type': 'multiple_choice',
                  'question': 'Znovu od zacatku?',
                  'options': [
                    {
                      'id': 'a',
                      'text': 'Zpet na zacatek',
                      'is_correct': true,
                      'go_to': 'B1',
                    },
                  ],
                },
              },
            ],
          },
      ],
    };

/// Completing a block kicks off a sync; the real one wants a signed-in client.
class _NoSync implements SyncService {
  @override
  Future<void> sync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// Offline, so the trophy and streak writes queue up instead of calling the
/// API — which, with [_SilentHttpOverrides], would never answer and keep the
/// lesson's save waiting forever.
class _Offline implements ConnectivityService {
  @override
  Future<bool> get isOnline async => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No achievements to check. The real repository downloads the config when
/// none is cached, and that request would outlive the test.
class _NoGamificationConfig implements GamificationConfigRepository {
  @override
  Future<GamificationConfig?> getConfig() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// google_fonts fetches its fonts over HTTP. The test binding answers every
/// request with 400, and inside a real-async window that failure lands as a
/// test error; a request that never answers stays silent.
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

  group('forward cross-block jump', () {
    late AppDatabase db;
    late SharedPreferences prefs;

    setUp(() async {
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
      await db.upsertUserCourse(const UserCoursesTableCompanion(
        id: Value(_userCourseId),
        userId: Value(_userId),
        courseId: Value('local-1'),
        status: Value('in_progress'),
        totalLessons: Value(1),
      ));
    });

    // Not awaited: the page's drift watches close on zero-delay timers, and
    // once the container is disposed in teardown nothing pumps them any more,
    // so an awaited close never returns.
    tearDown(() {
      db.close();
    });

    Future<void> pumpLesson(WidgetTester tester,
        {bool lastJumpsBack = false}) async {
      // Phone width (under kCompactMaxWidth), so the page renders its own
      // LessonHeader — that is where the x/N the reporter watched comes from.
      // The wide layout drops the header in favour of the side rail.
      // 560 rather than a true phone width: the action row overflows narrower
      // than that under the test font.
      tester.view.physicalSize = const Size(560, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = ProviderContainer(overrides: [
        appDatabaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        // No token: XP writes stay local, nothing goes out.
        authTokenStorageProvider
            .overrideWithValue(AuthTokenStorage(prefs: prefs)),
        workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
        syncServiceProvider.overrideWithValue(_NoSync()),
        connectivityServiceProvider.overrideWithValue(_Offline()),
        gamificationConfigRepositoryProvider
            .overrideWithValue(_NoGamificationConfig()),
      ]);
      addTearDown(container.dispose);
      await tester.runAsync(() => container.read(activeUserProvider.future));

      final course = Course.fromJsonData(
          id: 'local-1', data: _courseData(lastJumpsBack: lastJumpsBack));
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
    }

    /// Tap the confirm (✓) of the block the student is on.
    Future<void> tapConfirm(WidgetTester tester) async {
      final confirm = find.byIcon(Icons.check).last;
      await tester.ensureVisible(confirm);
      await tester.pumpAndSettle();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
    }

    /// Answer the current question with [option]. "Zkontrolovat" both grades
    /// the answer and closes the block, so it is this tap that resolves the
    /// answer's go_to.
    Future<void> answerQuestion(WidgetTester tester, String option) async {
      await tester.ensureVisible(find.text(option));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
      final check = find.text(AppStrings.lessonCheckAnswer).last;
      await tester.ensureVisible(check);
      await tester.pumpAndSettle();
      await tester.tap(check);
      await tester.pumpAndSettle();
    }

    int completedCount(WidgetTester tester) =>
        tester.widget<LessonHeader>(find.byType(LessonHeader)).completedCount;

    Future<Map<String, dynamic>> progressData(WidgetTester tester) async {
      final row = await tester
          .runAsync(() => db.getUserCourseById(_userCourseId));
      return jsonDecode(row!.progressDataJson) as Map<String, dynamic>;
    }

    testWidgets('books the answered block and the block it skips', (tester) async {
      await pumpLesson(tester);
      expect(completedCount(tester), 0);

      await answerQuestion(tester, 'Ano, preskocit');
      // The jump scrolls to its target on a 300 ms timer, which pumpAndSettle
      // leaves pending — and a pending timer outliving the tree is an error.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // B1 answered, B2 jumped over — the reporter saw neither counted.
      expect(completedCount(tester), 2,
          reason: 'the answered block and the one the jump skipped');
      expect(find.text('Cil skoku'), findsOneWidget,
          reason: 'the student is on the jump target');

      final progress = await progressData(tester);
      final lesson = (progress['lessons'] as Map)['L1'] as Map;
      expect(
        (lesson['completed_blocks'] as List).cast<String>(),
        containsAll(<String>['B1', 'B2']),
      );
    });

    testWidgets('the lesson still finishes after a forward jump', (tester) async {
      await pumpLesson(tester);

      await answerQuestion(tester, 'Ano, preskocit');
      await tapConfirm(tester); // B3, the jump target
      await tapConfirm(tester); // B4, the last block

      expect(completedCount(tester), 4, reason: 'this stayed on 2/4 before');

      final progress = await progressData(tester);
      final lesson = (progress['lessons'] as Map)['L1'] as Map;
      expect(lesson['is_completed'], isTrue,
          reason: 'the whole point of the report: the lesson can be finished');

      // 8 for the answered question + 1 each for B3 and B4. The skipped block
      // pays nothing — nobody answered it.
      expect(progress['xp_earned'], 10);
    });

    testWidgets('answering past the jump walks through every block',
        (tester) async {
      await pumpLesson(tester);

      await answerQuestion(tester, 'Ne, pokracovat');
      expect(completedCount(tester), 1,
          reason: 'no jump, so nothing is skipped over');
      expect(find.text('Preskakovany blok'), findsOneWidget);

      await tapConfirm(tester); // B2
      await tapConfirm(tester); // B3
      await tapConfirm(tester); // B4

      expect(completedCount(tester), 4);

      final progress = await progressData(tester);
      expect((progress['lessons'] as Map<String, dynamic>)['L1']['is_completed'],
          isTrue);
      // Every block earned: 8 + 1 + 1 + 1.
      expect(progress['xp_earned'], 11);
    });

    // BR-UM42RU — the block jumped over showed up in full, ticked off as done,
    // above the jump target. The student read "Při ‚Ano' ho lekce přeskočí"
    // in the very block the lesson was meant to skip.
    testWidgets('the skipped block is left out of the lesson', (tester) async {
      await pumpLesson(tester);

      await answerQuestion(tester, 'Ano, preskocit');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Preskakovany blok'), findsNothing,
          reason: 'the jump skips the block, it does not show it done');
      expect(find.text('Cil skoku'), findsOneWidget);
      expect(completedCount(tester), 2,
          reason: 'it still counts, or the lesson could not finish (BR-4XS5FD)');

      final progress = await progressData(tester);
      final lesson = (progress['lessons'] as Map)['L1'] as Map;
      expect((lesson['skipped_blocks'] as List).cast<String>(), ['B2']);
    });

    testWidgets('a reopened lesson keeps the skipped block out', (tester) async {
      await pumpLesson(tester);
      await answerQuestion(tester, 'Ano, preskocit');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      // Leave the lesson.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      await pumpLesson(tester);
      // The restore scroll runs on a timer that pumpAndSettle does not wait for.
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('Cil skoku'), findsOneWidget,
          reason: 'the saved progress was read back');
      expect(find.text('Preskakovany blok'), findsNothing);
      expect(completedCount(tester), 2);
    });

    testWidgets('a block put back in play by a backward jump shows again',
        (tester) async {
      await pumpLesson(tester, lastJumpsBack: true);

      await answerQuestion(tester, 'Ano, preskocit');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await tapConfirm(tester); // B3, the jump target
      await answerQuestion(tester, 'Zpet na zacatek'); // B4 → back to B1
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      // This time the student walks on instead of skipping.
      await answerQuestion(tester, 'Ne, pokracovat');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(find.text('Preskakovany blok'), findsOneWidget,
          reason: 'B2 is no longer skipped, the student is on it');

      final progress = await progressData(tester);
      final lesson = (progress['lessons'] as Map)['L1'] as Map;
      expect(lesson['skipped_blocks'], isEmpty);
    });
  });
}
