// lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart
//
// Phase 4 Task 4 — same-name Partner dedupe banner.
//
// Pure presentational. Owner-scoping, dup-pair detection and dismissed-state
// gating live on the screen (PartnerListScreen) so this widget stays trivially
// snapshot-testable.
//
// Visual lineage: matches the existing glassmorphic surface tokens used by
// PartnerListCard so it sits at the top of the list without breaking rhythm.
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class SameNameDedupeBanner extends StatelessWidget {
  final String partnerName;
  final VoidCallback onMergeTap;
  final VoidCallback onDismissTap;

  const SameNameDedupeBanner({
    super.key,
    required this.partnerName,
    required this.onMergeTap,
    required this.onDismissTap,
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
              '你有兩個「$partnerName」，要合併嗎？',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDismissTap,
                  child: const Text(
                    '以後再說',
                    style: TextStyle(color: AppColors.onBackgroundSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onMergeTap,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.ctaStart,
                  ),
                  child: const Text(
                    '立即合併',
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
