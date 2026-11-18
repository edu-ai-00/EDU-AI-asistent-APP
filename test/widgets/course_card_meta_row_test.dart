// BR-NF887W: on a phone the Knihovna list card puts the meta line
// (lessons · duration · version) and the Stáhnout / Aktualizovat button in one
// Row with a Spacer between them. Nothing in that Row could shrink, so on a
// narrow card the Row overflowed and — Flex does not clip — the button was
// painted past the card's right edge, partly off-screen.
//
// The button now stays pinned to the card's end at its full size.
//
// BR-5DRQ8T: the first fix let the meta run underneath the button, clipped at
// its leading edge — "3 hod 40 min" read "3 hod 40 mi" and the version was
// gone. The meta now wraps onto further lines beside the button instead, so
// every piece stays whole and readable.
//
//   flutter test test/widgets/course_card_meta_row_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/widgets/course_card_meta_row.dart';

const _actionKey = Key('action');

const _lessons = '12 lekcí';
const _duration = '3 hod 40 min';
const _version = 'v12';

Widget _item(IconData icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 13))),
      ],
    );

/// Same pieces as the real card: lesson count, duration, version.
List<Widget> _meta() => [
      _item(Icons.copy_rounded, _lessons),
      _item(Icons.access_time, _duration),
      const Text(_version, style: TextStyle(fontSize: 13)),
    ];

/// Stand-in for the Aktualizovat chip — a fixed natural size.
Widget _action() => Container(
      key: _actionKey,
      width: 120,
      height: 34,
      color: Colors.orange,
    );

Future<void> _pump(WidgetTester tester, double cardWidth) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: cardWidth,
          // The card body is a start-aligned Column, same as on the page.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CourseCardMetaRow(meta: _meta(), action: _action()),
            ],
          ),
        ),
      ),
    ),
  ));
}

/// Every meta label sits inside the row, left of the button — nothing is
/// hidden under it or cut at the card's edge.
void _expectMetaReadable(WidgetTester tester) {
  final row = tester.getRect(find.byType(CourseCardMetaRow));
  final action = tester.getRect(find.byKey(_actionKey));

  for (final label in [_lessons, _duration, _version]) {
    final rect = tester.getRect(find.text(label));
    expect(rect.left, greaterThanOrEqualTo(row.left), reason: label);
    expect(rect.right, lessThanOrEqualTo(action.left), reason: label);
    expect(rect.top, greaterThanOrEqualTo(row.top), reason: label);
    expect(rect.bottom, lessThanOrEqualTo(row.bottom), reason: label);
  }
}

void main() {
  // 360dp phone minus the list's 16px gutters and the card's 16px padding.
  const narrowCard = 296.0;

  testWidgets('a narrow card keeps the button whole at its right edge',
      (tester) async {
    await _pump(tester, narrowCard);

    // The old Row reported "A RenderFlex overflowed" here.
    expect(tester.takeException(), isNull);

    final row = tester.getRect(find.byType(CourseCardMetaRow));
    final action = tester.getRect(find.byKey(_actionKey));

    expect(row.width, narrowCard);
    // Pinned to the card's end, not pushed past it.
    expect(action.right, row.right);
    expect(action.size, const Size(120, 34));
  });

  testWidgets('a narrow card wraps the meta beside the button, not under it',
      (tester) async {
    await _pump(tester, narrowCard);

    expect(tester.takeException(), isNull);
    _expectMetaReadable(tester);

    // It did not fit on one line, so it wrapped — the version moved down.
    expect(
      tester.getRect(find.text(_version)).top,
      greaterThan(tester.getRect(find.text(_lessons)).top),
    );
  });

  testWidgets('a very narrow card still shows every piece', (tester) async {
    // Narrower than the duration piece alone: its label wraps in place.
    await _pump(tester, 220);

    expect(tester.takeException(), isNull);
    _expectMetaReadable(tester);
  });

  testWidgets('a wide card keeps meta and button on one line', (tester) async {
    await _pump(tester, 600);

    expect(tester.takeException(), isNull);
    _expectMetaReadable(tester);

    final row = tester.getRect(find.byType(CourseCardMetaRow));
    final action = tester.getRect(find.byKey(_actionKey));
    expect(action.right, row.right);

    final lessonsTop = tester.getRect(find.text(_lessons)).top;
    expect(tester.getRect(find.text(_duration)).top, lessonsTop);
    expect(tester.getRect(find.text(_version)).top,
        moreOrLessEquals(lessonsTop, epsilon: 2));
  });
}
