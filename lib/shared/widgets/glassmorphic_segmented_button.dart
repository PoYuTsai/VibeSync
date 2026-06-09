// lib/shared/widgets/glassmorphic_segmented_button.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

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
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder, width: 1.5),
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
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color:
                                AppColors.selectedStart.withValues(alpha: 0.5),
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
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          segment.label,
                          style: AppTypography.bodyMedium.copyWith(
                            color: isSelected
                                ? Colors.white
                                : AppColors.unselectedText,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                        ),
                      ),
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
