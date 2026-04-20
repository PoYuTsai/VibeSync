import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'warm_theme_widgets.dart';

class DimensionScores {
  final int heat; // 熱度
  final int engagement; // 投入度
  final int topicDepth; // 話題深度
  final int replyWillingness; // 回覆意願
  final int emotionalConnection; // 情感連結

  const DimensionScores({
    required this.heat,
    required this.engagement,
    required this.topicDepth,
    required this.replyWillingness,
    required this.emotionalConnection,
  });
}

class DimensionRadarChart extends StatelessWidget {
  final DimensionScores scores;

  const DimensionRadarChart({super.key, required this.scores});

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '五維度剖析',
                style: AppTypography.titleMedium.copyWith(
                  color: AppColors.glassTextPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '本次・0-100',
                style: AppTypography.caption.copyWith(
                  color: AppColors.glassTextHint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Radar chart
          SizedBox(
            height: 200,
            child: RadarChart(
              RadarChartData(
                dataSets: [
                  RadarDataSet(
                    dataEntries: [
                      RadarEntry(value: scores.heat.toDouble()),
                      RadarEntry(value: scores.engagement.toDouble()),
                      RadarEntry(value: scores.topicDepth.toDouble()),
                      RadarEntry(value: scores.replyWillingness.toDouble()),
                      RadarEntry(value: scores.emotionalConnection.toDouble()),
                    ],
                    fillColor: AppColors.ctaStart.withValues(alpha: 0.2),
                    borderColor: AppColors.ctaStart,
                    borderWidth: 2,
                    entryRadius: 4,
                  ),
                ],
                radarBackgroundColor: Colors.transparent,
                borderData: FlBorderData(show: false),
                radarBorderData:
                    BorderSide(color: AppColors.glassBorder, width: 1),
                gridBorderData: BorderSide(
                    color: AppColors.glassBorder.withValues(alpha: 0.5),
                    width: 1),
                tickCount: 4,
                ticksTextStyle:
                    const TextStyle(color: Colors.transparent, fontSize: 0),
                tickBorderData: BorderSide(
                    color: AppColors.glassBorder.withValues(alpha: 0.3)),
                titlePositionPercentageOffset: 0.2,
                getTitle: (index, angle) {
                  const titles = [
                    '熱度',
                    '投入度',
                    '話題深度',
                    '回覆意願',
                    '情感連結'
                  ];
                  return RadarChartTitle(
                    text: titles[index],
                    angle: angle,
                  );
                },
                titleTextStyle: AppTypography.caption.copyWith(
                  color: AppColors.glassTextSecondary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Score grid
          _buildScoreRow('熱度', scores.heat, '投入度', scores.engagement),
          const SizedBox(height: 8),
          _buildScoreRow(
              '話題深度', scores.topicDepth, '回覆意願', scores.replyWillingness),
          const SizedBox(height: 8),
          _buildScoreItem('情感連結', scores.emotionalConnection),
        ],
      ),
    );
  }

  Widget _buildScoreRow(
      String label1, int score1, String label2, int score2) {
    return Row(
      children: [
        Expanded(child: _buildScoreItem(label1, score1)),
        Expanded(child: _buildScoreItem(label2, score2)),
      ],
    );
  }

  Widget _buildScoreItem(String label, int score) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTypography.caption.copyWith(
            color: AppColors.glassTextSecondary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$score',
          style: AppTypography.titleSmall.copyWith(
            color: AppColors.glassTextPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}
