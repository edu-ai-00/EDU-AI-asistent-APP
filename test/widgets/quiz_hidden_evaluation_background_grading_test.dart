import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/database/app_database.dart';
import 'package:eduai/core/elo/elo_engine.dart';
import 'package:eduai/core/evaluation/ai_answer_evaluator.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/services/gaming_reference_service.dart';
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/pages/quiz_page.dart';

// Regression test for BR-5Q4MA3, on the real QuizPage.
//
// A course quiz with quiz_evaluate off shows nothing about an answer, so an
// open answer no longer holds the student on "Promýšlím tvou odpověď..." while
// the AI grades it: the next question appears at once. The grade still has to
// count — ELO moves by the AI's score, timed from when the answer was given,
// and the submitted attempt waits for the verdicts it reports.

const _userId = 'user-1';

ContentBlock _openQuestion(String blockId, String text) {
  final relation = List<int>.filled(kGpfDimensions, 0)..[0] = 2;
  final elo = List<double?>.filled(kGpfDimensions, null)..[0] = 6.0;
  return ContentBlock.fromJson({
    'block_id': blockId,
    'type': 'question',
    'gpf': {'relation_vector': relation, 'elo_vector': elo},
    'steps': [
      {
        'id': 's1',
        'type': 'question',
        'order': 1,
        'content': {'text': text},
        'question': {
          'type': 'open',
          'correct_answer': '4',
          'ai_evaluation': true,
          'show_answers': true,
          'show_solution': false,
        },
      },
    ],
  });
}

/// Hands out one gate per evaluation, opened only when the test says so.
class _GatedEvaluator implements AiAnswerEvaluator {
  final gates = <Completer<AiEvaluationOutcome>>[];

  @override
  Future<AiEvaluationOutcome> evaluate({
    required String question,
    String studentAnswer = '',
    String? photoName,
    String? help,
    String? solution,
    String? correctAnswer,
    String? criteria,
    List<QuestionCriterion> criteriaList = const [],
    String? language,
  }) {
    final gate = Completer<AiEvaluationOutcome>();
    gates.add(gate);
    return gate.future;
  }

  @override
  Future<UploadedPhoto?> uploadPhoto({
    required Uint8List bytes,
    required String filename,
    String? courseId,
  }) async =>
      null;
}

/// Records the quiz attempt instead of sending it; every read fails at once.
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

const _graded = AiEvaluationOutcome.success(AiEvaluationResult(
  score: 1.0,
  isCorrect: true,
  feedbackText: 'Správně.',
  model: 'test/model',
));

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
  });

  tearDown(() async {
    HttpOverrides.global = previousHttpOverrides;
    await db.close();
  });

  Future<List<Map<String, dynamic>>> eloRows(WidgetTester tester) async {
    final rows = (await tester.runAsync(() => (db.select(db.syncQueueTable)
          ..where((q) => q.tableName_.equals('elo_interactions')))
        .get()))!;
    return [
      for (final row in rows) jsonDecode(row.payload) as Map<String, dynamic>,
    ];
  }

  Future<void> answer(WidgetTester tester, String button) async {
    // Past the 2 s gaming floor, so the answer moves ELO.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2100)));
    await tester.enterText(find.byType(TextField), 'čtyřikrát');
    await tester.pumpAndSettle();
    await tester.tap(find.text(button));
    // Not pumpAndSettle: once the quiz is finished, the busy bar's spinner
    // never settles.
    // The engine completes the block in a post-frame callback and the quiz
    // advances in the next one.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('an open answer moves the quiz on and is graded in the background',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final evaluator = _GatedEvaluator();
    final api = _RecordingApi(AuthTokenStorage(prefs: prefs));
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
      syncServiceProvider.overrideWithValue(_NoSync()),
      gamingReferenceServiceProvider.overrideWithValue(_NoReference()),
      aiAnswerEvaluatorProvider.overrideWithValue(evaluator),
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(activeUserProvider.future));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: QuizPage(
            questionBlocks: [
              _openQuestion('Q1', 'Kolik je 2 + 2?'),
              _openQuestion('Q2', 'Kolik je 3 + 1?'),
            ],
            courseTitle: 'Kvíz',
            courseId: 'C-QUIZ',
            evaluate: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await answer(tester, AppStrings.actionContinue);

    // The next question is up while the first one is still being graded.
    expect(evaluator.gates, hasLength(1));
    expect(evaluator.gates.single.isCompleted, isFalse);
    // QuizPage keys each question's engine by its index.
    expect(find.byKey(const ValueKey('quiz_v2_1')), findsOneWidget,
        reason: 'the second question is on screen');
    expect(find.text(AppStrings.openFeedbackEvaluating), findsNothing);
    expect(await eloRows(tester), isEmpty,
        reason: 'ELO waits for the score it is moved by');

    // Real time passes before the verdict lands.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    final verdictAt = DateTime.now().toUtc();
    evaluator.gates[0].complete(_graded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final rows = await eloRows(tester);
    expect(rows, hasLength(1));
    expect(rows.single['block_id'], 'Q1');
    expect(rows.single['score'], 1.0);
    expect(
      DateTime.parse(rows.single['confirmed_at'] as String).isBefore(verdictAt),
      isTrue,
      reason: 'the answer counts from when it was given, not when it was graded',
    );

    // The last answer: the finished quiz waits for its grade before it goes
    // out — and says so without "thinking about your answer".
    await answer(tester, AppStrings.quizFinish);
    expect(evaluator.gates, hasLength(2));
    expect(find.text(AppStrings.quizSubmitting), findsOneWidget);
    expect(find.text(AppStrings.openFeedbackEvaluating), findsNothing);
    expect(api.posts, isEmpty);

    evaluator.gates[1].complete(_graded);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    final attempt = api.posts.values.single as Map<String, dynamic>;
    final answers = (attempt['answers'] as List).cast<Map<String, dynamic>>();
    expect(answers, hasLength(2));
    for (final a in answers) {
      expect(a['is_correct'], isTrue);
      expect(a['evaluated_by_ai'], isTrue);
      expect(a['ai_score'], 1.0);
    }
    expect(find.text(AppStrings.quizSubmitting), findsNothing);
  });
}
