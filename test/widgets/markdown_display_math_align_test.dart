import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/widgets/markdown_latex_widget.dart';

/// BR-H34ZVS — a display formula with a top-level `=` is split into parts so a
/// long equation can wrap on a narrow screen, and those parts went into a bare
/// `Wrap`, which shrink-wraps to its children and so sits on the left, while
/// every other display formula goes through `Center` and expands to the full
/// width. The admin preview centres all of them (KaTeX `.katex-display`), and
/// protected rule 12.6 asks the app to render content the same way.
void main() {
  const slot = Key('math-slot');

  /// The bounding box of every [Math] on screen — a split formula renders as
  /// several of them, and together they are the formula.
  Future<Rect> pumpFormula(
    WidgetTester tester,
    String markdown, {
    double width = 600,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          key: slot,
          width: width,
          child: MarkdownLatexWidget(content: markdown),
        ),
      ),
    ));

    final maths = find.byType(Math);
    expect(maths, findsWidgets);

    Rect? union;
    for (var i = 0; i < tester.widgetList(maths).length; i++) {
      final rect = tester.getRect(maths.at(i));
      union = union == null ? rect : union.expandToInclude(rect);
    }
    return union!;
  }

  /// The centre of the space the formula was given, which is what it should be
  /// centred on — the widget itself shrinks to its content.
  double centreOfSlot(WidgetTester tester) =>
      tester.getRect(find.byKey(slot)).center.dx;

  testWidgets('a display formula with a top-level = is centred',
      (tester) async {
    final rect = await pumpFormula(tester, r'$$a^2 + b^2 = c^2$$');

    expect(find.byType(Math), findsNWidgets(2), reason: 'split at the =');
    expect(rect.center.dx, moreOrLessEquals(centreOfSlot(tester), epsilon: 1));
  });

  testWidgets('a display formula without an = is centred', (tester) async {
    final rect = await pumpFormula(tester, r'$$\frac{a}{b}$$');

    expect(find.byType(Math), findsOneWidget);
    expect(rect.center.dx, moreOrLessEquals(centreOfSlot(tester), epsilon: 1));
  });

  testWidgets('an alignment environment is centred', (tester) async {
    final rect = await pumpFormula(
        tester, r'$$\begin{aligned} x &= 1 \\ y &= 2 \end{aligned}$$');

    expect(rect.center.dx, moreOrLessEquals(centreOfSlot(tester), epsilon: 1));
  });

  testWidgets('an equation too wide for the screen still breaks at the =',
      (tester) async {
    await pumpFormula(tester, r'$$a^2 + b^2 = c^2$$', width: 120);

    final left = tester.getRect(find.byType(Math).at(0));
    final right = tester.getRect(find.byType(Math).at(1));
    expect(right.top, greaterThanOrEqualTo(left.bottom),
        reason: 'the right-hand side moves to its own line');
  });
}
