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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.brandSurface.withValues(alpha: 0.96),
            AppColors.brandSurface2.withValues(alpha: 0.92),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.ctaStart, AppColors.brandBlush],
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: AppTypography.titleSmall.copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(
              subtitle!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _chips(),
          ),
        ],
      ),
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
        color: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const Color(0xFF4D2630);
          }
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFF3A2032);
          }
          return const Color(0xFF261735);
        }),
        backgroundColor: const Color(0xFF261735),
        selectedColor: const Color(0xFF4D2630),
        disabledColor: const Color(0xFF261735),
        surfaceTintColor: Colors.transparent,
        labelStyle: AppTypography.bodySmall.copyWith(
          color: selected
              ? Colors.white
              : AppColors.onBackgroundSecondary.withValues(alpha: 0.86),
          fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          height: 1.2,
        ),
        side: BorderSide(
          color: selected
              ? AppColors.ctaStart.withValues(alpha: 0.64)
              : Colors.white.withValues(alpha: 0.16),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.ctaEnd],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: AppColors.ctaStart.withValues(alpha: 0.24),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
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
