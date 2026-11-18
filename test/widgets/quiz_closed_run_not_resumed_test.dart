import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/evaluation/quiz_feedback_comment.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/services/gaming_reference_service.dart';
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/pages/quiz_page.dart';

// Regression test for BR-TUXYXC.
//
// The course page hands every launch of its Kvíz the same in-memory
// QuizProgress, so a student who backs out mid-run resumes where they left off
// (rule 6.3). A finished run went the same way: closing the feedback popup with
// "Hotovo" disposed QuizPage, which saved the whole finished run back into that
// progress — and the next tap on Kvíz reopened it on its last card ("Karta 10
// z 10, 9/10 správně") instead of drawing a new set of ten.

ContentBlock _question(String blockId, String text) => ContentBlock.fromJson({
      'block_id': blockId,
      'type': 'question',
      'content': text,
      'question': {
        'type': 'multiple_choice',
        'options': [
          {'id': 'a', 'text': '3', 'is_correct': false},
          {'id': 'b', 'text': '4', 'is_correct': true},
        ],
      },
    });

final _blocks = [
  _question('Q1', 'Kolik je 2 + 2?'),
  _question('Q2', 'Kolik je 3 + 1?'),
];

/// Records the quiz attempt instead of sending it.
class _RecordingApi extends ApiClient {
  _RecordingApi(super.tokens);

  final posts = <String, dynamic>{};

  @override
  Future<ApiResult<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
    Duration? receiveTimeout,
  }) async {
    posts[path] = data;
    return ApiResult.failure('offline');
  }

  @override
  Future<ApiResult<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    T Function(dynamic)? fromJson,
  }) async =>
      ApiResult.failure('offline');
}

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

class _NoSync implements SyncService {
  @override
  Future<void> sync() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  /// A course page stand-in: its "Kvíz" button launches QuizPage with the one
  /// QuizProgress it holds for the page's lifetime, like course_detail_page.
  Future<_RecordingApi> pumpCoursePage(
    WidgetTester tester,
    QuizProgress progress,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final api = _RecordingApi(AuthTokenStorage(prefs: prefs));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          sharedPreferencesProvider.overrideWithValue(prefs),
          workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
          quizFeedbackCommentProvider.overrideWithValue(_NoComment()),
          gamingReferenceServiceProvider.overrideWithValue(_NoReference()),
          syncServiceProvider.overrideWithValue(_NoSync()),
          apiClientProvider.overrideWithValue(api),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                      builder: (_) => QuizPage(
                        questionBlocks: progress.questionBlocks ?? _blocks,
                        courseTitle: 'Kurz',
                        courseId: 'C1',
                        progress: progress,
                        evaluate: true,
                      ),
                    ),
                  ),
                  child: const Text('Kvíz'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return api;
  }

  Future<void> openQuiz(WidgetTester tester) async {
    await tester.tap(find.text('Kvíz'));
    await tester.pumpAndSettle();
  }

  Future<void> answerRight(WidgetTester tester) async {
    await tester.tap(find.text('4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.quizCheck));
    await tester.pumpAndSettle();
  }

  testWidgets('closing the recap of a finished run starts the next one afresh',
      (tester) async {
    // The launcher's draw, pinned while the run holds answers (BR-WRMW7W).
    final progress = QuizProgress()..questionBlocks = _blocks;
    final api = await pumpCoursePage(tester, progress);

    await openQuiz(tester);
    await answerRight(tester);
    await tester.tap(find.text(AppStrings.actionContinue));
    await tester.pumpAndSettle();
    await answerRight(tester);
    await tester.tap(find.text(AppStrings.quizFinish));
    await tester.pumpAndSettle();

    expect(api.posts, hasLength(1), reason: 'the attempt was submitted');
    await tester.ensureVisible(find.text(AppStrings.quizDone));
    await tester.tap(find.text(AppStrings.quizDone));
    await tester.pumpAndSettle();
    expect(find.text('Kvíz'), findsOneWidget, reason: 'back on the course');

    // Nothing for the next launch to resume, and no draw holding it to the
    // same questions: courseQuizBlocks draws a new set.
    expect(progress.answeredFlags, isEmpty);
    expect(progress.currentIndex, 0);
    expect(progress.questionBlocks, isNull);

    await openQuiz(tester);
    expect(find.text(AppStrings.quizCardProgress(1, 2)), findsOneWidget);
    expect(find.text(AppStrings.quizCardProgress(2, 2)), findsNothing);
    expect(find.text(AppStrings.quizCorrectCount(0, 2)), findsOneWidget);
  });

  testWidgets('backing out mid-run still resumes it (rule 6.3)',
      (tester) async {
    final progress = QuizProgress()..questionBlocks = _blocks;
    await pumpCoursePage(tester, progress);

    await openQuiz(tester);
    await answerRight(tester);
    await tester.tap(find.text(AppStrings.actionContinue));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.quizCardProgress(2, 2)), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Kvíz'), findsOneWidget, reason: 'back on the course');

    expect(progress.answeredFlags, {0: true});
    expect(progress.questionBlocks, same(_blocks));

    await openQuiz(tester);
    expect(find.text(AppStrings.quizCardProgress(2, 2)), findsOneWidget);
  });
}
