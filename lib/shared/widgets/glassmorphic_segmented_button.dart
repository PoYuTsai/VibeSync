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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.glassBorder),
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
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.selectedStart.withValues(alpha: 0.4),
                            blurRadius: 8,
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
                        // 選中用白色，未選中用深色
                        color: isSelected ? Colors.white : AppColors.glassTextPrimary,
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
