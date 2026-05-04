import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/strings/app_strings.dart';
import '../core/theme/app_theme.dart';

class CustomBottomNav extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onItemTapped;

  const CustomBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onItemTapped,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final double bottomAreaHeight = bottomPadding > 0 ? bottomPadding : 16.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Navigation bar (transparent background)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              // Main navigation bar
              Container(
                height: 72,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: AppDecorations.radiusXL,
                  boxShadow: AppDecorations.shadowMedium,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildNavItem(0, 'assets/icons/home.svg', AppStrings.navPrehled),
                    _buildNavItem(1, 'assets/icons/chat.svg', AppStrings.navChat),
                    const SizedBox(width: 60), // Space for center button
                    _buildNavItem(3, 'assets/icons/kurzy.svg', AppStrings.navKurzy),
                    _buildNavItem(4, 'assets/icons/novinky.svg', AppStrings.navNovinky),
                  ],
                ),
              ),
              // Center floating button
              Positioned(
                top: -10,
                child: GestureDetector(
                  onTap: () => onItemTapped(2),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: AppDecorations.radiusPill,
                      boxShadow: AppDecorations.shadowStrong,
                    ),
                    child: Center(
                      child: SvgPicture.asset(
                        'assets/icons/add.svg',
                        width: 24,
                        height: 24,
                        colorFilter: ColorFilter.mode(
                          selectedIndex == 2
                              ? AppColors.primary
                              : AppColors.primaryDark,
                          BlendMode.srcIn,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Bottom spacing (transparent)
        SizedBox(height: bottomAreaHeight),
      ],
    );
  }

  Widget _buildNavItem(int index, String iconPath, String label) {
    final isSelected = selectedIndex == index;
    final color = isSelected ? AppColors.primary : AppColors.primaryDark;

    return GestureDetector(
      onTap: () => onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 70,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SvgPicture.asset(
              iconPath,
              width: 24,
              height: 24,
              colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: AppTextStyles.navLabel(
                color: color,
                weight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
