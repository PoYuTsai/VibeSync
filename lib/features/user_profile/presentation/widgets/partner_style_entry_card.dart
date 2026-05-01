import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/glassmorphic_container.dart';
import '../../data/providers/partner_style_providers.dart';

/// Inline entry card on PartnerDetailScreen surfacing per-partner style.
///
/// Two-state subtitle:
///  - "沿用全域預設" when override is null OR every field is empty
///  - "已自訂風格" otherwise
///
/// Whole card is tappable → /partner/:partnerId/my-style.
class PartnerStyleEntryCard extends ConsumerWidget {
  const PartnerStyleEntryCard({
    super.key,
    required this.partnerId,
    required this.partnerName,
  });

  final String partnerId;
  final String partnerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrideAsync = ref.watch(partnerStyleOverrideProvider(partnerId));
    // null OR loading OR empty all collapse to default state — see plan.
    final hasOverride = overrideAsync.valueOrNull?.isEmpty == false;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => context.push('/partner/$partnerId/my-style'),
      child: GlassmorphicContainer(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '我的風格 · 對$partnerName',
                    style: AppTypography.titleMedium.copyWith(
                      color: AppColors.glassTextPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasOverride ? '已自訂風格' : '沿用全域預設',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.glassTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.glassTextSecondary,
            ),
          ],
        ),
      ),
    );
  }
}
