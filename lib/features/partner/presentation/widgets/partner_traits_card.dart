// lib/features/partner/presentation/widgets/partner_traits_card.dart
//
// Pure render of PartnerAggregateView. Shows interest/trait chips, free-form
// notes, and counters (rounds / messages / last interaction).
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/extensions/partner_aggregates.dart';

class PartnerTraitsCard extends StatelessWidget {
  final PartnerAggregateView view;
  const PartnerTraitsCard({super.key, required this.view});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('對方特質', style: AppTypography.titleSmall),
            const SizedBox(height: 8),
            if (view.unionInterests.isEmpty && view.unionTraits.isEmpty)
              Text('尚未抽出特質',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.onBackgroundSecondary))
            else ...[
              if (view.unionInterests.isNotEmpty) ...[
                _Section(label: '興趣', tags: view.unionInterests),
                const SizedBox(height: 8),
              ],
              if (view.unionTraits.isNotEmpty)
                _Section(label: '個性', tags: view.unionTraits),
            ],
            if (view.unionNotes != null && view.unionNotes!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('備註', style: AppTypography.titleSmall),
              const SizedBox(height: 4),
              Text(view.unionNotes!, style: AppTypography.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                Text('${view.totalRounds} 段對話',
                    style: AppTypography.bodySmall),
                Text('${view.totalMessages} 則訊息',
                    style: AppTypography.bodySmall),
                if (view.latestHeat != null)
                  Text('最新熱度 ${view.latestHeat}',
                      style: AppTypography.bodySmall),
              ],
            ),
          ],
        ),
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
        Text(label,
            style: AppTypography.bodySmall
                .copyWith(color: AppColors.onBackgroundSecondary)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children:
              tags.map((t) => Chip(label: Text(t, style: AppTypography.bodySmall))).toList(),
        ),
      ],
    );
  }
}
