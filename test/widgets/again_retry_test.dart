import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/widgets/block_step_engine.dart';

// Regression test for BR-PW7WZD: a question block whose wrong options carry
// go_to=AGAIN must keep the wrong pick visible with its feedback and offer an
// explicit "Zkusit znovu" (try again) button — NOT silently reset to a blank,
// unanswered-looking state, and NOT advance/complete on a wrong answer.

ContentBlock _againBlock() {
  return ContentBlock.fromJson({
    'block_id': 'TEST_AGAIN',
    'type': 'question',
    'steps': [
      {'id': 's1', 'type': 'text', 'order': 1, 'content': 'Vyres rovnici'},
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
              'go_to': 'END',
            },
            {
              'id': 'opt_2',
              'text': 'Tri',
              'is_correct': false,
              'feedback': 'Pozor na zavazi',
              'go_to': 'AGAIN',
            },
          ],
          'show_answers': true,
        },
      },
    ],
  });
}

Widget _wrap(
  ContentBlock block, {
  VoidCallback? onWrong,
  VoidCallback? onDone,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: BlockStepEngine(
          block: block,
          onWrongAnswer: onWrong,
          onBlockCompleted: ({int earnedXp = 0, double scoreKoef = 1.0, String? mark}) =>
              onDone?.call(),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('wrong AGAIN answer shows feedback + "Zkusit znovu", does not advance',
      (tester) async {
    var wrongCalls = 0;
    var completed = false;
    await tester.pumpWidget(_wrap(
      _againBlock(),
      onWrong: () => wrongCalls++,
      onDone: () => completed = true,
    ));
    await tester.pumpAndSettle();

    // Pick the wrong option, then confirm.
    await tester.tap(find.text('Tri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();

    // Wrong-answer side effects: auto-bookmark fired, feedback shown, retry
    // button offered — and the block did NOT complete/advance.
    expect(wrongCalls, 1);
    expect(find.text('Pozor na zavazi'), findsOneWidget);
    expect(find.text('Zkusit znovu'), findsOneWidget);
    expect(completed, isFalse);
    // The correct option's text stays on screen (options are read-only now),
    // but no "continue" affordance exists — only retry.
    expect(find.text('Pokracovat'), findsNothing);
  });

  testWidgets('"Zkusit znovu" clears the pick and re-enables answering',
      (tester) async {
    await tester.pumpWidget(_wrap(_againBlock()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();

    // Retry resets to the awaiting state: the retry button is gone and the
    // wrong answer's feedback is cleared.
    await tester.tap(find.text('Zkusit znovu'));
    await tester.pumpAndSettle();
    expect(find.text('Zkusit znovu'), findsNothing);
    expect(find.text('Pozor na zavazi'), findsNothing);

    // Re-answering with the CORRECT option is a normal solution, not a retry
    // loop: its feedback shows and no "Zkusit znovu" button appears.
    await tester.tap(find.text('Dva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();
    expect(find.text('Vyborne'), findsOneWidget);
    expect(find.text('Zkusit znovu'), findsNothing);
  });
}
