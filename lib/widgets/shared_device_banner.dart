import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/core_providers.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';

class SharedDeviceBanner extends ConsumerStatefulWidget {
  final VoidCallback onLogout;

  /// Called after the session is successfully converted to persistent
  /// ("this is my device"). Lets the parent rebuild so the banner — which
  /// reads the now-cleared shared_device flag — disappears.
  final VoidCallback? onConverted;

  const SharedDeviceBanner({
    super.key,
    required this.onLogout,
    this.onConverted,
  });

  @override
  ConsumerState<SharedDeviceBanner> createState() => _SharedDeviceBannerState();
}

class _SharedDeviceBannerState extends ConsumerState<SharedDeviceBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Repaint once a second so the countdown ticks. It re-reads lastActiveAt,
    // which InactivityWatcher pushes forward on every pointer event, so the
    // displayed time resets automatically whenever the user acts. Skip the
    // rebuild entirely when this isn't a shared-device session.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (ref.read(sessionMetaProvider).sharedDevice) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  static String _formatRemaining(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionMetaProvider);
    if (!session.sharedDevice) return const SizedBox.shrink();

    final remaining = session.inactivityRemaining() ?? Duration.zero;

    return Material(
      color: AppColors.warning,
      child: InkWell(
        onTap: () => _showLogoutDialog(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Text(
            AppStrings.sharedDeviceBannerCountdown(_formatRemaining(remaining)),
            style: AppTextStyles.bodySmall(color: const Color(0xFF6B4F00)),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.sharedDeviceDialogTitle),
        content: Text(AppStrings.sharedDeviceDialogMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppStrings.actionCancel),
          ),
          // "This is my device" — convert to a persistent session so the user
          // stays logged in and the auto-logout stops (BR-CAQQW2).
          TextButton(
            onPressed: () async {
              final ok = await ref
                  .read(apiClientProvider)
                  .convertSessionToPersistent();
              if (ctx.mounted) Navigator.of(ctx).pop();
              if (ok) {
                widget.onConverted?.call();
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(AppStrings.sharedDeviceConvertError)),
                );
              }
            },
            child: Text(AppStrings.sharedDeviceDialogKeepLoggedIn),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onLogout();
            },
            child: Text(AppStrings.profileLogout),
          ),
        ],
      ),
    );
  }
}
