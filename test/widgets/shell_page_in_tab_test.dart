import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:eduai/core/providers/navigation_providers.dart';
import 'package:eduai/core/util/shell_route.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BR-HVUEFS: a course opened from Přehled kept "Přehled" lit in the sidebar —
// on the course page and on every lesson above it — and the course page's
// "Zpět na všechny kurzy" popped back to the dashboard. Both read the tab
// underneath ([mainTabIndexProvider]), and only the deep links moved it to
// Kurzy (BR-48B7DY).
//
// [pushShellPageInTab] is the dashboard's way of opening a page that belongs
// to another tab. These tests pin its three rules: wide viewports switch,
// only once the page covers the shell, and phones never switch.
// ─────────────────────────────────────────────────────────────────────────────

const _openLabel = 'open';
const _pageLabel = 'course page';

late ProviderContainer _container;

Future<void> _pump(WidgetTester tester, {required Size size}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  _container = ProviderContainer();
  addTearDown(_container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () => pushShellPageInTab<void>(
                context,
                ref,
                tabIndex: kKurzyTabIndex,
                builder: (_) => const Scaffold(body: Text(_pageLabel)),
              ),
              child: const Text(_openLabel),
            ),
          ),
        ),
      ),
    ),
  );
}

int get _tab => _container.read(mainTabIndexProvider);

void main() {
  testWidgets('wide: the shell ends up on the page\'s tab', (tester) async {
    await _pump(tester, size: const Size(1440, 900));
    expect(_tab, 0);

    await tester.tap(find.text(_openLabel));
    await tester.pumpAndSettle();

    expect(find.text(_pageLabel), findsOneWidget);
    expect(_tab, kKurzyTabIndex);
  });

  testWidgets(
      'wide: the tab waits for the page to cover the shell, so the other tab '
      'never shows through the cross-fade', (tester) async {
    await _pump(tester, size: const Size(1440, 900));

    await tester.tap(find.text(_openLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(_pageLabel), findsOneWidget);
    expect(_tab, 0, reason: 'still fading in');

    await tester.pumpAndSettle();
    expect(_tab, kKurzyTabIndex);
  });

  testWidgets('wide: a page closed before it covered the shell leaves the tab',
      (tester) async {
    await _pump(tester, size: const Size(1440, 900));

    await tester.tap(find.text(_openLabel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();

    expect(find.text(_pageLabel), findsNothing);
    expect(_tab, 0);
  });

  testWidgets(
      'phone: the tab stays — the page has a bare back arrow and no sidebar, '
      'so back means where the user came from', (tester) async {
    await _pump(tester, size: const Size(390, 844));

    await tester.tap(find.text(_openLabel));
    await tester.pumpAndSettle();

    expect(find.text(_pageLabel), findsOneWidget);
    expect(_tab, 0);
  });
}
