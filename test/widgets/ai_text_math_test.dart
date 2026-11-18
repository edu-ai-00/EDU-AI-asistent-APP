import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/models/open_answer_feedback.dart';
import 'package:eduai/widgets/chat/chat_message_views.dart';
import 'package:eduai/widgets/markdown_latex_widget.dart';
import 'package:eduai/widgets/open_answer_feedback_card.dart';

/// BR-4ZFY6D — formulas in AI-written text printed as source.
///
/// The open-answer feedback card set the model's three parts as plain [Text],
/// so a formula the model copied from the question came out as `$x^2$`. And
/// models write maths in TeX's own `\(…\)` / `\[…\]` as often as in dollars,
/// which nothing read: markdown took the backslashes as escapes and printed
/// the bare brackets with the TeX inside.
///
/// Course content keeps dollars only — the admin preview (remark-math) does
/// not read brackets, and a lesson must look the way the author saw it there.
void main() {
  Widget host(Widget child) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      );

  /// Every formula on screen, each of which must have parsed — a failed one
  /// still builds a [Math] but shows its source in orange instead.
  List<Math> formulas(WidgetTester tester) {
    final found = tester.widgetList<Math>(find.byType(Math)).toList();
    for (final math in found) {
      expect(math.parseError, isNull, reason: 'formula failed to parse');
    }
    return found;
  }

  bool showsSource(String source) => find
      .textContaining(source, findRichText: true)
      .evaluate()
      .isNotEmpty;

  group('open-answer feedback card', () {
    testWidgets('renders dollar formulas in every AI section', (tester) async {
      await tester.pumpWidget(host(const OpenAnswerFeedbackCard(
        feedback: FormativeFeedback(
          strengths: r'Správně jsi dosadil do $S = a \cdot b$.',
          improvements: r'Zkontroluj jednotky u $a^2$.',
          nextStep: r'Spočítej ještě $$\frac{1}{2} a v$$',
        ),
        retryPending: true,
      )));

      expect(formulas(tester), hasLength(3));
      expect(showsSource(r'$S'), isFalse);
      expect(showsSource(r'$a^2$'), isFalse);
    });

    testWidgets('renders bracket formulas', (tester) async {
      await tester.pumpWidget(host(const OpenAnswerFeedbackCard(
        feedback: FormativeFeedback(
          strengths: r'Vztah \(v = \frac{s}{t}\) používáš dobře.',
          // No top-level `=`: a displayed formula is split there into one
          // Math widget per side, which would muddle the count below.
          improvements: r'Chybí převod: \[ 36\,\text{km/h} \div 3{,}6 \]',
          nextStep: 'Zkus to znovu.',
        ),
      )));

      expect(formulas(tester), hasLength(2));
      expect(showsSource(r'\frac'), isFalse);
      expect(showsSource(r'\text'), isFalse);
    });

    testWidgets('renders formulas in flat legacy feedback', (tester) async {
      await tester.pumpWidget(
        host(OpenAnswerFeedbackCard.flat(r'Výsledek \(x = 2\) sedí.')!),
      );

      expect(formulas(tester), hasLength(1));
    });

    testWidgets('plain prose stays a plain Text', (tester) async {
      await tester.pumpWidget(host(const OpenAnswerFeedbackCard(
        feedback: FormativeFeedback(
          strengths: 'Chápeš, na co se ptáme.',
          improvements: 'Doplň jeden příklad.',
          nextStep: 'Zkus to znovu.',
        ),
      )));

      expect(find.text('Chápeš, na co se ptáme.'), findsOneWidget);
      expect(find.byType(Math), findsNothing);
    });
  });

  group('chat bubble', () {
    testWidgets('renders bracket formulas from the mentor', (tester) async {
      await tester.pumpWidget(host(const ChatBubble(
        content: 'Pro obsah čtverce platí \\(S = a^2\\).\n'
            '\n'
            '\\[\n'
            '\\sqrt{16} = 4\n'
            '\\]',
        isUser: false,
        avatarEmoji: '🤖',
      )));

      expect(formulas(tester), isNotEmpty);
      expect(showsSource(r'\sqrt'), isFalse);
      expect(showsSource('(S = a^2)'), isFalse);
    });

    testWidgets('dollar formulas still render', (tester) async {
      await tester.pumpWidget(host(const ChatBubble(
        content: r'Platí $a^2 + b^2 = c^2$.',
        isUser: false,
        avatarEmoji: '🤖',
      )));

      expect(formulas(tester), hasLength(1));
    });

    testWidgets('leaves code alone', (tester) async {
      await tester.pumpWidget(host(const ChatBubble(
        content: r'Regulární výraz `\(\d+\)` najde číslo v závorce.',
        isUser: false,
        avatarEmoji: '🤖',
      )));

      expect(find.byType(Math), findsNothing);
      expect(showsSource(r'\(\d+\)'), isTrue);
    });
  });

  testWidgets('course content does not read brackets, like the admin preview',
      (tester) async {
    await tester.pumpWidget(host(const MarkdownLatexWidget(
      content: r'Závorka \(x\) zůstává, $y$ se vykreslí.',
    )));

    expect(formulas(tester), hasLength(1));
  });
}
