import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/models/step_navigation.dart';
import 'package:eduai/widgets/block_step_engine.dart';

// Regression test for BR-6Y39JR: the AGAIN-retry behaviour must also work when
// the engine is driven by a BlockStepEngineController (the practice / quiz /
// exercise path, where QuizPage's bottom bar replaces the engine's own button).
//
// In that mode the engine hides its own "Zkusit znovu" button, so the retry
// affordance has to come from the controller: on a wrong go_to=AGAIN answer the
// controller must report isShowingSolution=true AND isAgainRetry=true, and
// retryAgain() must clear the pick and re-enable answering. A correct answer is
// a normal solution (isShowingSolution=true, isAgainRetry=false).

ContentBlock _againBlock() {
  return ContentBlock.fromJson({
    'block_id': 'TEST_AGAIN_CTRL',
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

/// Minimal harness mirroring QuizPage's bottom bar: it drives the engine
/// through the controller and picks the button the same way QuizPage does.
class _ControllerHarness extends StatefulWidget {
  const _ControllerHarness({required this.block});
  final ContentBlock block;

  @override
  State<_ControllerHarness> createState() => _ControllerHarnessState();
}

class _ControllerHarnessState extends State<_ControllerHarness> {
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
    final showing = _controller.isShowingSolution;
    final again = _controller.isAgainRetry;
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              BlockStepEngine(
                block: widget.block,
                exportMode: ExportMode.quizV2,
                controller: _controller,
                onBlockCompleted: ({int earnedXp = 0, double scoreKoef = 1.0, String? mark}) {},
              ),
              // Bottom-bar stand-in — same branch logic as QuizPage._buildBottomBar.
              if (showing)
                TextButton(
                  onPressed: again
                      ? _controller.retryAgain
                      : _controller.continueAfterSolution,
                  child: Text(again ? 'Zkusit znovu' : 'Pokracovat'),
                )
              else
                TextButton(
                  onPressed: _controller.confirm,
                  child: const Text('Zkontrolovat'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('controller-driven wrong AGAIN answer offers retry, not continue',
      (tester) async {
    await tester.pumpWidget(_ControllerHarness(block: _againBlock()));
    await tester.pumpAndSettle();

    // Pick the wrong option, then confirm via the controller-backed button.
    await tester.tap(find.text('Tri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();

    // Feedback shows; the bottom bar offers "Zkusit znovu" (retry), NOT
    // "Pokracovat" (continue) — the AGAIN state propagated through the controller.
    expect(find.text('Pozor na zavazi'), findsOneWidget);
    expect(find.text('Zkusit znovu'), findsOneWidget);
    expect(find.text('Pokracovat'), findsNothing);
  });

  testWidgets('controller retry clears the pick, then a correct answer shows solution',
      (tester) async {
    await tester.pumpWidget(_ControllerHarness(block: _againBlock()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Tri'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();

    // Retry via the controller-backed button clears the wrong pick + feedback.
    await tester.tap(find.text('Zkusit znovu'));
    await tester.pumpAndSettle();
    expect(find.text('Zkusit znovu'), findsNothing);
    expect(find.text('Pozor na zavazi'), findsNothing);
    // Back to the check state — button is "Zkontrolovat" again.
    expect(find.text('Zkontrolovat'), findsOneWidget);

    // Answering correctly is a normal solution, not a retry loop.
    await tester.tap(find.text('Dva'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zkontrolovat'));
    await tester.pumpAndSettle();
    expect(find.text('Vyborne'), findsOneWidget);
    expect(find.text('Zkusit znovu'), findsNothing);
    expect(find.text('Pokracovat'), findsOneWidget);
  });
}
