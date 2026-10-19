import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_icons.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../analysis/presentation/sections/guide_v3_result_section.dart'
    show guideV3LightColor;
import '../../domain/mindmap/mind_map_models.dart';
import '../../domain/mindmap/partner_insight_presentation.dart';

/// 詳情頁的作戰板入口卡（入口 1）。摘要 = 階段 + 下一步，點擊進全螢幕圖。最近分析是 v3
/// 的對象，階段旁邊多一顆燈號＋短狀態（跟報告作戰板、首頁對象卡同一組字；Bruce
/// 2026-10-19 路線二），改版前沒有階段的 v3 對象就只有這一顆。
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

  List<String> _leavesOf(MindMapBranch branch) {
    for (final b in map.root.children) {
      if (b.branch == branch) {
        return b.children.map((c) => c.label).toList();
      }
    }
    return const [];
  }

  @override
  Widget build(BuildContext context) {
    final stage = _leafOf(MindMapBranch.stage);
    final signals = map.latestGuideV3Signals;
    final status = signals?.status;
    // 入口卡只放短 preview（抓手/可接話題），完整下一步留給作戰板詳情與
    // 詳情頁下方主卡，避免「外層卡 = 內頁同一句」的重貼感。
    final presentation = PartnerInsightPresentation.derive(
      interests: _leavesOf(MindMapBranch.interests),
      traits: _leavesOf(MindMapBranch.traits),
    );
    final preview = presentation.topicsLine != null
        ? '可接話題：${presentation.topicsLine}'
        : (presentation.tacticalHook != null
            ? '抓手：${presentation.tacticalHook}'
            : null);

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
                const Icon(TablerIcons.map_2,
                    size: 18, color: AppColors.ctaStart),
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
              if (stage != null || status != null)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (stage != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          stage,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primaryLight,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (status != null)
                      _GuideV3StatusChip(
                        color: signals?.light == null
                            ? AppColors.onBackgroundSecondary
                            : guideV3LightColor(signals!.light!),
                        lightLabel: signals?.light?.label,
                        status: status,
                      ),
                  ],
                ),
              if (preview != null) ...[
                const SizedBox(height: 8),
                Text(
                  preview,
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

/// 燈號＋短狀態（跟首頁對象卡的膠囊同一個樣子）。字都留白色、顏色只放在燈號的點：綠、紅
/// 的 12 號字在這張卡上不到 4.5:1。
class _GuideV3StatusChip extends StatelessWidget {
  const _GuideV3StatusChip({
    required this.color,
    required this.lightLabel,
    required this.status,
  });

  final Color color;
  final String? lightLabel;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('mind-map-entry-v3-status'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          if (lightLabel != null) ...[
            const SizedBox(width: 5),
            Text(
              lightLabel!,
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(width: 6),
          Text(
            status,
            style: AppTypography.bodySmall.copyWith(
              color: Colors.white.withValues(alpha: 0.88),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
