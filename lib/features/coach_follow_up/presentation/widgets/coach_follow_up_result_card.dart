// Spec 5 C21 — CoachFollowUpResultCard 5-field widget.
//
// Renders a stored CoachFollowUpResult per design §1.3. Presentation only —
// no provider reads, no controller calls, no persistence side-effects. The
// section widget (C24) wires this card into the partner-detail screen.
//
// Visual style mirrors Spec 4's CoachActionCard (GlassmorphicContainer +
// labelled rows + highlighted suggestion bubble) for cross-coach consistency,
// but the field set is Spec 5's: 5 fields instead of 6, no learningLink, and
// boundaryReminder is required (carrying Spec 4's `avoid` semantics).

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../domain/entities/coach_follow_up_phase.dart';
import '../../domain/entities/coach_follow_up_result.dart';

class CoachFollowUpResultCard extends StatelessWidget {
  final CoachFollowUpResult result;

  const CoachFollowUpResultCard({
    super.key,
    required this.result,
  });

  /// Maps the stored stable .name key back to its 繁中 displayLabel. Falls
  /// back to the raw key if the local box pre-dates a future enum rename —
  /// graceful degradation prevents a blank header.
  String get _phaseLabel =>
      CoachFollowUpPhase.fromString(result.phase)?.displayLabel ?? result.phase;

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Phase header — small caption-style label so the bold headline
          // immediately below leads visually.
          Text(
            _phaseLabel,
            style: AppTypography.caption.copyWith(
              color: AppColors.ctaStart,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),

          // Headline — bold, NO label per design §1.3.
          Text(
            result.headline,
            style: AppTypography.titleMedium.copyWith(
              color: AppColors.glassTextPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),

          _LabeledRow(
            label: '我看到的重點',
            text: result.observation,
            textColor: AppColors.glassTextPrimary,
          ),
          const SizedBox(height: 6),

          _LabeledRow(
            label: '這次建議你做',
            text: result.task,
            textColor: AppColors.glassTextPrimary,
          ),

          if (result.suggestedLine != null) ...[
            const SizedBox(height: 10),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.ctaStart.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '可以這樣說',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.ctaStart,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    result.suggestedLine!,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.glassTextPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),
          _LabeledRow(
            label: '邊界提醒',
            text: result.boundaryReminder,
            textColor: AppColors.glassTextSecondary,
          ),
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
