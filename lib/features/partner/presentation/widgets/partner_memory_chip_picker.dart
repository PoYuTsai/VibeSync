import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/pressable_scale.dart';
import '../../domain/services/partner_memory_tag_catalog.dart';

/// 「關於她」chips 的共用畫面，新增對象與既有對象設定共用同一份 catalog。
class PartnerMemoryChipPicker extends StatelessWidget {
  const PartnerMemoryChipPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '只選你確定、長期成立的；不確定就不要選。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.glassTextSecondary,
                height: 1.4,
              ),
        ),
        const SizedBox(height: 12),
        for (final group in PartnerMemoryTagCatalog.groups) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  group.title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.glassTextSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Text(
                '最多選 ${group.maxSelections} 個',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.glassTextSecondary.withValues(
                        alpha: 0.76,
                      ),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final tag in group.tags)
                _MemoryTagChip(
                  key: ValueKey('partner-memory-chip-${tag.label}'),
                  label: tag.label,
                  selected: selected.contains(tag.label),
                  onTap: PartnerMemoryTagCatalog.canToggle(
                    selected,
                    tag.label,
                  )
                      ? () => onChanged(
                            PartnerMemoryTagCatalog.toggle(
                              selected,
                              tag.label,
                            ),
                          )
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MemoryTagChip extends StatelessWidget {
  const _MemoryTagChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.42,
      child: PressableScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: selected
                  ? AppColors.ctaStart.withValues(alpha: 0.14)
                  : AppColors.glassTextPrimary.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? AppColors.ctaStart.withValues(alpha: 0.64)
                    : AppColors.glassTextSecondary.withValues(alpha: 0.35),
              ),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: selected
                        ? AppColors.ctaStart
                        : AppColors.glassTextSecondary,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}
