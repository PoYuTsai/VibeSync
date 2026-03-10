// lib/shared/widgets/glassmorphic_text_field.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// 毛玻璃風格的輸入框
class GlassmorphicTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final bool isDense;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;

  const GlassmorphicTextField({
    super.key,
    this.controller,
    this.hintText,
    this.isDense = false,
    this.onSubmitted,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.glassWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: TextField(
            controller: controller,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.glassTextPrimary),
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextHint,
              ),
              isDense: isDense,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: isDense ? 12 : 14,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }
}
