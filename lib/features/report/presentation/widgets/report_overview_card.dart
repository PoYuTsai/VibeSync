import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';
import '../../domain/entities/report_models.dart';

/// 報告首屏摘要：先回答「整體往哪走」，再讓使用者往下查看個別依據。
class ReportOverviewCard extends StatelessWidget {
  const ReportOverviewCard({
    super.key,
    required this.averageScore,
    required this.scoreDelta,
    required this.totalConversations,
    required this.stageDistributions,
  });

  final double averageScore;
  final double scoreDelta;
  final int totalConversations;
  final List<StageDistribution> stageDistributions;

  @override
  Widget build(BuildContext context) {
    final stage = _dominantStage;
    return Semantics(
      container: true,
      label: '整體摘要，${_headline()}，共 $totalConversations 個已分析對話',
      child: BrandSurfaceCard(
        padding: const EdgeInsets.all(20),
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
                const SizedBox(width: 10),
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
                _DirectionBadge(delta: scoreDelta),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              _headline(),
              style: AppTypography.headlineMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                height: 1.22,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '先看方向，再往下確認是哪位對象、哪次互動帶來變化。',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
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
                    label: '平均投入',
                  ),
                  const _MetricDivider(),
                  _Metric(
                    value: _signedDelta,
                    label: '前後趨勢',
                    valueColor: _deltaColor,
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
                const SizedBox(width: 7),
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

  String _headline() {
    if (totalConversations <= 1) return '第一個互動基準已建立';
    if (scoreDelta >= 8) return '近期的投入訊號正在回升';
    if (scoreDelta <= -8) return '近期的投入訊號轉為保守';
    return '整體投入節奏大致穩定';
  }

  String get _signedDelta {
    final rounded = scoreDelta.round();
    if (rounded > 0) return '+$rounded';
    return '$rounded';
  }

  Color get _deltaColor {
    if (scoreDelta > 0) return AppColors.success;
    if (scoreDelta < 0) return AppColors.error;
    return Colors.white;
  }

  String? get _dominantStage {
    if (stageDistributions.isEmpty) return null;
    return stageDistributions
        .reduce((a, b) => a.count >= b.count ? a : b)
        .stageName;
  }
}

class _DirectionBadge extends StatelessWidget {
  const _DirectionBadge({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final isUp = delta >= 8;
    final isDown = delta <= -8;
    final color = isUp
        ? AppColors.success
        : isDown
            ? AppColors.error
            : AppColors.primaryLight;
    final label = isUp
        ? '回升'
        : isDown
            ? '放慢'
            : '穩定';
    final icon = isUp
        ? Icons.trending_up_rounded
        : isDown
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.value,
    required this.label,
    this.valueColor = Colors.white,
  });

  final String value;
  final String label;
  final Color valueColor;

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
              color: valueColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.68),
              fontSize: 11,
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
