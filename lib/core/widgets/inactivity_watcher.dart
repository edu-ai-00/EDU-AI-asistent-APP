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
    _checkTimer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    // Run a check next frame in case we resumed from a long sleep before
    // build wired up the lifecycle observer.
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final session = ref.read(sessionMetaProvider);
    if (state == AppLifecycleState.resumed) {
      _check();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      // Snapshot last-active so post-resume diff is honest.
      session.touchActivity();
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
