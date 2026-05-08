// lib/shared/widgets/coach_action_card.dart
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../features/analysis/domain/coach/coach_action_card_data.dart';
import 'warm_theme_widgets.dart';

class CoachActionCard extends StatelessWidget {
  final CoachActionCardData data;
  final ValueChanged<String>? onLearningLinkTap;

  const CoachActionCard({
    super.key,
    required this.data,
    this.onLearningLinkTap,
  });

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '本回合怎麼接',
                style: AppTypography.caption.copyWith(
                  color: AppColors.ctaStart,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '· ${data.actionLabel}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.glassTextSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            data.whyNow,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _LabeledRow(
            label: '這次只做',
            text: data.task,
            textColor: AppColors.glassTextPrimary,
          ),
          const SizedBox(height: 6),
          _LabeledRow(
            label: '先不要',
            text: data.avoid,
            textColor: AppColors.glassTextSecondary,
          ),
          if (data.suggestedLine != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: AppColors.ctaStart.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '試試這樣回',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ctaStart,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    data.suggestedLine!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.glassTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (data.learningLink != null) ...[
            const SizedBox(height: 10),
            InkWell(
              key: const Key('coach_action_learning_cta'),
              onTap: () => onLearningLinkTap?.call(data.learningLink!),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '看 3 分鐘教學',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ctaStart,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.arrow_forward,
                    size: 14,
                    color: AppColors.ctaStart,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LabeledRow extends StatelessWidget {
  final String label;
  final String text;
  final Color textColor;

  const _LabeledRow({
    required this.label,
    required this.text,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label：',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.glassTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: AppTypography.bodySmall.copyWith(color: textColor),
          ),
        ),
      ],
    );
  }
}
