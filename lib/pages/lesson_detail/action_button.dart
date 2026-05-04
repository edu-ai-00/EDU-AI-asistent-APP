import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

/// Small circular icon button used in the per-block action row
/// (bookmark / like / dislike / help).
class LessonActionButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final Color? activeColor;
  final VoidCallback onTap;

  const LessonActionButton({
    super.key,
    required this.icon,
    required this.isActive,
    this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: isActive ? (activeColor ?? AppColors.primaryDark) : AppColors.disabled,
          size: 24,
        ),
      ),
    );
  }
}
