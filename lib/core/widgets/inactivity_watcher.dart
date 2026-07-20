import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/core_providers.dart';
import '../services/session_meta.dart';

/// Wraps the app and enforces shared-device idle logout.
///
/// Active only when [SessionMeta.sharedDevice] is true. Hooks pointer events
/// to refresh last-active, runs a periodic check + lifecycle resume check,
/// and invokes [onLogout] when the inactivity limit (or hard cap) is hit.
class InactivityWatcher extends ConsumerStatefulWidget {
  final Widget child;
  final Future<void> Function() onLogout;

  const InactivityWatcher({
    super.key,
    required this.child,
    required this.onLogout,
  });

  @override
  ConsumerState<InactivityWatcher> createState() => _InactivityWatcherState();
}

class _InactivityWatcherState extends ConsumerState<InactivityWatcher>
    with WidgetsBindingObserver {
  Timer? _checkTimer;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 5s cadence keeps the shared-device banner countdown honest: logout fires
    // within a few seconds of the visible timer reaching 00:00 (not up to 30s
    // later). The check itself is a couple of cheap timestamp comparisons.
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) => _check());
    // Run a check next frame in case we resumed from a long sleep before
    // build wired up the lifecycle observer.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    // Start work-time heartbeat tracking (BR-9SAH2R) — independent of the
    // shared-device idle logout; runs for all authenticated users.
    ref.read(workTimeTrackerProvider).start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkTimer?.cancel();
    ref.read(workTimeTrackerProvider).stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _check();
    }
  }

  Future<void> _check() async {
    if (_loggingOut) return;
    final session = ref.read(sessionMetaProvider);
    if (!session.sharedDevice) return;

    if (session.isInactivityExpired() || session.isHardCapExceeded()) {
      _loggingOut = true;
      try {
        await widget.onLogout();
      } finally {
        _loggingOut = false;
      }
    }
  }

  void _onPointer(PointerEvent _) {
    // Work-time activity is tracked for everyone.
    ref.read(workTimeTrackerProvider).markActive();

    // Idle-logout activity only matters for shared-device sessions.
    final session = ref.read(sessionMetaProvider);
    if (!session.sharedDevice) return;
    session.touchActivity();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointer,
      onPointerMove: _onPointer,
      onPointerUp: _onPointer,
      child: widget.child,
    );
  }
}
