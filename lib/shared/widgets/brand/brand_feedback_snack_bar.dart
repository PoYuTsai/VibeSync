import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

SnackBar buildBrandFeedbackSnackBar({
  required String title,
  String? detail,
  IconData icon = Icons.check_circle_rounded,
  Color accentColor = AppColors.ctaStart,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 5),
}) {
  final hasAction = actionLabel != null && onAction != null;

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    backgroundColor: Colors.white.withValues(alpha: 0.96),
    elevation: 0,
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    duration: duration,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: accentColor.withValues(alpha: 0.24)),
    ),
    content: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accentColor, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              if (detail != null && detail.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  detail,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.glassTextSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
    action: hasAction
        ? SnackBarAction(
            label: actionLabel,
            textColor: AppColors.ctaEnd,
            onPressed: onAction,
          )
        : null,
  );
}

void showBrandFeedbackSnackBar(
  BuildContext context, {
  required String title,
  String? detail,
  IconData icon = Icons.check_circle_rounded,
  Color accentColor = AppColors.ctaStart,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 5),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      buildBrandFeedbackSnackBar(
        title: title,
        detail: detail,
        icon: icon,
        accentColor: accentColor,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                messenger.hideCurrentSnackBar();
                onAction();
              },
        duration: duration,
      ),
    );
}
