import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../../partner/domain/entities/partner.dart';

/// 報告頁底部「對象作戰板」橫向卡片列（入口 2，救回報告頁初衷）。
/// dogfood 期全 tier 可見（決策 A），不動既有三張圖與 Free gating。
///
/// 純資料 widget（partners + stageLabelOf + onTapPartner），不碰 provider，
/// 測試零 stub。section header 對齊本頁「我的報告」idiom
/// （bodySmall ctaStart 眉標 + 主標），卡片用 GlassmorphicContainer。
class PartnerMindMapCardList extends StatelessWidget {
  final List<Partner> partners;
  final String? Function(String partnerId) stageLabelOf;
  final ValueChanged<String> onTapPartner;

  const PartnerMindMapCardList({
    super.key,
    required this.partners,
    required this.stageLabelOf,
    required this.onTapPartner,
  });

  @override
  Widget build(BuildContext context) {
    if (partners.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '對象作戰板',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.ctaStart,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '每個對象的下一步，一張圖看懂',
          style: AppTypography.titleMedium
              .copyWith(color: AppColors.onBackgroundPrimary),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: partners.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final partner = partners[index];
              final stage = stageLabelOf(partner.id);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTapPartner(partner.id),
                child: GlassmorphicContainer(
                  borderRadius: 14,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 140),
                            child: Text(
                              partner.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium.copyWith(
                                color: AppColors.glassTextPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            Icons.chevron_right,
                            size: 16,
                            color: AppColors.glassTextPrimary
                                .withValues(alpha: 0.5),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        stage ?? '尚未分析',
                        style: AppTypography.bodySmall.copyWith(
                          color: stage != null
                              ? AppColors.primary
                              : AppColors.glassTextPrimary
                                  .withValues(alpha: 0.5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
