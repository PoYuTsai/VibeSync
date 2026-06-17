// lib/features/partner/presentation/widgets/partner_data_quality_banner.dart
//
// Spec 3 Phase 5 Task 18 — informational data-quality banner.
//
// Sibling of [SameNameDedupeBanner]. Shown on PartnerDetailScreen when the
// extractor detects that the conversation history mixes two distinct names
// for the same Partner (e.g. an AI summary still references the original
// name after the user renamed). Surfaces two organising actions:
//
//   • 「這是同一人」  → onMarkSamePerson (just clarification, e.g. nickname)
//   • 「拆成新對象」  → onSplit          (organise into a new Partner)
//
// Tone contract (per Spec 3 design §4.2 / §4.3): INFORMATIONAL, not alarming.
// Lexicon + visual rules are enforced by partner_data_quality_banner_test.dart
// (`does NOT use 紅色 ...`) — see that test for the exhaustive ban-list.
// Visual lineage matches [SameNameDedupeBanner] so it sits naturally inside
// the partner detail glass surface.
//
// Receive-only widget: no Riverpod, no NamePair coupling. The screen reads
// the data quality flag and supplies the two names + callbacks.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class PartnerDataQualityBanner extends StatelessWidget {
  final String nameA;
  final String nameB;
  final VoidCallback onMarkSamePerson;
  final VoidCallback onSplit;

  const PartnerDataQualityBanner({
    super.key,
    required this.nameA,
    required this.nameB,
    required this.onMarkSamePerson,
    required this.onSplit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.brandSurface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '我們在這個對象的對話裡看到「$nameA」和「$nameB」兩個名字',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '想怎麼整理這個對象？',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onSplit,
                  child: const Text(
                    '拆成新對象',
                    style: TextStyle(color: AppColors.onBackgroundSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onMarkSamePerson,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                  ),
                  child: const Text(
                    '這是同一人',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
