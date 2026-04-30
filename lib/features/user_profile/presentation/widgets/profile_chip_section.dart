import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Generic chip group used by [AboutMeScreen] for InteractionStyle (single
/// select), PracticeGoal (multi, max 3), TopicSeed (multi, max 5).
///
/// `showCheckmark: false` is intentional: see memory `1009`/`1010` —
/// without it, ChoiceChip leaves a ghost checkmark artifact on dark backgrounds.
class ProfileChipSection<T> extends StatelessWidget {
  const ProfileChipSection({
    super.key,
    required this.title,
    required this.options,
    required this.labelOf,
    required this.isSelected,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<T> options;
  final String Function(T) labelOf;
  final bool Function(T) isSelected;
  final void Function(T) onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.onBackgroundPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options.map((opt) {
            final selected = isSelected(opt);
            return ChoiceChip(
              label: Text(labelOf(opt)),
              selected: selected,
              showCheckmark: false,
              onSelected: (_) => onTap(opt),
            );
          }).toList(),
        ),
      ],
    );
  }
}
