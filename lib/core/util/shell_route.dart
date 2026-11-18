import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../layout/breakpoints.dart';
import '../providers/navigation_providers.dart';

/// Route for pages that redraw the shell chrome themselves (see `DetailShell`).
///
/// On a wide viewport the pushed page carries its own copy of the sidebar, so
/// the platform's slide transition drags the whole navigation across the
/// screen — it reads as the entire app jumping sideways rather than as the
/// content changing. A short cross-fade leaves the two identical sidebars
/// sitting still.
///
/// Phones keep the platform transition: there is no duplicated chrome there,
/// and the slide is the expected "going deeper" affordance.
Route<T> shellPageRoute<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  if (context.widthClass == WidthClass.compact) {
    return MaterialPageRoute<T>(builder: builder);
  }

  return _ShellFadeRoute<T>(builder: builder);
}

/// Push a [shellPageRoute] page that belongs to the tab [tabIndex], not to
/// the tab it was opened from — a course opened from Přehled.
///
/// On a wide viewport the page's sidebar, and every page pushed above it,
/// lights the tab underneath ([mainTabIndexProvider]), and its back link pops
/// to that tab. Opened from Přehled, a course kept "Přehled" lit through the
/// course and its lessons, and "Zpět na všechny kurzy" landed on the dashboard
/// (BR-HVUEFS) — what the deep links already fix by pointing the shell at
/// Kurzy (BR-48B7DY). The tab is written directly, not through `goToMainTab`:
/// a URL change makes `ShellEntry` close every pushed page, this one included.
///
/// Phones keep the tab they came from. The page has a bare back arrow and no
/// navigation there, so back means where the user came from.
///
/// The tab moves once the page has faded fully in. Moved first, the other tab
/// would show through the cross-fade; a page closed before then moves nothing.
Future<T?> pushShellPageInTab<T>(
  BuildContext context,
  WidgetRef ref, {
  required int tabIndex,
  required WidgetBuilder builder,
}) {
  final navigator = Navigator.of(context);
  if (context.widthClass == WidthClass.compact) {
    return navigator.push(shellPageRoute<T>(context, builder: builder));
  }

  // Read now: the page that called this may be gone by the time it fires.
  final tab = ref.read(mainTabIndexProvider.notifier);
  return navigator.push(_ShellFadeRoute<T>(
    builder: builder,
    onCovered: () => tab.state = tabIndex,
  ));
}

/// The wide-viewport [shellPageRoute].
class _ShellFadeRoute<T> extends PageRouteBuilder<T> {
  _ShellFadeRoute({required WidgetBuilder builder, this.onCovered})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (context, animation, secondaryAnimation, child) =>
              FadeTransition(opacity: animation, child: child),
          transitionDuration: const Duration(milliseconds: 120),
          reverseTransitionDuration: const Duration(milliseconds: 100),
        );

  /// Runs once the page has faded fully in over the shell.
  final VoidCallback? onCovered;

  // Off the push's own ticker, not [animation]: that is a proxy the hero
  // controller points at an always-complete animation for the push's first
  // frame. A ticker cut short by a pop never completes, so neither does this.
  @override
  TickerFuture didPush() {
    final pushed = super.didPush();
    final onCovered = this.onCovered;
    if (onCovered != null) pushed.then((_) => onCovered());
    return pushed;
  }
}
