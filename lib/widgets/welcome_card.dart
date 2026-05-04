import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// A welcome card widget with gradient background and mascot illustration.
///
/// Features:
/// - Purple gradient background (top to bottom)
/// - Small title text and large description
/// - Mascot illustration on the right (overflowing)
class WelcomeCard extends StatelessWidget {
  /// Small title text (e.g., "Skiny")
  final String title;

  /// Large description text (e.g., "Dosahl jsi\nlvl Wizard!")
  final String description;

  /// Path to the mascot illustration
  final String? illustrationPath;

  /// Callback when card is tapped
  final VoidCallback? onTap;

  const WelcomeCard({
    super.key,
    required this.title,
    required this.description,
    this.illustrationPath,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 148,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Gradient background
            Container(
              width: double.infinity,
              height: 148,
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
              decoration: BoxDecoration(
                gradient: AppColors.authGradient,
                borderRadius: AppDecorations.radiusXL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    title,
                    style: AppTextStyles.statValue(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Description
                  Text(
                    description,
                    style: AppTextStyles.heading1(
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // Mascot illustration - positioned on right, clipped to card radius
            if (illustrationPath != null)
              Positioned(
                right: -2,
                bottom: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomRight: Radius.circular(24),
                  ),
                  child: Image.asset(
                    illustrationPath!,
                    width: 162,
                    height: 128,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
