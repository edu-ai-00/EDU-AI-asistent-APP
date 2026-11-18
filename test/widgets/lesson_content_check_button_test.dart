import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/core/theme/app_theme.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/pages/lesson_detail/action_button_row.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BR-6BPJ24 — a question block without steps (the older block format) answers
// in two taps: the first checks the answer, the second moves on. Its button was
// an unlabeled check that went green after the first tap, the same green as a
// finished block, so the student read "done" and had to discover the second
// tap. Step-based blocks (BlockStepEngine) label the first tap "Zkontrolovat"
// and keep the check white until the block is done; this row now does too.
// ─────────────────────────────────────────────────────────────────────────────

ContentBlock _question({bool completed = false}) => ContentBlock(
      blockId: 'B1',
      type: BlockType.question,
      isCompleted: completed,
      atomicQuestion: const AtomicQuestion(
        type: 'true_false',
        options: [
          EvaluationOption(id: 'a', text: 'Ano', isCorrect: true),
          EvaluationOption(id: 'b', text: 'Ne'),
        ],
      ),
      selectedOptionId: 'a',
    );

ContentBlock _display() => ContentBlock(
      blockId: 'B2',
      type: BlockType.display,
      content: 'Výklad',
    );

class _Taps {
  int marked = 0;
  int confirmed = 0;
}

Future<_Taps> _pump(
  WidgetTester tester, {
  required ContentBlock block,
  bool canConfirm = true,
  bool isAnswered = false,
}) async {
  final taps = _Taps();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: LessonContentActionButtonsRow(
          block: block,
          isCurrent: true,
          canConfirm: canConfirm,
          isAnswered: isAnswered,
          onBookmark: () {},
          onLike: () {},
          onDislike: () {},
          onShowHint: () {},
          onMarkAnswered: () => taps.marked++,
          onConfirm: () => taps.confirmed++,
        ),
      ),
    ),
  );
  return taps;
}

/// Background colour of the round check button.
Color? _checkColor(WidgetTester tester) {
  final circle = tester
      .widgetList<Container>(find.ancestor(
        of: find.byIcon(Icons.check),
        matching: find.byType(Container),
      ))
      .map((c) => c.decoration)
      .whereType<BoxDecoration>()
      .firstWhere((d) => d.shape == BoxShape.circle);
  return circle.color;
}

void main() {
  testWidgets('an answered question offers "Zkontrolovat" for the first tap',
      (tester) async {
    final taps = await _pump(tester, block: _question());

    expect(find.text(AppStrings.lessonCheckAnswer), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(find.text(AppStrings.lessonCheckAnswer));
    expect(taps.marked, 1);
    expect(taps.confirmed, 0);
  });

  testWidgets('a checked question shows a white check, not the finished green',
      (tester) async {
    final taps =
        await _pump(tester, block: _question(), isAnswered: true);

    expect(find.text(AppStrings.lessonCheckAnswer), findsNothing);
    expect(_checkColor(tester), isNot(AppColors.success));

    await tester.tap(find.byIcon(Icons.check));
    expect(taps.confirmed, 1);
    expect(taps.marked, 0);
  });

  testWidgets('a finished question keeps the green check', (tester) async {
    await _pump(tester,
        block: _question(completed: true), isAnswered: true);

    expect(find.text(AppStrings.lessonCheckAnswer), findsNothing);
    expect(_checkColor(tester), AppColors.success);
  });

  testWidgets('no answer picked yet: no label, the check stays disabled',
      (tester) async {
    final taps = await _pump(tester, block: _question(), canConfirm: false);

    expect(find.text(AppStrings.lessonCheckAnswer), findsNothing);
    expect(_checkColor(tester), isNot(AppColors.success));

    await tester.tap(find.byIcon(Icons.check));
    await tester.pump(const Duration(seconds: 5));
    expect(taps.marked, 0);
    expect(taps.confirmed, 0);
  });

  testWidgets('a display block confirms on a single tap, no label',
      (tester) async {
    final taps = await _pump(tester, block: _display());

    expect(find.text(AppStrings.lessonCheckAnswer), findsNothing);
    await tester.tap(find.byIcon(Icons.check));
    expect(taps.confirmed, 1);
    expect(taps.marked, 0);
  });
}
