import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/providers/navigation_providers.dart';

/// URL path for each main tab, indexed the way `MainScreen.pages` and
/// `navDestinations` are — the same index [mainTabIndexProvider] holds.
///
/// Before these existed the whole signed-in app lived on `/`: switching tabs
/// moved a provider and never the URL, so the browser had no history to walk
/// back through and its back button left the site outright (BR-7RNBZ9). They
/// double as shareable links into a section.
///
/// English slugs, matching the rest of `buildAppRouter` (`/course/:code`,
/// `/terms`, `/consent/...`).
const mainTabPaths = <String>[
  '/dash',
  '/chat',
  '/library',
  '/courses',
  '/news',
];

/// URL path for each page that opens *over* the shell rather than being a tab,
/// keyed by the [ShellIntent] that opens it.
///
/// Doplňky and the profile are imperative pushes, so they had no URL: opening
/// one left the address bar on the tab underneath, and neither could be linked
/// to (BR-N6B622). Their routes host the same shell as the tabs — see
/// `ShellEntry.shellIntent` — and [openShellPage] keeps the URL in step.
const shellPagePaths = <ShellIntent, String>{
  ShellIntent.openDoplnky: '/tools',
  ShellIntent.openProfile: '/profile',
};

/// The tab [path] selects, or null if it is not a tab route.
///
/// `/` answers 0: it is where the app boots and it shows the dashboard, so it
/// is an alias of `/dash` rather than a section of its own. Without that,
/// tapping "Přehled" on the launch screen would push a second history entry
/// for the screen already on display.
int? mainTabIndexForPath(String path) {
  if (path == '/') return 0;
  final index = mainTabPaths.indexOf(path);
  return index == -1 ? null : index;
}

/// Switch to a main tab *and* move the browser to its URL.
///
/// Use this wherever the user asks for a tab: the bottom bar, either sidebar,
/// a "show all" link. Code that only points the shell at the tab sitting
/// *underneath* a page it is about to push keeps writing [mainTabIndexProvider]
/// directly — the `/course|/pin` deep link and the PIN login's course hand-off
/// (BR-48B7DY) both do that, and rewriting the URL there would throw the deep
/// link away and pop the page they just pushed.
///
/// `go`, not `push`: every shell route renders the same page (see `ShellEntry`),
/// so the router updates the one route in place. The browser still records a
/// history entry, but `AuthWrapper` keeps its State — no re-authentication and
/// no loading spinner on a tab tap.
void goToMainTab(BuildContext context, WidgetRef ref, int index) {
  ref.read(mainTabIndexProvider.notifier).state = index;

  // Null in widget tests that pump a page under a bare MaterialApp, and on any
  // screen drawn outside the router.
  final router = GoRouter.maybeOf(context);
  if (router == null) return;

  // Already on a URL that means this tab — the call came *from* the URL
  // (browser back/forward, cold start on a tab route), so navigating again
  // would stack a duplicate entry.
  if (mainTabIndexForPath(router.state.uri.path) == index) return;

  router.go(mainTabPaths[index]);
}

/// A tap on `MainScreen`'s own navigation — the phone bottom bar or the
/// sidebar beside the tabs.
///
/// [goToMainTab], except for the "+" (Knihovna) when the library is already
/// the tab on display. Selecting it again changes nothing, so that tap used to
/// do nothing at all (BR-RRSCCK). "+" means "add a course", and on the library
/// that is the code entry: it opens "Máš kód kurzu?", the same dialog as the
/// page's "Zadat kód kurzu" button.
///
/// Only the shell's own chrome comes through here. Deep links and a pushed
/// page's sidebar call [goToMainTab] — a link to `/library` must land on the
/// library, not on a dialog.
void tapMainTab(BuildContext context, WidgetRef ref, int index) {
  if (index == kLibraryTabIndex &&
      ref.read(mainTabIndexProvider) == kLibraryTabIndex) {
    ref.read(libraryCodeDialogRequestProvider.notifier).state++;
    return;
  }
  goToMainTab(context, ref, index);
}

/// Open the page [intent] names (Doplňky, the profile) with the URL following
/// it — the [goToMainTab] of the pages in [shellPagePaths] (BR-N6B622).
///
/// [push] puts the page on screen and completes once it is closed. It stays
/// with the caller (`MainScreen`), which owns the callbacks those pages need.
///
/// When the URL does not name the page yet, only the URL moves: the route's
/// `ShellEntry` closes whatever detail page is up and parks [intent], and the
/// shell calls back in here with the URL in place — that second call pushes.
/// One way in for a tap, a direct link and browser back/forward alike, so the
/// page is never pushed without its URL or twice for one.
Future<void> openShellPage(
  BuildContext context,
  WidgetRef ref,
  ShellIntent intent,
  Future<void> Function() push,
) async {
  final path = shellPagePaths[intent]!;

  // Null in widget tests that pump a page under a bare MaterialApp — push and
  // be done.
  final router = GoRouter.maybeOf(context);
  if (router != null && router.state.uri.path != path) {
    router.go(path);
    return;
  }

  // The tab cannot change while the page is up: every way of switching tabs
  // moves the URL off [path] first, and that is checked below.
  final tabPath = mainTabPaths[ref.read(mainTabIndexProvider)];
  await push();
  if (router == null) return;

  // Closed because the URL moved (browser back/forward, a sidebar tab, the
  // other page's link) — the URL is already right.
  if (router.state.uri.path != path) return;

  // Closed to hand over to a page: a pushed page's sidebar pops to the shell
  // first and parks the intent after (see `DetailShell`). Opening that page
  // moves the URL from here; stopping on the tab in between would leave the
  // browser a stray history entry.
  if (context.mounted &&
      shellPagePaths.containsKey(ref.read(pendingShellIntentProvider))) {
    return;
  }

  // Closed in place — its back arrow, Android back, logging out. The tab is
  // what is showing again, so that is what the URL names.
  router.go(tabPath);
}
