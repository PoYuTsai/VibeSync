// lib/features/report/presentation/widgets/stage_distribution_chart.dart

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/widgets/warm_theme_widgets.dart';
import '../../domain/entities/report_models.dart';

/// 對話階段分佈甜甜圈圖
class StageDistributionChart extends StatelessWidget {
  final List<StageDistribution> distributions;
  final int totalConversations;

  const StageDistributionChart({
    super.key,
    required this.distributions,
    required this.totalConversations,
  });

  static const _stageColors = <String, Color>{
    '破冰': AppColors.bokehYellow,
    '升溫': AppColors.bokehCoral,
    '深入': AppColors.ctaStart,
    '連結': AppColors.hot,
    '邀約': AppColors.veryHot,
  };

  @override
  Widget build(BuildContext context) {
    if (distributions.isEmpty) {
      return GlassmorphicContainer(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Text(
            '尚無數據',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.glassTextSecondary,
            ),
          ),
        ),
      );
    }

    return GlassmorphicContainer(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Left side: Donut chart with center text
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    centerSpaceRadius: 40,
                    sectionsSpace: 2,
                    sections: _buildSections(),
                  ),
                ),
                // Center text: total count + "對話"
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$totalConversations',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.glassTextPrimary,
                      ),
                    ),
                    const Text(
                      '對話',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.glassTextSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          // Right side: Legend
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '階段分佈',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.glassTextPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ...distributions.map((dist) {
                  final color = _stageColors[dist.stageName] ??
                      AppColors.glassTextSecondary;
                  return _buildLegendItem(dist.stageName, dist.count, color);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    return distributions.map((dist) {
      final color =
          _stageColors[dist.stageName] ?? AppColors.glassTextSecondary;
      return PieChartSectionData(
        value: dist.count.toDouble(),
        color: color,
        radius: 20,
        showTitle: false,
      );
    }).toList();
  }

  Widget _buildLegendItem(String stageName, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            stageName,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.glassTextSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '$count',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.glassTextPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
