// lib/shared/widgets/glassmorphic_segmented_button.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 毛玻璃風格的分段選擇按鈕 (改用實色背景)
class GlassmorphicSegmentedButton<T> extends StatelessWidget {
  final List<GlassSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  const GlassmorphicSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // 改用實色背景，不依賴 BackdropFilter
    // 加入微妙的外發光效果 (果凍感)
    // 移除外層 boxShadow 提升滾動效能
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(16),  // 更圓潤
        border: Border.all(color: AppColors.glassBorder, width: 1.5),  // 更粗的白色邊框
      ),
      child: Row(
        children: segments.map((segment) {
          final isSelected = segment.value == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(segment.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [
                            AppColors.selectedStart,
                            AppColors.selectedEnd,
                          ],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(14),  // 內部圓角
                  // 簡化為單層陰影，提升效能但保持發光效果
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.selectedStart.withValues(alpha: 0.5),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSelected) ...[
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      segment.label,
                      style: AppTypography.bodyMedium.copyWith(
                        // 選中用白色，未選中用深紫灰
                        color: isSelected ? Colors.white : AppColors.unselectedText,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class GlassSegment<T> {
  final T value;
  final String label;

  const GlassSegment({
    required this.value,
    required this.label,
  });
}
