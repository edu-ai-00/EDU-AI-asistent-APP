import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:eduai/core/providers/core_providers.dart';
import 'package:eduai/core/strings/app_strings.dart';
import 'package:eduai/pages/auth_page.dart';
import 'package:eduai/widgets/auth_hero_scaffold.dart';
import 'package:eduai/widgets/language_switcher.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BR-YR42DA: on an iPhone with the keyboard up, the e-mail form slid under the
// status bar — "Přihlásit se" ran into the clock, the back button was off the
// screen — and the language switcher stayed drawn on top of the white card,
// where its white labels disappeared.
//
// The sheet layout reads its insets inside an AnimatedBuilder that sits under
// the page's Scaffold, and Scaffold (resizeToAvoidBottomInset) strips the
// keyboard inset from its body's MediaQuery. So the keyboard always read as 0
// there: the BR-PXB3N3 clamp never engaged and the "hide the switcher while
// the keyboard is up" check never fired, while the body itself did shrink.
//
// Geometry of an iPhone 17 Pro: 402×874 pt, 62 pt status bar, 34 pt home
// indicator, ~336 pt keyboard.
// ─────────────────────────────────────────────────────────────────────────────

const Size _phone = Size(402, 874);
const double _statusBar = 62;
const double _homeIndicator = 34;
const double _keyboard = 336;

Future<void> _pumpPhone(
  WidgetTester tester, {
  required bool keyboardUp,
  required bool startInLoginMode,
}) async {
  const dpr = 3.0;
  tester.view.physicalSize = _phone * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = const FakeViewPadding(
    top: _statusBar * dpr,
    bottom: _homeIndicator * dpr,
  );
  tester.view.viewPadding = const FakeViewPadding(
    top: _statusBar * dpr,
    bottom: _homeIndicator * dpr,
  );
  if (keyboardUp) {
    tester.view.viewInsets = const FakeViewPadding(bottom: _keyboard * dpr);
  }
  addTearDown(tester.view.reset);

  // The test-only Ahem font is far wider than the real one, so labels overflow
  // their caps. Cosmetic and test-only — same suppression as the other
  // auth-page tests.
  final oldOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('overflowed')) return;
    oldOnError?.call(details);
  };
  addTearDown(() => FlutterError.onError = oldOnError);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        home: AuthPage(
          onEmailSubmit: (_) {},
          // Guest upgrade from the profile: e-mail form first, with a back
          // button — the screen in the report.
          startInLoginMode: startInLoginMode,
          onBack: () {},
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
}

/// Top edge of the white card: its scroll view fills it (no top SafeArea).
double _cardTop(WidgetTester tester) => tester
    .getRect(find.descendant(
      of: find.byKey(sheetKey),
      matching: find.byType(SingleChildScrollView),
    ))
    .top;

void main() {
  group('keyboard up', () {
    testWidgets('e-mail form stays below the status bar', (tester) async {
      await _pumpPhone(tester, keyboardUp: true, startInLoginMode: true);

      expect(_cardTop(tester), greaterThanOrEqualTo(_statusBar));
      expect(
        tester.getRect(find.byIcon(Icons.arrow_back)).top,
        greaterThanOrEqualTo(_statusBar),
      );
      // The submit button reads "Přihlásit se" too; the headline comes first.
      expect(
        tester.getRect(find.text(AppStrings.authFormHeadline).first).top,
        greaterThanOrEqualTo(_statusBar),
      );
    });

    testWidgets('language switcher is hidden on the e-mail form',
        (tester) async {
      await _pumpPhone(tester, keyboardUp: true, startInLoginMode: true);

      expect(find.byType(LanguageSwitcher), findsNothing);
    });

    testWidgets('language switcher is hidden on the code screen',
        (tester) async {
      // The shorter code-screen card is not clamped, but the shrunken body
      // still pushes its top up into the switcher's corner.
      await _pumpPhone(tester, keyboardUp: true, startInLoginMode: false);

      expect(find.byType(LanguageSwitcher), findsNothing);
      expect(_cardTop(tester), greaterThanOrEqualTo(_statusBar));
    });

    testWidgets('no artwork is drawn behind the status bar', (tester) async {
      await _pumpPhone(tester, keyboardUp: true, startInLoginMode: true);

      // With the card up to the status bar there is no band left for the
      // hero; it must shrink away rather than hang above the card.
      final hero = tester.getRect(find.byKey(compactSceneKey));
      expect(hero.height == 0 || hero.top >= _statusBar, isTrue,
          reason: 'hero at $hero overlaps the status bar');
    });
  });

  group('keyboard down', () {
    for (final loginMode in [true, false]) {
      testWidgets(
          'language switcher sits on the gradient above the card '
          '(${loginMode ? 'e-mail form' : 'code screen'})', (tester) async {
        await _pumpPhone(tester, keyboardUp: false, startInLoginMode: loginMode);

        final switcher = find.byType(LanguageSwitcher);
        expect(switcher, findsOneWidget);
        expect(tester.getRect(switcher).top, greaterThanOrEqualTo(_statusBar));
        expect(
          tester.getRect(switcher).bottom,
          lessThanOrEqualTo(_cardTop(tester)),
        );
      });
    }
  });
}
