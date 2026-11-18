import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eduai/models/block_model.dart';
import 'package:eduai/widgets/lesson_image.dart';
import 'package:eduai/widgets/step_content_renderer.dart';

/// BR-TFCS5D — every picture in a lesson sits in the middle. The step's own
/// Obrázek field already did; pictures written into the text (markdown
/// `![](…)` or HTML `<img>`) hugged the left edge, and a step image set to
/// the admin's "Inline with Content" position was not drawn at all.
void main() {
  const url = 'https://cdn.example.test/obrazek.png';
  const cardWidth = 900.0;

  /// Parks a decoded picture under the key [LessonImage] resolves to, so it
  /// paints without touching the network.
  Future<void> primeImage(WidgetTester tester) async {
    late final ui.Image decoded;
    await tester.runAsync(() async {
      decoded = await createTestImage(width: 320, height: 160);
    });
    PaintingBinding.instance.imageCache.putIfAbsent(
      const LessonImageProvider(url),
      () => OneFrameImageStreamCompleter(
        SynchronousFuture<ImageInfo>(ImageInfo(image: decoded)),
      ),
    );
  }

  Future<void> pump(WidgetTester tester, BlockStep step) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: cardWidth,
                child: StepContentRenderer(step: step),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(); // let the primed completer deliver its frame
  }

  void expectCentred(WidgetTester tester) {
    final picture = tester.getRect(find.byType(Image));
    final card = tester.getRect(find.byType(StepContentRenderer));
    expect(picture.width, 320, reason: 'centring must not stretch the picture');
    expect(picture.center.dx, card.center.dx);
  }

  tearDown(() => PaintingBinding.instance.imageCache.clear());

  testWidgets('markdown picture in the step text is centred', (tester) async {
    await primeImage(tester);

    await pump(
      tester,
      const BlockStep(
        stepId: 's1',
        type: StepType.text,
        content: StepContent(text: 'Úvodní odstavec.\n\n![Schéma]($url)\n\nDalší text.'),
      ),
    );

    expectCentred(tester);
  });

  testWidgets('markdown picture sharing a paragraph with text is centred',
      (tester) async {
    await primeImage(tester);

    await pump(
      tester,
      const BlockStep(
        stepId: 's1',
        type: StepType.text,
        content: StepContent(text: 'Podívej se na **obrázek**:\n![Schéma]($url)'),
      ),
    );

    expectCentred(tester);
  });

  testWidgets('HTML <img> in the step text is centred', (tester) async {
    await primeImage(tester);

    await pump(
      tester,
      const BlockStep(
        stepId: 's1',
        type: StepType.text,
        content: StepContent(text: '<p>Úvodní odstavec.</p><p><img src="$url"></p>'),
      ),
    );

    expectCentred(tester);
  });

  testWidgets('step image with the inline position is drawn above the text',
      (tester) async {
    await primeImage(tester);

    await pump(
      tester,
      const BlockStep(
        stepId: 's1',
        type: StepType.text,
        content: StepContent(text: 'Text kroku'),
        image: StepImage(url: url),
        position: 'inline',
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expectCentred(tester);
    expect(
      tester.getRect(find.byType(Image)).bottom,
      lessThanOrEqualTo(tester.getRect(find.text('Text kroku')).top),
    );
  });

  testWidgets('step image with the below position stays below the text',
      (tester) async {
    await primeImage(tester);

    await pump(
      tester,
      const BlockStep(
        stepId: 's1',
        type: StepType.text,
        content: StepContent(text: 'Text kroku'),
        image: StepImage(url: url),
        position: 'below',
      ),
    );

    expect(
      tester.getRect(find.byType(Image)).top,
      greaterThanOrEqualTo(tester.getRect(find.text('Text kroku')).bottom),
    );
  });
}
