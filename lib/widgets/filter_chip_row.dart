import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// A horizontal scrollable row of filter chips
class FilterChipRow extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final Function(int) onSelected;

  /// Space around the chips, inside the scrolling area.
  final EdgeInsetsGeometry padding;

  /// Lines the first chip up with a phone's 16px page gutter while letting
  /// the row scroll edge to edge.
  static const EdgeInsets gutterPadding = EdgeInsets.symmetric(horizontal: 16);

  const FilterChipRow({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.padding = gutterPadding,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            _buildChip(i, labels[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(int index, String label) {
    final isSelected = index == selectedIndex;

    return GestureDetector(
      onTap: () => onSelected(index),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryDark : Colors.transparent,
          borderRadius: AppDecorations.radiusS,
          border: isSelected
              ? null
              : Border.all(
                  color: AppColors.primaryDark24,
                  width: 1,
                ),
        ),
        child: Center(
          child: Text(
            label,
            style: AppTextStyles.chipLabelNunito(
              color: isSelected ? Colors.white : AppColors.primaryDark,
            ),
          ),
        ),
      ),
    );
  }
}
