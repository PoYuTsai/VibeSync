import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/mindmap/mind_map_models.dart';

/// 詳情頁的作戰板入口卡（入口 1）。摘要 = 階段 + 下一步，點擊進全螢幕圖。
///
/// 純資料 widget（PartnerMindMap + onTap），不碰 provider，測試零 stub。
/// 容器外觀對齊 partner_detail_screen 的 `_PartnerDetailSection` idiom
/// （白 0.08 填色、24 圓角、白 0.14 邊框、18 padding），文字 token 跟
/// 同頁卡片一致：onBackgroundPrimary / onBackgroundSecondary。
class PartnerMindMapEntryCard extends StatelessWidget {
  final PartnerMindMap map;
  final VoidCallback onTap;

  const PartnerMindMapEntryCard({
    super.key,
    required this.map,
    required this.onTap,
  });

  String? _leafOf(MindMapBranch branch) {
    for (final b in map.root.children) {
      if (b.branch == branch && b.children.isNotEmpty) {
        return b.children.first.label;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final stage = _leafOf(MindMapBranch.stage);
    final nextStep = _leafOf(MindMapBranch.nextStep);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🗺️', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  '對象作戰板',
                  style: AppTypography.titleSmall.copyWith(
                    color: AppColors.onBackgroundPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right,
                  color: AppColors.onBackgroundSecondary,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!map.hasAnalysisData)
              Text(
                '完成一次對話分析，解鎖作戰板',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.onBackgroundSecondary,
                  height: 1.35,
                ),
              )
            else ...[
              if (stage != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    stage,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.primaryLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              if (nextStep != null) ...[
                const SizedBox(height: 8),
                Text(
                  '下一步：$nextStep',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.ctaStart,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
