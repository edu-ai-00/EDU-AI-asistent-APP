import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/core/evaluation/ai_answer_evaluator.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/models/step_navigation.dart';
import 'package:eduai/widgets/block_step_engine.dart';

// Regression tests for BR-5Q4MA3.
//
// "Pokud je kurz nastaven, aby nezobrazoval vyhodnocení, nesmí aplikace
// zobrazovat 'Promýšlím tvou odpověď' a čekat na AI vyhodnocení. Má zobrazit
// další blok a vyhodnocení provede na pozadí."
//
// A quiz with quiz_evaluate off shows the student nothing about an answer, so
// the 5–25 s AI call bought them nothing but a spinner. The engine now records
// the answer, moves on, and hands the host the block's score once the verdict
// lands. Everywhere the verdict is still needed — on screen or to choose the
// next step — it waits as before.

const _expected = '4';

ContentBlock _block({Map<String, dynamic>? nextActions}) =>
    ContentBlock.fromJson({
      'block_id': 'TEST_HIDDEN_QUIZ',
      'type': 'question',
      'steps': [
        {
          'id': 's1',
          'type': 'question',
          'order': 1,
          'content': {'text': 'Jakou četnost má v datech hodnota a?'},
          'question': {
            'type': 'open',
            'correct_answer': _expected,
            'solution': 'Hodnota a se vyskytuje čtyřikrát.',
            'ai_evaluation': true,
            'show_answers': true,
            'show_solution': false,
          },
          if (nextActions != null) 'next_actions': nextActions,
        },
      ],
    });

/// An evaluator that answers only when the test says so.
class _GatedEvaluator implements AiAnswerEvaluator {
  /// Created on first use, inside the test's fake-async zone — see
  /// quiz_evaluating_indicator_test.dart for why setUp is the wrong place.
  Completer<AiEvaluationOutcome>? _gate;

  Completer<AiEvaluationOutcome> get gate =>
      _gate ??= Completer<AiEvaluationOutcome>();

  int calls = 0;

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
    calls++;
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

/// What the host saw, the way QuizPage sees it.
class _Host {
  final completions = <double>[];
  Future<BlockGrading>? grading;
  BlockGrading? settled;

  void onGradingDeferred(Future<BlockGrading> future) {
    grading = future;
    future.then((g) => settled = g);
  }
}

/// QuizPage stand-in: a controller drives the engine and the button lives
/// outside it.
class _QuizHarness extends StatefulWidget {
  const _QuizHarness({
    required this.block,
    required this.host,
    this.hideEvaluation = true,
    this.defers = true,
  });

  final ContentBlock block;
  final _Host host;
  final bool hideEvaluation;

  /// Whether the host can take a score later at all.
  final bool defers;

  @override
  State<_QuizHarness> createState() => _QuizHarnessState();
}

class _QuizHarnessState extends State<_QuizHarness> {
  final BlockStepEngineController _controller = BlockStepEngineController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              BlockStepEngine(
                block: widget.block,
                exportMode: ExportMode.quizV2,
                hideEvaluation: widget.hideEvaluation,
                showAnswerStatus: !widget.hideEvaluation,
                controller: _controller,
                onGradingDeferred:
                    widget.defers ? widget.host.onGradingDeferred : null,
                onBlockCompleted: (
                    {int earnedXp = 0, double scoreKoef = 1.0, String? mark}) {
                  widget.host.completions.add(scoreKoef);
                },
              ),
              TextButton(
                onPressed:
                    _controller.hasPendingAnswer ? _controller.confirm : null,
                child: const Text('Pokracovat'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

BlockStepEngineController _controllerOf(WidgetTester tester) =>
    tester.widget<BlockStepEngine>(find.byType(BlockStepEngine)).controller!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _GatedEvaluator evaluator;
  late _Host host;

  setUp(() {
    evaluator = _GatedEvaluator();
    host = _Host();
  });

  Future<void> pump(
    WidgetTester tester, {
    ContentBlock? block,
    bool hideEvaluation = true,
    bool defers = true,
  }) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [aiAnswerEvaluatorProvider.overrideWithValue(evaluator)],
      child: _QuizHarness(
        block: block ?? _block(),
        host: host,
        hideEvaluation: hideEvaluation,
        defers: defers,
      ),
    ));
    await tester.pumpAndSettle();
  }

  /// Type an answer and send it, the way the quiz's bottom bar does.
  Future<void> answer(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pokracovat'));
    // Not pumpAndSettle: a spinner, where there is one, never settles.
    await tester.pump();
    await tester.pump();
  }

  Future<void> land(WidgetTester tester, AiEvaluationOutcome outcome) async {
    evaluator.gate.complete(outcome);
    await tester.pump();
    await tester.pump();
  }

  const graded = AiEvaluationOutcome.success(AiEvaluationResult(
    score: 0.8,
    isCorrect: true,
    feedbackText: 'Správně, četnost je 4.',
    model: 'test/model',
  ));

  group('quiz with evaluation hidden', () {
    testWidgets('moves on without waiting for the verdict', (tester) async {
      await pump(tester);
      await answer(tester, 'čtyřikrát');

      expect(evaluator.calls, 1, reason: 'the answer is still graded by AI');
      expect(_controllerOf(tester).isEvaluating, isFalse,
          reason: 'nothing for the quiz bar to spin on');
      expect(host.completions, hasLength(1),
          reason: 'the block completes before the AI has answered');
      expect(host.grading, isNotNull);
      expect(host.settled, isNull, reason: 'the verdict is not in yet');

      await land(tester, graded);

      expect(host.settled, isNotNull);
      expect(host.settled!.scoreKoef, 0.8,
          reason: 'the AI score is what the block is worth');
      final step = host.settled!.progress.stepAnswers['s1']!;
      expect(step.isCorrect, isTrue);
      expect(step.evaluatedByAi, isTrue);
      expect(host.settled!.earnedXp, 5,
          reason: 'partial credit, so not the full-marks 8 XP');
    });

    testWidgets('the verdict still reaches the host once the engine is gone',
        (tester) async {
      await pump(tester);
      await answer(tester, 'čtyřikrát');
      expect(host.completions, hasLength(1));

      // QuizPage swaps the engine for the next question straight away.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await land(tester, graded);

      expect(host.settled, isNotNull);
      expect(host.settled!.scoreKoef, 0.8);
      expect(host.settled!.progress.stepAnswers['s1']!.evaluatedByAi, isTrue);
    });

    testWidgets('with the AI unreachable it falls back to the comparison',
        (tester) async {
      await pump(tester);
      await answer(tester, _expected);

      await land(
        tester,
        const AiEvaluationOutcome.failed(AiEvaluationFailure.offline),
      );

      expect(host.settled, isNotNull);
      expect(host.settled!.scoreKoef, 1.0,
          reason: 'the same fallback as the waiting path (BR-N26ACB)');
      final step = host.settled!.progress.stepAnswers['s1']!;
      expect(step.isCorrect, isTrue);
      expect(step.evaluatedByAi, isFalse);
    });
  });

  group('still waits for the verdict', () {
    testWidgets('when the quiz shows evaluation', (tester) async {
      await pump(tester, hideEvaluation: false);
      await answer(tester, 'čtyřikrát');

      expect(_controllerOf(tester).isEvaluating, isTrue);
      expect(host.completions, isEmpty);
      expect(host.grading, isNull);

      await land(tester, graded);
    });

    testWidgets('when the next step depends on right or wrong',
        (tester) async {
      await pump(
        tester,
        block: _block(nextActions: {'correct': 'END', 'incorrect': 'AGAIN'}),
      );
      await answer(tester, 'čtyřikrát');

      expect(_controllerOf(tester).isEvaluating, isTrue);
      expect(host.completions, isEmpty);
      expect(host.grading, isNull);

      await land(tester, graded);
    });

    testWidgets('when the host cannot take a score later', (tester) async {
      await pump(tester, defers: false);
      await answer(tester, 'čtyřikrát');

      expect(_controllerOf(tester).isEvaluating, isTrue);
      expect(host.completions, isEmpty);

      await land(tester, graded);
    });
  });
}
