import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/models/block_model.dart';
import 'package:eduai/models/step_navigation.dart';
import 'package:eduai/pages/lesson_detail/atomic_cards.dart';
import 'package:eduai/pages/lesson_detail/content_block_cards.dart';
import 'package:eduai/widgets/step_content_renderer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BR-92JSBK — lesson text took its look from the path it was rendered by: a
// paragraph with markdown in it came out 15px in full primaryDark, the one next
// to it without markdown 72 % grey (or 13px in feedback and solutions), HTML
// 88 %. The admin preview runs every field through one markdown renderer, so
// the author never saw the difference (rule 12.6). Each surface is pumped once
// with markdown and once without, and the two must look the same.
// ─────────────────────────────────────────────────────────────────────────────

const _markdown = r'Rovnice $x = 2$ platí.';
const _plain = 'Rovnice platí pro každé reálné číslo.';
const _html = '<p>Rovnice platí pro každé reálné číslo.</p>';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pump();
}

/// The paragraph style of the (only, or first) markdown body on screen.
TextStyle _markdownBody(WidgetTester tester) =>
    tester.widget<MarkdownBody>(find.byType(MarkdownBody).first).styleSheet!.p!;

TextStyle _plainText(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void _expectSameLook(TextStyle actual, TextStyle expected) {
  expect(actual.fontSize, expected.fontSize, reason: 'font size');
  expect(actual.fontWeight, expected.fontWeight, reason: 'font weight');
  expect(actual.color, expected.color, reason: 'colour');
  expect(actual.height, expected.height, reason: 'line height');
}

void _expectHtmlLooksLike(WidgetTester tester, TextStyle expected) {
  final body = tester.widget<Html>(find.byType(Html)).style['body']!;
  expect(body.fontSize?.value, expected.fontSize, reason: 'font size');
  expect(body.fontWeight, expected.fontWeight, reason: 'font weight');
  expect(body.color, expected.color, reason: 'colour');
  expect(body.lineHeight?.size, expected.height, reason: 'line height');
}

// ─── Block V2 steps ─────────────────────────────────────────────────────────

BlockStep _textStep(String text) => BlockStep(
  stepId: 's1',
  type: StepType.text,
  content: StepContent(text: text),
);

BlockStep _answeredQuestion({String? feedback, String? solution}) => BlockStep(
  stepId: 'q1',
  type: StepType.question,
  evaluationConfig: EvaluationConfig(
    type: 'single_select',
    question: 'Kolik je x?',
    solution: solution,
    options: [
      EvaluationOption(id: 'a', text: '2', isCorrect: true, feedback: feedback),
      const EvaluationOption(id: 'b', text: '3'),
    ],
  ),
);

const _answered = StepAnswerState(
  selectedOptionId: 'a',
  isAnswered: true,
  isCorrect: true,
);

// ─── Atomic blocks (outside steps) ──────────────────────────────────────────

ContentBlock _displayBlock(String content) =>
    ContentBlock(blockId: 'b1', type: BlockType.display, content: content);

ContentBlock _questionBlock(String content, {String? solution}) => ContentBlock(
  blockId: 'b2',
  type: BlockType.question,
  content: content,
  atomicQuestion: AtomicQuestion(
    type: 'multiple_choice',
    solution: solution,
    options: const [
      EvaluationOption(id: 'a', text: 'Ano', isCorrect: true),
      EvaluationOption(id: 'b', text: 'Ne'),
    ],
  ),
);

Widget _questionCard(ContentBlock block) => LessonAtomicQuestionCard(
  block: block,
  question: block.atomicQuestion,
  isAnswered: true,
  evaluate: true,
  openInput: null,
  actionRow: const SizedBox.shrink(),
  onOptionSelected: (_) {},
);

Widget _openInput(String solution) => LessonAtomicOpenQuestionInput(
  controller: TextEditingController(text: 'x = 2'),
  question: AtomicQuestion(type: 'open', solution: solution),
  userAnswer: 'x = 2',
  isAnswered: true,
  isCorrect: true,
  showEvaluation: true,
  onChanged: () {},
  onCheckAnswer: () {},
);

void main() {
  group('step content', () {
    testWidgets('a plain text step looks like a markdown one', (tester) async {
      await _pump(tester, StepContentRenderer(step: _textStep(_markdown)));
      final markdown = _markdownBody(tester);

      await _pump(tester, StepContentRenderer(step: _textStep(_plain)));
      _expectSameLook(_plainText(tester, _plain), markdown);
    });

    testWidgets('an HTML text step looks like a markdown one', (tester) async {
      await _pump(tester, StepContentRenderer(step: _textStep(_markdown)));
      final markdown = _markdownBody(tester);

      await _pump(tester, StepContentRenderer(step: _textStep(_html)));
      _expectHtmlLooksLike(tester, markdown);
    });

    testWidgets('plain option feedback looks like markdown feedback', (
      tester,
    ) async {
      await _pump(
        tester,
        StepContentRenderer(
          step: _answeredQuestion(feedback: _markdown),
          answerState: _answered,
        ),
      );
      final markdown = _markdownBody(tester);

      await _pump(
        tester,
        StepContentRenderer(
          step: _answeredQuestion(feedback: _plain),
          answerState: _answered,
        ),
      );
      _expectSameLook(_plainText(tester, _plain), markdown);
    });

    testWidgets('a plain solution looks like a markdown solution', (
      tester,
    ) async {
      await _pump(
        tester,
        StepContentRenderer(
          step: _answeredQuestion(solution: _markdown),
          answerState: _answered,
          showSolution: true,
        ),
      );
      final markdown = _markdownBody(tester);

      await _pump(
        tester,
        StepContentRenderer(
          step: _answeredQuestion(solution: _plain),
          answerState: _answered,
          showSolution: true,
        ),
      );
      _expectSameLook(_plainText(tester, _plain), markdown);
    });
  });

  group('atomic blocks', () {
    testWidgets('a plain display block looks like a markdown one', (
      tester,
    ) async {
      await _pump(
        tester,
        LessonAtomicDisplayCard(
          block: _displayBlock(_markdown),
          actionRow: const SizedBox.shrink(),
        ),
      );
      final markdown = _markdownBody(tester);

      await _pump(
        tester,
        LessonAtomicDisplayCard(
          block: _displayBlock(_plain),
          actionRow: const SizedBox.shrink(),
        ),
      );
      _expectSameLook(_plainText(tester, _plain), markdown);
    });

    testWidgets('an HTML display block looks like a markdown one', (
      tester,
    ) async {
      await _pump(
        tester,
        LessonAtomicDisplayCard(
          block: _displayBlock(_markdown),
          actionRow: const SizedBox.shrink(),
        ),
      );
      final markdown = _markdownBody(tester);

      await _pump(
        tester,
        LessonAtomicDisplayCard(
          block: _displayBlock(_html),
          actionRow: const SizedBox.shrink(),
        ),
      );
      _expectHtmlLooksLike(tester, markdown);
    });

    testWidgets('a plain question looks like a markdown one', (tester) async {
      await _pump(tester, _questionCard(_questionBlock(_markdown)));
      final markdown = _markdownBody(tester);

      await _pump(tester, _questionCard(_questionBlock(_plain)));
      _expectSameLook(_plainText(tester, _plain), markdown);
    });

    testWidgets('an HTML question looks like a markdown one', (tester) async {
      await _pump(tester, _questionCard(_questionBlock(_markdown)));
      final markdown = _markdownBody(tester);

      await _pump(tester, _questionCard(_questionBlock(_html)));
      _expectHtmlLooksLike(tester, markdown);
    });

    testWidgets('a plain multiple-choice solution looks like a markdown one', (
      tester,
    ) async {
      await _pump(
        tester,
        _questionCard(_questionBlock('Kolik je x?', solution: _markdown)),
      );
      final markdown = _markdownBody(tester);

      await _pump(
        tester,
        _questionCard(_questionBlock('Kolik je x?', solution: _plain)),
      );
      _expectSameLook(_plainText(tester, _plain), markdown);
    });

    testWidgets('a plain open-question solution looks like a markdown one', (
      tester,
    ) async {
      await _pump(tester, _openInput(_markdown));
      final markdown = _markdownBody(tester);

      await _pump(tester, _openInput(_plain));
      _expectSameLook(_plainText(tester, _plain), markdown);
    });
  });

  group('content-block text card', () {
    testWidgets('a plain step looks like a markdown one', (tester) async {
      await _pump(
        tester,
        const LessonContentTextCard(
          step: BlockStep(
            stepId: 's1',
            type: StepType.text,
            outputFormat: OutputFormat.markdown,
            content: StepContent(text: _markdown),
          ),
          actionRow: SizedBox.shrink(),
        ),
      );
      final markdown = _markdownBody(tester);

      await _pump(
        tester,
        LessonContentTextCard(
          step: _textStep(_plain),
          actionRow: const SizedBox.shrink(),
        ),
      );
      _expectSameLook(_plainText(tester, _plain), markdown);
    });

    testWidgets('an HTML step looks like a markdown one', (tester) async {
      await _pump(
        tester,
        const LessonContentTextCard(
          step: BlockStep(
            stepId: 's1',
            type: StepType.text,
            outputFormat: OutputFormat.markdown,
            content: StepContent(text: _markdown),
          ),
          actionRow: SizedBox.shrink(),
        ),
      );
      final markdown = _markdownBody(tester);

      await _pump(
        tester,
        const LessonContentTextCard(
          step: BlockStep(
            stepId: 's1',
            type: StepType.text,
            content: StepContent(htmlText: _html),
          ),
          actionRow: SizedBox.shrink(),
        ),
      );
      _expectHtmlLooksLike(tester, markdown);
    });
  });
}
