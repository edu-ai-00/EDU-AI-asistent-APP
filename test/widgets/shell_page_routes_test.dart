import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:eduai/core/providers/navigation_providers.dart';
import 'package:eduai/routing/shell_entry.dart';
import 'package:eduai/routing/tab_routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// BR-N6B622: the tabs got their own URLs in BR-7RNBZ9 (/dash, /chat, …), but
// Doplňky and the profile are pages pushed over the shell, not tabs — opening
// either left the address bar on the tab underneath, and /tools or /profile
// typed in hit the router's error page.
//
// Both now have a route that hosts the same shell as the tabs. ShellEntry
// closes whatever detail page is up and parks the page's ShellIntent; the
// shell (MainScreen) pushes the page once the URL names it, and puts the URL
// back on the tab when the page is closed in place.
//
// The router here is a cut-down buildAppRouter: same shared page key, real
// ShellEntry, but a stand-in for MainScreen (see [_FakeMainScreen]) because
// the real one needs a signed-in AuthWrapper — see tab_routes_test.dart for
// why that cannot be pumped.
// ─────────────────────────────────────────────────────────────────────────────

/// Mirrors the parts of `MainScreen` this feature runs through: the intent
/// slot drained on mount and on change, and the two pages opened through
/// [openShellPage].
class _FakeMainScreen extends ConsumerStatefulWidget {
  const _FakeMainScreen();

  @override
  ConsumerState<_FakeMainScreen> createState() => _FakeMainScreenState();
}

class _FakeMainScreenState extends ConsumerState<_FakeMainScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consume());
  }

  void _consume() {
    if (!mounted) return;
    switch (takePendingShellIntent(ref)) {
      case ShellIntent.openDoplnky:
        openDoplnky();
      case ShellIntent.openProfile:
        openProfile();
      case _:
        return;
    }
  }

  void openDoplnky() =>
      openShellPage(context, ref, ShellIntent.openDoplnky, _pushDoplnky);

  void openProfile() =>
      openShellPage(context, ref, ShellIntent.openProfile, _pushProfile);

  Future<void> _pushDoplnky() =>
      Navigator.of(context).push(_page('tools page', const []));

  Future<void> _pushProfile() => Navigator.of(context).push(
        _page('profile page', [
          // ProfilePage's own Doplňky row.
          ElevatedButton(
            onPressed: openDoplnky,
            child: const Text('profile → Doplňky'),
          ),
        ]),
      );

  Route<void> _page(String label, List<Widget> actions) => MaterialPageRoute(
        builder: (_) => Scaffold(body: Column(children: [Text(label), ...actions])),
      );

  @override
  Widget build(BuildContext context) {
    ref.listen<ShellIntent?>(pendingShellIntentProvider, (_, intent) {
      if (intent == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) => _consume());
    });

    return Scaffold(
      body: Column(
        children: [
          Text('tab ${ref.watch(mainTabIndexProvider)}'),
          ElevatedButton(
            onPressed: openDoplnky,
            child: const Text('open Doplňky'),
          ),
          ElevatedButton(
            onPressed: openProfile,
            child: const Text('open profile'),
          ),
        ],
      ),
    );
  }
}

GoRouter _buildRouter(String initialLocation) {
  const key = ValueKey('app-shell');
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      for (var i = 0; i < mainTabPaths.length; i++)
        GoRoute(
          path: mainTabPaths[i],
          pageBuilder: (context, state) => NoTransitionPage(
            key: key,
            child: ShellEntry(tabIndex: i, child: const _FakeMainScreen()),
          ),
        ),
      for (final entry in shellPagePaths.entries)
        GoRoute(
          path: entry.value,
          pageBuilder: (context, state) => NoTransitionPage(
            key: key,
            child: ShellEntry(
              shellIntent: entry.key,
              child: const _FakeMainScreen(),
            ),
          ),
        ),
    ],
  );
}

void main() {
  late ProviderContainer container;
  late GoRouter router;

  /// Every location the router reported, in order — what the browser would
  /// have recorded as history entries.
  late List<String> visited;

  String path() => router.state.uri.path;

  Future<void> pumpApp(WidgetTester tester, {String at = '/dash'}) async {
    container = ProviderContainer();
    addTearDown(container.dispose);
    router = _buildRouter(at);
    addTearDown(router.dispose);

    visited = [];
    router.routeInformationProvider.addListener(
      () => visited.add(router.routeInformationProvider.value.uri.path),
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  NavigatorState navigator(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  test('Doplňky and the profile have the paths the client asked for', () {
    expect(shellPagePaths[ShellIntent.openDoplnky], '/tools');
    expect(shellPagePaths[ShellIntent.openProfile], '/profile');
  });

  test('neither path is mistaken for a tab', () {
    for (final path in shellPagePaths.values) {
      expect(mainTabIndexForPath(path), isNull, reason: path);
    }
  });

  testWidgets('opening Doplňky moves the URL to /tools', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('open Doplňky'));
    await tester.pumpAndSettle();

    expect(find.text('tools page'), findsOneWidget);
    expect(path(), '/tools');
  });

  testWidgets('opening the profile moves the URL to /profile', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.text('open profile'));
    await tester.pumpAndSettle();

    expect(find.text('profile page'), findsOneWidget);
    expect(path(), '/profile');
  });

  testWidgets('a direct link opens the page over the dashboard',
      (tester) async {
    // Cold start on /profile — a shared link, or a reload while the profile
    // was open. The intent waits in its slot until the shell has mounted.
    await pumpApp(tester, at: '/profile');

    expect(find.text('profile page'), findsOneWidget);
    expect(path(), '/profile');
    expect(container.read(mainTabIndexProvider), 0);
  });

  testWidgets('closing the page in place puts the URL back on the tab',
      (tester) async {
    // Its back arrow, Android back: the page goes, the address bar must not
    // keep naming it.
    await pumpApp(tester, at: '/chat');
    await tester.tap(find.text('open Doplňky'));
    await tester.pumpAndSettle();

    navigator(tester).pop();
    await tester.pumpAndSettle();

    expect(find.text('tools page'), findsNothing);
    expect(path(), '/chat');
    expect(container.read(mainTabIndexProvider), 1);
  });

  testWidgets('browser back closes the page and leaves the URL alone',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('open Doplňky'));
    await tester.pumpAndSettle();

    // What a popstate looks like to the app: the URL changes underneath it.
    router.go('/dash');
    await tester.pumpAndSettle();

    expect(find.text('tools page'), findsNothing);
    expect(path(), '/dash');

    // And forward brings it back.
    router.go('/tools');
    await tester.pumpAndSettle();

    expect(find.text('tools page'), findsOneWidget);
  });

  testWidgets('the URL is opened only once, not once per hop',
      (tester) async {
    await pumpApp(tester);
    visited.clear();

    await tester.tap(find.text('open profile'));
    await tester.pumpAndSettle();

    expect(visited, ['/profile']);
    expect(find.text('profile page'), findsOneWidget);
  });

  testWidgets('Doplňky from the profile replaces it', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('open profile'));
    await tester.pumpAndSettle();
    visited.clear();

    await tester.tap(find.text('profile → Doplňky'));
    await tester.pumpAndSettle();

    expect(find.text('tools page'), findsOneWidget);
    expect(find.text('profile page'), findsNothing);
    expect(path(), '/tools');
    // No stop on the tab in between, which a closed profile would otherwise
    // have sent the URL to.
    expect(visited, ['/tools']);
  });

  testWidgets('a pushed sidebar handing over to the other page skips the tab',
      (tester) async {
    // DetailShell's sidebar pops to the shell first and then parks the
    // intent. The page that pop closes must not drag the URL back to the
    // tab — the browser would gain a stray /dash between the two pages.
    await pumpApp(tester);
    await tester.tap(find.text('open Doplňky'));
    await tester.pumpAndSettle();
    visited.clear();

    navigator(tester).popUntil((route) => route.isFirst);
    container.read(pendingShellIntentProvider.notifier).state =
        ShellIntent.openProfile;
    await tester.pumpAndSettle();

    expect(find.text('profile page'), findsOneWidget);
    expect(find.text('tools page'), findsNothing);
    expect(visited, ['/profile']);
  });

  testWidgets('a pushed sidebar reopening the same page keeps its URL',
      (tester) async {
    // The avatar editor sits on top of the profile, and its sidebar's
    // account block asks for the profile again.
    await pumpApp(tester);
    await tester.tap(find.text('open profile'));
    await tester.pumpAndSettle();
    navigator(tester).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('avatar editor')),
      ),
    );
    await tester.pumpAndSettle();
    visited.clear();

    navigator(tester).popUntil((route) => route.isFirst);
    container.read(pendingShellIntentProvider.notifier).state =
        ShellIntent.openProfile;
    await tester.pumpAndSettle();

    expect(find.text('profile page'), findsOneWidget);
    expect(find.text('avatar editor'), findsNothing);
    expect(path(), '/profile');
    expect(visited, isEmpty);
  });

  testWidgets('with no router above, it just pushes the page', (tester) async {
    // Widget tests that pump a page under a bare MaterialApp, and any screen
    // drawn outside the router.
    container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: _FakeMainScreen()),
      ),
    );

    await tester.tap(find.text('open Doplňky'));
    await tester.pumpAndSettle();
    expect(find.text('tools page'), findsOneWidget);

    navigator(tester).pop();
    await tester.pumpAndSettle();
    expect(find.text('tools page'), findsNothing);
  });
}
