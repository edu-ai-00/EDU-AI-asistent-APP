import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/evaluation/quiz_feedback_comment.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/pages/quiz_page.dart';

// Regression test for BR-83CDA8.
//
// A practice session has no retry button in its recap, yet a score under 70 %
// still printed "Zkus to znovu!" under it — an invitation to a button that
// was not there. The client asked for the line to go from practice; a course
// quiz, which does offer the retry, keeps it.

ContentBlock _block() => ContentBlock.fromJson({
      'block_id': 'TEST_PRACTICE_TRY_AGAIN',
      'type': 'question',
      'content': 'Kolik je 2 + 2?',
      'question': {
        'type': 'multiple_choice',
        'options': [
          {'id': 'a', 'text': '3', 'is_correct': false},
          {'id': 'b', 'text': '4', 'is_correct': true},
        ],
      },
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

/// Finishing a session kicks off a sync; nothing in this test needs it, and
/// the real one wants a signed-in API client.
class _NoSync implements SyncService {
  @override
  Future<void> sync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A course quiz submits its attempt on finish and the guess filter asks for
/// reference times; both are best-effort, so an offline answer is all the test
/// needs.
class _OfflineApi implements ApiClient {
  @override
  Future<ApiResult<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async =>
      ApiResult.failure('offline in test');

  @override
  Future<ApiResult<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    Duration? receiveTimeout,
  }) async =>
      ApiResult.failure('offline in test');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pumpQuiz(WidgetTester tester, {required bool practice}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
          quizFeedbackCommentProvider.overrideWithValue(_NoComment()),
          syncServiceProvider.overrideWithValue(_NoSync()),
          apiClientProvider.overrideWithValue(_OfflineApi()),
        ],
        child: MaterialApp(
          home: QuizPage(
            questionBlocks: [_block()],
            courseTitle: practice ? AppStrings.practiceTitle : 'Kurz',
            courseId: 'course-1',
            evaluate: true,
            // A plain exercise pops without a recap; a course quiz is not one.
            isExercise: practice,
            isFsrsPractice: practice,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Answers right but instantly, so the guess filter scores it as nothing
  /// (BR-RQQVP6): 0 of 1, well under the 70 % line.
  Future<void> finishWithZeroScore(WidgetTester tester) async {
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.quizCheck));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.quizFinish));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.quizCorrectResult(0, 1)), findsOneWidget);
  }

  testWidgets('a low practice score shows no "try again" line', (tester) async {
    await pumpQuiz(tester, practice: true);
    await finishWithZeroScore(tester);

    expect(find.text(AppStrings.practiceCompleted), findsOneWidget);
    expect(find.text(AppStrings.quizTryAgain), findsNothing);
    expect(find.text(AppStrings.quizRetry), findsNothing);
  });

  testWidgets('a low course-quiz score keeps the line next to its retry',
      (tester) async {
    await pumpQuiz(tester, practice: false);
    await finishWithZeroScore(tester);

    expect(find.text(AppStrings.quizTryAgain), findsOneWidget);
    expect(find.text(AppStrings.quizRetry), findsOneWidget);
  });
}
