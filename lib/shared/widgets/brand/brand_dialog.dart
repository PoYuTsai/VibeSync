import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class BrandAlertDialog extends StatelessWidget {
  const BrandAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.contentPadding,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final colorScheme = baseTheme.colorScheme.copyWith(
      surface: AppColors.glassWhite,
      onSurface: AppColors.glassTextPrimary,
      primary: AppColors.ctaStart,
      onPrimary: Colors.white,
      error: AppColors.error,
      onError: Colors.white,
      outline: AppColors.glassTextSecondary,
    );

    return Theme(
      data: baseTheme.copyWith(
        colorScheme: colorScheme,
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: AppColors.ctaStart),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.ctaStart,
            foregroundColor: Colors.white,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.72),
          labelStyle: AppTypography.bodySmall.copyWith(
            color: AppColors.glassTextSecondary,
          ),
          hintStyle: AppTypography.bodyMedium.copyWith(
            color: AppColors.glassTextHint.withValues(alpha: 0.72),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(
              color: AppColors.glassBorder.withValues(alpha: 0.92),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.ctaStart, width: 1.4),
          ),
          counterStyle: AppTypography.caption.copyWith(
            color: AppColors.glassTextSecondary,
          ),
        ),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: AppColors.ctaStart,
        ),
      ),
      child: AlertDialog(
        backgroundColor: AppColors.glassWhite,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titleTextStyle: AppTypography.titleLarge.copyWith(
          color: AppColors.glassTextPrimary,
          fontWeight: FontWeight.w800,
        ),
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: AppColors.glassTextPrimary,
          height: 1.42,
        ),
        contentPadding: contentPadding,
        title: title,
        content: content,
        actions: actions,
      ),
    );
  }
}
