// BR-QF7RQ6 — the dashboard banners carried a hard `\n` in their description,
// placed where the line happened to break on the designer's screen. The copy
// column is narrower than the card (the mascot claims the right side), so on a
// phone the first half wrapped as well: "Zeptej se Cermatíka na / cokoli /
// kolem přijímaček", the middle line a single word.
//
// The copy now wraps to whatever width it is given, so every line but the last
// is full.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/widgets/promo_card.dart';

/// The dashboard banners' copy — `PromoCard` is built with these four and
/// nothing else.
const _promoDescriptionKeys = [
  'promoDescription',
  'promoDescriptionReward',
  'jpzDescription',
  'jpzCermatikDescription',
];

/// Wide enough that any of the four fits on one line even in the test font,
/// where every glyph is a full em.
const _wideCard = 1200.0;

void main() {
  test('no dashboard banner copy carries a hard line break', () {
    AppStrings.translationTables.forEach((locale, table) {
      for (final key in _promoDescriptionKeys) {
        expect(table[key], isNotNull, reason: '$key missing in $locale');
        expect(table[key], isNot(contains('\n')),
            reason: '$key in $locale breaks its own line — let the card wrap '
                'it instead (BR-QF7RQ6)');
      }
    });
  });

  testWidgets('the description uses the whole width it is given',
      (tester) async {
    final description = AppStrings.jpzCermatikDescription;

    // The default 800px test viewport would clamp the card and wrap the copy
    // on width alone, which is not what this test is about.
    tester.view.physicalSize = const Size(_wideCard + 200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: _wideCard,
              child: PromoCard(
                badge: AppStrings.jpzBadge,
                title: AppStrings.jpzTitle,
                description: description,
              ),
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);

    // One line's worth of `AppTextStyles.body` (15px, line-height 20). A hard
    // break would paint two lines however much room the card has.
    expect(tester.getSize(find.text(description)).height, lessThan(40));
  });
}
