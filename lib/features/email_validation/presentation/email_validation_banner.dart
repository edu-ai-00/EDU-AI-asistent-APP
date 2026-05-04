import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/strings/app_strings.dart';
import '../../../core/theme/app_theme.dart';
import 'email_verification_dialog.dart';

/// Banner shown at the top of MainScreen when user's email is not validated.
/// Shows different message for guest users (no email) vs registered users (unverified email).
/// Tapping it opens the verification dialog (if online) or shows a SnackBar (if offline).
class EmailValidationBanner extends ConsumerWidget {
  const EmailValidationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(activeUserStreamProvider);
    final isGuest = userAsync.valueOrNull?.email.isEmpty ?? true;

    return GestureDetector(
      onTap: () => _handleTap(context, ref),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.bannerGradient,
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              Icon(
                isGuest ? Icons.person_add_outlined : Icons.mail_outline,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isGuest
                      ? AppStrings.bannerGuestMessage
                      : AppStrings.bannerVerifyMessage,
                  style: AppTextStyles.bodySmall(color: Colors.white),
                ),
              ),
              const Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    // Check connectivity
    final connectivity = ref.read(connectivityServiceProvider);
    final isOnline = await connectivity.isOnline;

    if (!context.mounted) return;

    if (!isOnline) {
      // Show offline SnackBar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.bannerOfflineMessage,
            style: AppTextStyles.bodySmall(),
          ),
          backgroundColor: AppColors.primaryDark,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: AppDecorations.radiusS,
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
      return;
    }

    // Get current user email
    final user = await ref.read(appDatabaseProvider).getActiveUser();
    final email = user?.email ?? '';

    if (!context.mounted) return;

    // Show verification dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => EmailVerificationDialog(email: email),
    );
  }
}
