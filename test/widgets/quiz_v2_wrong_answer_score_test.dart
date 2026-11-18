import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/evaluation/quiz_feedback_comment.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/gaming_reference_service.dart';
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/pages/quiz_page.dart';

// Regression test for BR-VZV2JA.
//
// Since BR-PW5EQK the step engine reports a pick before it is checked. QuizPage
// fed that report back to the engine as "saved progress" without a score, the
// model's 1.0 default filled the gap, and the engine took 1.0 as the best score
// so far — so every wrong answer on a step-based card came out as correct:
// "9 správně" after mostly wrong answers.

ContentBlock _block() => ContentBlock.fromJson({
      'block_id': 'TEST_V2_WRONG_SCORE',
      'type': 'exercise',
      'steps': [
        {
          'id': 's1',
          'type': 'text',
          'order': 1,
          'content': 'Které tlačítko otevře dialog s AI asistentem?',
        },
        {
          'id': 's2',
          'type': 'question',
          'order': 2,
          'question': {
            'type': 'multiple_choice',
            'options': [
              {'id': 'opt_1', 'text': 'Kurzy', 'is_correct': false},
              {'id': 'opt_2', 'text': 'Novinky', 'is_correct': false},
              {'id': 'opt_3', 'text': 'Nápověda', 'is_correct': true},
            ],
            'show_answers': true,
            'solution': 'Správně je nápověda.',
          },
        },
      ],
    });

/// The recap's AI comment is online-only and best-effort; the test keeps it out
/// of the way so the popup renders without waiting on a network call.
class _NoComment implements QuizFeedbackCommentService {
  @override
  Future<String?> fetchComment({
    required List<QuizFeedbackTask> tasks,
    Map<String, double> domainDeltas = const {},
    String? language,
  }) async =>
      null;
}

class _NoReference implements GamingReferenceService {
  @override
  Future<Map<String, List<double>>> fetch(Iterable<String> blockIds) async =>
      const {};
}

/// Finishing a session kicks off a sync; nothing in this test needs it, and
/// the real one wants a signed-in API client.
class _NoSync implements SyncService {
  @override
  Future<void> sync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// google_fonts fetches its fonts over HTTP. The test binding answers every
/// request with 400, and inside the real-async wait below that failure lands
/// as a test error; a request that never answers stays silent.
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
  late HttpOverrides? previousHttpOverrides;

  setUp(() async {
    previousHttpOverrides = HttpOverrides.current;
    HttpOverrides.global = _SilentHttpOverrides();
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    await db.close();
  });

  /// A practice session: it reaches the same recap as the course quiz without
  /// submitting an attempt over the network.
  Future<void> pumpPractice(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
          quizFeedbackCommentProvider.overrideWithValue(_NoComment()),
          gamingReferenceServiceProvider.overrideWithValue(_NoReference()),
          syncServiceProvider.overrideWithValue(_NoSync()),
        ],
        child: MaterialApp(
          home: QuizPage(
            questionBlocks: [_block()],
            courseTitle: AppStrings.practiceTitle,
            courseId: 'course-1',
            evaluate: true,
            isExercise: true,
            isFsrsPractice: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Picks [option], checks it and continues past the solution to the recap.
  /// Real time passes first: the quiz times answers on the wall clock, and an
  /// answer under the 2 s gaming floor scores as a guess either way.
  Future<void> answer(WidgetTester tester, String option) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2100)));
    await tester.tap(find.text(option));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.quizCheck));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.actionContinue));
    await tester.pumpAndSettle();
  }

  testWidgets('a wrong answer on a step-based card scores as wrong',
      (tester) async {
    await pumpPractice(tester);
    await answer(tester, 'Novinky');

    expect(find.text(AppStrings.quizCorrectResult(0, 1)), findsOneWidget);
    expect(find.text(AppStrings.quizCorrectResult(1, 1)), findsNothing);
  });

  testWidgets('a right answer on a step-based card still scores as right',
      (tester) async {
    await pumpPractice(tester);
    await answer(tester, 'Nápověda');

    expect(find.text(AppStrings.quizCorrectResult(1, 1)), findsOneWidget);
    expect(find.text(AppStrings.quizCorrectResult(0, 1)), findsNothing);
  });
}
