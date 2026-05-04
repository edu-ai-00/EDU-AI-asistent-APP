import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Standard rounded container used to wrap each lesson block card.
class LessonCardContainer extends StatelessWidget {
  final List<Widget> children;

  const LessonCardContainer({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppDecorations.radiusXL,
        boxShadow: AppDecorations.shadowStrong,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}
