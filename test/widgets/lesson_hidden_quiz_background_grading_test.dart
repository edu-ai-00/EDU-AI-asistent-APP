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
import 'package:eduai/core/evaluation/ai_answer_evaluator.dart';
import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/services/work_time_tracker.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/sync/sync_service.dart';
import 'package:eduai/models/course_model.dart';
import 'package:eduai/pages/lesson_detail_page.dart';
import 'package:eduai/widgets/block_step_engine.dart';

// Regression test for BR-5Q4MA3, in a quiz-type course's lesson.
//
// With quiz_evaluate off the lesson shows nothing about an answer, so an open
// answer now reveals the next block straight away and is graded in the
// background. The block's ELO still moves by the AI's score — once it is in.

const _userId = 'user-1';

Course _course() {
  final relation = List<int>.filled(35, 0)..[0] = 2;
  final elo = List<double?>.filled(35, null)..[0] = 6.0;
  return Course.fromJsonData(
    id: 'local-1',
    data: {
      'course_id': 'C-QUIZ-LESSON',
      'name': 'Test',
      'language': 'cs',
      'export_type': 'quiz_v2',
      'quiz_evaluate': false,
      'lessons': [
        {
          'lesson_id': 'L1',
          'name': 'Lekce 1',
          'order': 1,
          'blocks': [
            {'block_id': 'B-OPEN', 'order': 1},
            {'block_id': 'B-NEXT', 'order': 2},
          ],
        },
      ],
      'blocks': [
        {
          'block_id': 'B-OPEN',
          'type': 'exercise',
          'gpf': {'relation_vector': relation, 'elo_vector': elo},
          'steps': [
            {
              'id': 's1',
              'type': 'question',
              'order': 1,
              'text': 'Kolik je 2 + 2?',
              'question': {
                'type': 'open',
                'correct_answer': '4',
                'ai_evaluation': true,
                'show_answers': true,
                'show_solution': false,
              },
            },
          ],
        },
        {
          'block_id': 'B-NEXT',
          'type': 'exercise',
          'steps': [
            {
              'id': 's1',
              'type': 'question',
              'order': 1,
              'text': 'Kolik je 3 + 1?',
              'question': {
                'type': 'multiple_choice',
                'options': [
                  {'id': 'a', 'text': 'tri', 'is_correct': false},
                  {'id': 'b', 'text': 'ctyri', 'is_correct': true},
                ],
              },
            },
          ],
        },
      ],
    },
  );
}

/// Answers only when the test opens the gate.
class _GatedEvaluator implements AiAnswerEvaluator {
  Completer<AiEvaluationOutcome>? _gate;

  Completer<AiEvaluationOutcome> get gate =>
      _gate ??= Completer<AiEvaluationOutcome>();

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
  }) =>
      gate.future;

  @override
  Future<UploadedPhoto?> uploadPhoto({
    required Uint8List bytes,
    required String filename,
    String? courseId,
  }) async =>
      null;
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

  testWidgets('an open answer reveals the next block and is graded later',
      (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final evaluator = _GatedEvaluator();
    final container = ProviderContainer(overrides: [
      appDatabaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      workTimeTrackerProvider.overrideWithValue(WorkTimeTracker(db)),
      syncServiceProvider.overrideWithValue(_NoSync()),
      aiAnswerEvaluatorProvider.overrideWithValue(evaluator),
    ]);
    addTearDown(container.dispose);
    await tester.runAsync(() => container.read(activeUserProvider.future));

    final course = _course();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: LessonDetailPage(
            course: course,
            lesson: course.lessons.first,
            lessonIndex: 0,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // A block not yet reached is not built at all.
    bool isCurrent(String blockId) {
      final engine = find.byKey(ValueKey('${blockId}_0'));
      return engine.evaluate().isNotEmpty &&
          tester.widget<BlockStepEngine>(engine).isCurrent;
    }
    expect(isCurrent('B-NEXT'), isFalse);

    // Past the 2 s gaming floor, so the answer moves ELO.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2100)));
    await tester.enterText(find.byType(TextField), 'čtyři');
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.engineCheck));
    await tester.pumpAndSettle();

    expect(isCurrent('B-NEXT'), isTrue,
        reason: 'the next block is up while the answer is still being graded');
    expect(find.text(AppStrings.openFeedbackEvaluating), findsNothing);
    expect(await eloRows(tester), isEmpty,
        reason: 'ELO waits for the score it is moved by');

    evaluator.gate.complete(const AiEvaluationOutcome.success(
      AiEvaluationResult(score: 0.6, isCorrect: true, feedbackText: ''),
    ));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    final rows = await eloRows(tester);
    expect(rows, hasLength(1));
    expect(rows.single['block_id'], 'B-OPEN');
    expect(rows.single['score'], 0.6,
        reason: 'the AI score, not the 0 the block completed with');
  });
}
