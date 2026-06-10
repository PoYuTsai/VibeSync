import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Generic chip group used by [AboutMeScreen] for InteractionStyle (ordered
/// dual select via [badgeOf]), PracticeGoal (multi, max 3), TopicSeed (multi,
/// max 5).
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
    this.badgeOf,
  });

  final String title;
  final String? subtitle;
  final List<T> options;
  final String Function(T) labelOf;
  final bool Function(T) isSelected;
  final void Function(T) onTap;

  /// Optional 主/副 badge for ordered dual select (style pair). Null result
  /// renders a plain chip.
  final String? Function(T)? badgeOf;

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
          children: _chips(),
        ),
      ],
    );
  }

  List<Widget> _chips() {
    return options.map((opt) {
      final selected = isSelected(opt);
      final badge = badgeOf?.call(opt);
      return ChoiceChip(
        label: badge == null
            ? Text(labelOf(opt))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(labelOf(opt)),
                  const SizedBox(width: 4),
                  StyleRoleBadge(text: badge),
                ],
              ),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(opt),
      );
    }).toList();
  }
}

/// Small 主/副 pill rendered inside a selected style chip. Shared by
/// [ProfileChipSection] and the partner style edit screen so the pair badge
/// looks identical on both surfaces.
class StyleRoleBadge extends StatelessWidget {
  const StyleRoleBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.ctaStart,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.2,
        ),
      ),
    );
  }
}
