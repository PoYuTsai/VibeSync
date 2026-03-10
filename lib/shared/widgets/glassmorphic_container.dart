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

  const GlassmorphicContainer({
    super.key,
    required this.child,
    this.borderRadius = 12,
    this.isSelected = false,
    this.padding,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    // 改用實色背景，不依賴 BackdropFilter
    return Container(
      width: width,
      height: height,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isSelected
            ? AppColors.selectedStart.withValues(alpha: 0.3)
            : AppColors.glassWhite,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isSelected
              ? AppColors.selectedStart.withValues(alpha: 0.5)
              : AppColors.glassBorder,
          width: 1,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.selectedStart.withValues(alpha: 0.4),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}
