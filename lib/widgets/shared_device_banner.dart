import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers/core_providers.dart';
import '../core/theme/app_theme.dart';

/// Banner shown above the main app shell when the current session is in
/// shared-device mode. Reminds the user that idle logout is enforced and
/// exposes a one-tap logout for end-of-class teardown.
class SharedDeviceBanner extends ConsumerWidget {
  final VoidCallback onLogout;

  const SharedDeviceBanner({super.key, required this.onLogout});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionMetaProvider);
    if (!session.sharedDevice) {
      return SizedBox(height: MediaQuery.of(context).padding.top);
    }

    return Container(
      width: double.infinity,
      color: AppColors.warning,
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 8,
        8,
        8,
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock, size: 18, color: Color(0xFF6B4F00)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Sdílené zařízení — odhlášení po 15 min nečinnosti',
              style: AppTextStyles.bodySmall(color: const Color(0xFF6B4F00)),
            ),
          ),
          TextButton(
            onPressed: onLogout,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B4F00),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'Odhlásit',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
