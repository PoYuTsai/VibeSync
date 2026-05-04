// lib/features/partner/presentation/widgets/partner_traits_card.dart
//
// Pure render of PartnerAggregateView. Shows interest/trait chips, free-form
// notes, and counters (rounds / messages / last interaction).
//
// Post-A2 visual polish (2026-04-28): glass surface (white 8% bg, white 14%
// border, radius 24) + glass-styled pill chips. Same data, no AI synthesis.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/extensions/partner_aggregates.dart';

class PartnerTraitsCard extends StatelessWidget {
  final PartnerAggregateView view;
  final String? customNote;
  final VoidCallback? onEditNote;

  const PartnerTraitsCard({
    super.key,
    required this.view,
    this.customNote,
    this.onEditNote,
  });

  @override
  Widget build(BuildContext context) {
    final trimmedCustomNote = customNote?.trim();
    final hasCustomNote =
        trimmedCustomNote != null && trimmedCustomNote.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
        ),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '對方特質',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                  ),
                ),
              ),
              if (onEditNote != null)
                IconButton(
                  tooltip: '設定對方資訊',
                  onPressed: onEditNote,
                  icon: const Icon(Icons.settings_outlined, size: 20),
                  color: AppColors.onBackgroundSecondary,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasCustomNote) ...[
            Text(
              '你的設定',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              trimmedCustomNote,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (view.unionInterests.isEmpty && view.unionTraits.isEmpty)
            Text(
              '尚未抽出特質',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            )
          else ...[
            if (view.unionInterests.isNotEmpty) ...[
              _Section(label: '興趣', tags: view.unionInterests),
              const SizedBox(height: 10),
            ],
            if (view.unionTraits.isNotEmpty)
              _Section(label: '個性', tags: view.unionTraits),
          ],
          if (view.unionNotes != null && view.unionNotes!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '備註',
              style: AppTypography.titleSmall.copyWith(
                color: AppColors.onBackgroundPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              view.unionNotes!,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _CounterText('${view.totalRounds} 段對話'),
              _CounterText('${view.totalMessages} 則訊息'),
              if (view.latestHeat != null)
                _CounterText('最新熱度 ${view.latestHeat}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String label;
  final List<String> tags;
  const _Section({required this.label, required this.tags});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.onBackgroundSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: tags.map((t) => _GlassChip(text: t)).toList(),
        ),
      ],
    );
  }
}

/// Glass-styled pill chip. Replaces Material `Chip` so it doesn't fight the
/// dark glass surface (Material Chip ships its own opaque bg by default).
class _GlassChip extends StatelessWidget {
  final String text;
  const _GlassChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.14),
        ),
      ),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundPrimary,
        ),
      ),
    );
  }
}

class _CounterText extends StatelessWidget {
  final String text;
  const _CounterText(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTypography.bodySmall.copyWith(
        color: AppColors.onBackgroundSecondary,
      ),
    );
  }
}
