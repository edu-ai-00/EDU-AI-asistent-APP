import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';
import '../core/strings/app_strings.dart';
import '../widgets/page_header.dart';

/// Terms of Use page with placeholder text.
class TermsPage extends StatelessWidget {
  final VoidCallback? onBack;

  const TermsPage({super.key, this.onBack});

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
              title: AppStrings.termsTitle,
              onBack: onBack,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                AppStrings.termsLastUpdated,
                style: AppTextStyles.bodySmall(color: AppColors.primaryDark48),
              ),
            ),
            const SizedBox(height: 24),
            // Content
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSection(
                      AppStrings.termsSection1Title,
                      AppStrings.termsSection1Body,
                    ),
                    _buildSection(
                      AppStrings.termsSection2Title,
                      AppStrings.termsSection2Body,
                    ),
                    _buildSection(
                      AppStrings.termsSection3Title,
                      AppStrings.termsSection3Body,
                    ),
                    _buildSection(
                      AppStrings.termsSection4Title,
                      AppStrings.termsSection4Body,
                    ),
                    _buildSection(
                      AppStrings.termsSection5Title,
                      AppStrings.termsSection5Body,
                    ),
                    _buildSection(
                      AppStrings.termsSection6Title,
                      AppStrings.termsSection6Body,
                    ),
                    _buildSection(
                      AppStrings.termsSection7Title,
                      AppStrings.termsSection7Body,
                    ),
                    _buildSection(
                      AppStrings.termsSection8Title,
                      AppStrings.termsSection8Body,
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.subtitle(),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: AppTextStyles.body(
              color: AppColors.primaryDark.withValues(alpha: 0.72),
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
