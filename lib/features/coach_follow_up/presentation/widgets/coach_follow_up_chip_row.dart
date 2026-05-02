// Spec 5 C22 — phase chip row + AI hint + 額度 caption.
//
// Pure presentation widget. Renders 3 phase chips (always in
// CoachFollowUpPhase.values order), an optional AI hint line below them, and
// a fixed quota caption. Telemetry is the parent's responsibility — this
// widget surfaces taps via onPhaseSelected and that's it.
//
// Selection priority for visual highlight:
//   1. selectedPhase (user-explicit choice)
//   2. hintedPhase  (C18 resolver suggestion — visual nudge only)
//   3. nothing highlighted

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/coach_follow_up_phase.dart';

class CoachFollowUpChipRow extends StatelessWidget {
  final CoachFollowUpPhase? selectedPhase;
  final CoachFollowUpPhase? hintedPhase;
  final String? hintText;
  final bool isLoading;
  final ValueChanged<CoachFollowUpPhase> onPhaseSelected;

  const CoachFollowUpChipRow({
    super.key,
    this.selectedPhase,
    this.hintedPhase,
    this.hintText,
    this.isLoading = false,
    required this.onPhaseSelected,
  });

  bool _isHighlighted(CoachFollowUpPhase phase) {
    if (selectedPhase != null) return selectedPhase == phase;
    return hintedPhase == phase;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: CoachFollowUpPhase.values.map((phase) {
            return ChoiceChip(
              label: Text(phase.displayLabel),
              selected: _isHighlighted(phase),
              // showCheckmark: false avoids the dark-bg ghost-checkmark
              // artifact that bit ProfileChipSection (memory ref).
              showCheckmark: false,
              onSelected:
                  isLoading ? null : (_) => onPhaseSelected(phase),
            );
          }).toList(growable: false),
        ),
        if (hintText != null) ...[
          const SizedBox(height: 8),
          Text(
            '💡 $hintText',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.glassTextSecondary,
            ),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          '生成會使用 1 則額度',
          style: AppTypography.caption.copyWith(
            color: AppColors.glassTextSecondary,
          ),
        ),
      ],
    );
  }
}
