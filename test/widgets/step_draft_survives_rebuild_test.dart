import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/core/evaluation/ai_answer_evaluator.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/models/step_navigation.dart';
import 'package:eduai/widgets/answer_photo_picker.dart';
import 'package:eduai/widgets/block_step_engine.dart';

// Regression tests for BR-PW5EQK: an answer filled in but not yet checked
// vanished once the student scrolled up to earlier blocks and came back.
//
// The lesson is a lazy list, so a block scrolled far enough away is torn down
// and built again from what the engine last reported through onStepProgress.
// Typing, picking an option and attaching a photo never reported anything, so
// the rebuilt block came back empty. The harness below plays the lesson page:
// it keeps what the engine reports and can drop the engine and build it anew.

ContentBlock _block(Map<String, dynamic> question) => ContentBlock.fromJson({
      'block_id': 'B-DRAFT',
      'type': 'question',
      'steps': [
        {
          'id': 's1',
          'type': 'question',
          'order': 1,
          'text': 'Otázka',
          'question': question,
        },
      ],
    });

final _open = _block({
  'type': 'open',
  'correct_answer': 'cokoli',
  'allow_photo': true,
});

final _numeric = _block({'type': 'numeric', 'correct_answer': '42'});

final _single = _block({
  'type': 'multiple_choice',
  'options': [
    {'id': 'a', 'text': 'tri', 'is_correct': false},
    {'id': 'b', 'text': 'ctyri', 'is_correct': true},
  ],
});

final _multi = _block({
  'type': 'multiple_choice',
  'allow_multiple': true,
  'options': [
    {'id': 'a', 'text': 'jedna', 'is_correct': true},
    {'id': 'b', 'text': 'dva', 'is_correct': true},
    {'id': 'c', 'text': 'tri', 'is_correct': false},
  ],
});

/// A real 1x1 PNG — the picker renders a thumbnail with Image.memory.
final _photo = PickedAnswerPhoto(
  bytes: base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
  ),
  filename: 'reseni.png',
);

/// Nothing in these tests gets as far as checking an answer.
class _UnusedEvaluator implements AiAnswerEvaluator {
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
  }) async =>
      const AiEvaluationOutcome.failed(AiEvaluationFailure.offline);
}

/// Stands in for LessonDetailPage: holds what the engine reports and hands it
/// back to the engine it builds next, as the page does through savedProgress.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.block});
  final ContentBlock block;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  StepProgressData? saved;
  PickedAnswerPhoto? photo;
  bool shown = true;
  int generation = 0;

  /// The block leaves the screen and is torn down.
  void scrollAway() => setState(() => shown = false);

  /// The block comes back into view: a new engine, built from what was kept.
  void scrollBack() => setState(() {
        shown = true;
        generation++;
      });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: shown
              ? BlockStepEngine(
                  key: ValueKey('engine_$generation'),
                  block: widget.block,
                  onBlockCompleted: (
                          {int earnedXp = 0,
                          double scoreKoef = 1.0,
                          String? mark}) {},
                  onStepProgress: (progress) => saved = progress,
                  savedProgress: saved,
                  pickedPhoto: photo,
                  onPickedPhotoChanged: (picked) => photo = picked,
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

void main() {
  final hostKey = GlobalKey<_HostState>();

  Future<void> pumpHost(WidgetTester tester, ContentBlock block) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aiAnswerEvaluatorProvider.overrideWithValue(_UnusedEvaluator()),
      ],
      child: _Host(key: hostKey, block: block),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> scrollAwayAndBack(WidgetTester tester) async {
    hostKey.currentState!.scrollAway();
    await tester.pumpAndSettle();
    expect(find.byType(BlockStepEngine), findsNothing);
    hostKey.currentState!.scrollBack();
    await tester.pumpAndSettle();
  }

  String fieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  StepAnswerState? draft() => hostKey.currentState!.saved?.stepAnswers['s1'];

  testWidgets('typed open answer comes back', (tester) async {
    await pumpHost(tester, _open);
    await tester.enterText(find.byType(TextField), 'Rozepsaná odpověď');
    await tester.pumpAndSettle();

    await scrollAwayAndBack(tester);

    expect(fieldText(tester), 'Rozepsaná odpověď');
    expect(draft()?.isAnswered, isFalse,
        reason: 'a draft is not an answer until it is checked');
    expect(find.text('Zkontrolovat'), findsOneWidget,
        reason: 'the restored draft can be checked straight away');
  });

  testWidgets('typed number comes back', (tester) async {
    await pumpHost(tester, _numeric);
    await tester.enterText(find.byType(TextField), '41');
    await tester.pumpAndSettle();

    await scrollAwayAndBack(tester);

    expect(fieldText(tester), '41');
    expect(find.text('Zkontrolovat'), findsOneWidget);
  });

  testWidgets('picked option comes back unchecked', (tester) async {
    await pumpHost(tester, _single);
    await tester.tap(find.text('ctyri'));
    await tester.pumpAndSettle();

    await scrollAwayAndBack(tester);

    expect(draft()?.selectedOptionId, 'b');
    expect(draft()?.isAnswered, isFalse);
    expect(find.text('Zkontrolovat'), findsOneWidget);
  });

  testWidgets('picked options of a multi-select come back', (tester) async {
    await pumpHost(tester, _multi);
    await tester.tap(find.text('jedna'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dva'));
    await tester.pumpAndSettle();

    await scrollAwayAndBack(tester);

    expect(draft()?.selectedOptionIds, {'a', 'b'});
    expect(find.text('Zkontrolovat'), findsOneWidget);
  });

  testWidgets('attached photo comes back, and removing it sticks too',
      (tester) async {
    await pumpHost(tester, _open);
    tester
        .widget<AnswerPhotoPicker>(find.byType(AnswerPhotoPicker))
        .onPicked!(_photo);
    await tester.pumpAndSettle();

    await scrollAwayAndBack(tester);

    expect(
      tester.widget<AnswerPhotoPicker>(find.byType(AnswerPhotoPicker)).picked,
      same(_photo),
    );
    expect(find.text('Zkontrolovat'), findsOneWidget,
        reason: 'a photo on its own is a complete answer');

    tester
        .widget<AnswerPhotoPicker>(find.byType(AnswerPhotoPicker))
        .onRemoved!();
    await tester.pumpAndSettle();

    await scrollAwayAndBack(tester);

    expect(
      tester.widget<AnswerPhotoPicker>(find.byType(AnswerPhotoPicker)).picked,
      isNull,
    );
  });
}
