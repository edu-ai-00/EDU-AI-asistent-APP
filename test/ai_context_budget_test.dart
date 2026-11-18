import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/core/utils/ai_context_sanitizer.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/pages/lesson_detail_page.dart';

/// BR-SX85ED — the task statement was cut at 400 characters before it reached
/// the mentor. The first block of "Nerovnice 1" (course "Rovnice a nerovnice")
/// runs to 1017 characters, so the cut landed mid-sentence at "a Bára již…"
/// and swallowed both the markdown table the question is about and the
/// question itself. The mentor duly answered that the assignment was missing
/// the amounts, and then that it had only been shown "useknutá verze textu".
///
/// 25 of that course's 128 blocks sit over the old budget, so roughly one task
/// in five reached the mentor truncated.
void main() {
  group('limitAiContext', () {
    test('text within budget is returned untouched', () {
      const text = 'Krátké zadání úlohy.';

      expect(limitAiContext(text, 400), text);
    });

    test('a cut falls on a line boundary, never mid table row', () {
      final table = [
        '| Týden | 1 | 2 | 3 |',
        '|:---:|:---:|:---:|:---:|',
        '| **Sára** | 260 | 320 | 380 |',
        '| **Bára** | 340 | 380 | 420 |',
      ].join('\n');

      // A budget that lands in the middle of the third row.
      final out = limitAiContext(table, 60);

      expect(out, endsWith('\n...'));
      // Every row that survived is whole.
      for (final line in out.split('\n').where((l) => l.startsWith('|'))) {
        expect(line, endsWith('|'));
      }
    });

    test('a single oversized line still gets cut', () {
      final out = limitAiContext('x' * 100, 20);

      expect(out, 'x' * 20 + '\n...');
    });
  });

  group('buildLessonChatContext keeps the whole statement', () {
    /// The reported block, verbatim from the stage course JSON: two text steps
    /// framing the question, the second carrying the table.
    ContentBlock inequalitiesBlock() => ContentBlock(
          blockId: 'A2-Nerovnice_01',
          type: BlockType.question,
          steps: const [
            BlockStep(
              stepId: 's1',
              type: StepType.text,
              content: StepContent(
                text: '## Co Tě v této lekci čeká?\n\n'
                    'V této lekci **se zaměříme na nerovnice**. Nebudeme se '
                    'zatím přímo zabývat algoritmem výpočtu, ale budeme řešit '
                    '**reálné situace** intuitivním způsobem. Na samotný '
                    'postup výpočtu se zaměříme v další lekci. \n\n'
                    'Začneme konkrétním příkladem:',
              ),
            ),
            BlockStep(
              stepId: 's2',
              type: StepType.text,
              content: StepContent(
                text: '### Příklad\n\n'
                    'Sestry Sára a Bára se obě rozhodly šetřit si peníze. '
                    'Když se takto rozhodly, měla již Sára našetřeno \$200\$ '
                    'Kč a Bára již \$300\$ Kč. Od tohoto momentu si Sára '
                    'každý týden ušetřila \$60\$ Kč a dala si je stranou k '
                    'již ušetřené částce, Bára si stejným způsobem dala každý '
                    'týden stranou \$40\$ Kč. Po kolika týdnech bude mít Sára '
                    'našetřeno více než Bára?\n\n'
                    '### Řešení\n\n'
                    'Situaci v prvních devíti týdnech popisuje tato tabulka:\n\n'
                    '| Týden | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |\n'
                    '|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|\n'
                    '| **Sára** | 260 | 320 | 380 | 440 | 500 | 560 | 620 | 680 | 740 |\n'
                    '| **Bára** | 340 | 380 | 420 | 460 | 500 | 540 | 580 | 620 | 660 |\n\n'
                    'Vyber **všechny týdny v tabulce**, ve kterých má Sára '
                    'našetřeno více než Bára:',
              ),
              hint: 'Podívej se do tabulky a **porovnej částky obou děvčat** '
                  'v každém týdnu.',
              help: 'Kdy jsou hodnoty **v řádku Sáry větší, než v řádku '
                  'Báry**?',
            ),
            BlockStep(
              stepId: 's3',
              type: StepType.question,
              content: StepContent(text: ''),
              evaluationConfig: EvaluationConfig(
                type: 'multiple_choice',
                options: [
                  EvaluationOption(id: 'opt_6', text: '6. týden'),
                  EvaluationOption(id: 'opt_7', text: '7. týden'),
                ],
              ),
            ),
          ],
        );

    test('the markdown table survives into the mentor context', () {
      final context = buildLessonChatContext(
        block: inequalitiesBlock(),
        courseName: 'Rovnice a nerovnice',
        lessonName: 'Nerovnice 1',
        liveStepIndex: 2,
      );

      // The sentence the old 400-char cut landed in, now whole.
      expect(context, contains('Bára již \$300\$ Kč'));
      expect(context, contains('Bára si stejným způsobem dala každý týden '
          'stranou \$40\$ Kč'));

      // Both table rows reach the mentor intact — the numbers the question is
      // actually about.
      expect(context,
          contains('| **Sára** | 260 | 320 | 380 | 440 | 500 | 560 | 620 | 680 | 740 |'));
      expect(context,
          contains('| **Bára** | 340 | 380 | 420 | 460 | 500 | 540 | 580 | 620 | 660 |'));

      // And so does the question that follows it.
      expect(context, contains('Vyber **všechny týdny v tabulce**'));

      // Nothing was elided.
      expect(context, isNot(contains('\n...')));
    });

    test('the assembled context stays inside the API 8000-char limit', () {
      // A statement far beyond any real block: the context must still be
      // short enough for the API to accept it (`max:8000`), because a 422
      // leaves the student with no answer at all.
      final huge = List.generate(2000, (i) => 'Řádek zadání číslo $i.').join('\n');
      final context = buildLessonChatContext(
        block: ContentBlock(
          blockId: 'b1',
          type: BlockType.question,
          steps: [
            BlockStep(
              stepId: 's1',
              type: StepType.text,
              content: StepContent(text: huge),
            ),
          ],
        ),
        courseName: 'Kurz',
        lessonName: 'Lekce',
        liveStepIndex: 0,
      );

      expect(context.length, lessThanOrEqualTo(kAiContextMaxChars));
      // Trimmed on the task statement, which keeps its own budget, so the
      // elision marker sits inside the message rather than at its end.
      expect(context, contains('Řádek zadání číslo 0.'));
      expect(context, contains('\n...\n'));
    });
  });
}
