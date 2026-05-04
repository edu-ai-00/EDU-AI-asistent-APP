import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/core_providers.dart';
import '../core/strings/app_strings.dart';
import '../core/sync/sync_service.dart';
import '../core/theme/app_theme.dart';

/// Animated banner that slides down from the top to show sync status.
///
/// Self-manages visibility: slides in when syncing/error, slides out when idle.
/// Uses [AnimatedAlign] with [heightFactor] to collapse in layout when hidden,
/// so it occupies zero space in the parent Column.
class SyncStatusBanner extends ConsumerStatefulWidget {
  const SyncStatusBanner({super.key});

  @override
  ConsumerState<SyncStatusBanner> createState() => _SyncStatusBannerState();
}

class _SyncStatusBannerState extends ConsumerState<SyncStatusBanner> {
  bool _visible = false;
  _BannerContent _content = _BannerContent.syncing;
  Timer? _dismissTimer;
  SyncState? _prevState;

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _onStateChanged(SyncState state) {
    _dismissTimer?.cancel();

    switch (state) {
      case SyncState.syncing:
        setState(() {
          _content = _BannerContent.syncing;
          _visible = true;
        });

      case SyncState.error:
        setState(() {
          _content = _BannerContent.error;
          _visible = true;
        });

      case SyncState.idle:
        if (_prevState == SyncState.syncing) {
          setState(() {
            _content = _BannerContent.done;
            _visible = true;
          });
          _dismissTimer = Timer(const Duration(seconds: 2), () {
            if (mounted) setState(() => _visible = false);
          });
        } else {
          setState(() => _visible = false);
        }
    }

    _prevState = state;
  }

  void _onRetry() {
    ref.read(syncServiceProvider).forceSync();
  }

  @override
  Widget build(BuildContext context) {
    final syncState =
        ref.watch(syncStateProvider).valueOrNull ?? SyncState.idle;

    if (syncState != _prevState) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onStateChanged(syncState);
      });
    }

    final topPadding = MediaQuery.of(context).padding.top;

    return ClipRect(
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        heightFactor: _visible ? 1.0 : 0.0,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 300),
          opacity: _visible ? 1.0 : 0.0,
          child: GestureDetector(
            onTap: _content == _BannerContent.error ? _onRetry : null,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: topPadding + 8,
                bottom: 8,
              ),
              decoration: BoxDecoration(gradient: _content.gradient),
              child: Row(
                children: [
                  _content.buildLeading(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _content.label,
                      style: AppTextStyles.bodySmall(color: Colors.white),
                    ),
                  ),
                  if (_content == _BannerContent.error)
                    const Icon(Icons.refresh, color: Colors.white, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _BannerContent {
  syncing,
  done,
  error;

  String get label => switch (this) {
        syncing => AppStrings.syncSyncing,
        done => AppStrings.syncDone,
        error => AppStrings.syncFailed,
      };

  LinearGradient get gradient => switch (this) {
        syncing => LinearGradient(
            colors: [AppColors.primary, AppColors.gradientPurple],
          ),
        done => LinearGradient(
            colors: [AppColors.success, AppColors.success],
          ),
        error => LinearGradient(
            colors: [AppColors.error, AppColors.errorLight],
          ),
      };

  Widget buildLeading() => switch (this) {
        syncing => const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        done => const Icon(
            Icons.check_circle_outline, color: Colors.white, size: 18),
        error => const Icon(
            Icons.warning_amber_rounded, color: Colors.white, size: 18),
      };
}
