import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/strings/app_strings.dart';
import '../widgets/page_header.dart';

/// Privacy and Security placeholder page.
class PrivacyPage extends StatelessWidget {
  final VoidCallback? onBack;

  const PrivacyPage({super.key, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            PageHeader(
              title: AppStrings.privacyTitle,
              onBack: onBack,
            ),
            // Content - Coming soon
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: AppColors.primaryDark16,
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('🔒', style: TextStyle(fontSize: 48)),
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        AppStrings.privacyComingSoon,
                        style: AppTextStyles.heading3(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        AppStrings.privacyComingSoonMessage,
                        style: AppTextStyles.body(
                          color: AppColors.primaryDark64,
                          height: 1.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
