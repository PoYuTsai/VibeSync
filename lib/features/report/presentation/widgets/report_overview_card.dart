import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/report_models.dart';

/// 報告首屏摘要：只描述「目前各段對話的快照」，不推斷時間方向。
///
/// 這張卡的來源是各 Conversation 最新有效快照，不是同一人的事件序列；把
/// 不同對話的快照切前後半相減得到的「回升／轉為保守」會被讀成某位對象或
/// 使用者的進步，所以拿掉。要看前後變化，往下選一位對象看單人序列。
class ReportOverviewCard extends StatelessWidget {
  const ReportOverviewCard({
    super.key,
    required this.averageScore,
    required this.totalConversations,
    required this.stageDistributions,
  });

  final double averageScore;
  final int totalConversations;
  final List<StageDistribution> stageDistributions;

  static const headline = '目前的對話概況';
  static const subline = '整理各段對話最近一次有效分析；要看前後變化，請往下選一位對象。';

  @override
  Widget build(BuildContext context) {
    final stage = _dominantStage;
    return Semantics(
      container: true,
      label: '整體摘要，$headline，共 $totalConversations 個已分析對話，'
          '對話平均投入 ${averageScore.round()}，常見階段 ${stage ?? '尚無'}',
      child: BrandSurfaceCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const BrandIconBadge(
                  icon: Icons.auto_graph_rounded,
                  size: 36,
                  iconSize: 19,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '整體摘要',
                        style: AppTypography.labelMedium.copyWith(
                          color: AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.78),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$totalConversations 個已分析對話',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.onBackgroundSecondary
                              .withValues(alpha: 0.68),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              headline,
              style: AppTypography.headlineMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subline,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.055),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.075),
                ),
              ),
              child: Row(
                children: [
                  _Metric(
                    value: averageScore.round().toString(),
                    label: '對話平均投入',
                  ),
                  const _MetricDivider(),
                  // 數的是對話不是對象：同一人可能有多段 Conversation。
                  _Metric(
                    value: '$totalConversations',
                    label: '有效對話',
                  ),
                  const _MetricDivider(),
                  _Metric(
                    value: stage ?? '—',
                    label: '常見階段',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color:
                      AppColors.onBackgroundSecondary.withValues(alpha: 0.60),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '投入度只整理文字訊號，不等於關係進度或對方心意。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary
                          .withValues(alpha: 0.66),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? get _dominantStage {
    if (stageDistributions.isEmpty) return null;
    return stageDistributions
        .reduce((a, b) => a.count >= b.count ? a : b)
        .stageName;
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
  });

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.titleLarge.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.68),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      color: Colors.white.withValues(alpha: 0.10),
    );
  }
}
