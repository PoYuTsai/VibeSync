// lib/features/partner/presentation/widgets/partner_list_card.dart
//
// Pure render — receives aggregate, does NOT subscribe to providers.
// Keeps tests hermetic (no per-row provider override needed) and makes
// the card trivially reusable in non-list contexts.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/entities/partner.dart';
import '../../domain/extensions/partner_aggregates.dart';

class PartnerListCard extends StatelessWidget {
  final Partner partner;
  final PartnerAggregateView aggregate;
  final VoidCallback onTap;

  const PartnerListCard({
    super.key,
    required this.partner,
    required this.aggregate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final heat = aggregate.latestHeat;
    return ListTile(
      onTap: onTap,
      title: Text(partner.name, style: AppTypography.titleSmall),
      subtitle: Text(
        '${aggregate.totalRounds} 段對話'
        '${heat != null ? ' · 熱度 $heat' : ''}',
        style: AppTypography.bodySmall.copyWith(
          color: AppColors.onBackgroundSecondary,
        ),
      ),
    );
  }
}
