// lib/shared/widgets/glassmorphic_container.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';

/// 毛玻璃效果容器 (改用實色背景)
class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final bool isSelected;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final Color? color;
  final Color? borderColor;
  final Color? selectedColor;
  final Color? selectedBorderColor;

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.isSelected = false,
    this.padding,
    this.width,
    this.height,
    this.color,
    this.borderColor,
    this.selectedColor,
    this.selectedBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    // 改用實色背景，不依賴 BackdropFilter
    // 加入微妙的外發光效果 (果凍感)
    return Container(
      width: width,
      height: height,
      padding:
          padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected
            ? selectedColor ?? AppColors.selectedStart.withValues(alpha: 0.3)
            : color ?? AppColors.glassWhite,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSelected
              ? selectedBorderColor ??
                  AppColors.selectedStart.withValues(alpha: 0.5)
              : borderColor ?? AppColors.glassBorder,
          width: 1.5,
        ),
        // 優化：只在選中時使用 boxShadow，減少滾動時的重繪負擔
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.selectedStart.withValues(alpha: 0.5),
                  blurRadius: 15,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
