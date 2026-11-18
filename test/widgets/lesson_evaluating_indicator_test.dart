import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/connectivity/connectivity_service.dart';
import 'package:eduai/core/evaluation/ai_answer_evaluator.dart';
import 'package:eduai/core/network/api_client.dart';
import 'package:eduai/core/services/auth_token_storage.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/models/course_model.dart';
import 'package:eduai/pages/lesson_detail/atomic_cards.dart';
import 'package:eduai/widgets/block_step_engine.dart';

// Regression tests for BR-J8DEXT: BR-4AT4CC gave the quiz a bottom bar that
// says "Promýšlím tvou odpověď..." while an open answer is out for AI grading,
// but in a lesson the same wait only shrank the check button to a bare 20px
// spinner — in the engine's case a pill at the far right of the card, metres
// from the field the student just typed in on a monitor. Three to five seconds
// of that reads as a frozen page, which is what the report describes.
//
// Both in-lesson surfaces must now name the wait the way the quiz does: the
// V2 step engine driving its own button (no controller), and the atomic
// open-question card.

/// An evaluator that never answers until the test says so, so the in-flight
/// state can be inspected instead of raced.
class _GatedEvaluator extends AiAnswerEvaluator {
  _GatedEvaluator(super.api, super.connectivity);

  /// Created on first use rather than in setUp: a Completer schedules its
  /// continuation in the zone it was built in, and setUp runs outside the
  /// test's fake-async zone — completing it there would never be flushed by
  /// tester.pump(), leaving the evaluation permanently in flight.
  Completer<AiEvaluationOutcome>? _gate;

  Completer<AiEvaluationOutcome> get gate =>
      _gate ??= Completer<AiEvaluationOutcome>();

  bool get isPending => _gate != null && !_gate!.isCompleted;

  @override
  Future<UploadedPhoto?> uploadPhoto({
    required Uint8List bytes,
    required String filename,
    String? courseId,
  }) async =>
      null;

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
}

/// V2 step block with an AI-graded open question — the in-lesson shape.
ContentBlock _v2Block() => ContentBlock.fromJson({
      'block_id': 'TEST_AI_V2',
      'type': 'question',
      'steps': [
        {
          'id': 's1',
          'type': 'question',
          'order': 1,
          'question': {
            'type': 'open',
            'question': 'Co znamena "jablko nepada daleko od stromu"?',
            'ai_evaluation': true,
            'show_answers': true,
          },
        },
      ],
    });

/// The lesson's atomic open-question card, with no page around it — the card
/// takes the in-flight state as a plain flag, so the whole lesson page does not
/// have to be stood up to see what it draws.
Widget _atomicCard({required bool isEvaluating}) => MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: LessonAtomicOpenQuestionInput(
            controller: TextEditingController(text: 'Deti se podobaji rodicum'),
            question: AtomicQuestion.fromJson(const {
              'type': 'open',
              'ai_evaluation': true,
            }),
            userAnswer: 'Deti se podobaji rodicum',
            isAnswered: false,
            isCorrect: false,
            showEvaluation: true,
            onChanged: () {},
            onCheckAnswer: () {},
            isEvaluating: isEvaluating,
          ),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _GatedEvaluator evaluator;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // Never reached — every network method is overridden — but the superclass
    // needs something to hold.
    evaluator = _GatedEvaluator(
      ApiClient(AuthTokenStorage(prefs: prefs)),
      ConnectivityService(),
    );
  });

  tearDown(() {
    if (evaluator.isPending) {
      evaluator.gate.complete(
          const AiEvaluationOutcome.failed(AiEvaluationFailure.unavailable));
    }
  });

  /// The reporter's window: a desktop browser, where the engine's pill sits far
  /// from the answer field and there is no keyboard dismissal to signal a tap.
  void useDesktopViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1536, 872);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  void expectBusyLabel() {
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'the wait must still be visible as progress',
    );
    expect(
      find.text(AppStrings.openFeedbackEvaluating),
      findsOneWidget,
      reason: 'a bare spinner does not tell the student what is happening',
    );
  }

  testWidgets('in-lesson V2 open step names the wait while the AI grades it',
      (tester) async {
    useDesktopViewport(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [aiAnswerEvaluatorProvider.overrideWithValue(evaluator)],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              // No controller: the lesson lets the engine drive its own button.
              child: BlockStepEngine(
                block: _v2Block(),
                isCurrent: true,
                onBlockCompleted: ({int earnedXp = 0, double scoreKoef = 0, String? mark}) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField).first, 'Deti se podobaji rodicum');
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.engineCheck));
    // Not pumpAndSettle: the progress indicator animates forever, and the gate
    // is deliberately still open.
    await tester.pump();

    expectBusyLabel();
    expect(
      find.text(AppStrings.engineCheck),
      findsNothing,
      reason: 'a live "Zkontrolovat" invites the dead tap the report describes',
    );
  });

  testWidgets('the label is not gated on a wide window', (tester) async {
    // The design's phone artboard. The sentence is new to this surface, so the
    // phone has to be checked too — not for pixel fit (the test font is one em
    // per glyph, nothing like Poppins) but for the layout holding: the label
    // is Flexible with an ellipsis inside a full-width button, so it is shown
    // at every width rather than dropped on the narrow one.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_atomicCard(isEvaluating: true));
    await tester.pump();

    expectBusyLabel();
  });

  testWidgets('in-lesson atomic open question names the wait',
      (tester) async {
    useDesktopViewport(tester);

    await tester.pumpWidget(_atomicCard(isEvaluating: true));
    await tester.pump();

    expectBusyLabel();
    expect(
      find.text(AppStrings.lessonCheckAnswer),
      findsNothing,
      reason: 'the button is inert while grading runs',
    );
  });
}
