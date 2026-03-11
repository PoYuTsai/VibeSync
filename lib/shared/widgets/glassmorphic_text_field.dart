// lib/shared/widgets/glassmorphic_text_field.dart
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
    // 改用實色背景，不依賴 BackdropFilter (更穩定)
    // 加入微妙的外發光效果 (果凍感)
    return Container(
      decoration: BoxDecoration(
        color: AppColors.glassWhite,
        borderRadius: BorderRadius.circular(16),  // 更圓潤
        border: Border.all(color: AppColors.glassBorder, width: 1.5),  // 更粗的白色邊框
        boxShadow: [
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.15),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
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
          // 覆蓋 theme 的深灰色 fillColor，讓 Container 背景色顯示
          filled: true,
          fillColor: Colors.transparent,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }
}
