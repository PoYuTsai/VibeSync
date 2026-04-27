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
          color: AppColors.glassWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.glassBorder),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '你有兩個「$partnerName」，要合併嗎？',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.glassTextPrimary,
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
                    style: TextStyle(color: AppColors.glassTextSecondary),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: onMergeTap,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
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
