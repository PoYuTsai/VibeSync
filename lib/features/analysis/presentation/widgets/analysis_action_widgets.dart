import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Keeps the primary analyze action reachable while the user reviews a long
/// conversation preview.
///
/// The extended pill is deliberate: a circle works for a familiar icon, but
/// 「開始分析」is a decision and needs a readable label. The button floats over
/// the scroll viewport, so the user does not have to hunt for the action after
/// checking a long imported conversation.
class FloatingAnalysisActionButton extends StatelessWidget {
  static const buttonKey = ValueKey('floating-analysis-action');

  final VoidCallback? onPressed;

  const FloatingAnalysisActionButton({
    super.key,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.scale(
          alignment: Alignment.bottomRight,
          scale: 0.92 + (0.08 * value),
          child: child,
        ),
      ),
      child: Semantics(
        button: true,
        label: '使用目前對話開始分析',
        child: ExcludeSemantics(
          child: FilledButton.icon(
            key: buttonKey,
            onPressed: onPressed,
            icon: const Icon(Icons.auto_awesome_rounded, size: 19),
            label: Text(
              '開始分析',
              style: AppTypography.titleSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size(132, 52),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              backgroundColor: AppColors.ctaStart,
              foregroundColor: Colors.white,
              disabledBackgroundColor:
                  AppColors.ctaStart.withValues(alpha: 0.46),
              disabledForegroundColor: Colors.white.withValues(alpha: 0.72),
              elevation: 9,
              shadowColor: Colors.black.withValues(alpha: 0.38),
              shape: StadiumBorder(
                side: BorderSide(
                  color: Colors.white.withValues(alpha: 0.22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
