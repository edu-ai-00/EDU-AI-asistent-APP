import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/widgets/block_step_engine.dart';

// Regression test for BR-DVUNJD: an option whose "kam dál" (go_to) points at
// the question's own step or an earlier one must send the student back to a
// question they can answer again. Before the fix the recorded answer stayed
// put, so the jump re-derived the solution screen it was taken from and the
// continue tap did nothing for ever — a dead end with no way out but leaving
// the lesson (rule 6.4).

ContentBlock _block({required String wrongGoTo, String correctGoTo = 'END'}) {
  return ContentBlock.fromJson({
    'block_id': 'TEST_GOTO_BACK',
    'type': 'question',
    'steps': [
      {'id': 's1', 'type': 'text', 'order': 1, 'content': 'Vyklad o zavazi'},
      {
        'id': 's2',
        'type': 'question',
        'order': 2,
        'question': {
          'type': 'multiple_choice',
          'options': [
            {
              'id': 'opt_1',
              'text': 'Dva',
              'is_correct': true,
              'feedback': 'Vyborne',
              'go_to': correctGoTo,
            },
            {
              'id': 'opt_2',
              'text': 'Tri',
              'is_correct': false,
              'feedback': 'Pozor na zavazi',
              'go_to': wrongGoTo,
            },
          ],
          'show_answers': true,
        },
      },
    ],
  });
}

/// A block whose correct option jumps *forward*, past two display steps.
ContentBlock _forwardJumpBlock() {
  return ContentBlock.fromJson({
    'block_id': 'TEST_GOTO_FWD',
    'type': 'question',
    'steps': [
      {'id': 's1', 'type': 'text', 'order': 1, 'content': 'Vyklad'},
      {
        'id': 's2',
        'type': 'question',
        'order': 2,
        'question': {
          'type': 'multiple_choice',
          'options': [
            {
              'id': 'opt_1',
              'text': 'Dva',
              'is_correct': true,
              'feedback': 'Vyborne',
              'go_to': 's4',
            },
            {'id': 'opt_2', 'text': 'Tri', 'is_correct': false},
          ],
          'show_answers': true,
        },
      },
      {'id': 's3', 'type': 'text', 'order': 3, 'content': 'Odbocka'},
      {'id': 's4', 'type': 'text', 'order': 4, 'content': 'Zaver'},
    ],
  });
}

Widget _wrap(
  ContentBlock block, {
  void Function({int earnedXp, double scoreKoef, String? mark})? onDone,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: BlockStepEngine(
          block: block,
          onBlockCompleted: onDone ??
              ({int earnedXp = 0, double scoreKoef = 1.0, String? mark}) {},
        ),
      ),
    ),
  );
}

/// Pick the wrong option, confirm, and tap the checkmark that continues past
/// the solution.
Future<void> _answerWrongAndContinue(WidgetTester tester) async {
  await tester.tap(find.text('Tri'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Zkontrolovat'));
  await tester.pumpAndSettle();

  // The solution screen is up, with the checkmark as the only way on.
  expect(find.text('Pozor na zavazi'), findsOneWidget);
  await tester.tap(find.byIcon(Icons.check));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('go_to back to an earlier step reopens the question',
      (tester) async {
    var completed = false;
    await tester.pumpWidget(_wrap(
      _block(wrongGoTo: 's1'),
      onDone: ({int earnedXp = 0, double scoreKoef = 1.0, String? mark}) =>
          completed = true,
    ));
    await tester.pumpAndSettle();

    await _answerWrongAndContinue(tester);

    // Back on the question, awaiting an answer: the verdict is gone and the
    // block has not been completed or skipped past.
    expect(find.text('Pozor na zavazi'), findsNothing);
    expect(completed, isFalse);

    // And the answer really is live again — the correct option now grades.
    await tester.tap(find.text('Dva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();
    expect(find.text('Vyborne'), findsOneWidget);
  });

  testWidgets('go_to pointing at the question itself reopens it too',
      (tester) async {
    await tester.pumpWidget(_wrap(_block(wrongGoTo: 's2')));
    await tester.pumpAndSettle();

    await _answerWrongAndContinue(tester);

    expect(find.text('Pozor na zavazi'), findsNothing);
    await tester.tap(find.text('Dva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();
    expect(find.text('Vyborne'), findsOneWidget);
  });

  testWidgets('a forward go_to keeps the answer it jumped away from',
      (tester) async {
    var earned = 0;
    await tester.pumpWidget(_wrap(
      _forwardJumpBlock(),
      onDone: ({int earnedXp = 0, double scoreKoef = 1.0, String? mark}) =>
          earned = earnedXp,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Dva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    // Jumping past s3/s4 ends the block. The XP counts the question as
    // answered correctly without hints (8, against 5 for anything else) plus
    // one per display step — so 11 is the proof that reopening is scoped to
    // backward jumps and did not wipe this answer on the way out.
    expect(earned, 11);
  });
}
